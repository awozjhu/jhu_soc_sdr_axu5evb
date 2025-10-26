// -----------------------------------------------------------------------------
// slicer.sv (self-contained)
// BPSK/QPSK symbol slicer with AXI4-Lite control and internal vld/rdy/last.
// - Symbols in: {I[15:0], Q[15:0]} (Q1.15, signed), one symbol per beat.
// - Bytes out : bits packed LSB-first. TLAST asserted on last output byte
//               (generator ensures K*frameLen is byte-aligned).
// - QPSK Gray per project convention: bit0 = sign(I), bit1 = sign(Q).
// - BYPASS forces BPSK decisions (I-only) regardless of MODE.
//
// CSRs (word-aligned, base offset local to this block):
//   0x00 CTRL  : [0]=ENABLE, [1]=BYPASS, [2]=SW_RESET(one-shot),
//                [6:4]=MODE (0=BPSK, 1=QPSK), [8]=AMC_OVERRIDE (1=use local MODE)
//   0x04 STATUS: [0]=RUNNING (R/W1C), [2]=OVERFLOW (R/W1C)
//   0x18 RESULT0: byte_count (RO; W* clears to 0 for convenience)
//
// Notes:
// - AXI-Lite assumed in same clk domain (clk_bb). If not, add CDC.
// - Internal streams are AXIS-like: valid/ready/last only.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module slicer #(
  parameter integer BYTE_COUNT_W = 32
)(
  input  logic clk_bb,
  input  logic rst_n,

  // -------- internal "AXIS-like" symbols in: {I[15:0],Q[15:0]} --------
  input  logic        in_valid,
  output logic        in_ready,
  input  logic [31:0] in_data,     // {I[15:0], Q[15:0]}
  input  logic        in_last,

  // -------- internal "AXIS-like" bytes out (LSB-first) --------
  output logic        out_valid,
  input  logic        out_ready,
  output logic [7:0]  out_data,
  output logic        out_last,

  // Optional AMC-selected mode (only bit[0] used today: 0=BPSK, 1=QPSK)
  input  logic [2:0]  amc_mode_i,
  input  logic        amc_mode_valid_i,

  // ------------------------- AXI4-Lite (CSR) ------------------------------
  input  logic        s_axi_aclk,
  input  logic        s_axi_aresetn,
  // write address
  input  logic [7:0]  s_axi_awaddr,
  input  logic        s_axi_awvalid,
  output logic        s_axi_awready,
  // write data
  input  logic [31:0] s_axi_wdata,
  input  logic [3:0]  s_axi_wstrb,
  input  logic        s_axi_wvalid,
  output logic        s_axi_wready,
  // write resp
  output logic [1:0]  s_axi_bresp,
  output logic        s_axi_bvalid,
  input  logic        s_axi_bready,
  // read address
  input  logic [7:0]  s_axi_araddr,
  input  logic        s_axi_arvalid,
  output logic        s_axi_arready,
  // read data
  output logic [31:0] s_axi_rdata,
  output logic [1:0]  s_axi_rresp,
  output logic        s_axi_rvalid,
  input  logic        s_axi_rready
);

  // =========================================================================
  // CSR registers / AXI-Lite (always-ready style, like mapper)
  // =========================================================================
  logic        ctrl_enable;
  logic        ctrl_bypass;
  logic        ctrl_sw_reset;    // one-shot
  logic [2:0]  ctrl_mode;        // 0=BPSK, 1=QPSK
  logic        ctrl_amc_override;

  logic        st_running;       // set once first byte emitted; R/W1C
  logic        st_overflow;      // set if upstream violates ready; R/W1C

  logic [BYTE_COUNT_W-1:0] byte_count; // RESULT0

  logic [7:0]  awaddr_hold;
  logic        have_write;
  logic        do_write;
  logic [7:0]  araddr_hold;
  logic        do_read;

  always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
      s_axi_awready   <= 1'b1;
      s_axi_wready    <= 1'b1;
      s_axi_bvalid    <= 1'b0;
      s_axi_bresp     <= 2'b00;
      awaddr_hold     <= 8'h00;
      have_write      <= 1'b0;

      s_axi_arready   <= 1'b1;
      s_axi_rvalid    <= 1'b0;
      s_axi_rresp     <= 2'b00;
      s_axi_rdata     <= 32'h0;
      araddr_hold     <= 8'h00;

      ctrl_enable       <= 1'b0;
      ctrl_bypass       <= 1'b0;
      ctrl_sw_reset     <= 1'b0;
      ctrl_mode         <= 3'd1;   // default QPSK
      ctrl_amc_override <= 1'b1;   // default: use local MODE

      st_running        <= 1'b0;
      st_overflow       <= 1'b0;
      byte_count        <= {BYTE_COUNT_W{1'b0}};
    end else begin
      if (s_axi_awvalid) awaddr_hold <= s_axi_awaddr;
      have_write <= s_axi_awvalid & s_axi_wvalid & ~s_axi_bvalid;
      do_write   <= have_write;  // 1-cycle pulse

      if (do_write) begin
        unique case (awaddr_hold[7:2]) // word aligned
          6'h00: begin // CTRL
            if (s_axi_wstrb[0]) begin
              ctrl_enable       <= s_axi_wdata[0];
              ctrl_bypass       <= s_axi_wdata[1];
              ctrl_sw_reset     <= s_axi_wdata[2];  // one-shot below
              ctrl_mode         <= s_axi_wdata[6:4];
              ctrl_amc_override <= s_axi_wdata[8];
            end
          end
          6'h01: begin // STATUS R/W1C
            if (s_axi_wstrb[0]) begin
              if (s_axi_wdata[0]) st_running  <= 1'b0;
              if (s_axi_wdata[2]) st_overflow <= 1'b0;
            end
          end
          6'h06: begin // RESULT0 (optional clear-on-write)
            if (s_axi_wstrb != 4'b0000) byte_count <= {BYTE_COUNT_W{1'b0}};
          end
          default: ;
        endcase
        s_axi_bvalid <= 1'b1;
        s_axi_bresp  <= 2'b00;
      end else if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end

      do_read <= s_axi_arvalid & ~s_axi_rvalid;
      if (do_read) begin
        araddr_hold <= s_axi_araddr;
        unique case (s_axi_araddr[7:2])
          6'h00: s_axi_rdata <= {23'd0, ctrl_amc_override, 1'b0, ctrl_mode, ctrl_sw_reset, ctrl_bypass, ctrl_enable};
          6'h01: s_axi_rdata <= {29'd0, st_overflow, 1'b0, st_running};
          6'h06: s_axi_rdata <= {{(32-BYTE_COUNT_W){1'b0}}, byte_count};
          default: s_axi_rdata <= 32'h0000_0000;
        endcase
        s_axi_rresp  <= 2'b00;
        s_axi_rvalid <= 1'b1;
      end else if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
      end

      if (ctrl_sw_reset) ctrl_sw_reset <= 1'b0;
    end
  end

  // =========================================================================
  // Datapath: symbol → bits (LSB-first) → byte packer
  // =========================================================================
  // Effective mode: AMC override == 1 -> use ctrl_mode; else use amc_mode_i (if valid)
  logic [2:0] mode_sel;
  logic       eff_qpsk;
  logic       need2;
  logic [1:0] K;

  always_comb begin
    if (ctrl_amc_override)       mode_sel = ctrl_mode;
    else if (amc_mode_valid_i)   mode_sel = amc_mode_i;
    else                         mode_sel = ctrl_mode;

    eff_qpsk = mode_sel[0];
    need2    = (~ctrl_bypass) & eff_qpsk; // BYPASS forces BPSK
    K        = need2 ? 2'd2 : 2'd1;
  end

  // Symbol input split and sign → bits (b0 from I, b1 from Q)
  logic signed [15:0] I_in;
  logic signed [15:0] Q_in;
  logic               calc_b0;
  logic               calc_b1;

  assign I_in = in_data[31:16];
  assign Q_in = in_data[15:0];

  always_comb begin
    // Sign threshold at 0 (Q1.15). I<0 → bit1, else 0. Same for Q.
    calc_b0 = I_in[15];               // 1 if negative
    calc_b1 = need2 ? Q_in[15] : 1'b0;
  end

  // Byte packer
  logic [7:0] byte_buf;
  logic [3:0] bits_filled;            // 0..8
  logic [3:0] sum_bits;
  logic       would_make_full;
  logic       pipeline_blocked;
  logic [7:0] next_byte_fill;
  logic       frame_last_pending;
  logic       this_last_for_byte;

  always_comb begin
    sum_bits         = bits_filled + K;
    would_make_full  = (sum_bits == 4'd8);
    pipeline_blocked = (out_valid & ~out_ready);

    // Precompute what the byte would look like after inserting new bits
    next_byte_fill   = byte_buf;
    next_byte_fill[bits_filled] = calc_b0;
    if (need2) next_byte_fill[bits_filled + 1] = calc_b1;

    // TLAST for this output byte (generator guarantees alignment)
    this_last_for_byte = would_make_full & (in_last | frame_last_pending);
  end

  // Ready to accept a symbol:
  // - Always OK if sum_bits < 8 (we just accumulate).
  // - If sum_bits == 8, we can only accept if the output byte path isn't blocked.
  assign in_ready = ctrl_enable &
                    ( (sum_bits < 4'd8) | ( (sum_bits == 4'd8) & ~pipeline_blocked ) );

  always_ff @(posedge clk_bb or negedge rst_n) begin
    if (!rst_n) begin
      byte_buf            <= 8'h00;
      bits_filled         <= 4'd0;
      frame_last_pending  <= 1'b0;

      out_valid           <= 1'b0;
      out_data            <= 8'h00;
      out_last            <= 1'b0;

      st_running          <= 1'b0;
      st_overflow         <= 1'b0;
    end else begin
      // Local soft reset for datapath
      if (ctrl_sw_reset) begin
        byte_buf           <= 8'h00;
        bits_filled        <= 4'd0;
        frame_last_pending <= 1'b0;
        out_valid          <= 1'b0;
      end

      // Overflow sticky if upstream violates ready
      if (in_valid && !in_ready) begin
        st_overflow <= 1'b1;
      end

      // Accept a symbol
      if (in_valid && in_ready) begin
        // Track frame boundary if we haven't yet produced the last byte
        if (in_last) frame_last_pending <= 1'b1;

        if (would_make_full) begin
          // Emit a full byte immediately
          out_data            <= next_byte_fill;
          out_valid           <= 1'b1;
          out_last            <= this_last_for_byte;

          // Reset accumulator for next byte
          byte_buf            <= 8'h00;
          bits_filled         <= 4'd0;
          frame_last_pending  <= 1'b0; // consumed with this byte
        end else begin
          // Accumulate bits into partial byte
          byte_buf    <= next_byte_fill;
          bits_filled <= bits_filled + K;
        end
      end

      // Downstream handshake for output byte
      if (out_valid && out_ready) begin
        out_valid  <= 1'b0;
        st_running <= 1'b1;
        byte_count <= byte_count + {{(BYTE_COUNT_W-1){1'b0}}, 1'b1};
      end
    end
  end

endmodule

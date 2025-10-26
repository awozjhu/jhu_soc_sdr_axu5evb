`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// Slicer (BPSK/QPSK) with AXI4-Lite control and AXIS-like I/Q in → bits out.
// - Input  : {I[15:0], Q[15:0]} in Q1.15
// - Output : bits packed into bytes (LSB-first within each byte)
// - Gray map (QPSK): 00:(+,+), 01:(-,+), 11:(-,-), 10:(+,-)
// - TLAST propagated at frame boundary (pads final partial byte if needed)
// Registers (BASE 0xA000_F000):
//   0x00 CTRL   [0]=ENABLE, [1]=BYPASS, [2]=SW_RESET(one-shot), [6:4]=MODE(0=BPSK,1=QPSK)
//   0x04 STATUS [0]=RUNNING (R/W1C)
//   0x18 RESULT0: BIT_PACKED_COUNT (RO) - bytes produced
// -----------------------------------------------------------------------------
module slicer #(
  parameter logic signed [15:0] ZERO_THRESH = 16'sd0  // decision threshold at 0
)(
  input  logic clk_bb,
  input  logic rst_n,

  // -------- AXIS-like input {I,Q} --------
  input  logic        in_valid,
  output logic        in_ready,
  input  logic [31:0] in_data,    // {I[31:16], Q[15:0]}
  input  logic        in_last,

  // -------- AXIS-like output bits (bytes) --------
  output logic        out_valid,
  input  logic        out_ready,
  output logic [7:0]  out_data,   // LSB-first bit packing
  output logic        out_last,

  // ---------------- AXI4-Lite (same clk domain) ----------------
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
  // Types/locals
  // =========================================================================
  typedef logic signed [15:0] iq_t;

  // CTRL
  logic        ctrl_enable;
  logic        ctrl_bypass;
  logic        ctrl_sw_reset;   // one-shot
  logic [2:0]  ctrl_mode;       // [0]: 0=BPSK, 1=QPSK

  // STATUS/RESULTS
  logic        st_running;      // set after first output byte handshake (R/W1C)
  logic [31:0] res_byte_count;  // RESULT0: bytes produced (RO)

  // AXI-Lite simple ready/valid (always-ready) slave
  logic [7:0]  awaddr_hold, araddr_hold;
  logic        have_write, do_write, do_read;

  // =========================================================================
  // AXI-Lite
  // =========================================================================
  always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
      s_axi_awready   <= 1'b1;  s_axi_wready  <= 1'b1;
      s_axi_bvalid    <= 1'b0;  s_axi_bresp   <= 2'b00;
      s_axi_arready   <= 1'b1;  s_axi_rvalid  <= 1'b0; s_axi_rresp <= 2'b00; s_axi_rdata <= 32'h0;
      awaddr_hold     <= '0;    araddr_hold  <= '0;
      have_write      <= 1'b0;  do_write     <= 1'b0; do_read <= 1'b0;

      ctrl_enable     <= 1'b0;
      ctrl_bypass     <= 1'b0;
      ctrl_sw_reset   <= 1'b0;
      ctrl_mode       <= 3'd1;  // default QPSK

      st_running      <= 1'b0;
      res_byte_count  <= 32'd0;
    end else begin
      if (s_axi_awvalid) awaddr_hold <= s_axi_awaddr;
      have_write <= s_axi_awvalid & s_axi_wvalid & ~s_axi_bvalid;
      do_write   <= have_write;

      if (do_write) begin
        unique case (awaddr_hold[7:2]) // word-aligned
          6'h00: if (s_axi_wstrb[0]) begin
                   ctrl_enable   <= s_axi_wdata[0];
                   ctrl_bypass   <= s_axi_wdata[1];
                   ctrl_sw_reset <= s_axi_wdata[2];  // one-shot, self-clear below
                   ctrl_mode     <= s_axi_wdata[6:4];
                 end
          6'h01: if (s_axi_wstrb[0]) begin
                   if (s_axi_wdata[0]) st_running <= 1'b0; // R/W1C
                 end
          default: ;
        endcase
        s_axi_bvalid <= 1'b1; s_axi_bresp <= 2'b00;
      end else if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end

      do_read <= s_axi_arvalid & ~s_axi_rvalid;
      if (do_read) begin
        araddr_hold <= s_axi_araddr;
        unique case (s_axi_araddr[7:2])
          6'h00: s_axi_rdata <= {25'd0, ctrl_mode, ctrl_sw_reset, ctrl_bypass, ctrl_enable};
          6'h01: s_axi_rdata <= {31'd0, st_running};
          6'h06: s_axi_rdata <= res_byte_count; // 0x18 RESULT0
          default: s_axi_rdata <= 32'h0;
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
  // Datapath: decisions → bit packer → byte hold
  // =========================================================================
  logic eff_qpsk;
  always_comb eff_qpsk = ctrl_mode[0] & ~ctrl_bypass; // BYPASS can optionally force "simple" mode

  // Accumulator for bits (LSB-first) and pending frame end
  logic [31:0] bit_buf;
  logic  [5:0] bit_cnt;          // 0..32 bits currently buffered
  logic        frame_last_pending;

  // Byte output hold
  logic        hold_valid;
  logic [7:0]  hold_byte;
  logic        hold_last;

  // Ready when there's room for the next decision(s)
  logic [1:0]  K;                // bits per symbol: 1=BPSK, 2=QPSK
  always_comb K = (eff_qpsk) ? 2'd2 : 2'd1;

  // Accept new symbol if enabled and space available (avoid overflow even if out stalls)
  assign in_ready = ctrl_enable && ((32 - bit_cnt) >= K) && !ctrl_sw_reset;

  // Present output
  assign out_valid = hold_valid;
  assign out_data  = hold_byte;
  assign out_last  = hold_last;

  // Decision + pack, and byteization
  always_ff @(posedge clk_bb or negedge rst_n) begin
    if (!rst_n) begin
      bit_buf            <= '0;
      bit_cnt            <= '0;
      frame_last_pending <= 1'b0;

      hold_valid         <= 1'b0;
      hold_byte          <= 8'h00;
      hold_last          <= 1'b0;

      st_running         <= 1'b0;
      res_byte_count     <= 32'd0;
    end else begin
      // Software one-shot reset
      if (ctrl_sw_reset) begin
        bit_buf            <= '0;
        bit_cnt            <= '0;
        frame_last_pending <= 1'b0;
        hold_valid         <= 1'b0;
        hold_last          <= 1'b0;
      end

      // ----- Accept input symbol and compute decisions -----
      if (in_valid && in_ready) begin
        iq_t I = iq_t'(in_data[31:16]);
        iq_t Q = iq_t'(in_data[15:0]);

        // Sign-based hard decision at 0
        logic b0, b1;
        if (eff_qpsk) begin
          // QPSK (Gray): b0 from Q sign, b1 from I sign
          b0 = (Q < ZERO_THRESH); // 0 if Q>=0, 1 if Q<0
          b1 = (I < ZERO_THRESH); // 0 if I>=0, 1 if I<0
          // pack LSB-first: first b0 then b1
          bit_buf[bit_cnt +: 1] <= b0;
          bit_buf[bit_cnt+1 +: 1] <= b1;
          bit_cnt <= bit_cnt + 2;
        end else begin
          // BPSK: one bit from I sign
          b0 = (I < ZERO_THRESH);
          bit_buf[bit_cnt +: 1] <= b0;
          bit_cnt <= bit_cnt + 1;
        end

        if (in_last) frame_last_pending <= 1'b1;
      end

      // ----- Launch a byte into the output hold when available -----
      if (!hold_valid) begin
        if (bit_cnt >= 6'd8) begin
          hold_byte  <= bit_buf[7:0];
          // consume 8 bits immediately so buffer can continue to fill
          bit_buf    <= bit_buf >> 8;
          bit_cnt    <= bit_cnt - 6'd8;
          // this byte is last iff we had a frame end pending and no bits remain after consumption
          hold_last  <= frame_last_pending && ((bit_cnt - 6'd8) == 6'd0);
          if (hold_last) frame_last_pending <= 1'b0;
          hold_valid <= 1'b1;
        end else if (frame_last_pending && (bit_cnt != 0)) begin
          // Flush a partial final byte (zero-padded) at frame end
          hold_byte  <= bit_buf[7:0];
          bit_buf    <= '0;
          bit_cnt    <= '0;
          hold_last  <= 1'b1;
          frame_last_pending <= 1'b0;
          hold_valid <= 1'b1;
        end
      end

      // ----- Downstream handshake -----
      if (hold_valid && out_ready) begin
        hold_valid <= 1'b0;
        // Stats
        st_running     <= 1'b1;
        res_byte_count <= (res_byte_count == 32'hFFFF_FFFF) ? 32'hFFFF_FFFF
                                                            : res_byte_count + 1;
      end
    end
  end

endmodule

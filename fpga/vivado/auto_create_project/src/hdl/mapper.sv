// mapper.sv (self-contained)
// BPSK/QPSK symbol mapper with AXI4-Lite control and internal vld/rdy/last.
// - Bits in (8b, LSB-first within each byte) --> {I,Q} out in Q1.15.
// - QPSK Gray: 00:(+,+), 01:(-,+), 11:(-,-), 10:(+,-).
// - BYPASS forces BPSK (I-only) regardless of MODE.
//
// CSRs (word-aligned, base offset local to this block):
//   0x00 CTRL  : [0]=ENABLE, [1]=BYPASS, [2]=SW_RESET(one-shot),
//                [6:4]=MODE (0=BPSK, 1=QPSK), [8]=AMC_OVERRIDE (1=use local MODE)
//   0x04 STATUS: [0]=RUNNING (R/W1C), [2]=OVERFLOW (R/W1C)
//
// Notes:
// - AXI-Lite is assumed in the same clk domain (clk_bb). If not, add CDC.
// - Internal stream is AXIS-like: valid/ready/last only.

/*------------------------------------------------------------------------------
-  Symbol Mapper (mapper.sv)
-  ------------------------------------------------------------------------------
-  Purpose
-    Convert a byte-wide bitstream (AXIS-like, LSB-first per byte) into
-    complex baseband symbols in Q1.15 fixed-point. Supports BPSK and
-    Gray-coded QPSK. Optional BYPASS forces BPSK (I-only).
-
-  Interfaces
-    clk_bb, rst_n                       : datapath clock/reset
-    in_*  (valid,ready,data[7:0],last)  : input bits, 8 per beat, LSB-first
-    out_* (valid,ready,data[31:0],last) : output symbols; out_data = {I[15:0],Q[15:0]}
-    amc_mode_i[2:0], amc_mode_valid_i   : optional external mode (only bit[0] used)
-    AXI4-Lite slave                      : CTRL/STATUS registers (same clock domain)
-
-  Register Map (word-aligned)
-    0x00 CTRL
-         [0]  ENABLE          : 1=enable datapath
-         [1]  BYPASS          : 1=force BPSK (I-only) regardless of MODE
-         [2]  SW_RESET        : one-shot; clears internal buffers/holds
-         [6:4]MODE            : 0=BPSK, 1=QPSK (others reserved)
-         [8]  AMC_OVERRIDE    : 1=use local MODE; 0=use amc_mode_i when valid
-    0x04 STATUS (R/W1C bits)
-         [0]  RUNNING         : set after first symbol handshake on out_*
-         [2]  OVERFLOW        : set if upstream asserted in_valid when !in_ready
-
-  Operation
-    • Byte intake / bit buffer:
-        - Accepts a new input byte only when the internal bit buffer is empty and
-          the output hold register is free. This keeps frame TLAST aligned to byte
-          boundaries.
-        - Bits are consumed LSB-first from the buffer.
-
-    • Symbol formation:
-        - K = 1 (BPSK) or 2 (QPSK) bits per symbol.
-        - For BPSK: use b0 = current LSB; map I = ±AMP_BPSK, Q = 0.
-        - For QPSK (Gray):
-              Bit pair per symbol is [b0,b1] taken LSB-first from the buffer.
-              Q sign ← b0 (0 ⇒ +, 1 ⇒ −)
-              I sign ← b1 (0 ⇒ +, 1 ⇒ −)
-              Mapping: 00:(+,+), 01:(−,+), 11:(−,−), 10:(+,-)
-          Output amplitudes: AMP_BPSK=±32767, AMP_QPSK=±23170 (≈±1/√2 in Q1.15).
-
-    • TLAST propagation:
-        - in_last is latched with the current byte. out_last is asserted on the
-          symbol that consumes the final remaining bits of that byte (i.e., when
-          the buffer becomes empty after that symbol). This marks the end of the
-          frame at a symbol boundary.
-
-    • Handshakes:
-        - in_ready  = ENABLE & (bit buffer empty) & (output hold not valid).
-        - out_valid pulses when a symbol is ready; data transfers on out_valid &
-          out_ready.
-        - OVERFLOW sets if in_valid asserted when in_ready=0.
-
-    • Mode selection:
-        - If AMC_OVERRIDE=1, use CTRL.MODE; else, when amc_mode_valid_i=1, use
-          amc_mode_i[0] (0=BPSK, 1=QPSK).
-
-    • Reset / status:
-        - SW_RESET (CTRL[2]) is a one-shot that clears internal state.
-        - RUNNING sets after the first successful output transfer.
-        - STATUS bits are R/W1C.
-
-  Notes
-    - Q1.15 outputs are packed as {I[15:0], Q[15:0]} on out_data.
-    - Design assumes AXI-Lite and datapath share clk_bb; add CDC if not.
-------------------------------------------------------------------------------*/




`timescale 1ns/1ps

module mapper #(
  // Q1.15 amplitudes
  parameter logic signed [15:0] AMP_BPSK = 16'sd32767, // ±1.0
  parameter logic signed [15:0] AMP_QPSK = 16'sd23170  // ±1/sqrt(2)
)(
  input  logic clk_bb,
  input  logic rst_n,

  // -------- internal "AXIS-like" bitstream in (8-bit) --------
  input  logic        in_valid,
  output logic        in_ready,
  input  logic [7:0]  in_data,
  input  logic        in_last,

  // -------- internal "AXIS-like" symbols out: {I[15:0],Q[15:0]} --------
  output logic        out_valid,
  input  logic        out_ready,
  output logic [31:0] out_data,   // {I[15:0], Q[15:0]}
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
  // Local types/params
  // =========================================================================
  typedef logic signed [15:0] iq_comp_t;
  localparam int IQ_W      = 16;
  localparam int SYM_AXI_W = 32;

  // =========================================================================
  // CSRs
  // =========================================================================
  // CTRL
  logic        ctrl_enable;
  logic        ctrl_bypass;
  logic        ctrl_sw_reset;    // one-shot
  logic [2:0]  ctrl_mode;        // 0=BPSK, 1=QPSK
  logic        ctrl_amc_override;

  // STATUS sticky bits
  logic        st_running;       // set once first symbol emitted; R/W1C
  logic        st_overflow;      // set if upstream overdrives when not ready; R/W1C

  // AXI-Lite simple/robust always-ready slave
  logic [7:0]  awaddr_hold;
  logic        have_write;       // AW and W seen in this beat
  logic        do_write;
  logic [7:0]  araddr_hold;
  logic        do_read;

  // Write path
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

      // CTRL defaults
      ctrl_enable       <= 1'b0;
      ctrl_bypass       <= 1'b0;
      ctrl_sw_reset     <= 1'b0;
      ctrl_mode         <= 3'd1;   // default QPSK
      ctrl_amc_override <= 1'b1;   // default: use local MODE

      st_running        <= 1'b0;
      st_overflow       <= 1'b0;
    end else begin
      // -------- write address/data capture (always-ready) ----------
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
          default: ;
        endcase
        s_axi_bvalid <= 1'b1;
        s_axi_bresp  <= 2'b00;
      end else if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end

      // -------- read address / data ----------
      do_read <= s_axi_arvalid & ~s_axi_rvalid;
      if (do_read) begin
        araddr_hold <= s_axi_araddr;
        unique case (s_axi_araddr[7:2])
          6'h00: s_axi_rdata <= {23'd0, ctrl_amc_override, 1'b0, ctrl_mode, ctrl_sw_reset, ctrl_bypass, ctrl_enable};
          6'h01: s_axi_rdata <= {29'd0, st_overflow, 1'b0, st_running};
          default: s_axi_rdata <= 32'h0000_0000;
        endcase
        s_axi_rresp  <= 2'b00;
        s_axi_rvalid <= 1'b1;
      end else if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
      end

      // -------- self-clear SW_RESET ----------
      if (ctrl_sw_reset) ctrl_sw_reset <= 1'b0;
    end
  end

  // =========================================================================
  // Datapath
  // =========================================================================
  // Effective mode: AMC override == 1 -> use ctrl_mode; else use amc_mode_i (if valid)
  logic eff_qpsk;  // 0=BPSK, 1=QPSK
  logic [2:0] mode_sel;

  always_comb begin
    if (ctrl_amc_override)       mode_sel = ctrl_mode;
    else if (amc_mode_valid_i)   mode_sel = amc_mode_i;
    else                         mode_sel = ctrl_mode;
    eff_qpsk = mode_sel[0];
  end

  // Bit buffer (we refill only when empty to keep TLAST at byte boundaries)
  logic [7:0] bit_buf;
  logic [3:0] bits_avail;     // 0..8
  logic       last_pending;   // TLAST associated with current bit_buf

  // Hold register for one symbol beat
  iq_comp_t   hold_I, hold_Q;
  logic       hold_last, hold_valid;
  logic [1:0] hold_bits_used;

  // Combinational helper: how many bits needed this symbol?
  logic need2;
  logic [1:0] K;
  always_comb begin
    need2 = (ctrl_bypass) ? 1'b0 : eff_qpsk;
    K     = need2 ? 2'd2 : 2'd1;
  end

  // Ready to accept a new byte when buffer empty and output hold free
  assign in_ready  = ctrl_enable & (bits_avail == 4'd0) & (~hold_valid);

  // Output signals
  assign out_valid = hold_valid;
  assign out_data  = {hold_I, hold_Q};  // {I[15:0], Q[15:0]}
  assign out_last  = hold_last;

  // Mapping function
  function automatic void map_bits_to_iq (
      input  logic bypass, input logic qpsk,
      input  logic b0, input logic b1,
      output iq_comp_t i, output iq_comp_t q
  );
    if (bypass || !qpsk) begin
      // BPSK on I, Q=0
      i = (b0 == 1'b0) ? AMP_BPSK : -AMP_BPSK;
      q = '0;
    end else begin
      unique case ({b1,b0}) // Gray QPSK
        2'b00: begin i =  AMP_QPSK; q =  AMP_QPSK; end // (+,+)
        2'b01: begin i = -AMP_QPSK; q =  AMP_QPSK; end // (-,+)
        2'b11: begin i = -AMP_QPSK; q = -AMP_QPSK; end // (-,-)
        2'b10: begin i =  AMP_QPSK; q = -AMP_QPSK; end // (+,-)
        default: begin i = '0; q = '0; end
      endcase
    end
  endfunction

  // Datapath / handshakes
  always_ff @(posedge clk_bb or negedge rst_n) begin
    if (!rst_n) begin
      bit_buf        <= '0;
      bits_avail     <= 4'd0;
      last_pending   <= 1'b0;

      hold_I         <= '0;
      hold_Q         <= '0;
      hold_last      <= 1'b0;
      hold_valid     <= 1'b0;
      hold_bits_used <= 2'd0;

      st_running     <= 1'b0;
      st_overflow    <= 1'b0;
    end else begin
      // Local soft reset
      if (ctrl_sw_reset) begin
        bit_buf        <= '0;
        bits_avail     <= 4'd0;
        last_pending   <= 1'b0;
        hold_valid     <= 1'b0;
      end

      // Accept an input byte
      if (in_valid && in_ready) begin
        bit_buf      <= in_data;   // LSB-first usage
        bits_avail   <= 4'd8;
        last_pending <= in_last;
      end else if (in_valid && !in_ready) begin
        st_overflow  <= 1'b1;      // upstream violated ready
      end

      // Generate a symbol when possible
      if (!hold_valid && ctrl_enable && (bits_avail >= K)) begin
        iq_comp_t i_tmp, q_tmp;
        logic b0, b1;
        b0 = bit_buf[0];
        b1 = need2 ? bit_buf[1] : 1'b0;

        // $display("[MAPPER] using (b0,b1)=%0d,%0d  bits_avail=%0d  t=%0t", b0, b1, bits_avail, $time);
        map_bits_to_iq(ctrl_bypass, eff_qpsk, b0, b1, i_tmp, q_tmp);

        hold_I         <= i_tmp;
        hold_Q         <= q_tmp;
        hold_bits_used <= K;
        hold_last      <= (last_pending && (bits_avail == K));
        hold_valid     <= 1'b1;
      end

      // Downstream handshake
      if (hold_valid && out_ready) begin
        hold_valid  <= 1'b0;
        // consume bits
        bit_buf     <= bit_buf >> hold_bits_used;
        bits_avail  <= bits_avail - hold_bits_used;
        if (hold_last) last_pending <= 1'b0;
        st_running  <= 1'b1;
      end
    end
  end

  // Synthesis-time sanity
  // synopsys translate_off
  initial begin
    assert(AMP_BPSK == 16'sd32767) else $error("AMP_BPSK must be 32767 (Q1.15)");
    assert(AMP_QPSK == 16'sd23170) else $error("AMP_QPSK should be ~23170 (Q1.15)");
  end
  // synopsys translate_on

endmodule

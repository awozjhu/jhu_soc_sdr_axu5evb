// -----------------------------------------------------------------------------
// diff_encoder.sv (self-contained)
// Differential encoder for DBPSK/DQPSK.
// - AXIS In : phase-increment phasors {I,Q} in Q1.15 (e.g., 0°, ±90°, 180°)
// - AXIS Out: previous_symbol × increment (complex multiply), Q1.15
// - Reset state: prev = (32767, 0). TLAST propagated.
// - AXI-Lite: CTRL [0]=ENABLE, [2]=SW_RESET (prev←(1,0)), [6:4]=MODE (0=DBPSK,1=DQPSK)
//              STATUS [0]=RUNNING
// Notes:
// * No local declarations inside procedural blocks. No SV functions.
// * Fast-path for 0/±90/180° increments to avoid amplitude creep.
// * Generic fixed-point multiply (round + sat) used if inputs are non-axial.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module diff_encoder #(
  parameter logic signed [15:0] ONE_Q15 = 16'sd32767   // +1.0 in Q1.15
)(
  input  logic clk_bb,
  input  logic rst_n,

  // -------- AXIS-like symbols in: {I[15:0],Q[15:0]} (phase increments) ------
  input  logic        in_valid,
  output logic        in_ready,
  input  logic [31:0] in_data,     // {I[15:0], Q[15:0]} signed Q1.15 phasor
  input  logic        in_last,

  // -------- AXIS-like symbols out: {I[15:0],Q[15:0]} ------------------------
  output logic        out_valid,
  input  logic        out_ready,
  output logic [31:0] out_data,    // {I[15:0], Q[15:0]} signed Q1.15
  output logic        out_last,

  // ------------------------- AXI4-Lite (CSR) --------------------------------
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

  // ===========================================================================
  // Types / params
  // ===========================================================================
  typedef logic signed [15:0] iq16_t;
  typedef logic signed [31:0] i32_t;
  typedef logic signed [32:0] i33_t;

  localparam i33_t ROUND_CONST = 33'sd16384;  // 2^14 for Q1.15 rounding

  // ===========================================================================
  // CSRs (AXI-Lite always-ready style, like mapper/slicer)
  // ===========================================================================
  logic        ctrl_enable;
  logic        ctrl_sw_reset;       // one-shot
  logic [2:0]  ctrl_mode;           // 0=DBPSK, 1=DQPSK

  logic        st_running;          // R/W1C

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

      ctrl_enable     <= 1'b0;
      ctrl_sw_reset   <= 1'b0;
      ctrl_mode       <= 3'd1;   // default DQPSK

      st_running      <= 1'b0;
    end else begin
      if (s_axi_awvalid) awaddr_hold <= s_axi_awaddr;
      have_write <= s_axi_awvalid & s_axi_wvalid & ~s_axi_bvalid;
      do_write   <= have_write;

      if (do_write) begin
        unique case (awaddr_hold[7:2]) // word aligned
          6'h00: begin // CTRL
            if (s_axi_wstrb[0]) begin
              ctrl_enable   <= s_axi_wdata[0];
              ctrl_sw_reset <= s_axi_wdata[2];  // self-clears below
              ctrl_mode     <= s_axi_wdata[6:4];
            end
          end
          6'h01: begin // STATUS R/W1C
            if (s_axi_wstrb[0]) begin
              if (s_axi_wdata[0]) st_running <= 1'b0;
            end
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
          6'h00: s_axi_rdata <= {25'd0, ctrl_mode, 1'b0, ctrl_sw_reset, 1'b0, ctrl_enable};
          6'h01: s_axi_rdata <= {31'd0, st_running};
          default: s_axi_rdata <= 32'h0000_0000;
        endcase
        s_axi_rresp  <= 2'b00;
        s_axi_rvalid <= 1'b1;
      end else if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
      end

      if (ctrl_sw_reset) ctrl_sw_reset <= 1'b0; // one-shot
    end
  end

  // ===========================================================================
  // Datapath
  // ===========================================================================
  // Mode
  logic eff_dqpsk;
  always_comb begin
    eff_dqpsk = ctrl_mode[0];
  end

  // State: previous output symbol (Q1.15)
  iq16_t prev_I;
  iq16_t prev_Q;

  // Input unpack (phasor), and DBPSK coercion
  iq16_t in_I_raw;
  iq16_t in_Q_raw;
  iq16_t inc_I;     // effective increment used
  iq16_t inc_Q;

  assign in_I_raw = in_data[31:16];
  assign in_Q_raw = in_data[15:0];

  always_comb begin
    if (eff_dqpsk) begin
      inc_I = in_I_raw;
      inc_Q = in_Q_raw;
    end else begin
      // DBPSK: restrict to ±1 on real axis based on sign of I
      inc_I = in_I_raw[15] ? -ONE_Q15 : ONE_Q15;
      inc_Q = 16'sd0;
    end
  end

  // Fast-path classification for ideal axial phasors
  logic inc_is_p1, inc_is_m1, inc_is_pj, inc_is_mj;
  always_comb begin
    inc_is_p1 = (inc_I ==  ONE_Q15) && (inc_Q == 16'sd0);
    inc_is_m1 = (inc_I == -ONE_Q15) && (inc_Q == 16'sd0);
    inc_is_pj = (inc_I == 16'sd0)    && (inc_Q ==  ONE_Q15);
    inc_is_mj = (inc_I == 16'sd0)    && (inc_Q == -ONE_Q15);
  end

  // Generic complex multiply (prev × inc), fixed-point round & saturate
  // Intermediates (declared at module scope)
  i32_t p_re_re;
  i32_t p_im_im;
  i32_t p_re_im;
  i32_t p_im_re;
  i33_t acc_re;
  i33_t acc_im;
  i33_t acc_re_rnd;
  i33_t acc_im_rnd;
  logic signed [16:0] out_re_17;
  logic signed [16:0] out_im_17;
  iq16_t calc_out_I_generic;
  iq16_t calc_out_Q_generic;

  always_comb begin
    p_re_re = $signed(prev_I) * $signed(inc_I);
    p_im_im = $signed(prev_Q) * $signed(inc_Q);
    p_re_im = $signed(prev_I) * $signed(inc_Q);
    p_im_re = $signed(prev_Q) * $signed(inc_I);

    acc_re = $signed(p_re_re) - $signed(p_im_im);  // 33b guard
    acc_im = $signed(p_re_im) + $signed(p_im_re);

    // Signed round-to-nearest before >> 15:
    // add +2^14 for >=0, add -(2^14) for <0  → (x + sign?(-ROUND_CONST):ROUND_CONST)
    acc_re_rnd = acc_re + (acc_re[32] ? -ROUND_CONST : ROUND_CONST);
    acc_im_rnd = acc_im + (acc_im[32] ? -ROUND_CONST : ROUND_CONST);

    // Arithmetic shift by 15 (Q1.15)
    out_re_17 = acc_re_rnd >>> 15;  // 17 bits to check saturation
    out_im_17 = acc_im_rnd >>> 15;

    // Saturate to 16-bit signed
    if (out_re_17 > 17'sd32767) calc_out_I_generic = 16'sd32767;
    else if (out_re_17 < -17'sd32768) calc_out_I_generic = -16'sd32768;
    else calc_out_I_generic = out_re_17[15:0];

    if (out_im_17 > 17'sd32767) calc_out_Q_generic = 16'sd32767;
    else if (out_im_17 < -17'sd32768) calc_out_Q_generic = -16'sd32768;
    else calc_out_Q_generic = out_im_17[15:0];
  end

  // Fast-path outputs (no multipliers; exact rotations)
  iq16_t calc_out_I_fast;
  iq16_t calc_out_Q_fast;
  logic  use_fast;

  always_comb begin
    use_fast = (inc_is_p1 | inc_is_m1 | inc_is_pj | inc_is_mj);

    // Default hold (won't be used if use_fast=1)
    calc_out_I_fast = prev_I;
    calc_out_Q_fast = prev_Q;

    if (inc_is_p1) begin
      // +1 ∠0° : out = prev
      calc_out_I_fast = prev_I;
      calc_out_Q_fast = prev_Q;
    end else if (inc_is_m1) begin
      // -1 ∠180° : out = -prev
      calc_out_I_fast = -prev_I;
      calc_out_Q_fast = -prev_Q;
    end else if (inc_is_pj) begin
      // +j ∠+90° : out = prev × j = {-prev_Q, +prev_I}
      calc_out_I_fast = -prev_Q;
      calc_out_Q_fast =  prev_I;
    end else if (inc_is_mj) begin
      // -j ∠-90° : out = prev × (-j) = {+prev_Q, -prev_I}
      calc_out_I_fast =  prev_Q;
      calc_out_Q_fast = -prev_I;
    end
  end

  // Output hold regs
  iq16_t hold_I;
  iq16_t hold_Q;
  logic  hold_last;
  logic  hold_valid;

  // Ready/valid
  assign in_ready  = ctrl_enable & (~hold_valid);
  assign out_valid = hold_valid;
  assign out_data  = {hold_I, hold_Q};
  assign out_last  = hold_last;

  // Datapath / handshakes
  always_ff @(posedge clk_bb or negedge rst_n) begin
    if (!rst_n) begin
      prev_I      <= ONE_Q15;  // (1,0)
      prev_Q      <= 16'sd0;

      hold_I      <= '0;
      hold_Q      <= '0;
      hold_last   <= 1'b0;
      hold_valid  <= 1'b0;

      st_running  <= 1'b0;
    end else begin
      // Local soft reset
      if (ctrl_sw_reset) begin
        prev_I     <= ONE_Q15;
        prev_Q     <= 16'sd0;
        hold_valid <= 1'b0;
      end

      // Accept a new phasor increment (one symbol)
      if (in_valid && in_ready) begin
        if (use_fast) begin
          hold_I <= calc_out_I_fast;
          hold_Q <= calc_out_Q_fast;
        end else begin
          hold_I <= calc_out_I_generic;
          hold_Q <= calc_out_Q_generic;
        end
        hold_last  <= in_last;
        hold_valid <= 1'b1;
      end

      // Downstream handshake: commit output and advance state
      if (hold_valid && out_ready) begin
        hold_valid <= 1'b0;
        prev_I     <= hold_I;
        prev_Q     <= hold_Q;
        st_running <= 1'b1;
      end
    end
  end

  // Synthesis-time sanity
  // synopsys translate_off
  initial begin
    assert(ONE_Q15 == 16'sd32767) else $error("ONE_Q15 must be 32767 (Q1.15 +1.0)");
  end
  // synopsys translate_on

endmodule

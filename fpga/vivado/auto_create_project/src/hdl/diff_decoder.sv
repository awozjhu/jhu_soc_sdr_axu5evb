// -----------------------------------------------------------------------------
// diff_decoder.sv  — Differential decoder for DBPSK/DQPSK
//   • AXIS In  : encoded symbols {I[15:0], Q[15:0]} (Q1.15, signed)
//   • AXIS Out : phase increments d[k] = y[k] * conj(y[k-1])  (Q1.15, signed)
//   • Reset state (and SW_RESET): prev_y = (32767, 0) so first output is d[0]=y[0]
//   • TLAST propagated
//   • AXI-Lite CSRs (word-aligned):
//        0x00 CTRL   : [0]=ENABLE, [2]=SW_RESET(one-shot), [6:4]=MODE (0=DBPSK, 1=DQPSK)
//        0x04 STATUS : [0]=RUNNING (R/W1C)
//   • Vivado-friendly coding: no locals inside procedural blocks, no SV functions.
//   • Fast-path when y[k] is exactly {±1,0} or {0,±1} to avoid amplitude creep.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module diff_decoder #(
  parameter logic signed [15:0] ONE_Q15 = 16'sd32767   // +1.0 in Q1.15
)(
  input  logic clk_bb,
  input  logic rst_n,

  // -------- AXIS-like encoded symbols in: {I[15:0], Q[15:0]} ----------------
  input  logic        in_valid,
  output logic        in_ready,
  input  logic [31:0] in_data,     // {I[15:0], Q[15:0]} signed Q1.15
  input  logic        in_last,

  // -------- AXIS-like increments out: {I[15:0], Q[15:0]} --------------------
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
  // Types / temps (module scope)
  // ===========================================================================
  typedef logic signed [15:0] iq16_t;
  typedef logic signed [31:0] i32_t;
  typedef logic signed [32:0] i33_t;

  localparam i33_t ROUND_CONST = 33'sd16384; // 2^14 for round-to-nearest

  // ===========================================================================
  // CSRs — always-ready AXI-Lite
  // ===========================================================================
  logic        ctrl_enable;
  logic        ctrl_sw_reset;       // one-shot
  logic [2:0]  ctrl_mode;           // 0=DBPSK, 1=DQPSK (exposed for symmetry)

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
      do_write   <= have_write; // pulse

      if (do_write) begin
        unique case (awaddr_hold[7:2])
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

      if (ctrl_sw_reset) ctrl_sw_reset <= 1'b0;
    end
  end

  // ===========================================================================
  // Datapath: y[k] * conj(y[k-1])
  // ===========================================================================
  // Previous encoded symbol y[k-1]
  iq16_t prev_I;
  iq16_t prev_Q;

  // Input unpack (encoded y[k])
  iq16_t y_I_in;
  iq16_t y_Q_in;
  assign y_I_in = in_data[31:16];
  assign y_Q_in = in_data[15:0];

  // Fast-path detect when y[k] is exactly axis-aligned
  logic y_is_p1, y_is_m1, y_is_pj, y_is_mj;
  always_comb begin
    y_is_p1 = (y_I_in ==  ONE_Q15) && (y_Q_in == 16'sd0);
    y_is_m1 = (y_I_in == -ONE_Q15) && (y_Q_in == 16'sd0);
    y_is_pj = (y_I_in == 16'sd0)    && (y_Q_in ==  ONE_Q15);
    y_is_mj = (y_I_in == 16'sd0)    && (y_Q_in == -ONE_Q15);
  end

  // Generic complex multiply: d = y * conj(prev)
  // d_re = yI*prevI + yQ*prevQ
  // d_im = yQ*prevI - yI*prevQ
  i32_t p_yI_prevI;
  i32_t p_yQ_prevQ;
  i32_t p_yQ_prevI;
  i32_t p_yI_prevQ;
  i33_t acc_re;
  i33_t acc_im;
  i33_t acc_re_rnd;
  i33_t acc_im_rnd;
  logic signed [16:0] d_re_17;
  logic signed [16:0] d_im_17;
  iq16_t d_I_generic;
  iq16_t d_Q_generic;

  always_comb begin
    p_yI_prevI = $signed(y_I_in) * $signed(prev_I);
    p_yQ_prevQ = $signed(y_Q_in) * $signed(prev_Q);
    p_yQ_prevI = $signed(y_Q_in) * $signed(prev_I);
    p_yI_prevQ = $signed(y_I_in) * $signed(prev_Q);

    acc_re = $signed(p_yI_prevI) + $signed(p_yQ_prevQ);
    acc_im = $signed(p_yQ_prevI) - $signed(p_yI_prevQ);

    acc_re_rnd = acc_re + (acc_re[32] ? -ROUND_CONST : ROUND_CONST);
    acc_im_rnd = acc_im + (acc_im[32] ? -ROUND_CONST : ROUND_CONST);

    d_re_17 = acc_re_rnd >>> 15;
    d_im_17 = acc_im_rnd >>> 15;

    if (d_re_17 > 17'sd32767)       d_I_generic = 16'sd32767;
    else if (d_re_17 < -17'sd32768) d_I_generic = -16'sd32768;
    else                            d_I_generic = d_re_17[15:0];

    if (d_im_17 > 17'sd32767)       d_Q_generic = 16'sd32767;
    else if (d_im_17 < -17'sd32768) d_Q_generic = -16'sd32768;
    else                            d_Q_generic = d_im_17[15:0];
  end

  // Fast-path when y is axis-aligned:
  //  y=+1 : d =  conj(prev)       = { prev_I, -prev_Q}
  //  y=-1 : d = -conj(prev)       = {-prev_I,  prev_Q}
  //  y=+j : d =  j*conj(prev)     = { prev_Q,  prev_I}
  //  y=-j : d = -j*conj(prev)     = {-prev_Q, -prev_I}
  iq16_t d_I_fast;
  iq16_t d_Q_fast;
  logic  use_fast;

  always_comb begin
    use_fast = (y_is_p1 | y_is_m1 | y_is_pj | y_is_mj);

    d_I_fast = prev_I; // default (overwritten below)
    d_Q_fast = prev_Q;

    if (y_is_p1) begin
      d_I_fast =  prev_I;
      d_Q_fast = -prev_Q;
    end else if (y_is_m1) begin
      d_I_fast = -prev_I;
      d_Q_fast =  prev_Q;
    end else if (y_is_pj) begin
      d_I_fast =  prev_Q;
      d_Q_fast =  prev_I;
    end else if (y_is_mj) begin
      d_I_fast = -prev_Q;
      d_Q_fast = -prev_I;
    end
  end

  // Hold registers for one output beat and a latch of y[k] for prev update
  iq16_t hold_I;
  iq16_t hold_Q;
  logic  hold_last;
  logic  hold_valid;

  iq16_t latched_yI;
  iq16_t latched_yQ;

  assign in_ready  = ctrl_enable & (~hold_valid);
  assign out_valid = hold_valid;
  assign out_data  = {hold_I, hold_Q};
  assign out_last  = hold_last;

  // Sequential
  always_ff @(posedge clk_bb or negedge rst_n) begin
    if (!rst_n) begin
      prev_I      <= ONE_Q15;  // y[-1] = (1,0)
      prev_Q      <= 16'sd0;

      hold_I      <= '0;
      hold_Q      <= '0;
      hold_last   <= 1'b0;
      hold_valid  <= 1'b0;

      latched_yI  <= 16'sd0;
      latched_yQ  <= 16'sd0;

      st_running  <= 1'b0;
    end else begin
      // Local soft reset
      if (ctrl_sw_reset) begin
        prev_I     <= ONE_Q15;
        prev_Q     <= 16'sd0;
        hold_valid <= 1'b0;
      end

      // Accept an input symbol and compute d[k]
      if (in_valid && in_ready) begin
        if (use_fast) begin
          hold_I <= d_I_fast;
          hold_Q <= d_Q_fast;
        end else begin
          hold_I <= d_I_generic;
          hold_Q <= d_Q_generic;
        end
        hold_last  <= in_last;
        hold_valid <= 1'b1;

        // Latch y[k] for next-step prev update
        latched_yI <= y_I_in;
        latched_yQ <= y_Q_in;
      end

      // Downstream handshake: commit output and advance prev=y[k]
      if (hold_valid && out_ready) begin
        hold_valid <= 1'b0;
        prev_I     <= latched_yI;
        prev_Q     <= latched_yQ;
        st_running <= 1'b1;
      end
    end
  end

  // synopsys translate_off
  initial begin
    assert(ONE_Q15 == 16'sd32767) else $error("ONE_Q15 must be 32767 (Q1.15 +1.0)");
  end
  // synopsys translate_on

endmodule

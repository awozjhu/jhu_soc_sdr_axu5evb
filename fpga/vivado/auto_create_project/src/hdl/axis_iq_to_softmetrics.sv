`timescale 1ns/1ps

module axis_iq_to_softmetrics #(
  // Total bits per metric (3..5 is typical for Xilinx Viterbi soft width)
  parameter int SOFT_W = 3
)(
  input  logic         clk,
  input  logic         rst_n,

  // AXIS IN  (from diff decoder)
  input  logic [31:0]  s_axis_tdata,   // {I[15:0], Q[15:0]} Q1.15
  input  logic         s_axis_tvalid,
  output logic         s_axis_tready,
  input  logic         s_axis_tlast,

  // AXIS OUT (to Viterbi decoder)
  output logic [15:0]  m_axis_tdata,
  output logic         m_axis_tvalid,
  input  logic         m_axis_tready,
  output logic         m_axis_tlast
);

  // ---------------------------------------------------------------------------
  // Handshake pass-through (no extra cycle)
  // ---------------------------------------------------------------------------
  assign s_axis_tready = m_axis_tready;
  assign m_axis_tvalid = s_axis_tvalid;
  assign m_axis_tlast  = s_axis_tlast;

  // ---------------------------------------------------------------------------
  // Unpack I/Q (signed Q1.15)
  // ---------------------------------------------------------------------------
  logic signed [15:0] i_in;
  logic signed [15:0] q_in;

  assign i_in = s_axis_tdata[31:16];
  assign q_in = s_axis_tdata[15:0];

  // ---------------------------------------------------------------------------
  // Compute |I|, |Q| (unsigned 16-bit)
  // ---------------------------------------------------------------------------
  logic [15:0] abs_i;
  logic [15:0] abs_q;

  always_comb begin
    abs_i = i_in[15] ? (~i_in + 16'd1) : i_in;
    abs_q = q_in[15] ? (~q_in + 16'd1) : q_in;
  end

  // ---------------------------------------------------------------------------
  // Build soft metrics (SIGNED MAGNITUDE)
  //   metric = {sign_bit, magnitude[SOFT_W-2:0]}
  //   sign_bit: 0 = bit '0' (positive), 1 = bit '1' (negative)
  //   magnitude: use MSBs of |I| / |Q| as confidence.
  // ---------------------------------------------------------------------------
  localparam int MAG_W = (SOFT_W > 1) ? (SOFT_W-1) : 1;

  logic [MAG_W-1:0] mag_i, mag_q;
  logic             sign_i, sign_q;
  logic [SOFT_W-1:0] metric_I, metric_Q;

  always_comb begin
    // take the top MAG_W bits as confidence
    mag_i  = abs_i[15 -: MAG_W];
    mag_q  = abs_q[15 -: MAG_W];

    // sign from MSB of I/Q
    sign_i = i_in[15];
    sign_q = q_in[15];

    metric_I = {sign_i, mag_i};
    metric_Q = {sign_q, mag_q};
  end

  // ---------------------------------------------------------------------------
  // Pack into 16-bit Viterbi input.
  // Only lower 2*SOFT_W bits are used; upper bits are zero.
  // Order: { ... , metric_Q, metric_I }
  // ---------------------------------------------------------------------------
  localparam int USED_BITS = 2*SOFT_W;
  localparam int PAD_BITS  = 16 - USED_BITS;

  always_comb begin
    m_axis_tdata = { {PAD_BITS{1'b0}}, metric_Q, metric_I };
  end

  // ---------------------------------------------------------------------------
  // Optional synthesis-time checks
  // ---------------------------------------------------------------------------
  // synopsys translate_off
  initial begin
    if (SOFT_W < 2 || SOFT_W > 8) begin
      $error("axis_iq_to_softmetrics: SOFT_W=%0d is out of expected range", SOFT_W);
    end
  end
  // synopsys translate_on

endmodule

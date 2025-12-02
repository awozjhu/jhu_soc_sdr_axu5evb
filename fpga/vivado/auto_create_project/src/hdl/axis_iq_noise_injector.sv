// -----------------------------------------------------------------------------
// axis_iq_noise_injector.sv
// - AXI-Stream friendly I/Q noise injector
// - Perturbs I/Q in tdata[31:0] = {I[15:0], Q[15:0]}
// - Does NOT change tvalid/tready/tlast timing (no extra cycle).
// -----------------------------------------------------------------------------
module axis_iq_noise_injector #(
  parameter int WIDTH       = 16,  // I/Q width (signed)
  parameter int NOISE_SHIFT = 6    // larger -> smaller noise amplitude
)(
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  enable,

  // AXIS in
  input  logic [31:0]           s_axis_tdata,
  input  logic                  s_axis_tvalid,
  output logic                  s_axis_tready,
  input  logic                  s_axis_tlast,

  // AXIS out
  output logic [31:0]           m_axis_tdata,
  output logic                  m_axis_tvalid,
  input  logic                  m_axis_tready,
  output logic                  m_axis_tlast
);

  // Handshake just passes through
  assign s_axis_tready = m_axis_tready;
  assign m_axis_tvalid = s_axis_tvalid;
  assign m_axis_tlast  = s_axis_tlast;

  // Unpack I/Q as signed
  wire signed [WIDTH-1:0] i_in = s_axis_tdata[31:16];
  wire signed [WIDTH-1:0] q_in = s_axis_tdata[15:0];

  // Simple 8-bit LFSRs
  logic [7:0] lfsr_i, lfsr_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lfsr_i <= 8'hA5;
      lfsr_q <= 8'h3C;
    end else if (enable && s_axis_tvalid && s_axis_tready) begin
      // only step when a symbol actually flows
      lfsr_i <= {lfsr_i[6:0], lfsr_i[7] ^ lfsr_i[5] ^ lfsr_i[4] ^ lfsr_i[3]};
      lfsr_q <= {lfsr_q[6:0], lfsr_q[7] ^ lfsr_q[5] ^ lfsr_q[4] ^ lfsr_q[3]};
    end
  end

  // Convert LFSR to small signed noise and add (purely combinational on data)
  wire signed [WIDTH-1:0] noise_i =
      ( $signed({1'b0, lfsr_i}) - $signed(9'd128) ) >>> NOISE_SHIFT;
  wire signed [WIDTH-1:0] noise_q =
      ( $signed({1'b0, lfsr_q}) - $signed(9'd128) ) >>> NOISE_SHIFT;

  wire signed [WIDTH-1:0] i_noisy = enable ? (i_in + noise_i) : i_in;
  wire signed [WIDTH-1:0] q_noisy = enable ? (q_in + noise_q) : q_in;

  // Repack
  always_comb begin
    m_axis_tdata = {i_noisy, q_noisy};
  end

endmodule

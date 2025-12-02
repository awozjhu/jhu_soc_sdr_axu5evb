// -----------------------------------------------------------------------------
// axis_iq_noise_injector.sv
// - AXI-Stream friendly I/Q "noise" injector that causes real bit errors.
// - tdata[31:0] = {I[15:0], Q[15:0]}, signed Q1.15.
// - Handshake is pass-through: no added cycles, no handshake violations.
// - Two effects:
//     1) Optional small additive noise (like before, for fuzz in constellation).
//     2) Rare sign-bit flips on I and/or Q (forces symbol errors).
// -----------------------------------------------------------------------------
module axis_iq_noise_injector #(
  parameter int WIDTH            = 16,  // signed I/Q width
  parameter int NOISE_SHIFT      = 3,   // larger => smaller additive noise (fuzz)
  parameter int ERROR_RATE_LOG2  = 6    // 1 / 2^N of symbols get a sign flip
)(
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  enable,      // global enable for any noise/errors

  // runtime-programmable threshold (0–255)
  input  logic [7:0]            err_thresh,

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

  // ---------------------------------------------------------------------------
  // Handshake: pure pass-through
  // ---------------------------------------------------------------------------
  assign s_axis_tready = m_axis_tready;
  assign m_axis_tvalid = s_axis_tvalid;
  assign m_axis_tlast  = s_axis_tlast;

  // ---------------------------------------------------------------------------
  // Unpack I/Q as signed
  // ---------------------------------------------------------------------------
  wire signed [WIDTH-1:0] i_in = s_axis_tdata[31:16];
  wire signed [WIDTH-1:0] q_in = s_axis_tdata[15:0];

  // ---------------------------------------------------------------------------
  // Pseudo-random generator (LFSR)
  //   - Only advances when a symbol actually flows (fire).
  // ---------------------------------------------------------------------------
  logic [7:0] lfsr;

  wire fire = s_axis_tvalid && s_axis_tready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lfsr <= 8'hA5;
    end else if (enable && fire) begin
      // x^8 + x^6 + x^5 + x^4 + 1
      lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
    end
  end

  // ---------------------------------------------------------------------------
  // 1) Small additive noise for constellation "fuzz" (optional)
  // ---------------------------------------------------------------------------
  // Convert LFSR to small signed noise and add (combinational).
  // Center around 0 and shift down by NOISE_SHIFT.
  wire signed [WIDTH-1:0] noise_i =
      ( $signed({1'b0, lfsr}) - $signed(9'd128) ) >>> NOISE_SHIFT;
  wire signed [WIDTH-1:0] noise_q =
      ( $signed({1'b0, ~lfsr}) - $signed(9'd128) ) >>> NOISE_SHIFT; // decorrelate a bit

  wire signed [WIDTH-1:0] i_fuzzy = enable ? (i_in + noise_i) : i_in;
  wire signed [WIDTH-1:0] q_fuzzy = enable ? (q_in + noise_q) : q_in;

  // ---------------------------------------------------------------------------
  // 2) Symbol error injection via rare sign-bit flips
  // ---------------------------------------------------------------------------
  // Rough "error event" when the lower ERROR_RATE_LOG2 bits are all zero:
  // probability ≈ 1 / 2^ERROR_RATE_LOG2 when enable & fire.
  localparam int ER_BITS = (ERROR_RATE_LOG2 < 1) ? 1 : ERROR_RATE_LOG2;

  // pick an approximate BER: THRESH / 256
//   localparam int THRESH = 65;  // ~4/256 ≈ 1.5% of symbols corrupted

    wire error_event = enable && fire && (lfsr < err_thresh); // or use THRESH for hardcoded method

  // Use some LFSR bits to decide what to flip on an error event:
  //   lfsr[7] -> flip I sign
  //   lfsr[6] -> flip Q sign
  wire flip_I = error_event && lfsr[7];
  wire flip_Q = error_event && lfsr[6];

  wire signed [WIDTH-1:0] i_err =
      flip_I ? (i_fuzzy ^ ({{(WIDTH-1){1'b0}}, 1'b1} << (WIDTH-1))) : i_fuzzy;

  wire signed [WIDTH-1:0] q_err =
      flip_Q ? (q_fuzzy ^ ({{(WIDTH-1){1'b0}}, 1'b1} << (WIDTH-1))) : q_fuzzy;

  // ---------------------------------------------------------------------------
  // Repack I/Q to output
  // ---------------------------------------------------------------------------
  always_comb begin
    m_axis_tdata = {i_err, q_err};
  end

endmodule

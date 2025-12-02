// -----------------------------------------------------------------------------
// axis_prbs_mon.sv
//
// AXI-Stream PRBS byte monitor / checker.
// - Matches axis_prbs_src (same LFSR logic, same byte construction).
// - Only advances LFSR on a successful handshake (tvalid & tready).
// - Compares received byte to expected PRBS byte.
// - Counts byte errors (optionally bit errors).
// - Outputs expected byte for debug / ILA introspection.
//
// -----------------------------------------------------------------------------


module axis_prbs_mon #(
  // Same polynomial defaults as your PRBS source
  parameter int LFSR_W          = 31,
  parameter int TAP_A           = 30,
  parameter int TAP_B           = 27,
  parameter logic [LFSR_W-1:0] INIT_SEED = {{(LFSR_W-1){1'b0}}, 1'b1}
)(
  input  logic        clk,
  input  logic        rst_n,

  // Enable checking (1 = active, 0 = hold LFSR and counters)
  input  logic        enable,

  // AXI-Stream slave (RX side)
  input  logic [7:0]  s_axis_tdata,
  input  logic        s_axis_tvalid,
  output logic        s_axis_tready,
  input  logic        s_axis_tlast,

  // Expected PRBS byte (for debug / ILA)
  output logic [7:0]  expected_byte,

  // Error counters
  output logic [31:0] byte_error_count,
  output logic [31:0] bit_error_count
);

  // ---------------------------------------------------------------------------
  // LFSR state
  // ---------------------------------------------------------------------------
  logic [LFSR_W-1:0] lfsr_q;

  // Derived next-state function (same as source)
  function automatic logic [LFSR_W-1:0] next_lfsr(
    input logic [LFSR_W-1:0] cur
  );
    logic fb;
    fb        = cur[TAP_A] ^ cur[TAP_B];
    next_lfsr = {cur[LFSR_W-2:0], fb};
  endfunction

  // Build the next PRBS byte (8 LFSR steps, little-endian)
  function automatic logic [7:0] make_byte(
    input logic [LFSR_W-1:0] cur_state,
    output logic [LFSR_W-1:0] new_state
  );
    logic [LFSR_W-1:0] tmp;
    logic [7:0]        b;
    int i;
    begin
      tmp = cur_state;
      b   = '0;
      for (i = 0; i < 8; i++) begin
        b[i] = tmp[0];
        tmp  = next_lfsr(tmp);
      end
      new_state = tmp;
      return b;
    end
  endfunction

  // ---------------------------------------------------------------------------
  // AXIS ready: always accept if enabled
  // ---------------------------------------------------------------------------
  assign s_axis_tready = enable;

  wire fire = s_axis_tvalid && s_axis_tready;

  // ---------------------------------------------------------------------------
  // Sequential: LFSR + comparison + counters
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // Initialize LFSR
      if (INIT_SEED == '0)
        lfsr_q <= {{(LFSR_W-1){1'b0}}, 1'b1};
      else
        lfsr_q <= INIT_SEED;

      byte_error_count <= 32'd0;
      bit_error_count  <= 32'd0;
      expected_byte    <= 8'd0;

    end else if (enable) begin
      if (fire) begin
        // Compute expected byte & advance LFSR
        logic [LFSR_W-1:0] next_l;
        logic [7:0]        exp_b;

        exp_b = make_byte(lfsr_q, next_l);

        expected_byte <= exp_b;
        lfsr_q        <= next_l;

        // Compare against received
        if (exp_b != s_axis_tdata)
          byte_error_count <= byte_error_count + 1;

        // Optional: bit error counter
        bit_error_count <= bit_error_count +
                           $countones(exp_b ^ s_axis_tdata);
      end
    end
  end

endmodule

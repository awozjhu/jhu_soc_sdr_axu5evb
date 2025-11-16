/*------------------------------------------------------------------------------
 * byte_scrambler – 8-bit additive (XOR) scrambler/descrambler (fixed-seed)
 * with TLAST pass-through
 *
 * - Auto-seeds from INIT_SEED on reset (0 coerced to 1).
 * - Adds in_tlast/out_tlast that track the scrambled byte beat.
 * - One-beat elastic buffer; out_* held until accepted (out_ready=1).
 *----------------------------------------------------------------------------*/

module byte_scrambler #(
  parameter int LFSR_W = 7,
  parameter logic [LFSR_W-1:0] TAP_MASK  = 7'b1001000, // x^7 + x^4 + 1 (802.3)
  parameter logic [LFSR_W-1:0] INIT_SEED = 'h1         // non-zero recommended
)(
  input  logic                 clk,
  input  logic                 rst_n,

  // simple stream in (+ TLAST)
  input  logic [7:0]           in_data,
  input  logic                 in_valid,
  input  logic                 in_tlast,   // PRBS frame boundary (TLAST)
  output logic                 in_ready,

  // simple stream out (+ TLAST)
  output logic [7:0]           out_data,
  output logic                 out_valid,
  output logic                 out_tlast,  // forwarded TLAST aligned to out_data
  input  logic                 out_ready,

  // controls
  input  logic                 cfg_enable,
  input  logic                 cfg_bypass,

  output logic                 running_pulse
);

  // Warn if INIT_SEED is zero
  initial begin
    if (INIT_SEED == '0)
      $warning("byte_scrambler: INIT_SEED is 0; will be coerced to 1 at reset.");
  end

  // -----------------------------
  // LFSR step (Fibonacci, shift-right)
  // feedback = s[0] ^ XOR(taps)
  // -----------------------------
  function automatic logic [LFSR_W-1:0] lfsr_step(input logic [LFSR_W-1:0] s);
    logic fb;
    begin
      fb = s[0] ^ ^(s & TAP_MASK);
      return {fb, s[LFSR_W-1:1]};
    end
  endfunction

  // Generate 8 mask bits and the advanced state (bit 0 first in byte)
  function automatic void gen8 (
    input  logic [LFSR_W-1:0] s0,
    output logic [LFSR_W-1:0] s_next,
    output logic [7:0]        mask
  );
    logic [LFSR_W-1:0] s;
    begin
      s = s0;
      for (int i = 0; i < 8; i++) begin
        mask[i] = s[0];
        s       = lfsr_step(s);
      end
      s_next = s;
    end
  endfunction

  // -----------------------------
  // State
  // -----------------------------
  logic [LFSR_W-1:0] lfsr_q, lfsr_next;
  logic [7:0]        mask8;

  logic [7:0]        out_data_q;
  logic              out_valid_q;
  logic              out_tlast_q;

  // Handshake to accept a new input byte into the output register
  wire can_accept = (~out_valid_q) || out_ready;
  wire accept     = cfg_enable && in_valid && can_accept;

  // in_ready: ready when enabled and our output reg isn’t blocking
  assign in_ready   = cfg_enable ? can_accept : 1'b0;

  // out signals
  assign out_data   = out_data_q;
  assign out_valid  = out_valid_q;
  assign out_tlast  = out_tlast_q;

  // running pulse on each accepted byte
  assign running_pulse = accept;

  // -----------------------------
  // Datapath & LFSR update
  // -----------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // Auto-seed from INIT_SEED on reset (coerce 0 → 1)
      lfsr_q      <= (INIT_SEED == '0) ? 'h1 : INIT_SEED;
      out_data_q  <= 8'h00;
      out_valid_q <= 1'b0;
      out_tlast_q <= 1'b0;
    end else begin
      // Consume output when downstream ready
      if (out_valid_q && out_ready) begin
        out_valid_q <= 1'b0;
        out_tlast_q <= 1'b0;
      end

      // Accept a new byte (only when enabled and output slot is free)
      if (accept) begin
        out_tlast_q <= in_tlast; // latch TLAST with the data beat
        if (cfg_bypass) begin
          // Pass-through; hold LFSR state
          out_data_q  <= in_data;
          out_valid_q <= 1'b1;
        end else begin
          // Compute mask and next LFSR, XOR the byte
          gen8(lfsr_q, lfsr_next, mask8);
          out_data_q  <= in_data ^ mask8;
          out_valid_q <= 1'b1;
          lfsr_q      <= lfsr_next;   // advance once per accepted byte
        end
      end
    end
  end

endmodule

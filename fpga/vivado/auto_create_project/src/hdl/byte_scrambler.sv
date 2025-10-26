/*------------------------------------------------------------------------------
 * Module:  byte_scrambler
 * Type:    8-bit parallel additive (XOR) scrambler / descrambler core
 *
 * Summary
 *   Generates an 8-bit scramble mask from an LFSR and XORs it with each input
 *   byte. The LFSR advances exactly once per accepted byte (valid & ready).
 *   A second instance with the same polynomial/seed will perfectly descramble.
 *
 * Interface (simple stream, AXIS-like without sidebands)
 *   in_data[7:0],  in_valid,  in_ready  -> input byte & handshake
 *   out_data[7:0], out_valid, out_ready -> output byte & handshake
 *   cfg_enable     : enable scrambling; gates in_ready/out_valid
 *   cfg_bypass     : pass-through data; LFSR holds its state
 *   cfg_seed_wr    : pulse to load cfg_seed (coerces 0 to 1 to avoid all-zeros)
 *   cfg_seed[LFSR_W-1:0] : non-zero LFSR seed value
 *   running_pulse  : 1-cycle strobe on each accepted byte (for STATUS.RUNNING)
 *
 * Parameters
 *   LFSR_W   : LFSR width (default 7)
 *   TAP_MASK : tap mask for the feedback polynomial *excluding the +1 term*.
 *              Default 7'b1001000 implements x^7 + x^4 + 1 (802.3 style).
 *              In this design:
 *                feedback = s[0] ^ ^(s & TAP_MASK);
 *              i.e., XOR the LFSR output bit (s[0]) with the XOR-reduction of
 *              the tapped stages, then shift-right and insert at MSB.
 *
 * Operation
 *   - On handshake (cfg_enable && !cfg_bypass && in_valid && out_ready):
 *       • Compute mask[7:0] by stepping the LFSR 8 times (bit 0 first).
 *       • out_data = in_data ^ mask.
 *       • Commit the advanced LFSR state (one byte consumed).
 *   - Under stall (in_valid && !out_ready):
 *       • out_data shows the scrambled byte for visibility,
 *         but the LFSR state does not advance until the handshake.
 *   - When disabled or bypassed:
 *       • Pass-through; LFSR holds state.
 *
 * Reset / Seeding
 *   - On reset the LFSR initializes to 'h1 (non-zero).
 *   - Writing cfg_seed with cfg_seed_wr loads a new non-zero seed.
 *   - The all-zeros state is a trap; design prevents loading it.
 *
 * Timing / Latency / Throughput
 *   - 0-cycle data latency, 1:1 beat mapping.
 *   - Sustains 1 byte/cycle when in_valid && out_ready remain high.
 *   - Backpressure propagates via in_ready/out_ready.
 *
 * Notes
 *   - Bit order within a byte is LSB-first: mask[i] scrambles in_data[i].
 *   - Module does not carry TLAST/TKEEP; pass those externally if needed.
 *   - A second instance with identical settings acts as a descrambler when it
 *     sees the same byte handshakes (e.g., src → scrambler → descrambler).
 *   - Fully synthesizable (XORs + flops), no RAM/DSP.
 *----------------------------------------------------------------------------*/


module byte_scrambler #(
  parameter int LFSR_W = 7,                       // 802.3 default
  parameter logic [LFSR_W-1:0] TAP_MASK = 7'b1001000 // taps @ [6] and [3]
)(
  input  logic                 clk,
  input  logic                 rst_n,

  // simple stream in
  input  logic [7:0]           in_data,
  input  logic                 in_valid,
  output logic                 in_ready,

  // simple stream out
  output logic [7:0]           out_data,
  output logic                 out_valid,
  input  logic                 out_ready,

  // AXI4-Lite-mapped controls (hook these to your regfile)
  input  logic                 cfg_enable,   // CTRL[0]
  input  logic                 cfg_bypass,   // CTRL[1]
  input  logic                 cfg_seed_wr,  // pulse when SEED written
  input  logic [LFSR_W-1:0]    cfg_seed,     // non-zero seed

  // status pulse you can OR into STATUS.RUNNING
  output logic                 running_pulse
);

  logic [LFSR_W-1:0] lfsr_q, lfsr_d;
  logic [LFSR_W-1:0] lfsr_adv;
  logic [7:0]        mask8_pre;

  // Accept data only when enabled
  assign in_ready  = cfg_enable ? out_ready : 1'b0;
  assign out_valid = cfg_enable ? in_valid  : 1'b0;

  // 1-step Fibonacci LFSR (shift-right), include s[0] for the +1 term
  function automatic logic [LFSR_W-1:0] step(input logic [LFSR_W-1:0] s);
  logic fb;
  begin
      fb = s[0] ^ ^(s & TAP_MASK);      // <-- include s[0]
      return {fb, s[LFSR_W-1:1]};       // shift right, insert at MSB
  end
  endfunction

  // Generate 8 mask bits and next state (bit 0 first within the byte)
  function automatic void gen8 (
    input  logic [LFSR_W-1:0] s0,
    output logic [LFSR_W-1:0] s_next,
    output logic [7:0]        mask
  );
    logic [LFSR_W-1:0] s;
    begin
      s = s0;
      for (int i=0; i<8; i++) begin
        mask[i] = s[0];
        s       = step(s);
      end
      s_next = s;
    end
  endfunction

  always_comb begin
    // Precompute from current state
    gen8(lfsr_q, lfsr_adv, mask8_pre);

    // Defaults
    lfsr_d  = lfsr_q;

    if (cfg_bypass || !cfg_enable) begin
      out_data = in_data;                // pass-through
    end else begin
      out_data = in_data ^ mask8_pre;    // scrambled view even under stall
      if (in_valid && out_ready) begin
        lfsr_d = lfsr_adv;               // advance only on handshake
      end
    end
  end

  // State & seeding
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lfsr_q <= 'h1;                      // non-zero default
    end else if (cfg_seed_wr) begin
      lfsr_q <= (cfg_seed == '0) ? 'h1 : cfg_seed;
    end else begin
      lfsr_q <= lfsr_d;
    end
  end

  // Running strobe for STATUS.RUNNING
  assign running_pulse = (cfg_enable && in_valid && out_ready);
endmodule

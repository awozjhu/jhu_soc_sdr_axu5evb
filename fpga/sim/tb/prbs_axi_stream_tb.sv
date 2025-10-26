/*------------------------------------------------------------------------------
  PRBS AXI-Stream Generator — Self-checking Testbench (tb_prbs_axi_stream.sv)
  What this TB verifies, how it stimulates the DUT, and how it decides pass/fail
--------------------------------------------------------------------------------

DUT CONTRACT (summarized)
- Interface: AXI4-Lite control/status; AXI-Stream master data.
- Stream format: ALWAYS byte-packed. One LFSR bit per clock goes into the byte
  little-endian (first generated bit → tdata[0], then tdata[1], … tdata[7]).
- Framing: If FRAME_LEN_BYTES==0 → continuous stream (TLAST never asserted).
  If FRAME_LEN_BYTES==N>0 → assert TLAST on the Nth accepted byte of each frame,
  i.e., TLAST is high on the same cycle the last byte handshakes (tvalid&tready).
- STATUS is R/W1C and sticky:
  * RUNNING sets on first accepted transfer while enabled and holds until W1C.
  * DONE sets when a TLAST transfer handshakes and holds until W1C.
- BYTE_COUNT/BIT_COUNT increment ONLY on accepted transfers (tvalid && tready).
- SEED writes zero-coerce to 1 (to avoid an all-zero LFSR lockup).
- MODE selects PRBS7/15/23/31.

TB ARCHITECTURE
1) AXI-Lite BFM (tasks)
   - axil_write(addr, data, wstrb): Drives AW/W together (as the DUT expects),
     waits for OKAY BRESP.
   - axil_read(addr, data_out): Drives AR, waits for RVALID, captures RDATA.
   - ctrl_word(en, mode, swreset, clear): Composes the CTRL register field image.

2) Reference PRBS model (pure SV functions)
   - tapA(mode)/tapB(mode): Encodes the polynomial taps used by the DUT.
     (7→(6,5), 15→(14,13), 23→(22,17), 31→(30,27) mapped to 0-based bit indices.)
   - fb_bit(state, mode): XOR of the two tap bits (Fibonacci LFSR).
   - prbs_next_bit(state, mode): Returns current LSB as the output bit, then
     shifts left and inserts fb_bit at MSB — matches DUT’s orientation.
   - prbs_next_byte(state, mode): Calls prbs_next_bit() eight times, placing
     each successive output bit into the next little-endian position of a byte.
   The reference model advances ONLY when the TB consumes bytes from the DUT.

3) Stream consumer + scoreboard
   - consume_and_check(N, use_random_ready):
       • Drives m_axis_tready either constantly 1 (no stalls) or pseudo-random
         (~75% ready / ~25% stall) to exercise back-pressure.
       • On each accepted byte (tvalid && tready), it:
         - Computes the expected byte using the reference LFSR.
         - Compares tdata to the expected byte.
         - Computes the expected TLAST (= (frame_len_int>0) &&
           ((accepted_bytes+1) % frame_len_int == 0)) and compares to DUT.
         - Updates software counters accepted_bytes/bits for later CSR checks.
       • If any mismatch occurs, $fatal with an informative message.

4) Assertion (optional; guard with `SVA`)
   - p_axis_stable_when_stalled: If the stream is stalled (tvalid && !tready),
     tdata and tlast must hold their values until the stall is released.
     This catches LFSR advancing or TLAST glitching under back-pressure.

5) Test sequencing (four focused scenarios)
   TEST 1 — Continuous mode, PRBS31, random back-pressure
     - Program SEED=1, FRAME_LEN=0 (continuous).
     - CTRL: ENABLE=1, SW_RESET=1 (one-shot), CLEAR=1 (counter clear).
     - Consume 128 bytes with randomized stalls.
     - Read/Check:
         • STATUS.RUNNING must be 1 (sticky set by first handshake).
         • BYTE_COUNT == accepted_bytes; BIT_COUNT == accepted_bits.
     - W1C clear RUNNING (write 1 to bit), verify it clears.

   TEST 2 — Framed mode (FRAME_LEN=16), PRBS31, no stalls
     - Keep MODE/SEED; write FRAME_LEN=16.
     - W1C clear DONE; CLEAR counters (CTRL.CLEAR=1).
     - Consume 48 bytes (3 exact frames) with ready=1.
     - Expect TLAST precisely on byte numbers 16, 32, 48.
     - STATUS.DONE must be 1 (sticky set by TLAST handshake), then W1C clear.

   TEST 3 — PRBS7, FRAME_LEN=8, random back-pressure, zero-seed coercion
     - Write SEED=0 to exercise zero-coerce → DUT should behave as SEED=1.
     - Set FRAME_LEN=8, CTRL: ENABLE=1, SW_RESET=1, CLEAR=1.
     - Consume 40 bytes (≈5 frames) with stalls.
     - Check BYTE_COUNT/BIT_COUNT against software counters.

   TEST 4 — PRBS15, continuous (FRAME_LEN=0), no stalls
     - Re-seed to 1, set MODE=PRBS15, FRAME_LEN=0, SW_RESET+CLEAR.
     - Consume 32 bytes, verify no TLAST assertions occur.

   Each test prints a fatal on the first discrepancy; otherwise, the TB prints
   “*** ALL TESTS PASSED ***” at the end.

KEY IMPLEMENTATION DETAILS THAT THE TB EXERCISES
- Little-endian packing inside each byte: The scoreboard’s reference byte is
  built with bit[0] = first generated PRBS bit, matching the DUT’s packer.
- Exact TLAST cycle: The TB checks TLAST on the same cycle as data handshake.
  This implicitly verifies the DUT computes `last_q` when the byte is produced
  and holds it stable until consumed (no “one-cycle late” bugs).
- Framing edge-cases:
  * FRAME_LEN=0 → TLAST is permanently 0; DONE should never set.
  * Switching from continuous to framed (0→N) mid-run: TEST 2 programs
    FRAME_LEN then starts consuming; the TB expects the first TLAST on the Nth
    accepted byte after that point (not N+1).
- Sticky STATUS semantics: RUNNING set on first handshake; DONE set only on a
  TLAST handshake; both clear with W1C writes and on SW_RESET.
- Counter semantics: The TB compares hardware counters against a “ground truth”
  count based solely on handshakes (tvalid && tready). Back-pressure patterns
  ensure counts would diverge if the DUT incremented on tvalid alone.
- Zero-seed coercion: TEST 3 writes SEED=0 and expects deterministic behavior
  identical to SEED=1.
- XSim-friendly style: The TB declares locals at block tops (no mid-block decls)
  and avoids exotic casts; SVA can be disabled by not defining `SVA`.

WHAT TO PROBE IF SOMETHING FAILS
- Stream: m_axis_tvalid/tready/tdata/tlast.
- Framing: last_q (internal), frame_cnt_q.
- LFSR path: lfsr_q[0], feedback_bit, bit_cnt, byte_shift.
- Events & status: fire (tvalid&&tready), st_running, st_done, BYTE_COUNT, BIT_COUNT.

EXPECTED OUTPUT
- During failures: $fatal messages like
    “TLAST mismatch @byte XX: got Y exp Z (frame_len=N)”
  which include enough context to locate the bug quickly.
- On success: a final banner
    *** ALL TESTS PASSED ***
  and normal simulator completion.

-------------------------------------------------------------------------------
*/


`timescale 1ns/1ps

module tb_prbs_axi_stream;

  // -----------------------------
  // Clock / Reset
  // -----------------------------
  logic clk = 0;
  always #5 clk = ~clk; // 100 MHz

  logic rst_n = 0;
  initial begin
    rst_n = 0;
    repeat (10) @(posedge clk);
    rst_n = 1;
  end

  // -----------------------------
  // DUT I/O
  // -----------------------------
  // AXI-Lite
  logic [5:0]  s_axil_awaddr;
  logic        s_axil_awvalid;
  logic        s_axil_awready;
  logic [31:0] s_axil_wdata;
  logic [3:0]  s_axil_wstrb;
  logic        s_axil_wvalid;
  logic        s_axil_wready;
  logic [1:0]  s_axil_bresp;
  logic        s_axil_bvalid;
  logic        s_axil_bready;
  logic [5:0]  s_axil_araddr;
  logic        s_axil_arvalid;
  logic        s_axil_arready;
  logic [31:0] s_axil_rdata;
  logic [1:0]  s_axil_rresp;
  logic        s_axil_rvalid;
  logic        s_axil_rready;

  // AXI-Stream
  logic [7:0]  m_axis_tdata;
  logic        m_axis_tvalid;
  logic        m_axis_tready;
  logic        m_axis_tlast;

//-----------------------------
// Byte Scrambler I/O (for instantiation test)
// -----------------------------
logic        in_ready;          // PRBS backpressure (to tready)

logic [7:0]  out_data;          // scrambler → descrambler
logic        out_valid;
logic        out_ready;

logic [7:0]  dsc_data;          // descrambler → sink/scoreboard
logic        dsc_valid;
logic        dsc_ready;

assign dsc_ready = 1'b1;        // always-accept sink for now


  // -----------------------------
  // Instantiate DUT PRBS (AXI-Stream source)
  // -----------------------------
  prbs_axi_stream dut (
    .clk(clk),
    .rst_n(rst_n),

    .s_axil_awaddr (s_axil_awaddr),
    .s_axil_awvalid(s_axil_awvalid),
    .s_axil_awready(s_axil_awready),
    .s_axil_wdata  (s_axil_wdata),
    .s_axil_wstrb  (s_axil_wstrb),
    .s_axil_wvalid (s_axil_wvalid),
    .s_axil_wready (s_axil_wready),
    .s_axil_bresp  (s_axil_bresp),
    .s_axil_bvalid (s_axil_bvalid),
    .s_axil_bready (s_axil_bready),
    .s_axil_araddr (s_axil_araddr),
    .s_axil_arvalid(s_axil_arvalid),
    .s_axil_arready(s_axil_arready),
    .s_axil_rdata  (s_axil_rdata),
    .s_axil_rresp  (s_axil_rresp),
    .s_axil_rvalid (s_axil_rvalid),
    .s_axil_rready (s_axil_rready),

    .m_axis_tdata (m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    // .m_axis_tready(m_axis_tready),
    .m_axis_tready(in_ready), // connect to byte_scrambler input ready
    .m_axis_tlast (m_axis_tlast)
  );

// Optional: propagate tlast straight through (no latency inside scrambler/descrambler)
logic final_tlast;
assign final_tlast = m_axis_tlast;

// -------------------------
// Scrambler
// -------------------------
byte_scrambler #(
  .LFSR_W  (7),
  .TAP_MASK(7'b1001000)
) u_scrambler (
  .clk         (clk),
  .rst_n       (rst_n),

  // simple stream in (from PRBS AXIS)
  .in_data     (m_axis_tdata),
  .in_valid    (m_axis_tvalid),
  .in_ready    (in_ready),        // drives PRBS tready

  // simple stream out (to descrambler)
  .out_data    (out_data),
  .out_valid   (out_valid),
  .out_ready   (out_ready),       // will be driven by descrambler.in_ready

  // AXI4-Lite-mapped controls (tied for bring-up)
  .cfg_enable  (1'b1),
  .cfg_bypass  (1'b0),
  .cfg_seed_wr (1'b0),
  .cfg_seed    ('0),

  .running_pulse()
);

// -------------------------
// Descrambler (identical core)
// -------------------------
byte_scrambler #(
  .LFSR_W  (7),
  .TAP_MASK(7'b1001000)
) u_descrambler (
  .clk         (clk),
  .rst_n       (rst_n),

  // simple stream in (from scrambler)
  .in_data     (out_data),
  .in_valid    (out_valid),
  .in_ready    (out_ready),       // backpressure to scrambler

  // simple stream out (to sink/scoreboard)
  .out_data    (dsc_data),
  .out_valid   (dsc_valid),
  .out_ready   (dsc_ready),

  // AXI4-Lite-mapped controls (same settings & seed behavior)
  .cfg_enable  (1'b1),
  .cfg_bypass  (1'b0),
  .cfg_seed_wr (1'b0),
  .cfg_seed    ('0),

  .running_pulse()
);

// -------------------------
// (Optional) quick check in TB:
// Compare descrambled data to PRBS source on each accepted beat.
// Enable once your TB has a clock/reset in place.
// -------------------------
always_ff @(posedge clk) if (rst_n && dsc_valid && dsc_ready)
  assert(dsc_data == m_axis_tdata)
    else $fatal(1, "Descrambler mismatch at %t", $time);


  // -----------------------------
  // AXI-Lite helpers
  // -----------------------------
  localparam CTRL_ADDR      = 6'h00;
  localparam STATUS_ADDR    = 6'h04;
  localparam SEED_ADDR      = 6'h08;
  localparam FRMLEN_ADDR    = 6'h0C;
  localparam BYTECOUNT_ADDR = 6'h18;
  localparam BITCOUNT_ADDR  = 6'h1C;

  // CTRL bits
  localparam CTRL_EN_BIT    = 0;
  localparam CTRL_SWRESET   = 2;
  localparam CTRL_MODE_HI   = 6;
  localparam CTRL_MODE_LO   = 4;
  localparam CTRL_CLEAR     = 15;

  // STATUS bits (R/W1C)
  localparam ST_RUNNING_BIT = 0;
  localparam ST_OVUN_BIT    = 2;
  localparam ST_DONE_BIT    = 8;

  task automatic axil_write(input [5:0] addr, input [31:0] data, input [3:0] wstrb = 4'hF);
    begin : t_axil_write
      @(posedge clk);
      s_axil_awaddr  <= addr;
      s_axil_awvalid <= 1'b1;
      s_axil_wdata   <= data;
      s_axil_wstrb   <= wstrb;
      s_axil_wvalid  <= 1'b1;
      s_axil_bready  <= 1'b1;

      // Accept when both AW and W valid
      wait (s_axil_awvalid && s_axil_awready && s_axil_wvalid && s_axil_wready);
      @(posedge clk);
      s_axil_awvalid <= 1'b0;
      s_axil_wvalid  <= 1'b0;

      // Wait for OKAY
      wait (s_axil_bvalid);
      @(posedge clk);
      s_axil_bready  <= 1'b0;
    end
  endtask

  task automatic axil_read(input [5:0] addr, output [31:0] data);
    begin : t_axil_read
      @(posedge clk);
      s_axil_araddr  <= addr;
      s_axil_arvalid <= 1'b1;
      s_axil_rready  <= 1'b1;

      wait (s_axil_arvalid && s_axil_arready);
      @(posedge clk);
      s_axil_arvalid <= 1'b0;

      wait (s_axil_rvalid);
      data = s_axil_rdata;
      @(posedge clk);
      s_axil_rready <= 1'b0;
    end
  endtask

  // Compose CTRL word
  function automatic [31:0] ctrl_word(input bit en, input [2:0] mode, input bit swreset, input bit clear);
    reg [31:0] tmp;
    begin
      tmp = 32'd0;
      tmp[CTRL_EN_BIT] = en;
      tmp[CTRL_SWRESET] = swreset;
      tmp[CTRL_MODE_HI:CTRL_MODE_LO] = mode;
      tmp[CTRL_CLEAR] = clear;
      ctrl_word = tmp;
    end
  endfunction

  // -----------------------------
  // PRBS reference model
  // -----------------------------
  function automatic [5:0] tapA(input [2:0] mode);
    case (mode)
      3'd0: tapA = 6'd5;    // PRBS7: (6,5) -> 5
      3'd1: tapA = 6'd13;   // PRBS15: (14,13) -> 13
      3'd2: tapA = 6'd21;   // PRBS23: (22,17) -> 21
      default: tapA = 6'd29;// PRBS31: (30,27) -> 29
    endcase
  endfunction

  function automatic [5:0] tapB(input [2:0] mode);
    case (mode)
      3'd0: tapB = 6'd4;    // PRBS7
      3'd1: tapB = 6'd12;   // PRBS15
      3'd2: tapB = 6'd16;   // PRBS23
      default: tapB = 6'd26;// PRBS31
    endcase
  endfunction

  function automatic bit fb_bit(input logic [30:0] s, input [2:0] mode);
    fb_bit = s[tapA(mode)] ^ s[tapB(mode)];
  endfunction

  // Advance one bit; return output bit (LSB before shift)
  function automatic bit prbs_next_bit(ref logic [30:0] s, input [2:0] mode);
    bit out;
    out = s[0];
    s = {s[29:0], fb_bit(s, mode)};
    return out;
  endfunction

  // Generate next byte (little-endian: first bit -> bit0)
  function automatic [7:0] prbs_next_byte(ref logic [30:0] s, input [2:0] mode);
    reg [7:0] b;
    begin
      b = 8'd0;
      for (int i = 0; i < 8; i++) begin
        b[i] = prbs_next_bit(s, mode);
      end
      prbs_next_byte = b;
    end
  endfunction

  // -----------------------------
  // Ready driver & scoreboard
  // -----------------------------
  int accepted_bytes;
  int accepted_bits;
  int unsigned frame_len_int;   // 0 => continuous (for math)
  logic [15:0] frame_len16;     // for register writes
  logic [30:0] ref_state;
  logic [2:0]  cur_mode;
  logic [31:0] rd;              // readback scratch

  function automatic bit rand_ready();
    // ~75% ready, ~25% stall
    rand_ready = ($urandom_range(0,3) != 0);
  endfunction

  // Consume N bytes, checking data & TLAST
  task automatic consume_and_check(input int N, input bit use_random_ready);
    int i;
    logic [7:0] exp_b;
    bit         exp_last;
    begin
      i = 0;
      while (i < N) begin
        @(posedge clk);
        m_axis_tready <= use_random_ready ? rand_ready() : 1'b1;

        if (m_axis_tvalid && m_axis_tready) begin
          // Compare data byte
          exp_b = prbs_next_byte(ref_state, cur_mode);
          if (m_axis_tdata !== exp_b) begin
            $fatal(1, "Data mismatch @byte %0d: got 0x%02x exp 0x%02x (mode %0d)",
                   accepted_bytes, m_axis_tdata, exp_b, cur_mode);
          end

          // TLAST expectation
          exp_last = (frame_len_int > 0) ? (((accepted_bytes + 1) % frame_len_int) == 0) : 1'b0;
          if (m_axis_tlast !== exp_last) begin
            $fatal(1, "TLAST mismatch @byte %0d: got %0b exp %0b (frame_len=%0d)",
                   accepted_bytes, m_axis_tlast, exp_last, frame_len_int);
          end

          accepted_bytes++;
          accepted_bits += 8;
          i++;
        end
      end
      @(posedge clk);
      m_axis_tready <= 1'b0;
    end
  endtask

  // -----------------------------
  // Assertions: stability under back-pressure
  // -----------------------------
`ifdef SVA
  property p_axis_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
      (m_axis_tvalid && !m_axis_tready) |=> (m_axis_tdata == $past(m_axis_tdata) && m_axis_tlast == $past(m_axis_tlast));
  endproperty
  assert property (p_axis_stable_when_stalled) else
    $fatal(1, "AXIS changed while stalled");
`endif

  // -----------------------------
  // Test sequence
  // -----------------------------
  initial begin : main
    // Init AXI-Lite master defaults
    s_axil_awaddr  = '0; s_axil_awvalid = 0;
    s_axil_wdata   = '0; s_axil_wstrb   = 4'h0; s_axil_wvalid = 0;
    s_axil_bready  = 0;
    s_axil_araddr  = '0; s_axil_arvalid = 0;
    s_axil_rready  = 0;

    // AXIS ready low initially
    m_axis_tready = 0;

    // Wait reset
    wait (rst_n);
    @(posedge clk);

    // -------------------------
    // TEST 1: Continuous stream, PRBS31, counters & RUNNING
    // -------------------------
    cur_mode       = 3'd3;           // PRBS31
    frame_len_int  = 0;              // continuous
    frame_len16    = 16'd0;
    ref_state      = 31'd1;          // expected start (coercion path covered later)
    accepted_bytes = 0; accepted_bits = 0;

    // Program SEED, FRAME_LEN, CTRL (with SW_RESET pulse + CLEAR)
    axil_write(SEED_ADDR, {1'b0, 31'd1});
    axil_write(FRMLEN_ADDR, {16'd0, frame_len16});
    axil_write(CTRL_ADDR, ctrl_word(1'b1, cur_mode, 1'b1, 1'b1));

    // Consume 128 bytes with random back-pressure
    consume_and_check(128, /*random_ready*/ 1'b1);

    // Check RUNNING sticky and counters
    axil_read(STATUS_ADDR, rd);
    if (rd[ST_RUNNING_BIT] !== 1'b1)
      $fatal(1, "RUNNING sticky not set after streaming");
    axil_read(BYTECOUNT_ADDR, rd);
    if (rd !== accepted_bytes) $fatal(1, "BYTE_COUNT mismatch: got %0d exp %0d", rd, accepted_bytes);
    axil_read(BITCOUNT_ADDR, rd);
    if (rd !== accepted_bits)  $fatal(1, "BIT_COUNT mismatch: got %0d exp %0d", rd, accepted_bits);

    // W1C clear RUNNING, verify clears
    axil_write(STATUS_ADDR, (32'h1 << ST_RUNNING_BIT));
    axil_read(STATUS_ADDR, rd);
    if (rd[ST_RUNNING_BIT] !== 1'b0)
      $fatal(1, "RUNNING W1C did not clear");

    // -------------------------
    // TEST 2: Framed stream (TLAST), PRBS31, fixed ready=1
    // -------------------------
    frame_len_int  = 16;
    frame_len16    = 16'(frame_len_int);
    // Keep LFSR state; just set frame length, clear DONE and counters
    axil_write(FRMLEN_ADDR, {16'd0, frame_len16});
    axil_write(STATUS_ADDR, (32'h1 << ST_DONE_BIT)); // clear DONE
    axil_write(CTRL_ADDR,   ctrl_word(1'b1, cur_mode, 1'b0, 1'b1)); // CLEAR=1

    // Consume exactly 3 frames (48 bytes), ready=1
    consume_and_check(48, /*random_ready*/ 1'b0);
    // repeat (2) @(posedge clk);

    // DONE should be sticky high
    axil_read(STATUS_ADDR, rd);
    if (rd[ST_DONE_BIT] !== 1'b1)
      $fatal(1, "STATUS.DONE not set after frame end");
    // W1C clear DONE
    axil_write(STATUS_ADDR, (32'h1 << ST_DONE_BIT));
    axil_read(STATUS_ADDR, rd);
    if (rd[ST_DONE_BIT] !== 1'b0)
      $fatal(1, "STATUS.DONE did not clear on W1C");

    // -------------------------
    // TEST 3: Mode switch to PRBS7, small frames, random backpressure
    // -------------------------
    cur_mode       = 3'd0; // PRBS7
    frame_len_int  = 8;
    frame_len16    = 16'(frame_len_int);
    // Re-seed to 0 to test zero-coercion (DUT coerces to 1)
    axil_write(SEED_ADDR, {1'b0, 31'd0});
    ref_state      = 31'd1;
    accepted_bytes = 0; accepted_bits = 0;

    axil_write(FRMLEN_ADDR, {16'd0, frame_len16});
    axil_write(CTRL_ADDR,   ctrl_word(1'b1, cur_mode, 1'b1, 1'b1)); // SW_RESET+CLEAR

    // 40 bytes (~5 frames) with random stalls
    consume_and_check(40, /*random_ready*/ 1'b1);

    // Check counters again
    axil_read(BYTECOUNT_ADDR, rd);
    if (rd !== accepted_bytes) $fatal(1, "BYTE_COUNT mismatch (PRBS7): got %0d exp %0d", rd, accepted_bytes);
    axil_read(BITCOUNT_ADDR, rd);
    if (rd !== accepted_bits)  $fatal(1, "BIT_COUNT mismatch (PRBS7): got %0d exp %0d", rd, accepted_bits);

    // -------------------------
    // TEST 4: PRBS15 short burst, continuous mode (no TLAST)
    // -------------------------
    cur_mode       = 3'd1; // PRBS15
    frame_len_int  = 0;
    frame_len16    = 16'd0;
    axil_write(SEED_ADDR, {1'b0, 31'h1});
    ref_state      = 31'h1;
    accepted_bytes = 0; accepted_bits = 0;

    axil_write(FRMLEN_ADDR, {16'd0, frame_len16});
    axil_write(CTRL_ADDR,   ctrl_word(1'b1, cur_mode, 1'b1, 1'b1));

    // Consume 32 bytes, verify no tlast
    consume_and_check(32, /*random_ready*/ 1'b0);

    $display("\n*** ALL TESTS PASSED ***\n");
    #50 $finish;
  end

endmodule

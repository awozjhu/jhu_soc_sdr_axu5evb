// -----------------------------------------------------------------------------
// Module: PreambleInserter
// Purpose:
//   Inserts a fixed QPSK preamble of length PREAMBLE_LEN (symbols) at the
//   *start of each frame* before forwarding the payload. Frames are delineated
//   by the upstream TLAST on the payload stream.
//
// Interface (AXI4-Stream):
//   - Slave  (s_axis_*): payload source (QPSK symbols, 32b {I[15:0],Q[15:0]})
//   - Master (m_axis_*): to next stage (preamble + payload)
//
// AXI4-Stream Handshake Rules (followed here strictly):
//   - Transfer occurs on a cycle only when TVALID && TREADY == 1.
//   - Master (us) holds TVALID high and keeps TDATA/TLAST *stable* until sink
//     raises TREADY and the transfer completes.
//   - Slave side (our s_axis_*) must not consume data unless we raise TREADY,
//     and only on a handshake.
//
// High-level behavior:
//   1) IDLE:
//        *Wait ready* for the first payload beat of a new frame.
//        On handshake, we CAPTURE that first beat (hold registers)
//        and then move to INSERT.
//   2) INSERT:
//        Emit PREAMBLE_LEN symbols from ROM (no TLAST), stalling payload input.
//   3) FORWARD_HOLD:
//        Output the captured first payload beat (with backpressure).
//        If that beat had TLAST, frame ends immediately (tiny frame).
//   4) FORWARD_PASS:
//        Transparent pass-through for the remainder of the payload until TLAST.
//        Back to IDLE.
// -----------------------------------------------------------------------------
module PreambleInserter #(
    parameter int PREAMBLE_LEN = 64
) (
    input  logic          aclk,
    input  logic          aresetn,

    // AXI4-Stream slave input (payload source)
    input  logic          s_axis_tvalid,
    output logic          s_axis_tready,
    input  logic [31:0]   s_axis_tdata,   // {I[15:0], Q[15:0]} in Q1.15
    input  logic          s_axis_tlast,   // payload end-of-frame

    // AXI4-Stream master output (to next stage)
    output logic          m_axis_tvalid,
    input  logic          m_axis_tready,
    output logic [31:0]   m_axis_tdata,   // {I[15:0], Q[15:0]} in Q1.15
    output logic          m_axis_tlast    // end-of-frame (from payload only)
);

    // -----------------------------
    // PREAMBLE ROM (Q1.15 QPSK)
    //   32-bit word packs I then Q: {I[15:0], Q[15:0]}
    //   Sequence cycles: (+,+), (+,−), (−,+), (−,−)
    //   P ≈ +0.7071, N ≈ −0.7071
    // -----------------------------
    localparam logic [15:0] P = 16'h5A82; // +0.7071 -> +23170
    localparam logic [15:0] N = 16'hA57E; // -0.7071 -> -23170

    logic [31:0] preamble_mem [0:PREAMBLE_LEN-1];

    initial begin : init_preamble
        // Repeat the 4-point QPSK pattern to fill PREAMBLE_LEN entries.
        for (int i = 0; i < PREAMBLE_LEN; i++) begin
            unique case (i % 4)
                0: preamble_mem[i] = {P, P};
                1: preamble_mem[i] = {P, N};
                2: preamble_mem[i] = {N, P};
                default: preamble_mem[i] = {N, N};
            endcase
        end
    end

    // -----------------------------
    // FSM & Bookkeeping
    // -----------------------------
    typedef enum logic [1:0] {
        IDLE,          // waiting & capturing first payload beat
        INSERT,        // emitting preamble (no TLAST)
        FORWARD_HOLD,  // output the captured first beat
        FORWARD_PASS   // transparent pass-through for rest of frame
    } state_t;

    state_t state, next_state;

    // Counter width derived from preamble length
    localparam int CNT_W = (PREAMBLE_LEN <= 1) ? 1 : $clog2(PREAMBLE_LEN);
    logic [CNT_W-1:0] preamble_count; // counts accepted preamble symbols

    // First payload beat captured at SOF
    logic [31:0] hold_data;
    logic        hold_last;
    logic        hold_valid;

    // ----------------------------------------
    // Sequential: state, counters, and holding
    // ----------------------------------------
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state           <= IDLE;
            preamble_count  <= '0;
            hold_data       <= '0;
            hold_last       <= 1'b0;
            hold_valid      <= 1'b0;
        end else begin
            state <= next_state;

            // Count accepted preamble beats (only on handshake)
            if (state == INSERT && m_axis_tvalid && m_axis_tready)
                preamble_count <= preamble_count + 1'b1;

            // Reset counter when entering INSERT
            if (state != INSERT && next_state == INSERT)
                preamble_count <= '0;

            // Capture first payload beat at frame start (SOF) on handshake
            if (state == IDLE && s_axis_tvalid && s_axis_tready) begin
                hold_data  <= s_axis_tdata;
                hold_last  <= s_axis_tlast;
                hold_valid <= 1'b1;
            end

            // After we successfully output the held beat, clear the flag
            if (state == FORWARD_HOLD && m_axis_tvalid && m_axis_tready)
                hold_valid <= 1'b0;
        end
    end

    // ----------------------------------------
    // Combinational: outputs & next-state
    // ----------------------------------------
    always_comb begin
        // Defaults
        s_axis_tready = 1'b0;
        m_axis_tvalid = 1'b0;
        m_axis_tdata  = 32'h0000_0000;
        m_axis_tlast  = 1'b0;
        next_state    = state;

        unique case (state)

            // -------------------------------------------------
            // IDLE
            //   - We ASSERT s_axis_tready to avoid deadlock with
            //     "polite" masters that only drive TVALID when TREADY=1.
            //   - On handshake, we CAPTURE the first payload beat to
            //     hold while we emit the preamble.
            // -------------------------------------------------
            IDLE: begin
                s_axis_tready = 1'b1; // FIX: was 0 → could deadlock with polite masters
                if (s_axis_tvalid) begin
                    // handshake implied by TREADY=1
                    next_state = INSERT;
                end
            end

            // -------------------------------------------------
            // INSERT
            //   - Emit preamble from ROM (no TLAST).
            //   - Stall the payload input (s_axis_tready=0).
            //   - Honor backpressure on the master side: hold the same
            //     preamble word until m_axis_tready goes high.
            // -------------------------------------------------
            INSERT: begin
                s_axis_tready = 1'b0;              // hold off payload until preamble sent
                m_axis_tvalid = 1'b1;              // always have preamble to send
                m_axis_tdata  = preamble_mem[preamble_count];
                m_axis_tlast  = 1'b0;              // preamble never asserts TLAST

                if (m_axis_tready) begin
                    if (preamble_count == PREAMBLE_LEN-1) begin
                        // last preamble symbol accepted; next beat to output is the held payload
                        next_state = FORWARD_HOLD;
                    end
                end
            end

            // -------------------------------------------------
            // FORWARD_HOLD
            //   - Output the captured first payload beat (the one that
            //     triggered us to start the preamble).
            //   - Only after that beat is accepted do we start draining
            //     the live payload stream.
            // -------------------------------------------------
            FORWARD_HOLD: begin
                m_axis_tvalid = hold_valid;        // present held beat
                m_axis_tdata  = hold_data;
                m_axis_tlast  = hold_last;

                // Drain input only *after* we emitted the held beat
                s_axis_tready = m_axis_tready && !hold_valid;

                if (m_axis_tready && hold_valid) begin
                    // If the frame was a single-beat frame, we're done
                    next_state = hold_last ? IDLE : FORWARD_PASS;
                end
            end

            // -------------------------------------------------
            // FORWARD_PASS
            //   - Transparent pass-through of the remainder of payload.
            //   - Backpressure propagates naturally (TREADY mirrors).
            // -------------------------------------------------
            FORWARD_PASS: begin
                s_axis_tready = m_axis_tready;
                m_axis_tvalid = s_axis_tvalid;
                m_axis_tdata  = s_axis_tdata;
                m_axis_tlast  = s_axis_tlast;

                if (s_axis_tvalid && m_axis_tready && s_axis_tlast)
                    next_state = IDLE; // frame complete
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule

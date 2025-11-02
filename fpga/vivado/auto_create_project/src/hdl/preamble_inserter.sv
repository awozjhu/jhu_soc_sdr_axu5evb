module PreambleInserter #(
    parameter int PREAMBLE_LEN = 64
) (
    input  logic          aclk,
    input  logic          aresetn,
    // AXI4-Stream slave input (payload source)
    input  logic          s_axis_tvalid,
    output logic          s_axis_tready,
    input  logic [31:0]   s_axis_tdata,
    input  logic          s_axis_tlast,
    // AXI4-Stream master output (to next stage)
    output logic          m_axis_tvalid,
    input  logic          m_axis_tready,
    output logic [31:0]   m_axis_tdata,
    output logic          m_axis_tlast
);

    // ** Preamble ROM ** – 64 complex QPSK symbols in Q1.15 format (I and Q each 16-bit).
    // Each 32-bit entry: {I[15:0], Q[15:0]}.

    // Unit-power QPSK magnitude (≈ 1/√2 in Q1.15)
    localparam logic [15:0] P = 16'h5A82; // +0.7071 -> +23170
    localparam logic [15:0] N = 16'hA57E; // -0.7071 -> -23170

    // Procedural ROM so we don't have to list 64 items by hand
    logic [31:0] preamble_mem [0:PREAMBLE_LEN-1];

    initial begin : init_preamble
    // Simple repeating QPSK sequence: {+,+}, {+,-}, {-,+}, {-,-}
    // Repeat to fill PREAMBLE_LEN entries.
    for (int i = 0; i < PREAMBLE_LEN; i++) begin
        unique case (i % 4)
        0: preamble_mem[i] = {P, P};
        1: preamble_mem[i] = {P, N};
        2: preamble_mem[i] = {N, P};
        default: preamble_mem[i] = {N, N};
        endcase
    end
    end

    // When driving output during INSERT, use preamble_mem
    // m_axis_tdata = preamble_mem[preamble_count];


    // ** FSM State Definition **
    typedef enum logic [1:0] { IDLE=2'b00, INSERT=2'b01, FORWARD=2'b10 } state_t;
    state_t state, next_state;
    logic [5:0] preamble_count;  // Counter for preamble symbols (0 to 63)

    // Sequential logic: state and counter update on clock
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state <= IDLE;
            preamble_count <= 6'd0;
        end else begin
            state <= next_state;
            // On entering INSERT state, reset the preamble counter
            if (state == IDLE && next_state == INSERT) begin
                preamble_count <= 6'd0;
            end 
            // While in INSERT, increment counter on each accepted beat
            else if (state == INSERT && m_axis_tvalid && m_axis_tready) begin
                preamble_count <= preamble_count + 6'd1;
            end
            // (No special handling needed for leaving FORWARD; counter is only for preamble)
        end
    end

    // Combinational logic: next state decisions and output signals
    always_comb begin
        // Default outputs (may be overridden in each state)
        s_axis_tready = 1'b0;
        m_axis_tvalid = 1'b0;
        m_axis_tdata  = 32'b0;
        m_axis_tlast  = 1'b0;
        next_state    = state;

        case (state)
            //-----------------------------------------------------
            IDLE: begin
                // In IDLE, wait for a new frame start (input valid after last frame).
                s_axis_tready = 1'b0;    // Not ready to consume data until preamble is inserted
                m_axis_tvalid = 1'b0;    // No output during idle
                if (s_axis_tvalid) begin
                    // Detected an incoming frame (valid data when idle)
                    next_state = INSERT;
                    // (Preamble counter will be reset on the state transition in sequential logic)
                end
            end

            //-----------------------------------------------------
            INSERT: begin
                // Output preamble symbols from ROM, stall input.
                m_axis_tvalid = 1'b1;                     // We have preamble data to send
                m_axis_tdata  = preamble_mem[preamble_count]; // Drive current preamble symbol
                m_axis_tlast  = 1'b0;                     // Preamble symbols are not end-of-frame
                s_axis_tready = 1'b0;                     // Remain not ready – hold off payload
                if (m_axis_tready && m_axis_tvalid) begin
                    // Downstream accepted this preamble symbol (handshake occurred)
                    if (preamble_count == PREAMBLE_LEN-1) begin
                        // Last preamble symbol sent, switch to forwarding payload
                        next_state = FORWARD;
                    end 
                    // (preamble_count increments in sequential block after handshake)
                end
                // If m_axis_tready is 0, we stay in INSERT and *do not* increment the counter.
                // m_axis_tvalid remains 1 with the same PREAMBLE[preamble_count] until the sink is ready.
            end

            //-----------------------------------------------------
            FORWARD: begin
                // Stream the payload through to output.
                s_axis_tready = m_axis_tready;  // Backpressure: only ready when downstream is ready
                m_axis_tvalid = s_axis_tvalid;  // Mirror input valid to output
                m_axis_tdata  = s_axis_tdata;   // Pass through data
                m_axis_tlast  = s_axis_tlast;   // Pass through TLAST (end-of-frame flag)
                if (s_axis_tvalid && m_axis_tready) begin
                    // A payload word is transferred
                    if (s_axis_tlast) begin
                        // End of frame reached – after this beat, go back to IDLE
                        next_state = IDLE;
                    end
                end
                // If not ready or no valid, the module will wait:
                // - If m_axis_tready=0, s_axis_tready=0 (stall input, hold current data stable).
                // - If s_axis_tvalid=0, no data to forward yet (wait for input).
            end

            default: next_state = IDLE;
        endcase
    end

endmodule

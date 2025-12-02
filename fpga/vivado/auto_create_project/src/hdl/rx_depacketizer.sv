module rx_depacketizer #(
    parameter int DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // AXIS input (from packetizer)
    input  logic [DATA_WIDTH-1:0]  s_axis_tdata,
    input  logic                   s_axis_tvalid,
    output logic                   s_axis_tready,
    input  logic                   s_axis_tlast,

    // AXIS output (payload only)
    output logic [DATA_WIDTH-1:0]  m_axis_tdata,
    output logic                   m_axis_tvalid,
    input  logic                   m_axis_tready,
    output logic                   m_axis_tlast
);

    // ------------------------------------------------------------------------
    // Types / state
    // ------------------------------------------------------------------------
    typedef enum logic [1:0] { HDR, FWD_PAYLOAD } state_t;
    state_t state, next_state;

    // Header word indexing:
    //   0 : looking for SYNC_WORD
    //   1 : header word 1 (seq + length)
    //   2 : header word 2 (stat/mode/flags)
    logic [1:0]  header_count;

    // Constants to match packetizer
    localparam logic [31:0] SYNC_WORD = 32'hDEAD_BEEF;

    // Parsed fields
    logic [15:0] seq_num;
    logic [15:0] payload_length;

    // Optional extra header info (currently unused, but kept)
    logic [15:0] stat_word;
    logic [7:0]  header_len;
    logic [3:0]  mode;
    logic [3:0]  flags;

    // Payload length remaining (down-counter)
    logic [15:0] payload_remaining;

    // Output staging from combinational to registered AXIS master
    logic [DATA_WIDTH-1:0] send_data;
    logic                  send_valid;
    logic                  send_last;
    logic                  last_now;
    logic                  any_differences;
    logic                  words_identical;
    logic [DATA_WIDTH-1:0]  xor_result;
    logic [DATA_WIDTH-1:0]  prev_word;

    // Handy handshake shorthand
    wire in_beat  = s_axis_tvalid && s_axis_tready;
    wire out_beat = m_axis_tvalid && m_axis_tready;

    // ------------------------------------------------------------------------
    // Output register (elastic AXIS master)
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tvalid <= 1'b0;
            m_axis_tdata  <= '0;
            m_axis_tlast  <= 1'b0;
        end else if (!m_axis_tvalid || m_axis_tready) begin
            m_axis_tvalid <= send_valid;
            if (send_valid) begin
                m_axis_tdata <= send_data;
                m_axis_tlast <= send_last;
            end else begin
                m_axis_tlast <= 1'b0;
            end
            // else: hold previous data/last
        end
    end

     // Step 1: XOR the two words bit-by-bit
    assign xor_result = s_axis_tdata ^ prev_word;
    // Step 2: Check if any bit is different
    assign any_differences = |xor_result;
    // Step 3: If no differences, words are the same
    assign words_identical = ~any_differences;


    // ------------------------------------------------------------------------
    // State, header fields, and counters
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= HDR;
            header_count      <= 2'd0;
            seq_num           <= 16'h0000;
            payload_length    <= 16'h0000;
            stat_word         <= 16'h0000;
            header_len        <= 8'h00;
            mode              <= 4'h0;
            flags             <= 4'h0;
            payload_remaining <= 16'h1111;
            prev_word         <= 32'h00000000;
        end else begin
            state <= next_state;

            // ---------------- Header word consumption ----------------
            if (state == HDR && in_beat) begin
                unique case (header_count)
                    2'd0: begin
                        // Search for sync word
                        if (s_axis_tdata == SYNC_WORD) begin
                            header_count <= 2'd1;   // next is header word 1
                        end else begin
                            header_count <= 2'd0;   // keep searching
                        end
                         prev_word <= s_axis_tdata;
                    end

                    2'd1: begin
                        // Header word 1: {seq_num, payload_length}
                        if (~words_identical) begin // only accept if different from previous
                            seq_num        <= s_axis_tdata[31:16];
                            payload_length <= s_axis_tdata[15:0];
                            header_count   <= 2'd2;     // next is header word 2
                        end
                        prev_word <= s_axis_tdata;
                    end

                    2'd2: begin
                        if (~words_identical) begin // only accept if different from previous
                            // Header word 2: {STAT_WORD, HEADER_LEN, {MODE,FLAGS}}
                            stat_word  <= s_axis_tdata[31:16];
                            header_len <= s_axis_tdata[15:8];
                            mode       <= s_axis_tdata[7:4];
                            flags      <= s_axis_tdata[3:0];
                            // After this beat, header is done; combinational
                            // logic will decide whether to go to payload or
                            // back to searching. Reset count here.
                            header_count <= 2'd0;
                        end
                    end

                    default: header_count <= 2'd0;
                endcase
            end

            // When entering FWD_PAYLOAD, preload remaining from payload_length
            if (state == HDR && next_state == FWD_PAYLOAD) begin
                payload_remaining <= payload_length - 16'd1; // minus one for this beat
            end

            // Reset header_count when going back to HDR from payload
            if (state == FWD_PAYLOAD && next_state == HDR) begin
                header_count <= 2'd0;
            end

            // Payload decrement on every forwarded beat
            if (state == FWD_PAYLOAD && in_beat) begin
                if (payload_remaining != 16'd0)
                    payload_remaining <= payload_remaining - 16'd1;
            end
        end
    end

    // ------------------------------------------------------------------------
    // FSM + output control (combinational)
    // ------------------------------------------------------------------------
    always_comb begin
        // Defaults
        next_state    = state;
        s_axis_tready = 1'b0;
        send_valid    = 1'b0;
        send_data     = '0;
        send_last     = 1'b0;
        last_now      = 1'b0;

        unique case (state)
            // ---------------- HDR: search for SYNC + eat 3 header words ------
            HDR: begin
                s_axis_tready = 1'b1;  // always ready while searching / in header

                if (s_axis_tvalid) begin
                    // When header_count was 2, we are currently consuming
                    // header word 2 (stat/mode/flags). After this beat,
                    // header is complete.
                    if (header_count == 2'd2) begin
                        if (payload_length == 16'd0) begin
                            // Zero-length payload: go back to searching
                            next_state = HDR;
                        end else begin
                            // Non-zero payload: switch to forwarding
                            next_state = FWD_PAYLOAD;
                        end
                    end
                end
            end

            // ---------------- FWD_PAYLOAD: forward payload only -------------
            FWD_PAYLOAD: begin
                // one-beat elastic coupling
                if (!m_axis_tvalid || m_axis_tready) begin
                    s_axis_tready = 1'b1;

                    if (s_axis_tvalid) begin
                        send_valid = 1'b1;
                        send_data  = s_axis_tdata;

                        // last beat when remaining count is 1
                        // (optionally OR with incoming TLAST if you like)
                        if (payload_remaining == 16'd0) begin
                            send_last = 1'b1;
                            next_state = HDR;
                        end
                    end
                end
                // else: stalled → deassert s_axis_tready, hold outputs
            end

            default: next_state = HDR;
        endcase
    end

endmodule

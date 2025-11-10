// rx_depacketizer.sv
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

    typedef enum logic [1:0] { HDR, FWD_PAYLOAD } state_t;
    state_t state, next_state;

    // 3 header words: 0,1,2
    logic [1:0]  header_count;

    // Parsed fields (optional/debug)
    logic [15:0] sync_word;
    logic [7:0]  header_len;
    logic [3:0]  mode;
    logic [3:0]  flags;
    logic [15:0] seq_num;
    logic [15:0] payload_length;

    // Payload counter
    logic [15:0] payload_count;

    // Output staging
    logic [DATA_WIDTH-1:0] send_data;
    logic                  send_valid;
    logic                  send_last;
    logic                  last_now;

    // NEW: flag to drop exactly the first beat after consuming header word #2
    logic drop_first;

    // Hold outputs until accepted
    // replace the output stage with:
    always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        m_ord: m_axis_tvalid <= 1'b0;
        m_axis_tdata  <= '0;
        m_axis_tlast  <= 1'b0;
    end else if (!m_axis_tvalid || m_axis_tready) begin
        m_axis_tvalid <= send_valid;
        if (send_valid) begin
        m_axis_tdata <= send_data;
        m_axis_tlast <= send_last;
        end
        // else: keep previous data; don't push a spurious zero
    end
    end


    // State & counters (sequential)
    always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state         <= HDR;
        header_count  <= 2'd0;
        payload_count <= 16'd0;
        sync_word     <= 16'h0000;
        header_len    <= 8'h00;
        mode          <= 4'h0;
        flags         <= 4'h0;
        seq_num       <= 16'h0000;
        payload_length<= 16'h0000;
        drop_first    <= 1'b0;
    end else begin
        state <= next_state;

        // Header consumption
        if (state == HDR && s_axis_tvalid && s_axis_tready) begin
        unique case (header_count)
            2'd0: begin
            sync_word  <= s_axis_tdata[31:16];
            header_len <= s_axis_tdata[15:8];
            mode       <= s_axis_tdata[7:4];
            flags      <= s_axis_tdata[3:0];
            end
            2'd1: begin
            seq_num        <= s_axis_tdata[31:16];
            payload_length <= s_axis_tdata[15:0];
            end
            default: ; // 2 -> reserved
        endcase
        header_count <= header_count + 2'd1;

        // Arm one-beat drop after last header word
        if (header_count == 2'd2)
            drop_first <= 1'b1;
        end

        // Reset counters when returning to HDR
        if (next_state == HDR && state != HDR) begin
        header_count  <= 2'd0;
        payload_count <= 16'd0;
        end

        // Reset payload_count exactly when entering FWD_PAYLOAD
        if (state == HDR && next_state == FWD_PAYLOAD) begin
        payload_count <= 16'd0;
        end

        // Payload word count (only when we actually forward a payload beat)
        if (state == FWD_PAYLOAD && s_axis_tvalid && s_axis_tready && !drop_first) begin
        payload_count <= payload_count + 16'd1;
        end

        // Clear the drop flag exactly when we consume that first post-header beat
        if (state == FWD_PAYLOAD && s_axis_tvalid && s_axis_tready && drop_first) begin
        drop_first <= 1'b0;
        end
    end
    end


    // FSM (combinational)
    always_comb begin
        // Defaults
        next_state    = state;
        s_axis_tready = 1'b0;
        send_valid    = 1'b0;
        send_data     = '0;
        send_last     = 1'b0;

        unique case (state)
            // ----- Eat (and drop) 3 header words -----
            HDR: begin
                s_axis_tready = 1'b1; // always ready for header
                if (s_axis_tvalid) begin
                    if (header_count == 2'd2) begin
                        // After 3rd header word: either go straight back to HDR (0-len)
                        // or start forwarding payload.
                        next_state = (payload_length == 16'd0) ? HDR : FWD_PAYLOAD;
                    end
                end
            end

            // ----- Forward payload -----
            FWD_PAYLOAD: begin
            // one-beat elastic coupling
            if (!m_axis_tvalid || m_axis_tready) begin
                s_axis_tready = 1'b1;

                if (s_axis_tvalid) begin
                if (drop_first) begin
                    // consume exactly one beat after header without forwarding it
                    send_valid = 1'b0;          // <-- swallow this beat
                    // send_data/send_last stay don't-care
                end else begin
                    send_valid = 1'b1;
                    send_data  = s_axis_tdata;

                    // Robust last detection: length OR incoming TLAST OR zero-length
                    last_now  = (payload_length == 16'd0) ||
                                ((payload_count + 16'd1) == payload_length) ||
                                s_axis_tlast;
                    send_last = last_now;
                    if (last_now) next_state = HDR;
                end
                end
            end
            // else: stalled → deassert s_axis_tready, hold outputs
            end


            default: next_state = HDR;
        endcase
    end

endmodule

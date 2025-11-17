module packet_rec(
    input               rst,
    input               rx_clk,
    input  [31:0]       rx_data,
    input  [3:0]        rx_ctrl,
    output [31:0]       rx_data_align,
    output [3:0]        rx_ctrl_align,
    output [31:0]       packet_cnt_o,
    output [31:0]       error_packet_cnt_o,

    // NEW: AXI-Stream-style payload output (to rx_depacketizer)
    output [31:0]       m_axis_tdata,
    output              m_axis_tvalid,
    input               m_axis_tready,
    output              m_axis_tlast
);

localparam IDLE        = 3'd0;
localparam WAIT_HEADER = 3'd1;
localparam SEQ_NUM     = 3'd2;
localparam CTRL        = 3'd3;
localparam DATA        = 3'd4;
localparam CHECK       = 3'd5;

reg [2:0]  state;
reg [31:0] sequence_number;
reg [31:0] last_sequence_number;
reg [15:0] packet_len;
reg [7:0]  packet_type;
reg [31:0] check_sum;
reg [15:0] data_cnt;
reg [31:0] packet_cnt;
reg [31:0] error_packet_cnt;

assign packet_cnt_o       = packet_cnt;
assign error_packet_cnt_o = error_packet_cnt;

wire [31:0] gt_rx_data;
wire [3:0]  gt_rx_ctrl;

assign gt_rx_data = rx_data_align;
assign gt_rx_ctrl = rx_ctrl_align;

// Word align as before
word_align word_align_m0 (
    .rst           (rst),
    .rx_clk        (rx_clk),
    .gt_rx_data    (rx_data),
    .gt_rx_ctrl    (rx_ctrl),
    .rx_data_align (rx_data_align),
    .rx_ctrl_align (rx_ctrl_align)
);

// ------------------------------------------------------------
// Packet counters / error counters
// ------------------------------------------------------------
always @(posedge rx_clk or posedge rst) begin
    if (rst) begin
        packet_cnt       <= 32'd0;
        error_packet_cnt <= 32'd0;
    end else if (state == CHECK) begin
        packet_cnt <= packet_cnt + 1;

        if (check_sum != gt_rx_data ||
            sequence_number != (last_sequence_number + 1))
            error_packet_cnt <= error_packet_cnt + 1;
    end
end

// ------------------------------------------------------------
// AXI-Stream payload out
// ------------------------------------------------------------
reg [31:0] m_axis_tdata_r;
reg        m_axis_tvalid_r;
reg        m_axis_tlast_r;

assign m_axis_tdata  = m_axis_tdata_r;
assign m_axis_tvalid = m_axis_tvalid_r;
assign m_axis_tlast  = m_axis_tlast_r;

// ------------------------------------------------------------
// Main FSM
// ------------------------------------------------------------
always @(posedge rx_clk or posedge rst) begin
    if (rst) begin
        state              <= IDLE;
        sequence_number    <= 32'hffff_ffff;
        last_sequence_number <= 32'd0;
        data_cnt           <= 16'd0;
        check_sum          <= 32'd0;
        packet_type        <= 8'd0;
        packet_len         <= 16'd0;

        m_axis_tdata_r     <= 32'd0;
        m_axis_tvalid_r    <= 1'b0;
        m_axis_tlast_r     <= 1'b0;
    end else begin
        // defaults every cycle
        m_axis_tvalid_r <= 1'b0;
        m_axis_tlast_r  <= 1'b0;

        case (state)
            IDLE: begin
                state <= WAIT_HEADER;
            end

            WAIT_HEADER: begin
                check_sum <= 32'd0;
                data_cnt  <= 16'd0;

                // Look for header: ctrl[0] + magic word
                if (gt_rx_ctrl[0] == 1'b1 && gt_rx_data == 32'hff_00_00_bc)
                    state <= SEQ_NUM;
            end

            SEQ_NUM: begin
                last_sequence_number <= sequence_number;
                sequence_number      <= gt_rx_data;
                state                <= CTRL;
            end

            CTRL: begin
                packet_len  <= gt_rx_data[31:16];
                packet_type <= gt_rx_data[7:0];
                check_sum   <= 32'd0;
                data_cnt    <= 16'd0;

                if (gt_rx_ctrl[0] == 1'b1) begin
                    // unexpected control during CTRL, restart
                    state <= WAIT_HEADER;
                end else if (packet_len == 16'd0) begin
                    // no payload -> go straight to checksum
                    state <= CHECK;
                end else begin
                    state <= DATA;
                end
            end

            DATA: begin
                // Optionally bail out if a control symbol appears mid-packet
                if (gt_rx_ctrl[0] == 1'b1) begin
                    state <= WAIT_HEADER;
                end else begin
                    // Only "accept" data if downstream is ready
                    if (m_axis_tready) begin
                        m_axis_tdata_r  <= gt_rx_data;
                        m_axis_tvalid_r <= 1'b1;

                        check_sum <= check_sum + gt_rx_data;

                        if (data_cnt == packet_len - 1) begin
                            // last payload word
                            m_axis_tlast_r <= 1'b1;
                            m_axis_tvalid_r <= 1'b0;
                            data_cnt       <= 16'd0;
                            state          <= CHECK;
                        end else begin
                            data_cnt <= data_cnt + 1'b1;
                            state    <= DATA;
                        end
                    end
                    // If not ready, we "see" the word but don't advance counters.
                    // In your final system, keep m_axis_tready high to avoid drops.
                end
            end

            CHECK: begin
                // At this point, gt_rx_data is the checksum word
                state <= WAIT_HEADER;
            end

            default: begin
                state <= IDLE;
            end
        endcase
    end
end

endmodule

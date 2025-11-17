module packet_send(
    input         rst,
    input         tx_clk,
    input         tx_packet_req,
    input  [15:0] tx_packet_len,
    output        tx_packet_done,
    input  [7:0]  tx_packet_type,
    input  [31:0] tx_packet_data,
    output reg    tx_packet_data_rd,

    output reg [31:0] gt_tx_data,
    output reg [3:0]  gt_tx_ctrl
);

localparam IDLE          = 4'd0;
localparam SEND_CORRECTION = 4'd1;
localparam SEND_DUMMY    = 4'd2;
localparam SEND_HEADER   = 4'd3;
localparam SEND_SEQ_NUM  = 4'd4;
localparam SEND_CTRL     = 4'd5;
localparam SEND_DATA     = 4'd6;
localparam SEND_CHECK    = 4'd7;
// (old SEND_DATA_END/SEND_IDLE states not used anymore)

reg [3:0]  state;
reg [31:0] sequence_number;
reg [15:0] data_cnt;
reg [31:0] check_sum;

assign tx_packet_done = (state == SEND_CHECK);

always @(posedge tx_clk or posedge rst) begin
    if (rst) begin
        state             <= IDLE;
        gt_tx_data        <= 32'd0;
        gt_tx_ctrl        <= 4'd0;
        sequence_number   <= 32'd0;
        data_cnt          <= 16'd0;
        tx_packet_data_rd <= 1'b0;
        check_sum         <= 32'd0;
    end else begin
        // default each cycle
        tx_packet_data_rd <= 1'b0;

        case (state)
            IDLE: begin
                gt_tx_data <= 32'd0;
                gt_tx_ctrl <= 4'd0;
                if (tx_packet_req)
                    state <= SEND_CORRECTION;
                else
                    state <= IDLE;
            end

            SEND_CORRECTION: begin
                gt_tx_data <= 32'hf7_f7_f7_f7;
                gt_tx_ctrl <= 4'b1111;
                state      <= SEND_DUMMY;
            end

            SEND_DUMMY: begin
                gt_tx_data <= 32'hff_00_00_55;
                gt_tx_ctrl <= 4'b0000;
                state      <= SEND_HEADER;
            end

            SEND_HEADER: begin
                gt_tx_data <= 32'hff_00_00_bc;
                gt_tx_ctrl <= 4'b0001;
                check_sum  <= 32'd0;
                state      <= SEND_SEQ_NUM;
            end

            SEND_SEQ_NUM: begin
                gt_tx_data      <= sequence_number;
                gt_tx_ctrl      <= 4'b0000;
                data_cnt        <= 16'd0;   // start counting payload words from 0
                state           <= SEND_CTRL;
            end

            SEND_CTRL: begin
                gt_tx_data <= {tx_packet_len, 8'd0, tx_packet_type};
                gt_tx_ctrl <= 4'b0000;

                if (tx_packet_len == 16'd0) begin
                    // no payload words, go straight to checksum
                    state <= SEND_CHECK;
                end else begin
                    state <= SEND_DATA;
                end
            end

            SEND_DATA: begin
                // Now we actually consume tx_packet_data
                tx_packet_data_rd <= 1'b1;         // handshake: "give me a word"
                gt_tx_data        <= tx_packet_data;
                gt_tx_ctrl        <= 4'b0000;
                check_sum         <= check_sum + tx_packet_data;

                if (data_cnt == tx_packet_len - 1) begin
                    // just consumed the last payload word
                    data_cnt        <= 16'd0;
                    sequence_number <= sequence_number + 32'd1;
                    state           <= SEND_CHECK;
                end else begin
                    data_cnt <= data_cnt + 1'b1;
                    state    <= SEND_DATA;
                end
            end

            SEND_CHECK: begin
                gt_tx_data <= check_sum;
                gt_tx_ctrl <= 4'b0000;
                state      <= IDLE;
            end

            default: begin
                state <= IDLE;
            end
        endcase
    end
end

endmodule

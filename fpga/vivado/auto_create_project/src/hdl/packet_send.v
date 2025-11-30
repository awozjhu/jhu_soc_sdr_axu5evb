module packet_send_axis_in (
    input         rst,
    input         tx_clk,

    // Packet control
    input         tx_packet_req,
    input  [15:0] tx_packet_len,   // payload length in 32-bit words
    output        tx_packet_done,
    input  [7:0]  tx_packet_type,

    // AXI-Stream payload input (32-bit)
    input  [31:0] s_axis_tdata,
    input         s_axis_tvalid,
    output        s_axis_tready,
    input         s_axis_tlast,    // optional; not required for operation

    // GT outputs (unchanged style)
    output reg [31:0] gt_tx_data,
    output reg [3:0]  gt_tx_ctrl
);

  localparam IDLE            = 4'd0;
  localparam SEND_CORRECTION = 4'd1;
  localparam SEND_DUMMY      = 4'd2;
  localparam SEND_HEADER     = 4'd3;
  localparam SEND_SEQ_NUM    = 4'd4;
  localparam SEND_CTRL       = 4'd5;
  localparam SEND_DATA       = 4'd6;
  localparam SEND_CHECK      = 4'd7;

  reg  [3:0]  state;
  reg  [31:0] sequence_number;
  reg  [15:0] data_cnt;
  reg  [31:0] check_sum;

  // AXIS handshake for input payload
  wire payload_fire = s_axis_tvalid && s_axis_tready;

  // Ready only during SEND_DATA: this block never backpressures the GT,
  // but it is AXI-Stream compliant on the input side.
  assign s_axis_tready = (state == SEND_DATA);

  // Done pulse when checksum word is being sent
  assign tx_packet_done = (state == SEND_CHECK);

  always @(posedge tx_clk or posedge rst) begin
    if (rst) begin
      state           <= IDLE;
      gt_tx_data      <= 32'd0;
      gt_tx_ctrl      <= 4'd0;
      sequence_number <= 32'd0;
      data_cnt        <= 16'd0;
      check_sum       <= 32'd0;
    end else begin
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
          data_cnt        <= 16'd0;   // start counting payload words
          state           <= SEND_CTRL;
        end

        SEND_CTRL: begin
          gt_tx_data <= {tx_packet_len, 8'd0, tx_packet_type};
          gt_tx_ctrl <= 4'b0000;

          if (tx_packet_len == 16'd0) begin
            // no payload: jump straight to checksum
            sequence_number <= sequence_number + 32'd1;
            state           <= SEND_CHECK;
          end else begin
            state <= SEND_DATA;
          end
        end

        SEND_DATA: begin
          gt_tx_ctrl <= 4'b0000;

          if (payload_fire) begin
            // Only accept word when AXIS handshake occurs
            gt_tx_data <= s_axis_tdata;
            check_sum  <= check_sum + s_axis_tdata;

            if (data_cnt == tx_packet_len - 1) begin
              data_cnt        <= 16'd0;
              sequence_number <= sequence_number + 32'd1;
              state           <= SEND_CHECK;
            end else begin
              data_cnt <= data_cnt + 1'b1;
              state    <= SEND_DATA;
            end
          end else begin
            // No valid payload this cycle: keep sending something benign.
            // You can choose to repeat last data, or send idle pattern.
            gt_tx_data <= gt_tx_data; // hold previous word
            state      <= SEND_DATA;  // wait until all payload words accepted
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

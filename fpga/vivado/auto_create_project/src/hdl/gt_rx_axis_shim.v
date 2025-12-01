module rx_axis_shim (
    input  wire        rx_clk,
    input  wire        rst,

    input  wire [31:0] rx_data,
    input  wire [3:0]  rx_ctrl,   // 0 = data, others = control/idle

    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast   // not used by depacketizer; tie low
);

  reg [31:0] data_r;
  reg        valid_r;

  assign m_axis_tdata  = data_r;
  assign m_axis_tvalid = valid_r;
  assign m_axis_tlast  = 1'b0;

  always @(posedge rx_clk or posedge rst) begin
    if (rst) begin
      data_r  <= 32'd0;
      valid_r <= 1'b0;
    end else begin
      // If we still have an unconsumed word, hold it until ready
      if (valid_r && !m_axis_tready) begin
        // hold data_r and valid_r
        valid_r <= valid_r;
      end else begin
        // We can accept a new GT word this cycle
        if (rx_ctrl == 4'h0) begin
          // real data beat
          data_r  <= rx_data;
          valid_r <= 1'b1;
        end else begin
          // control / idle beat – don't forward
          valid_r <= 1'b0;
        end
      end
    end
  end

endmodule

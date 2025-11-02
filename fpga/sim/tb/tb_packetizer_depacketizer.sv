`timescale 1ns/1ps

module tb_pkt_loopback;

  // --------------------------------------------------------------------------
  // Parameters
  // --------------------------------------------------------------------------
  parameter DATA_WIDTH = 32;
  parameter CLK_PERIOD = 4;   // 250 MHz

  // --------------------------------------------------------------------------
  // Clock and reset
  // --------------------------------------------------------------------------
  reg clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  reg rst_n = 0;
  initial begin
    rst_n = 0;
    repeat (10) @(posedge clk);
    rst_n = 1;
  end

  // --------------------------------------------------------------------------
  // AXIS connections
  // --------------------------------------------------------------------------
  reg  [DATA_WIDTH-1:0] s_axis_tdata = 0;
  reg                   s_axis_tvalid = 0;
  wire                  s_axis_tready;
  reg                   s_axis_tlast  = 0;

  wire [DATA_WIDTH-1:0] link_tdata;
  wire                  link_tvalid;
  wire                  link_tready;
  wire                  link_tlast;

  wire [DATA_WIDTH-1:0] m_axis_tdata;
  wire                  m_axis_tvalid;
  reg                   m_axis_tready = 1;
  wire                  m_axis_tlast;

  // --------------------------------------------------------------------------
  // Instantiate DUTs
  // --------------------------------------------------------------------------
  tx_packetizer #(.DATA_WIDTH(DATA_WIDTH)) u_tx (
    .clk(clk),
    .rst_n(rst_n),
    .s_axis_tdata (s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tlast (s_axis_tlast),
    .m_axis_tdata (link_tdata),
    .m_axis_tvalid(link_tvalid),
    .m_axis_tready(link_tready),
    .m_axis_tlast (link_tlast)
  );

  rx_depacketizer #(.DATA_WIDTH(DATA_WIDTH)) u_rx (
    .clk(clk),
    .rst_n(rst_n),
    .s_axis_tdata (link_tdata),
    .s_axis_tvalid(link_tvalid),
    .s_axis_tready(link_tready),
    .s_axis_tlast (link_tlast),
    .m_axis_tdata (m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast (m_axis_tlast)
  );

  // --------------------------------------------------------------------------
  // Key fix: start RX ready HIGH early
  // --------------------------------------------------------------------------
  // depacketizer starts with link_tready = 1 to break header deadlock
  // (This signal comes from rx_depacketizer.s_axis_tready)
  // If rx_depacketizer drives it internally, ensure it's initialized to 1 inside that RTL.
  // Otherwise, you can directly tie it off here for loopback testing:
  assign link_tready = 1'b1;

  // --------------------------------------------------------------------------
  // Optional backpressure (after startup)
  // --------------------------------------------------------------------------
  integer cycle_count = 0;
  always @(posedge clk) begin
    if (!rst_n) begin
      cycle_count <= 0;
      m_axis_tready <= 1;
    end else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count > 200)
        m_axis_tready <= ($random % 3 != 0); // occasional stalls
      else
        m_axis_tready <= 1; // fully open at start
    end
  end

  // --------------------------------------------------------------------------
  // Test vectors
  // --------------------------------------------------------------------------
  localparam NUM_WORDS = 16;
  reg [DATA_WIDTH-1:0] test_data [0:NUM_WORDS-1];
  reg [DATA_WIDTH-1:0] recv_data [0:NUM_WORDS-1];
  reg exp_last [0:NUM_WORDS-1];
  integer sent_count = 0;
  integer recv_count = 0;
  integer errors = 0;

  initial begin
    integer i;
    for (i = 0; i < NUM_WORDS; i = i + 1) begin
      test_data[i] = 32'hA0000000 + i;
      exp_last[i]  = (i == NUM_WORDS-1);
    end
  end

  // --------------------------------------------------------------------------
  // Drive TX payload into packetizer
  // --------------------------------------------------------------------------
  initial begin
    wait(rst_n);
    repeat (10) @(posedge clk);
    $display("[%0t] Starting frame transmission...", $time);
    sent_count = 0;
    while (sent_count < NUM_WORDS) begin
      s_axis_tdata  <= test_data[sent_count];
      s_axis_tlast  <= exp_last[sent_count];
      s_axis_tvalid <= 1;
      @(posedge clk);
      if (s_axis_tvalid && s_axis_tready)
        sent_count = sent_count + 1;
    end
    s_axis_tvalid <= 0;
    s_axis_tlast  <= 0;
    $display("[%0t] TX done sending %0d words", $time, sent_count);
  end

  // --------------------------------------------------------------------------
  // Capture RX output
  // --------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n && m_axis_tvalid && m_axis_tready) begin
      recv_data[recv_count] <= m_axis_tdata;
      recv_count <= recv_count + 1;
    end
  end

  // --------------------------------------------------------------------------
  // End of test
  // --------------------------------------------------------------------------
  initial begin
    wait(rst_n);
    wait(recv_count == NUM_WORDS);
    repeat (20) @(posedge clk);
    $display("[%0t] Received %0d words", $time, recv_count);
    $display("==== TEST COMPLETE ====");
    $finish;
  end

endmodule

`timescale 1ns/1ps

module tb_bb_chain_wrapper_no_fec;

  // ------------------------------------------------------------
  // Clock / Reset
  // ------------------------------------------------------------
  localparam real CLK_PERIOD_NS = 4.0; // 250 MHz

  logic clk = 0;
  always #(CLK_PERIOD_NS/2.0) clk = ~clk;

  logic rst_n;
  initial begin
    rst_n = 1'b0;
    repeat (20) @(posedge clk);
    rst_n = 1'b1;
  end

  // ------------------------------------------------------------
  // DUT interface signals (use wire to match wrapper ports)
  // ------------------------------------------------------------

  // TX side (from wrapper)
  wire [31:0] tx_pkt_tdata;
  wire        tx_pkt_tvalid;
  wire        tx_pkt_tready;
  wire        tx_pkt_tlast;

  // PRBS monitor (from wrapper)
  wire [7:0]  prbs_mon_tdata;
  wire        prbs_mon_tvalid;
  wire        prbs_mon_tlast;
  wire        prbs_mon_tready; // output from DUT

  // RX side input into wrapper (from packet_rec)
  wire [31:0] rx_sym_tdata;
  wire        rx_sym_tvalid;
  wire        rx_sym_tlast;
  wire        rx_sym_tready;   // output from DUT

  // Slicer output monitor (from wrapper)
  wire [7:0]  rx_byte_tdata;
  wire        rx_byte_tvalid;
  wire        rx_byte_tlast;
  wire        rx_byte_tready;

  // ------------------------------------------------------------
  // Baseband wrapper instantiation
  // ------------------------------------------------------------
  bb_chain_wrapper_no_fec #(
    .PREAMBLE_LEN (64),
    .USE_QPSK     (1)
  ) dut (
    .clk_tx           (clk),
    .clk_rx           (clk),
    .rst_tx_n         (rst_n),
    .rst_rx_n         (rst_n),

    // TX out (to packet_send)
    .tx_pkt_tdata     (tx_pkt_tdata),
    .tx_pkt_tvalid    (tx_pkt_tvalid),
    .tx_pkt_tready    (tx_pkt_tready),
    .tx_pkt_tlast     (tx_pkt_tlast),

    // PRBS monitor
    .prbs_mon_tdata   (prbs_mon_tdata),
    .prbs_mon_tvalid  (prbs_mon_tvalid),
    .prbs_mon_tlast   (prbs_mon_tlast),
    .prbs_mon_tready  (prbs_mon_tready),

    // RX symbols in (from packet_rec)
    .rx_sym_tdata     (rx_sym_tdata),
    .rx_sym_tvalid    (rx_sym_tvalid),
    .rx_sym_tready    (rx_sym_tready),
    .rx_sym_tlast     (rx_sym_tlast),

    // Slicer output bytes
    .rx_byte_tdata    (rx_byte_tdata),
    .rx_byte_tvalid   (rx_byte_tvalid),
    .rx_byte_tlast    (rx_byte_tlast),
    .rx_byte_tready   (rx_byte_tready)
  );

  // ------------------------------------------------------------
  // packet_send instantiation (TX side)
  // ------------------------------------------------------------
  wire [31:0] ps_gt_tx_data;
  wire [3:0]  ps_gt_tx_ctrl;
  wire        tx_packet_done;

  packet_send u_packet_send (
    .rst              (~rst_n),          // active-high reset
    .tx_clk           (clk),
    .tx_packet_req    (1'b1),            // always request packets in TB
    .tx_packet_len    (16'd64),          // payload length for test
    .tx_packet_done   (tx_packet_done),
    .tx_packet_type   (8'h01),

    // Drive from wrapper packetizer
    .tx_packet_data   (tx_pkt_tdata),
    .tx_packet_data_rd(tx_pkt_tready),   // tready back into wrapper

    .gt_tx_data       (ps_gt_tx_data),
    .gt_tx_ctrl       (ps_gt_tx_ctrl)
  );

  // ------------------------------------------------------------
  // packet_rec instantiation (RX side)
  // ------------------------------------------------------------
  wire [31:0] rx_data_align;
  wire [3:0]  rx_ctrl_align;
  wire [31:0] packet_cnt_o;
  wire [31:0] error_packet_cnt_o;

  // AXIS payload out of packet_rec
  wire [31:0] pr_m_axis_tdata;
  wire        pr_m_axis_tvalid;
  wire        pr_m_axis_tready;
  wire        pr_m_axis_tlast;

  packet_rec u_packet_rec (
    .rst                 (~rst_n),
    .rx_clk              (clk),
    .rx_data             (ps_gt_tx_data),
    .rx_ctrl             (ps_gt_tx_ctrl),
    .rx_data_align       (rx_data_align),
    .rx_ctrl_align       (rx_ctrl_align),
    .packet_cnt_o        (packet_cnt_o),
    .error_packet_cnt_o  (error_packet_cnt_o),

    // AXI-Stream-style payload output
    .m_axis_tdata        (pr_m_axis_tdata),
    .m_axis_tvalid       (pr_m_axis_tvalid),
    .m_axis_tready       (pr_m_axis_tready),
    .m_axis_tlast        (pr_m_axis_tlast)
  );

  // ------------------------------------------------------------
  // Connect packet_rec payload AXIS into wrapper RX AXIS
  // ------------------------------------------------------------
  assign rx_sym_tdata   = pr_m_axis_tdata;
  assign rx_sym_tvalid  = pr_m_axis_tvalid;
  assign rx_sym_tlast   = pr_m_axis_tlast;
  assign pr_m_axis_tready = rx_sym_tready;  // backpressure from wrapper

  // Always ready to consume slicer output in this TB
  assign rx_byte_tready = 1'b1;

  // ------------------------------------------------------------
  // Simple monitoring
  // ------------------------------------------------------------

  initial begin
    $dumpfile("tb_bb_chain_wrapper_no_fec.vcd");
    $dumpvars(0, tb_bb_chain_wrapper_no_fec);

    #(200_000); // 200 us at 250 MHz
    $display("[%0t] Simulation finished", $time);
    $finish;
  end

  // Print a few PRBS bytes and recovered bytes to the console
  always @(posedge clk) begin
    if (rst_n && prbs_mon_tvalid) begin
      $display("[%0t] PRBS  : %02x (last=%0b)",
               $time, prbs_mon_tdata, prbs_mon_tlast);
    end
    if (rst_n && rx_byte_tvalid) begin
      $display("[%0t] SLICER: %02x (last=%0b)",
               $time, rx_byte_tdata, rx_byte_tlast);
    end
  end

endmodule

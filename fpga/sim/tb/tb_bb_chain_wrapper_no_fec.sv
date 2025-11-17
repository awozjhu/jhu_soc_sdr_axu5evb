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
  // DUT interface signals
  // ------------------------------------------------------------

  // TX side (from wrapper)
  logic [31:0] tx_pkt_tdata;
  logic        tx_pkt_tvalid;
  logic        tx_pkt_tready;
  logic        tx_pkt_tlast;

  // PRBS monitor (from wrapper)
  logic [7:0]  prbs_mon_tdata;
  logic        prbs_mon_tvalid;
  logic        prbs_mon_tlast;
  logic        prbs_mon_tready; // output from DUT

  // RX side input into wrapper (loopback from TX)
  logic [31:0] rx_sym_tdata;
  logic        rx_sym_tvalid;
  logic        rx_sym_tlast;
  logic        rx_sym_tready;   // output from DUT

  // Slicer output monitor (from wrapper)
  logic [7:0]  rx_byte_tdata;
  logic        rx_byte_tvalid;
  logic        rx_byte_tlast;
  logic        rx_byte_tready;

  // ------------------------------------------------------------
  // DUT instantiation
  // ------------------------------------------------------------
  bb_chain_wrapper_no_fec #(
    .PREAMBLE_LEN (64),
    .USE_QPSK     (1'b1)
  ) dut (
    .clk_tx           (clk),
    .clk_rx           (clk),
    .rst_tx_n         (rst_n),
    .rst_rx_n         (rst_n),

    // TX out (to "packet_send" in real design, looped back here)
    .tx_pkt_tdata  (tx_pkt_tdata),
    .tx_pkt_tvalid (tx_pkt_tvalid),
    .tx_pkt_tready (tx_pkt_tready),
    .tx_pkt_tlast  (tx_pkt_tlast),

    // PRBS monitor
    .prbs_mon_tdata  (prbs_mon_tdata),
    .prbs_mon_tvalid (prbs_mon_tvalid),
    .prbs_mon_tlast  (prbs_mon_tlast),
    .prbs_mon_tready (prbs_mon_tready),

    // RX symbols in (from loopback)
    .rx_sym_tdata  (rx_sym_tdata),
    .rx_sym_tvalid (rx_sym_tvalid),
    .rx_sym_tready (rx_sym_tready),
    .rx_sym_tlast  (rx_sym_tlast),

    // Slicer output bytes
    .rx_byte_tdata  (rx_byte_tdata),
    .rx_byte_tvalid (rx_byte_tvalid),
    .rx_byte_tlast  (rx_byte_tlast),
    .rx_byte_tready (rx_byte_tready)
  );

  // ------------------------------------------------------------
  // Simple loopback: TX packet stream -> RX symbol stream
  // ------------------------------------------------------------

  // Forward TX data/control to RX inputs
  assign rx_sym_tdata  = tx_pkt_tdata;
  assign rx_sym_tvalid = tx_pkt_tvalid;
  assign rx_sym_tlast  = tx_pkt_tlast;

  // Backpressure: RX ready drives TX ready
  assign tx_pkt_tready = rx_sym_tready;

  // Always ready to consume slicer output in this TB
  assign rx_byte_tready = 1'b1;

  // ------------------------------------------------------------
  // Simple monitoring
  // ------------------------------------------------------------

  // Dump waves for viewing (GTKWave, SimVision, etc.)
  initial begin
    $dumpfile("tb_bb_chain_wrapper_no_fec.vcd");
    $dumpvars(0, tb_bb_chain_wrapper_no_fec);

    // Run for some time then finish
    #(200_000); // 200 us at 250 MHz is plenty to see frames
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

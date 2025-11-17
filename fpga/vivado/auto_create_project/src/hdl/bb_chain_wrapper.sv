`timescale 1ns/1ps

module bb_chain_wrapper_no_fec #(
  parameter integer PREAMBLE_LEN = 64,
  parameter integer USE_QPSK     = 1   // 1 = QPSK, 0 = BPSK
)(
  // ------------------------------------------------------------
  // Clocks / resets
  // ------------------------------------------------------------
  input  wire        clk_tx,     // tx baseband clock (use tx0_clk)
  input  wire        clk_rx,     // rx baseband clock (use rx0_clk)
  input  wire        rst_tx_n,   // active-low synchronous reset for tx datapath
  input  wire        rst_tx_n,   // active-low synchronous reset for rx datapath

  // ------------------------------------------------------------
  // TX side: output of tx_packetizer (to hook to packet_send)
  // ------------------------------------------------------------
  output wire [31:0] tx_pkt_tdata,
  output wire        tx_pkt_tvalid,
  input  wire        tx_pkt_tready,
  output wire        tx_pkt_tlast,

  // PRBS stream monitor (for ILA)
  output wire [7:0]  prbs_mon_tdata,
  output wire        prbs_mon_tvalid,
  output wire        prbs_mon_tlast,
  output wire        prbs_mon_tready,

  // ------------------------------------------------------------
  // RX side: input stream into RX chain
  // (you'll drive this from rx0_data_align + glue)
  // ------------------------------------------------------------
  input  wire [31:0] rx_sym_tdata,
  input  wire        rx_sym_tvalid,
  output wire        rx_sym_tready,
  input  wire        rx_sym_tlast,

  // Slicer output monitor (for ILA / downstream)
  output wire [7:0]  rx_byte_tdata,
  output wire        rx_byte_tvalid,
  output wire        rx_byte_tlast,
  input  wire        rx_byte_tready
);


  // ============================================================
  // PRBS AXI-Stream source (AXI-Lite tied off)
  // ============================================================
  logic [7:0] prbs_tdata;
  logic       prbs_tvalid, prbs_tready, prbs_tlast;

  // Dummy wires for AXI-Lite outputs
  logic        prbs_awready, prbs_wready, prbs_bvalid, prbs_arready, prbs_rvalid;
  logic [1:0]  prbs_bresp, prbs_rresp;
  logic [31:0] prbs_rdata;

  prbs_axi_stream #(
    .AXIL_ADDR_WIDTH(6),
    .AXIL_DATA_WIDTH(32)
  ) u_prbs (
    .clk            (clk_tx),
    .rst_n          (rst_tx_n),

    // AXI-Lite: inputs tied low, outputs ignored
    .s_axil_awaddr  (6'd0),
    .s_axil_awvalid (1'b0),
    .s_axil_awready (prbs_awready),
    .s_axil_wdata   (32'd0),
    .s_axil_wstrb   (4'd0),
    .s_axil_wvalid  (1'b0),
    .s_axil_wready  (prbs_wready),
    .s_axil_bresp   (prbs_bresp),
    .s_axil_bvalid  (prbs_bvalid),
    .s_axil_bready  (1'b0),
    .s_axil_araddr  (6'd0),
    .s_axil_arvalid (1'b0),
    .s_axil_arready (prbs_arready),
    .s_axil_rdata   (prbs_rdata),
    .s_axil_rresp   (prbs_rresp),
    .s_axil_rvalid  (prbs_rvalid),
    .s_axil_rready  (1'b0),

    // AXI-Stream
    .m_axis_tdata   (prbs_tdata),
    .m_axis_tvalid  (prbs_tvalid),
    .m_axis_tready  (prbs_tready),
    .m_axis_tlast   (prbs_tlast)
  );

  // Expose PRBS stream for ILA
  assign prbs_mon_tdata  = prbs_tdata;
  assign prbs_mon_tvalid = prbs_tvalid;
  assign prbs_mon_tlast  = prbs_tlast;
  assign prbs_mon_tready = prbs_tready;

  // ============================================================
  // TX chain: PRBS -> Mapper -> Diff Encoder -> PreambleInserter -> TX Packetizer
  // ============================================================

  // ---------------- Mapper ----------------
  logic        map_in_valid, map_in_ready, map_in_last;
  logic [7:0]  map_in_data;
  logic        map_out_valid, map_out_ready, map_out_last;
  logic [31:0] map_out_data;

  assign map_in_valid = prbs_tvalid;
  assign map_in_data  = prbs_tdata;
  assign map_in_last  = prbs_tlast;
  assign prbs_tready  = map_in_ready;

  // dummy wires for mapper AXI-Lite outputs
  logic        m_awready, m_wready, m_bvalid, m_arready, m_rvalid;
  logic [1:0]  m_bresp, m_rresp;
  logic [31:0] m_rdata;

  mapper u_mapper (
    .clk_bb           (clk_tx),
    .rst_n            (rst_tx_n),

    .in_valid         (map_in_valid),
    .in_ready         (map_in_ready),
    .in_data          (map_in_data),
    .in_last          (map_in_last),

    .out_valid        (map_out_valid),
    .out_ready        (map_out_ready),
    .out_data         (map_out_data),
    .out_last         (map_out_last),

    .amc_mode_i       (3'(USE_QPSK)),
    .amc_mode_valid_i (1'b0),

    // AXI-Lite tied off
    .s_axi_aclk       (clk_tx),
    .s_axi_aresetn    (rst_tx_n),
    .s_axi_awaddr     (8'd0),
    .s_axi_awvalid    (1'b0),
    .s_axi_awready    (m_awready),
    .s_axi_wdata      (32'd0),
    .s_axi_wstrb      (4'd0),
    .s_axi_wvalid     (1'b0),
    .s_axi_wready     (m_wready),
    .s_axi_bresp      (m_bresp),
    .s_axi_bvalid     (m_bvalid),
    .s_axi_bready     (1'b0),
    .s_axi_araddr     (8'd0),
    .s_axi_arvalid    (1'b0),
    .s_axi_arready    (m_arready),
    .s_axi_rdata      (m_rdata),
    .s_axi_rresp      (m_rresp),
    .s_axi_rvalid     (m_rvalid),
    .s_axi_rready     (1'b0)
  );

  // ---------------- Diff Encoder ----------------
  logic        de_in_valid, de_in_ready, de_in_last;
  logic [31:0] de_in_data,  de_out_data;
  logic        de_out_valid, de_out_ready, de_out_last;

  assign de_in_valid   = map_out_valid;
  assign de_in_data    = map_out_data;
  assign de_in_last    = map_out_last;
  assign map_out_ready = de_in_ready;

  // dummy AXI-Lite outputs
  logic        de_awready, de_wready, de_bvalid, de_arready, de_rvalid;
  logic [1:0]  de_bresp, de_rresp;
  logic [31:0] de_rdata;

  diff_encoder u_diff_enc (
    .clk_bb        (clk_tx),
    .rst_n         (rst_tx_n),

    .in_valid      (de_in_valid),
    .in_ready      (de_in_ready),
    .in_data       (de_in_data),
    .in_last       (de_in_last),

    .out_valid     (de_out_valid),
    .out_ready     (de_out_ready),
    .out_data      (de_out_data),
    .out_last      (de_out_last),

    .s_axi_aclk    (clk_tx),
    .s_axi_aresetn (rst_tx_n),
    .s_axi_awaddr  (8'd0),
    .s_axi_awvalid (1'b0),
    .s_axi_awready (de_awready),
    .s_axi_wdata   (32'd0),
    .s_axi_wstrb   (4'd0),
    .s_axi_wvalid  (1'b0),
    .s_axi_wready  (de_wready),
    .s_axi_bresp   (de_bresp),
    .s_axi_bvalid  (de_bvalid),
    .s_axi_bready  (1'b0),
    .s_axi_araddr  (8'd0),
    .s_axi_arvalid (1'b0),
    .s_axi_arready (de_arready),
    .s_axi_rdata   (de_rdata),
    .s_axi_rresp   (de_rresp),
    .s_axi_rvalid  (de_rvalid),
    .s_axi_rready  (1'b0)
  );

  // ---------------- Preamble Inserter ----------------
  logic        pi_tvalid, pi_tready, pi_tlast;
  logic [31:0] pi_tdata;

  PreambleInserter #(
    .PREAMBLE_LEN(PREAMBLE_LEN)
  ) u_preamble_ins (
    .aclk          (clk_tx),
    .aresetn       (rst_tx_n),

    .s_axis_tvalid (de_out_valid),
    .s_axis_tready (de_out_ready),
    .s_axis_tdata  (de_out_data),
    .s_axis_tlast  (de_out_last),

    .m_axis_tvalid (pi_tvalid),
    .m_axis_tready (pi_tready),
    .m_axis_tdata  (pi_tdata),
    .m_axis_tlast  (pi_tlast)
  );

  // ---------------- TX Packetizer ----------------
  tx_packetizer u_tx_pkt (
    .clk           (clk_tx),
    .rst_n         (rst_tx_n),

    .s_axis_tdata  (pi_tdata),
    .s_axis_tvalid (pi_tvalid),
    .s_axis_tready (pi_tready),
    .s_axis_tlast  (pi_tlast),

    .m_axis_tdata  (tx_pkt_tdata),
    .m_axis_tvalid (tx_pkt_tvalid),
    .m_axis_tready (tx_pkt_tready),
    .m_axis_tlast  (tx_pkt_tlast)
  );

  // ============================================================
  // RX chain: RX symbols -> Depacketizer -> Preamble Corr -> Diff Dec -> Slicer
  // ============================================================

  // ---------------- Depacketizer ----------------
  logic        dep_tvalid, dep_tready, dep_tlast;
  logic [31:0] dep_tdata;

  rx_depacketizer u_rx_depkt (
    .clk           (clk_rx),
    .rst_n         (rst_rx_n),

    .s_axis_tdata  (rx_sym_tdata),
    .s_axis_tvalid (rx_sym_tvalid),
    .s_axis_tready (rx_sym_tready),
    .s_axis_tlast  (rx_sym_tlast),

    .m_axis_tdata  (dep_tdata),
    .m_axis_tvalid (dep_tvalid),
    .m_axis_tready (dep_tready),
    .m_axis_tlast  (dep_tlast)
  );

  // ---------------- Preamble Correlator ----------------
  logic        pc_tvalid, pc_tready, pc_tlast;
  logic [31:0] pc_tdata;
  logic        frame_start;

  PreambleCorrelator #(
    .PREAMBLE_LEN(PREAMBLE_LEN)
  ) u_pcorr (
    .clk           (clk_rx),
    .rst_n         (rst_rx_n),

    .s_axis_tvalid (dep_tvalid),
    .s_axis_tready (dep_tready),
    .s_axis_tdata  (dep_tdata),
    .s_axis_tlast  (dep_tlast),

    .m_axis_tvalid (pc_tvalid),
    .m_axis_tready (pc_tready),
    .m_axis_tdata  (pc_tdata),
    .m_axis_tlast  (pc_tlast),

    .frame_start   (frame_start)
  );

  // ---------------- Diff Decoder ----------------
  logic        dd_in_valid, dd_in_ready, dd_in_last;
  logic [31:0] dd_in_data;
  logic        dd_out_valid, dd_out_ready, dd_out_last;
  logic [31:0] dd_out_data;

  assign dd_in_valid = pc_tvalid;
  assign dd_in_data  = pc_tdata;
  assign dd_in_last  = pc_tlast;
  assign pc_tready   = dd_in_ready;

  // dummy AXI-Lite outputs
  logic        dd_awready, dd_wready, dd_bvalid, dd_arready, dd_rvalid;
  logic [1:0]  dd_bresp, dd_rresp;
  logic [31:0] dd_rdata;

  diff_decoder u_diff_dec (
    .clk_bb        (clk_rx),
    .rst_n         (rst_rx_n),

    .in_valid      (dd_in_valid),
    .in_ready      (dd_in_ready),
    .in_data       (dd_in_data),
    .in_last       (dd_in_last),
    .frame_start_i (frame_start),

    .out_valid     (dd_out_valid),
    .out_ready     (dd_out_ready),
    .out_data      (dd_out_data),
    .out_last      (dd_out_last),

    .s_axi_aclk    (clk_rx),
    .s_axi_aresetn (rst_rx_n),
    .s_axi_awaddr  (8'd0),
    .s_axi_awvalid (1'b0),
    .s_axi_awready (dd_awready),
    .s_axi_wdata   (32'd0),
    .s_axi_wstrb   (4'd0),
    .s_axi_wvalid  (1'b0),
    .s_axi_wready  (dd_wready),
    .s_axi_bresp   (dd_bresp),
    .s_axi_bvalid  (dd_bvalid),
    .s_axi_bready  (1'b0),
    .s_axi_araddr  (8'd0),
    .s_axi_arvalid (1'b0),
    .s_axi_arready (dd_arready),
    .s_axi_rdata   (dd_rdata),
    .s_axi_rresp   (dd_rresp),
    .s_axi_rvalid  (dd_rvalid),
    .s_axi_rready  (1'b0)
  );

  // ---------------- Slicer ----------------
  logic        sl_in_valid, sl_in_ready, sl_in_last;
  logic [31:0] sl_in_data;
  logic        sl_out_valid, sl_out_last;
  logic [7:0]  sl_out_data;

  // dummy AXI-Lite outputs
  logic        sl_awready, sl_wready, sl_bvalid, sl_arready, sl_rvalid;
  logic [1:0]  sl_bresp, sl_rresp;
  logic [31:0] sl_rdata;

  assign sl_in_valid  = dd_out_valid;
  assign sl_in_data   = dd_out_data;
  assign sl_in_last   = dd_out_last;
  assign dd_out_ready = sl_in_ready;

  slicer u_slicer (
    .clk_bb        (clk_rx),
    .rst_n         (rst_rx_n),

    .in_valid      (sl_in_valid),
    .in_ready      (sl_in_ready),
    .in_data       (sl_in_data),
    .in_last       (sl_in_last),

    .out_valid     (sl_out_valid),
    .out_ready     (rx_byte_tready),
    .out_data      (sl_out_data),
    .out_last      (sl_out_last),

    .amc_mode_i    (3'(USE_QPSK)),

    .s_axi_aclk    (clk_rx),
    .s_axi_aresetn (rst_rx_n),
    .s_axi_awaddr  (8'd0),
    .s_axi_awvalid (1'b0),
    .s_axi_awready (sl_awready),
    .s_axi_wdata   (32'd0),
    .s_axi_wstrb   (4'd0),
    .s_axi_wvalid  (1'b0),
    .s_axi_wready  (sl_wready),
    .s_axi_bresp   (sl_bresp),
    .s_axi_bvalid  (sl_bvalid),
    .s_axi_bready  (1'b0),
    .s_axi_araddr  (8'd0),
    .s_axi_arvalid (1'b0),
    .s_axi_arready (sl_arready),
    .s_axi_rdata   (sl_rdata),
    .s_axi_rresp   (sl_rresp),
    .s_axi_rvalid  (sl_rvalid),
    .s_axi_rready  (1'b0)
  );

  // Expose slicer output
  assign rx_byte_tdata  = sl_out_data;
  assign rx_byte_tvalid = sl_out_valid;
  assign rx_byte_tlast  = sl_out_last;

endmodule

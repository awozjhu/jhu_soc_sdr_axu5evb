`timescale 1ns/1ps

module bb_chain_wrapper_fec #(
  parameter integer PREAMBLE_LEN = 64,
  parameter integer USE_QPSK     = 1   // 1 = QPSK, 0 = BPSK
)(
  // ------------------------------------------------------------
  // Clocks / resets
  // ------------------------------------------------------------
  input  wire        clk,     // tx and rx baseband clock
  input  wire        rst_n,   // active-low synchronous reset for tx and rx datapath

  // control points
  // runtime-programmable threshold (0–255)
  input  wire [7:0]            err_thresh,
  input  wire                  sel_fec,      // 0 = no FEC (to slicer), 1 = with FEC (to Viterbi)

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
  input  wire        rx_byte_tready,

  // RX: Viterbi decoder output
  output wire [7:0] vit_out_data,
  output wire       vit_out_valid,
  input  wire       vit_out_ready,

  // ------------------------------------------------------------
  // *** Debug / observability ports ***
  // ------------------------------------------------------------

  // TX: mapper output
  output wire [31:0] dbg_map_out_tdata,
  output wire        dbg_map_out_tvalid,
  output wire        dbg_map_out_tready,
  output wire        dbg_map_out_tlast,

  // TX: diff encoder output
  output wire [31:0] dbg_de_out_tdata,
  output wire        dbg_de_out_tvalid,
  output wire        dbg_de_out_tready,
  output wire        dbg_de_out_tlast,

  // RX: depacketizer output
  output wire [31:0] dbg_dep_tdata,
  output wire        dbg_dep_tvalid,
  output wire        dbg_dep_tready,
  output wire        dbg_dep_tlast,

  // RX: preamble correlator output + frame_start
  // output wire [31:0] dbg_pc_tdata,
  // output wire        dbg_pc_tvalid,
  // output wire        dbg_pc_tready,
  // output wire        dbg_pc_tlast,
  // output wire        dbg_frame_start,

  // RX: diff decoder output
  output wire [31:0] dbg_dd_out_tdata,
  output wire        dbg_dd_out_tvalid,
  output wire        dbg_dd_out_tready,
  output wire        dbg_dd_out_tlast,

  // RX: slicer input (symbols)
  output wire [31:0] dbg_sl_in_tdata,
  output wire        dbg_sl_in_tvalid,
  output wire        dbg_sl_in_tready,
  output wire        dbg_sl_in_tlast
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

  // ============================================================
  // TX chain: 
  // ============================================================

  localparam int COUNTER_FRAME_LEN = 256;  // bytes per frame; or 0 for no TLAST
  localparam int FEC_LAT = 4;               // convolutional encoder latency in cycles
  

  axis_prbs_src #(
    .FRAME_LEN_BYTES (COUNTER_FRAME_LEN)   // 0 => never assert TLAST
  ) u_axis_prbs_src (
    .clk          (clk),             // input  logic
    .rst_n        (rst_n),           // input  logic, active-low

    .enable       (1'b1),       // input  logic

    .m_axis_tdata (prbs_tdata),        // output logic [7:0]
    .m_axis_tvalid(prbs_tvalid),       // output logic
    .m_axis_tready(prbs_tready),       // input  logic
    .m_axis_tlast (prbs_tlast)         // output logic
  );

  logic        map_in_valid, map_in_ready, map_in_last;
  logic [7:0]  map_in_data;

  // ---------------- Convolutional Encoder ----------------
  logic        conv_en_tvalid, conv_en_tready, conv_en_tlast, prbs_tready_enc;
  logic [7:0]  conv_en_tdata;

  // convolution_0 u_conv_encoder (
  //   .aclk(clk),                              // input wire aclk
  //   .aresetn(rst_n),                        // input wire aresetn
  //   .s_axis_data_tdata(prbs_tdata),    // input wire [7 : 0] s_axis_data_tdata
  //   .s_axis_data_tvalid(prbs_tvalid),  // input wire s_axis_data_tvalid
  //   .s_axis_data_tready(prbs_tready_enc),  // output wire s_axis_data_tready

  //   .m_axis_data_tdata(conv_en_tdata),    // output wire [7 : 0] m_axis_data_tdata
  //   .m_axis_data_tvalid(conv_en_tvalid),  // output wire m_axis_data_tvalid
  //   .m_axis_data_tready(conv_en_tready)  // input wire m_axis_data_tready
  // );


// From encoder wrapper
wire [15:0] dbg_in_bytes, dbg_out_bytes;

axis_conv_encoder_wrap u_enc_wrap (
  .clk               (clk),
  .rst_n             (rst_n),

  .s_axis_tdata      (prbs_tdata),
  .s_axis_tvalid     (prbs_tvalid),
  .s_axis_tready     (prbs_tready_enc),
  .s_axis_tlast      (prbs_tlast),

  .m_axis_tdata      (conv_en_tdata),
  .m_axis_tvalid     (conv_en_tvalid),
  .m_axis_tready     (conv_en_tready),
  .m_axis_tlast      (conv_en_tlast),

  .dbg_in_frame_bytes (dbg_in_bytes),
  .dbg_out_frame_bytes(dbg_out_bytes)
);

// For now, you can either:
//  - Tie enc_wr_tready = 1'b1 in the testbench, or
//  - Later connect {enc_wr_*} to your mapper in_t* ports.

// assign enc_wr_tready = 1'b1;

  // ---------------- FEC selection mux ----------------

// Align TLAST from PRBS source to convolutional encoder output
// logic [FEC_LAT-1:0] fec_tlast_sr;

// always_ff @(posedge clk or negedge rst_n) begin
//   if (!rst_n)
//     fec_tlast_sr <= '0;
//   else if (sel_fec && prbs_tvalid && prbs_tready)
//     fec_tlast_sr <= {fec_tlast_sr[FEC_LAT-2:0], prbs_tlast};
// end

// wire fec_tlast_aligned = fec_tlast_sr[FEC_LAT-1];


  // When FEC is OFF → Mapper sees raw PRBS.
  // When FEC is ON  → Mapper sees encoded bytes.

  assign map_in_valid = sel_fec ? conv_en_tvalid : prbs_tvalid;
  assign map_in_data  = sel_fec ? conv_en_tdata  : prbs_tdata;
  assign map_in_last  = sel_fec ? conv_en_tlast  : prbs_tlast;

  assign prbs_tready =
      sel_fec ? prbs_tready_enc : map_in_ready;

  assign conv_en_tready =
      sel_fec ? map_in_ready : 1'b0;


  // ---------------- Mapper ----------------
  logic        map_out_valid, map_out_ready, map_out_last;
  logic [31:0] map_out_data;

  // Expose PRBS stream for ILA
  assign prbs_mon_tdata  = prbs_tdata;
  assign prbs_mon_tvalid = prbs_tvalid;
  assign prbs_mon_tlast  = prbs_tlast;
  assign prbs_mon_tready = prbs_tready;


  // dummy wires for mapper AXI-Lite outputs
  logic        m_awready, m_wready, m_bvalid, m_arready, m_rvalid;
  logic [1:0]  m_bresp, m_rresp;
  logic [31:0] m_rdata;



  mapper_streamer u_mapper_stream (
    .clk_bb           (clk),
    .rst_n            (rst_n),

    .in_valid         (map_in_valid),
    .in_ready         (map_in_ready),
    .in_data          (map_in_data),

    .out_valid        (map_out_valid),
    .out_ready        (map_out_ready),
    .out_data         (map_out_data),
    .out_last         (map_out_last),

    .amc_mode_i       (3'(USE_QPSK)),
    .amc_mode_valid_i (1'b0)
  );




  // mapper u_mapper (
  //   .clk_bb           (clk),
  //   .rst_n            (rst_n),

  //   .in_valid         (map_in_valid),
  //   .in_ready         (map_in_ready),
  //   .in_data          (map_in_data),
  //   .in_last          (map_in_last),

  //   .out_valid        (map_out_valid),
  //   .out_ready        (map_out_ready),
  //   .out_data         (map_out_data),
  //   .out_last         (map_out_last),

  //   .amc_mode_i       (3'(USE_QPSK)),
  //   .amc_mode_valid_i (1'b0),

  //   // AXI-Lite tied off
  //   .s_axi_aclk       (clk),
  //   .s_axi_aresetn    (rst_n),
  //   .s_axi_awaddr     (8'd0),
  //   .s_axi_awvalid    (1'b0),
  //   .s_axi_awready    (m_awready),
  //   .s_axi_wdata      (32'd0),
  //   .s_axi_wstrb      (4'd0),
  //   .s_axi_wvalid     (1'b0),
  //   .s_axi_wready     (m_wready),
  //   .s_axi_bresp      (m_bresp),
  //   .s_axi_bvalid     (m_bvalid),
  //   .s_axi_bready     (1'b0),
  //   .s_axi_araddr     (8'd0),
  //   .s_axi_arvalid    (1'b0),
  //   .s_axi_arready    (m_arready),
  //   .s_axi_rdata      (m_rdata),
  //   .s_axi_rresp      (m_rresp),
  //   .s_axi_rvalid     (m_rvalid),
  //   .s_axi_rready     (1'b0)
  // );

//---------------------------------------------------------------------
// Noise Injector Instance (AXIS-safe)
//---------------------------------------------------------------------
logic [31:0] noisy_tdata;
logic        noisy_tvalid;
logic        noisy_tready;
logic        noisy_tlast;

// Enable during simulation; disable in hardware if desired
logic noise_enable = 1'b1;

axis_iq_noise_injector #(
  .WIDTH(16),        // signed 16-bit I and Q
  .NOISE_SHIFT(6)    // adjust noise amplitude
) u_noise_injector (
  .clk           (clk),
  .rst_n         (rst_n),
  .enable        (noise_enable),

  .err_thresh   (err_thresh),

  // AXIS IN  (from mapper)
  .s_axis_tdata  (map_out_data),
  .s_axis_tvalid (map_out_valid),
  .s_axis_tready (map_out_ready),
  .s_axis_tlast  (map_out_last),

  // AXIS OUT (to downstream stage)
  .m_axis_tdata  (noisy_tdata),
  .m_axis_tvalid (noisy_tvalid),
  .m_axis_tready (noisy_tready), // output backpressure
  .m_axis_tlast  (noisy_tlast)
);


  // ---------------- Diff Encoder ----------------
  logic        de_in_valid, de_in_ready, de_in_last;
  logic [31:0] de_in_data,  de_out_data;
  logic        de_out_valid, de_out_ready, de_out_last;

  // if noise injector is used, connect mapper directly to diff encoder
  assign de_in_data    = noisy_tdata;
  assign de_in_valid   = noisy_tvalid;
  assign noisy_tready  = de_in_ready;
  assign de_in_last    = noisy_tlast;

// if noise injector is NOT used, connect mapper directly to diff encoder
  // assign de_in_valid   = map_out_valid;
  // assign de_in_data    = map_out_data;
  // assign de_in_last    = map_out_last;
  // assign map_out_ready = de_in_ready;

  // dummy AXI-Lite outputs
  logic        de_awready, de_wready, de_bvalid, de_arready, de_rvalid;
  logic [1:0]  de_bresp, de_rresp;
  logic [31:0] de_rdata;

  diff_encoder u_diff_enc (
    .clk_bb        (clk),
    .rst_n         (rst_n),

    .in_valid      (de_in_valid),
    .in_ready      (de_in_ready),
    .in_data       (de_in_data),
    .in_last       (de_in_last),

    .out_valid     (de_out_valid),
    .out_ready     (de_out_ready),
    .out_data      (de_out_data),
    .out_last      (de_out_last),

    .s_axi_aclk    (clk),
    .s_axi_aresetn (rst_n),
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


  // ---------------- TX Packetizer ----------------
  tx_packetizer u_tx_pkt (
    .clk           (clk),
    .rst_n         (rst_n),

    .s_axis_tdata  (de_out_data),
    .s_axis_tvalid (de_out_valid),
    .s_axis_tready (de_out_ready),
    .s_axis_tlast  (de_out_last),

    .m_axis_tdata  (tx_pkt_tdata),
    .m_axis_tvalid (tx_pkt_tvalid),
    .m_axis_tready (tx_pkt_tready),
    .m_axis_tlast  (tx_pkt_tlast)
  );


  // ============================================================
  // RX chain: RX symbols -> Depacketizer -> Preamble Corr -> Diff Dec -> Slicer
  // ============================================================

  // UPDATED RX Chain, No Preamble CHAIN: RX symbols -> Depacketizer -> Diff Dec -> Slicer


  // ---------------- Depacketizer ----------------
  logic        dep_tvalid, dep_tready, dep_tlast;
  logic [31:0] dep_tdata;

  rx_depacketizer u_rx_depkt (
    .clk           (clk),
    .rst_n         (rst_n),

    .s_axis_tdata  (rx_sym_tdata),
    .s_axis_tvalid (rx_sym_tvalid),
    .s_axis_tready (rx_sym_tready),
    .s_axis_tlast  (rx_sym_tlast),

    .m_axis_tdata  (dep_tdata),
    .m_axis_tvalid (dep_tvalid),
    .m_axis_tready (dep_tready),
    .m_axis_tlast  (dep_tlast)
  );


  // ---------------- Diff Decoder ----------------
  logic        dd_in_valid, dd_in_ready, dd_in_last;
  logic [31:0] dd_in_data;
  logic        dd_out_valid, dd_out_ready, dd_out_last;
  logic [31:0] dd_out_data;

  assign dd_in_valid = dep_tvalid;
  assign dd_in_data  = dep_tdata;
  assign dd_in_last  = dep_tlast;
  assign dep_tready   = dd_in_ready;


  // dummy AXI-Lite outputs
  logic        dd_awready, dd_wready, dd_bvalid, dd_arready, dd_rvalid;
  logic [1:0]  dd_bresp, dd_rresp;
  logic [31:0] dd_rdata;

  diff_decoder u_diff_dec (
    .clk_bb        (clk),
    .rst_n         (rst_n),

    .in_valid      (dd_in_valid),
    .in_ready      (dd_in_ready),
    .in_data       (dd_in_data),
    .in_last       (dd_in_last),
    // .frame_start_i (frame_start),
    .frame_start_i (1'b0), // tie off for no preamble

    .out_valid     (dd_out_valid),
    .out_ready     (dd_out_ready),
    .out_data      (dd_out_data),
    .out_last      (dd_out_last),

    .s_axi_aclk    (clk),
    .s_axi_aresetn (rst_n),
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

  // ------------------------------
  // MUX: diff decoder to either slicer or soft-metrics
  // ------------------------------
  wire        path0_tvalid;
  wire [31:0] path0_tdata;
  wire        path0_tlast;

  wire        path1_tvalid;
  wire [31:0] path1_tdata;
  wire        path1_tlast;

  wire path0_tready;   // to slicer
  wire path1_tready;   // to soft-metrics

  // Diff-decoder ready depends on selected path
  assign dd_out_ready =
      (sel_fec == 1'b0) ? path0_tready :
      (sel_fec == 1'b1) ? path1_tready :
                          1'b0; // defensive

  // Drive muxed valid/data/last to each sink
  // sel_fec == 1'b0: to slicer
  assign path0_tvalid = (sel_fec == 1'b0) ? dd_out_valid : 1'b0;
  assign path0_tdata  = dd_out_data;
  assign path0_tlast  = dd_out_last;

  // sel_fec == 1'b1: to soft-metrics
  assign path1_tvalid = (sel_fec == 1'b1) ? dd_out_valid : 1'b0;
  assign path1_tdata  = dd_out_data;
  assign path1_tlast  = dd_out_last;

  // To Viterbi
  wire [15:0] vit_in_data;
  wire        vit_in_valid, vit_in_ready, vit_in_last;

  // assign vit_in_ready = 1'b1; // tie off for now

  axis_iq_to_softmetrics #(
    .SOFT_W(3)              // must match Viterbi "Soft Width"
  ) u_softmet (
    .clk          (clk),
    .rst_n        (rst_n),

    .s_axis_tdata (path1_tdata),
    .s_axis_tvalid(path1_tvalid),
    .s_axis_tready(path1_tready),
    .s_axis_tlast (path1_tlast),

    .m_axis_tdata (vit_in_data),
    .m_axis_tvalid(vit_in_valid),
    .m_axis_tready(vit_in_ready),
    .m_axis_tlast (vit_in_last)
  );

  // ------------------------------------------------------------
  // Viterbi Decoder IP 
  // ------------------------------------------------------------\

  viterbi_0 u_vit_decoder (
    .aclk(clk),                              // input wire aclk
    .aresetn(rst_n),                        // input wire aresetn
    .s_axis_data_tdata(vit_in_data),    // input wire [15 : 0] s_axis_data_tdata
    .s_axis_data_tvalid(vit_in_valid),  // input wire s_axis_data_tvalid
    .s_axis_data_tready(vit_in_ready),  // output wire s_axis_data_tready

    .m_axis_data_tdata(vit_out_data),    // output wire [7 : 0] m_axis_data_tdata
    .m_axis_data_tvalid(vit_out_valid),  // output wire m_axis_data_tvalid
    .m_axis_data_tready(vit_out_ready)  // input wire m_axis_data_tready
  );


  // ---------------- Slicer ----------------
  logic        sl_in_valid, sl_in_ready, sl_in_last;
  logic [31:0] sl_in_data;
  logic        sl_out_valid, sl_out_last, sl_out_ready;
  logic [7:0]  sl_out_data;

  // dummy AXI-Lite outputs
  logic        sl_awready, sl_wready, sl_bvalid, sl_arready, sl_rvalid;
  logic [1:0]  sl_bresp, sl_rresp;
  logic [31:0] sl_rdata;

  assign sl_in_valid  = path0_tvalid;
  assign sl_in_data   = path0_tdata;
  assign sl_in_last   = path0_tlast;
  assign path0_tready = sl_in_ready;

  slicer u_slicer (
    .clk_bb        (clk),
    .rst_n         (rst_n),

    .in_valid      (sl_in_valid),
    .in_ready      (sl_in_ready),
    .in_data       (sl_in_data),
    .in_last       (sl_in_last),

    .out_valid     (sl_out_valid),
    .out_ready     (rx_byte_tready), // input
    .out_data      (sl_out_data),
    .out_last      (sl_out_last),

    .amc_mode_i    (3'(USE_QPSK)),

    .s_axi_aclk    (clk),
    .s_axi_aresetn (rst_n),
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


  // ------------------------------------------------------------
  // Debug signal hookups
  // ------------------------------------------------------------

  // TX: mapper
  assign dbg_map_out_tdata  = map_out_data;
  assign dbg_map_out_tvalid = map_out_valid;
  assign dbg_map_out_tready = map_out_ready;
  assign dbg_map_out_tlast  = map_out_last;

  // TX: diff encoder
  assign dbg_de_out_tdata   = de_out_data;
  assign dbg_de_out_tvalid  = de_out_valid;
  assign dbg_de_out_tready  = de_out_ready;
  assign dbg_de_out_tlast   = de_out_last;

  // RX: depacketizer
  assign dbg_dep_tdata      = dep_tdata;
  assign dbg_dep_tvalid     = dep_tvalid;
  assign dbg_dep_tready     = dep_tready;
  assign dbg_dep_tlast      = dep_tlast;

  // RX: preamble correlator
  // assign dbg_pc_tdata       = pc_tdata;
  // assign dbg_pc_tvalid      = pc_tvalid;
  // assign dbg_pc_tready      = pc_tready;
  // assign dbg_pc_tlast       = pc_tlast;
  // assign dbg_frame_start    = frame_start;

  // RX: diff decoder
  assign dbg_dd_out_tdata   = dd_out_data;
  assign dbg_dd_out_tvalid  = dd_out_valid;
  assign dbg_dd_out_tready  = dd_out_ready;
  assign dbg_dd_out_tlast   = dd_out_last;

  // RX: slicer input
  assign dbg_sl_in_tdata    = sl_in_data;
  assign dbg_sl_in_tvalid   = sl_in_valid;
  assign dbg_sl_in_tready   = sl_in_ready;
  assign dbg_sl_in_tlast    = sl_in_last;

endmodule

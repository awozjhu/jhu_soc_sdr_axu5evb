`timescale 1ns/1ps
module tb_full_chain_no_fec;

  // ------------------------------------------------------------
  // Parameters
  // ------------------------------------------------------------
  localparam int CLK_PER_NS    = 4;      // 250 MHz
  localparam int PREAMBLE_LEN  = 64;     // QPSK symbols (multiple of 4)
  localparam int PAYLOAD_BYTES = 256;    // per frame
  localparam int N_FRAMES      = 2;
  localparam bit USE_QPSK      = 1;

  // ------------------------------------------------------------
  // Clock / Reset
  // ------------------------------------------------------------
  logic clk = 0;
  always #(CLK_PER_NS/2.0) clk = ~clk;

  logic rst_n;
  initial begin
    rst_n = 0;
    repeat (20) @(posedge clk);
    rst_n = 1;
  end

  wire s_axi_aclk    = clk;
  wire s_axi_aresetn = rst_n;

  // ------------------------------------------------------------
  // PRBS AXI-Stream (TX source)
  // ------------------------------------------------------------
  // AXIS
  logic [7:0] prbs_tdata;
  logic       prbs_tvalid, prbs_tready, prbs_tlast;

  // AXI-Lite (6-bit addr for PRBS)
  logic [5:0]  prbs_awaddr; logic prbs_awvalid, prbs_awready;
  logic [31:0] prbs_wdata;  logic [3:0]  prbs_wstrb; logic prbs_wvalid, prbs_wready;
  logic [1:0]  prbs_bresp;  logic prbs_bvalid, prbs_bready;
  logic [5:0]  prbs_araddr; logic prbs_arvalid, prbs_arready;
  logic [31:0] prbs_rdata;  logic [1:0]  prbs_rresp; logic prbs_rvalid, prbs_rready;

  prbs_axi_stream #(.AXIL_ADDR_WIDTH(6), .AXIL_DATA_WIDTH(32)) u_prbs (
    .clk            (clk),
    .rst_n          (rst_n),
    .s_axil_awaddr  (prbs_awaddr),
    .s_axil_awvalid (prbs_awvalid),
    .s_axil_awready (prbs_awready),
    .s_axil_wdata   (prbs_wdata),
    .s_axil_wstrb   (prbs_wstrb),
    .s_axil_wvalid  (prbs_wvalid),
    .s_axil_wready  (prbs_wready),
    .s_axil_bresp   (prbs_bresp),
    .s_axil_bvalid  (prbs_bvalid),
    .s_axil_bready  (prbs_bready),
    .s_axil_araddr  (prbs_araddr),
    .s_axil_arvalid (prbs_arvalid),
    .s_axil_arready (prbs_arready),
    .s_axil_rdata   (prbs_rdata),
    .s_axil_rresp   (prbs_rresp),
    .s_axil_rvalid  (prbs_rvalid),
    .s_axil_rready  (prbs_rready),
    .m_axis_tdata   (prbs_tdata),
    .m_axis_tvalid  (prbs_tvalid),
    .m_axis_tready  (prbs_tready),
    .m_axis_tlast   (prbs_tlast)
  );

  // ------------------------------------------------------------
  // TX: Mapper → Diff Encoder → Preamble Inserter
  // (Scrambler removed)
  // ------------------------------------------------------------

  // Mapper
  logic        map_in_valid, map_in_ready, map_in_last;
  logic [7:0]  map_in_data;
  logic        map_out_valid, map_out_ready, map_out_last;
  logic [31:0] map_out_data;

  // PRBS → Mapper
  assign map_in_valid = prbs_tvalid;
  assign map_in_data  = prbs_tdata;
  assign map_in_last  = prbs_tlast;
  assign prbs_tready  = map_in_ready;

  // Mapper AXI-Lite (8-bit addr)
  logic [7:0]  m_awaddr;  logic m_awvalid, m_awready;
  logic [31:0] m_wdata;   logic [3:0]  m_wstrb; logic m_wvalid, m_wready;
  logic [1:0]  m_bresp;   logic m_bvalid, m_bready;
  logic [7:0]  m_araddr;  logic m_arvalid, m_arready;
  logic [31:0] m_rdata;   logic [1:0]  m_rresp; logic m_rvalid, m_rready;

  mapper u_mapper (
    .clk_bb(clk), .rst_n(rst_n),
    .in_valid(map_in_valid), .in_ready(map_in_ready),
    .in_data (map_in_data),  .in_last (map_in_last),
    .out_valid(map_out_valid), .out_ready(map_out_ready),
    .out_data (map_out_data),  .out_last (map_out_last),
    .amc_mode_i(3'(USE_QPSK)), .amc_mode_valid_i(1'b0),
    .s_axi_aclk(s_axi_aclk), .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(m_awaddr), .s_axi_awvalid(m_awvalid), .s_axi_awready(m_awready),
    .s_axi_wdata (m_wdata),  .s_axi_wstrb(m_wstrb), .s_axi_wvalid(m_wvalid), .s_axi_wready(m_wready),
    .s_axi_bresp (m_bresp),  .s_axi_bvalid(m_bvalid), .s_axi_bready(m_bready),
    .s_axi_araddr(m_araddr), .s_axi_arvalid(m_arvalid), .s_axi_arready(m_arready),
    .s_axi_rdata (m_rdata),  .s_axi_rresp(m_rresp), .s_axi_rvalid(m_rvalid), .s_axi_rready(m_rready)
  );

  // Diff Encoder
  logic        de_in_valid, de_in_ready, de_in_last;
  logic [31:0] de_in_data,  de_out_data;
  logic        de_out_valid, de_out_ready, de_out_last;

  assign de_in_valid   = map_out_valid;
  assign de_in_data    = map_out_data;
  assign de_in_last    = map_out_last;
  assign map_out_ready = de_in_ready;

  // Diff Encoder AXI-Lite
  logic [7:0]  de_awaddr;  logic de_awvalid, de_awready;
  logic [31:0] de_wdata;   logic [3:0]  de_wstrb; logic de_wvalid, de_wready;
  logic [1:0]  de_bresp;   logic de_bvalid, de_bready;
  logic [7:0]  de_araddr;  logic de_arvalid, de_arready;
  logic [31:0] de_rdata;   logic [1:0]  de_rresp; logic de_rvalid, de_rready;

  diff_encoder u_diff_enc (
    .clk_bb(clk), .rst_n(rst_n),
    .in_valid(de_in_valid), .in_ready(de_in_ready),
    .in_data (de_in_data),  .in_last (de_in_last),
    .out_valid(de_out_valid), .out_ready(de_out_ready),
    .out_data (de_out_data),  .out_last (de_out_last),
    .s_axi_aclk(s_axi_aclk), .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(de_awaddr), .s_axi_awvalid(de_awvalid), .s_axi_awready(de_awready),
    .s_axi_wdata (de_wdata),  .s_axi_wstrb(de_wstrb), .s_axi_wvalid(de_wvalid), .s_axi_wready(de_wready),
    .s_axi_bresp (de_bresp),  .s_axi_bvalid(de_bvalid), .s_axi_bready(de_bready),
    .s_axi_araddr(de_araddr), .s_axi_arvalid(de_arvalid), .s_axi_arready(de_arready),
    .s_axi_rdata (de_rdata),  .s_axi_rresp(de_rresp), .s_axi_rvalid(de_rvalid), .s_axi_rready(de_rready)
  );

  // Preamble Inserter (symbols)
  logic        pi_tvalid, pi_tready, pi_tlast;
  logic [31:0] pi_tdata;

  PreambleInserter #(.PREAMBLE_LEN(PREAMBLE_LEN)) u_preamble_ins (
    .aclk(clk), .aresetn(rst_n),
    .s_axis_tvalid(de_out_valid), .s_axis_tready(de_out_ready),
    .s_axis_tdata(de_out_data),   .s_axis_tlast(de_out_last),
    .m_axis_tvalid(pi_tvalid), .m_axis_tready(pi_tready),
    .m_axis_tdata(pi_tdata),   .m_axis_tlast(pi_tlast)
  );

  // ------------------------------------------------------------
  // RX: Preamble Correlator → Diff Decoder → Slicer
  // (NO packetizer/depacketizer; single correlator)
  // ------------------------------------------------------------
  logic        pc_tvalid, pc_tready, pc_tlast;
  logic [31:0] pc_tdata;
  logic        frame_start;

  PreambleCorrelator #(.PREAMBLE_LEN(PREAMBLE_LEN)) u_pcorr (
    .clk(clk), .rst_n(rst_n),
    .s_axis_tvalid(pi_tvalid), .s_axis_tready(pi_tready),
    .s_axis_tdata(pi_tdata),   .s_axis_tlast(pi_tlast),
    .m_axis_tvalid(pc_tvalid), .m_axis_tready(pc_tready),
    .m_axis_tdata(pc_tdata),   .m_axis_tlast(pc_tlast),
    .frame_start(frame_start)
  );

  // Diff Decoder
  logic        dd_in_valid, dd_in_ready, dd_in_last;
  logic [31:0] dd_in_data;
  logic        dd_out_valid, dd_out_ready, dd_out_last;
  logic [31:0] dd_out_data;

  assign dd_in_valid = pc_tvalid;
  assign dd_in_data  = pc_tdata;
  assign dd_in_last  = pc_tlast;
  assign pc_tready   = dd_in_ready;

  // Diff Decoder AXI-Lite
  logic [7:0]  dd_awaddr;  logic dd_awvalid, dd_awready;
  logic [31:0] dd_wdata;   logic [3:0]  dd_wstrb; logic dd_wvalid, dd_wready;
  logic [1:0]  dd_bresp;   logic dd_bvalid, dd_bready;
  logic [7:0]  dd_araddr;  logic dd_arvalid, dd_arready;
  logic [31:0] dd_rdata;   logic [1:0]  dd_rresp; logic dd_rvalid, dd_rready;

  diff_decoder u_diff_dec (
    .clk_bb(clk), .rst_n(rst_n),
    .in_valid(dd_in_valid), .in_ready(dd_in_ready),
    .in_data (dd_in_data),  .in_last (dd_in_last),
    .frame_start_i(frame_start),
    .out_valid(dd_out_valid), .out_ready(dd_out_ready),
    .out_data (dd_out_data),  .out_last (dd_out_last),
    .s_axi_aclk(s_axi_aclk), .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(dd_awaddr), .s_axi_awvalid(dd_awvalid), .s_axi_awready(dd_awready),
    .s_axi_wdata (dd_wdata),  .s_axi_wstrb(dd_wstrb), .s_axi_wvalid(dd_wvalid), .s_axi_wready(dd_wready),
    .s_axi_bresp (dd_bresp),  .s_axi_bvalid(dd_bvalid), .s_axi_bready(dd_bready),
    .s_axi_araddr(dd_araddr), .s_axi_arvalid(dd_arvalid), .s_axi_arready(dd_arready),
    .s_axi_rdata (dd_rdata),  .s_axi_rresp(dd_rresp), .s_axi_rvalid(dd_rvalid), .s_axi_rready(dd_rready)
  );

  // Slicer
  logic        sl_in_valid, sl_in_ready, sl_in_last;
  logic [31:0] sl_in_data;
  logic        sl_out_valid, sl_out_ready, sl_out_last;
  logic [7:0]  sl_out_data;

  assign sl_in_valid   = dd_out_valid;
  assign sl_in_data    = dd_out_data;
  assign sl_in_last    = dd_out_last;
  assign dd_out_ready  = sl_in_ready;

  // Slicer AXI-Lite
  logic [7:0]  sl_awaddr;  logic sl_awvalid, sl_awready;
  logic [31:0] sl_wdata;   logic [3:0]  sl_wstrb; logic sl_wvalid, sl_wready;
  logic [1:0]  sl_bresp;   logic sl_bvalid, sl_bready;
  logic [7:0]  sl_araddr;  logic sl_arvalid, sl_arready;
  logic [31:0] sl_rdata;   logic [1:0]  sl_rresp; logic sl_rvalid, sl_rready;

  slicer u_slicer (
    .clk_bb(clk), .rst_n(rst_n),
    .in_valid(sl_in_valid), .in_ready(sl_in_ready),
    .in_data (sl_in_data),  .in_last (sl_in_last),
    .out_valid(sl_out_valid), .out_ready(sl_out_ready),
    .out_data (sl_out_data),  .out_last (sl_out_last),
    .amc_mode_i(3'(USE_QPSK)), .amc_mode_valid_i(1'b0),
    .s_axi_aclk(s_axi_aclk), .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(sl_awaddr), .s_axi_awvalid(sl_awvalid), .s_axi_awready(sl_awready),
    .s_axi_wdata (sl_wdata),  .s_axi_wstrb(sl_wstrb), .s_axi_wvalid(sl_wvalid), .s_axi_wready(sl_wready),
    .s_axi_bresp (sl_bresp),  .s_axi_bvalid(sl_bvalid), .s_axi_bready(sl_bready),
    .s_axi_araddr(sl_araddr), .s_axi_arvalid(sl_arvalid), .s_axi_arready(sl_arready),
    .s_axi_rdata (sl_rdata),  .s_axi_rresp(sl_rresp),  .s_axi_rvalid(sl_rvalid), .s_axi_rready(sl_rready)
  );

  // Free-run the sink for waves
  assign sl_out_ready = 1'b1;

  // ------------------------------------------------------------
  // CSV logging (PRBS out & SLICER out)
  // ------------------------------------------------------------
  integer f_prbs, f_slc;
  int prbs_frame_idx = 0, prbs_beat_idx = 0;
  int slc_frame_idx  = 0, slc_beat_idx  = 0;

  // open files & headers
  initial begin
    wait (rst_n);
    f_prbs = $fopen("prbs_out.csv","w");
    f_slc  = $fopen("slicer_out.csv","w");
    if (f_prbs == 0 || f_slc == 0) $fatal(1,"Failed to open CSV files.");
    $fdisplay(f_prbs,"time_ns,frame_idx,beat_idx,tvalid,tready,tlast,data_hex");
    $fdisplay(f_slc, "time_ns,frame_idx,beat_idx,tvalid,tready,tlast,data_hex");
  end

  // PRBS → Mapper (accepted bytes)
  always @(posedge clk) begin
    if (rst_n && prbs_tvalid && prbs_tready) begin
      $fdisplay(f_prbs, "%0t,%0d,%0d,%0d,%0d,%0d,%02h",
        $time, prbs_frame_idx, prbs_beat_idx,
        prbs_tvalid, prbs_tready, prbs_tlast, prbs_tdata);
      prbs_beat_idx++;
      if (prbs_tlast) begin
        prbs_frame_idx++;
        prbs_beat_idx = 0;
      end
    end
  end

  // SLICER output (accepted bytes)
  always @(posedge clk) begin
    if (rst_n && sl_out_valid && sl_out_ready) begin
      $fdisplay(f_slc, "%0t,%0d,%0d,%0d,%0d,%0d,%02h",
        $time, slc_frame_idx, slc_beat_idx,
        sl_out_valid, sl_out_ready, sl_out_last, sl_out_data);
      slc_beat_idx++;
      if (sl_out_last) begin
        slc_frame_idx++;
        slc_beat_idx = 0;
      end
    end
  end

  // close files on finish
  final begin
    if (f_prbs) $fclose(f_prbs);
    if (f_slc)  $fclose(f_slc);
    $display("Wrote prbs_out.csv and slicer_out.csv");
  end

  // ------------------------------------------------------------
  // REMOVED / COMMENTED OUT (kept for reference)
  // ------------------------------------------------------------
  // byte_scrambler u_scr_tx (/* removed */);
  // tx_packetizer u_tx_pkt (/* removed for this run */);
  // rx_depacketizer u_rx_depkt (/* removed for this run */);
  // PreambleCorrelator u_pcorr1 (/* not used here */);
  // byte_scrambler u_scr_rx (/* removed */);
  // Frame gate / scoreboard / timeout blocks (removed)

  // ------------------------------------------------------------
  // AXI-Lite write tasks (unchanged)
  // ------------------------------------------------------------
  task automatic axil_write_mapper(input byte addr, input logic [31:0] data);
  begin
    m_awaddr  <= addr;
    m_awvalid <= 1'b1;
    m_wdata   <= data;
    m_wstrb   <= 4'hF;
    m_wvalid  <= 1'b1;
    do @(posedge s_axi_aclk); while (!(m_awready && m_wready));
    m_awvalid <= 1'b0;
    m_wvalid  <= 1'b0;
    do @(posedge s_axi_aclk); while (!m_bvalid);
    m_bready <= 1'b1; @(posedge s_axi_aclk); m_bready <= 1'b0;
  end
  endtask

  task automatic axil_write_de(input byte addr, input logic [31:0] data);
  begin
    de_awaddr  <= addr;  de_awvalid <= 1'b1;
    de_wdata   <= data;  de_wstrb   <= 4'hF;  de_wvalid <= 1'b1;
    do @(posedge s_axi_aclk); while (!(de_awready && de_wready));
    de_awvalid <= 1'b0;  de_wvalid <= 1'b0;
    do @(posedge s_axi_aclk); while (!de_bvalid);
    de_bready  <= 1'b1;  @(posedge s_axi_aclk);  de_bready <= 1'b0;
  end
  endtask

  task automatic axil_write_dd(input byte addr, input logic [31:0] data);
  begin
    dd_awaddr  <= addr;  dd_awvalid <= 1'b1;
    dd_wdata   <= data;  dd_wstrb   <= 4'hF;  dd_wvalid <= 1'b1;
    do @(posedge s_axi_aclk); while (!(dd_awready && dd_wready));
    dd_awvalid <= 1'b0;  dd_wvalid <= 1'b0;
    do @(posedge s_axi_aclk); while (!dd_bvalid);
    dd_bready  <= 1'b1;  @(posedge s_axi_aclk);  dd_bready <= 1'b0;
  end
  endtask

  task automatic axil_write_sl(input byte addr, input logic [31:0] data);
  begin
    sl_awaddr  <= addr;  sl_awvalid <= 1'b1;
    sl_wdata   <= data;  sl_wstrb   <= 4'hF;  sl_wvalid <= 1'b1;
    do @(posedge s_axi_aclk); while (!(sl_awready && sl_wready));
    sl_awvalid <= 1'b0;  sl_wvalid <= 1'b0;
    do @(posedge s_axi_aclk); while (!sl_bvalid);
    sl_bready  <= 1'b1;  @(posedge s_axi_aclk);  sl_bready <= 1'b0;
  end
  endtask

  task automatic axil_write_prbs(input byte addr8, input logic [31:0] data);
    logic [5:0] a6;
  begin
    a6 = addr8[5:0];
    prbs_awaddr  <= a6;   prbs_awvalid <= 1'b1;
    prbs_wdata   <= data; prbs_wstrb   <= 4'hF; prbs_wvalid <= 1'b1;
    do @(posedge s_axi_aclk); while (!(prbs_awready && prbs_wready));
    prbs_awvalid <= 1'b0; prbs_wvalid  <= 1'b0;
    do @(posedge s_axi_aclk); while (!prbs_bvalid);
    prbs_bready  <= 1'b1; @(posedge s_axi_aclk); prbs_bready <= 1'b0;
  end
  endtask

  // ------------------------------------------------------------
  // Init & simple programming (unchanged)
  // ------------------------------------------------------------
  initial begin
    // zero AXI-Lite drivers
    {m_awvalid,m_wvalid,m_bready,m_arvalid,m_rready} = '0;
    {de_awvalid,de_wvalid,de_bready,de_arvalid,de_rready} = '0;
    {dd_awvalid,dd_wvalid,dd_bready,dd_arvalid,dd_rready} = '0;
    {sl_awvalid,sl_wvalid,sl_bready,sl_arvalid,sl_rready} = '0;
    {prbs_awvalid,prbs_wvalid,prbs_bready,prbs_arvalid,prbs_rready} = '0;

    m_awaddr=0; m_wdata=0; m_wstrb=0;
    de_awaddr=0; de_wdata=0; dd_wstrb=0; // note: de_wstrb assigned above; harmless here
    dd_awaddr=0; dd_wdata=0; dd_wstrb=0;
    sl_awaddr=0; sl_wdata=0; sl_wstrb=0;
    prbs_awaddr=0; prbs_wdata=0; prbs_wstrb=0;

    wait (s_axi_aresetn); @(posedge s_axi_aclk);

    // Mapper: ENABLE=1, MODE=QPSK(1), AMC_OVERRIDE=1
    axil_write_mapper(8'h00, 32'h0000_0131);

    // Diff Enc/Dec: ENABLE=1, MODE=DQPSK(1)
    axil_write_de(8'h00, 32'h0000_0031);
    axil_write_dd(8'h00, 32'h0000_0031);

    // Slicer: ENABLE=1, MODE=QPSK(1), AMC_OVERRIDE=1
    axil_write_sl(8'h00, 32'h0000_0131);

    // PRBS: SEED, FRAME_LEN, then CTRL (ENABLE=1 | SW_RESET=1 | MODE=PRBS31)
    axil_write_prbs(8'h08, 32'h0000_0001);
    axil_write_prbs(8'h0C, {16'd0, PAYLOAD_BYTES[15:0]});
    axil_write_prbs(8'h00, 32'h0000_0031);
  end

  // No self-checking; stop the sim whenever you’re done inspecting waves.

endmodule

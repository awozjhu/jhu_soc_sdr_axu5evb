`timescale 1ns/1ps
module tb_full_chain_no_fec;

  // ------------------------------------------------------------
  // Parameters
  // ------------------------------------------------------------
  localparam int CLK_PER_NS    = 4;      // 250 MHz
  localparam int PAYLOAD_BYTES = 256;    // per frame
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

  // AXI-Lite domain
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
  // TX: (optional) Scrambler BYPASS → Mapper
  // ------------------------------------------------------------
  logic [7:0] scr_tdata;  logic scr_tvalid, scr_tready, scr_tlast;

  byte_scrambler #(.LFSR_W(7), .TAP_MASK(7'b1001000)) u_scr_tx (
    .clk(clk), .rst_n(rst_n),
    .in_data (prbs_tdata), .in_valid(prbs_tvalid), .in_ready(prbs_tready),
    .out_data(scr_tdata),  .out_valid(scr_tvalid), .out_ready(scr_tready),
    .cfg_enable(1'b1), .cfg_bypass(1'b1), .cfg_seed_wr(1'b0), .cfg_seed('0),
    .running_pulse()
  );
  assign scr_tlast = prbs_tlast;

  // Mapper
  logic        map_in_valid, map_in_ready, map_in_last;
  logic [7:0]  map_in_data;
  logic        map_out_valid, map_out_ready, map_out_last;
  logic [31:0] map_out_data;

  assign map_in_valid = scr_tvalid;
  assign map_in_data  = scr_tdata;
  assign map_in_last  = scr_tlast;
  assign scr_tready   = map_in_ready;

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

  // ------------------------------------------------------------
  // RX: Slicer (directly from Mapper)
  // ------------------------------------------------------------
  logic        sl_in_valid, sl_in_ready, sl_in_last;
  logic [31:0] sl_in_data;
  logic        sl_out_valid, sl_out_last;
  logic [7:0]  sl_out_data;
  logic        sl_out_ready;

  // Connect mapper → slicer
  assign sl_in_valid   = map_out_valid;
  assign sl_in_data    = map_out_data;
  assign sl_in_last    = map_out_last;
  assign map_out_ready = sl_in_ready;

  // Always ready at the sink for this test
  assign sl_out_ready = 1'b1;

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
    .s_axi_rdata (sl_rdata),  .s_axi_rresp(sl_rresp), .s_axi_rvalid(sl_rvalid), .s_axi_rready(sl_rready)
  );

  // ------------------------------------------------------------
  // COMMENTED OUT modules for step 1
  // ------------------------------------------------------------
  /*
  // diff_encoder u_diff_enc ( ... );
  // PreambleInserter u_preamble_ins ( ... );
  // tx_packetizer u_tx_pkt ( ... );
  // rx_depacketizer u_rx_depkt ( ... );
  // PreambleCorrelator u_pcorr ( ... );
  // diff_decoder u_diff_dec ( ... );
  // byte_scrambler u_scr_rx ( ... );
  */

  // ------------------------------------------------------------
  // Scoreboard: PRBS bytes vs slicer bytes (handshake-accurate)
  // ------------------------------------------------------------
  byte unsigned tx_q[$];
  int mismatches = 0;

  // Capture accepted TX PRBS bytes
  always_ff @(posedge clk) begin
    if (prbs_tvalid && prbs_tready) begin
      tx_q.push_back(prbs_tdata);
    end
  end

  // Compare when a byte exits the slicer
  always_ff @(posedge clk) begin
    if (sl_out_valid && sl_out_ready) begin
      if (tx_q.size() == 0) begin
        $display("[%0t] RX byte with empty TX queue!", $time);
        mismatches++;
      end else begin
        byte unsigned exp = tx_q.pop_front();
        if (sl_out_data !== exp) begin
          $display("[%0t] MISM exp=0x%02x got=0x%02x", $time, exp, sl_out_data);
          mismatches++;
        end
      end
    end
  end

  // ------------------------------------------------------------
  // AXI-Lite write tasks (Vivado-safe)
  // ------------------------------------------------------------
  task automatic axil_write_mapper(input byte addr, input logic [31:0] data);
  begin
    m_awaddr  <= addr;  m_awvalid <= 1'b1;
    m_wdata   <= data;  m_wstrb   <= 4'hF;  m_wvalid <= 1'b1;
    do @(posedge s_axi_aclk); while (!(m_awready && m_wready));
    m_awvalid <= 1'b0;  m_wvalid  <= 1'b0;
    do @(posedge s_axi_aclk); while (!m_bvalid);
    m_bready  <= 1'b1;  @(posedge s_axi_aclk);  m_bready <= 1'b0;
  end
  endtask

  task automatic axil_write_sl(input byte addr, input logic [31:0] data);
  begin
    sl_awaddr <= addr; sl_awvalid <= 1'b1;
    sl_wdata  <= data; sl_wstrb   <= 4'hF;  sl_wvalid <= 1'b1;
    do @(posedge s_axi_aclk); while (!(sl_awready && sl_wready));
    sl_awvalid <= 1'b0; sl_wvalid <= 1'b0;
    do @(posedge s_axi_aclk); while (!sl_bvalid);
    sl_bready  <= 1'b1; @(posedge s_axi_aclk); sl_bready <= 1'b0;
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
  // Programming sequence
  // ------------------------------------------------------------
  initial begin
    // drive all *_awvalid/*_wvalid/*_bready low first
    {m_awvalid,m_wvalid,m_bready,m_arvalid,m_rready} = '0;
    {sl_awvalid,sl_wvalid,sl_bready,sl_arvalid,sl_rready} = '0;
    {prbs_awvalid,prbs_wvalid,prbs_bready,prbs_arvalid,prbs_rready} = '0;
    m_awaddr=0; m_wdata=0; m_wstrb=0;
    sl_awaddr=0; sl_wdata=0; sl_wstrb=0;
    prbs_awaddr=0; prbs_wdata=0; prbs_wstrb=0;

    wait (s_axi_aresetn); @(posedge s_axi_aclk);

    // Mapper: ENABLE=1, MODE=QPSK(1), AMC_OVERRIDE=1
    axil_write_mapper(8'h00, 32'h0000_0131);

    // Slicer: ENABLE=1, MODE=QPSK(1), AMC_OVERRIDE=1
    axil_write_sl(8'h00, 32'h0000_0131);

    // PRBS: SEED=1, FRAME_LEN=PAYLOAD_BYTES, CTRL: ENABLE=1 | SW_RESET=1 | MODE=PRBS31
    axil_write_prbs(8'h08, 32'h0000_0001);
    axil_write_prbs(8'h0C, {16'd0, PAYLOAD_BYTES[15:0]});
    axil_write_prbs(8'h00, 32'h0000_0031);
  end

  // ------------------------------------------------------------
  // End-of-test / timeout
  // ------------------------------------------------------------
  initial begin
    fork
      begin : timeout
        repeat (200000) @(posedge clk);
        $fatal(1, "[TB] TIMEOUT");
      end
      begin : done
        // let a bunch of bytes flow
        repeat (PAYLOAD_BYTES+64) @(posedge clk);
        $display("[TB] Mismatches=%0d", mismatches);
        if (mismatches==0) $display("[TB] *** PASS (mapper↔slicer) ***");
        else               $display("[TB] *** FAIL (mapper↔slicer) ***");
        #20 $finish;
      end
    join_any
    disable fork;
  end

endmodule

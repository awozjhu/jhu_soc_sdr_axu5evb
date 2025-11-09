`timescale 1ns/1ps
module tb_full_chain_no_fec;

  // ------------------------------------------------------------
  // Parameters
  // ------------------------------------------------------------
  localparam int CLK_PER_NS    = 4;      // 250 MHz
  localparam int PAYLOAD_BYTES = 256;    // per PRBS frame
  localparam int N_FRAMES      = 2;

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
  // PRBS → (mapper) → diff_encoder → diff_decoder → slicer
  // ------------------------------------------------------------

  // Mapper
  logic        map_in_valid, map_in_ready, map_in_last;
  logic [7:0]  map_in_data;
  logic        map_out_valid, map_out_ready, map_out_last;
  logic [31:0] map_out_data;

  // Connect PRBS directly into mapper (scrambler removed for this step)
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
    .amc_mode_i(3'd0), .amc_mode_valid_i(1'b0),   // using local CTRL (AMC_OVERRIDE=1)
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

  // Diff Decoder
  logic        dd_in_valid, dd_in_ready, dd_in_last;
  logic [31:0] dd_in_data;
  logic        dd_out_valid, dd_out_ready, dd_out_last;
  logic [31:0] dd_out_data;

  assign dd_in_valid  = de_out_valid;
  assign dd_in_data   = de_out_data;
  assign dd_in_last   = de_out_last;
  assign de_out_ready = dd_in_ready;

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
    .out_valid(dd_out_valid), .out_ready(dd_out_ready),
    .out_data (dd_out_data),  .out_last (dd_out_last),
    .s_axi_aclk(s_axi_aclk), .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(dd_awaddr), .s_axi_awvalid(dd_awvalid), .s_axi_awready(dd_awready),
    .s_axi_wdata (dd_wdata),  .s_axi_wstrb(dd_wstrb), .s_axi_wvalid(dd_wvalid), .s_axi_wready(dd_wready),
    .s_axi_bresp (dd_bresp),  .s_axi_bvalid(dd_bvalid), .s_axi_bready(dd_bready),
    .s_axi_araddr(dd_araddr), .s_axi_arvalid(dd_arvalid), .s_axi_arready(dd_arready),
    .s_axi_rdata (dd_rdata),  .s_axi_rresp(dd_rresp), .s_axi_rvalid(dd_rvalid), .s_axi_rready(dd_rready)
  );

  // Slicer (sink always-ready here)
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
    .amc_mode_i(3'd0), .amc_mode_valid_i(1'b0),   // using local CTRL (AMC_OVERRIDE=1)
    .s_axi_aclk(s_axi_aclk), .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(sl_awaddr), .s_axi_awvalid(sl_awvalid), .s_axi_awready(sl_awready),
    .s_axi_wdata (sl_wdata),  .s_axi_wstrb(sl_wstrb), .s_axi_wvalid(sl_wvalid), .s_axi_wready(sl_wready),
    .s_axi_bresp (sl_bresp),  .s_axi_bvalid(sl_bvalid), .s_axi_bready(sl_bready),
    .s_axi_araddr(sl_araddr), .s_axi_arvalid(sl_arvalid), .s_axi_arready(sl_arready),
    .s_axi_rdata (sl_rdata),  .s_axi_rresp(sl_rresp), .s_axi_rvalid(sl_rvalid), .s_axi_rready(sl_rready)
  );

  // Always-ready sink for this step
  assign sl_out_ready = 1'b1;

  // ------------------------------------------------------------
  // COMMENTED OUT modules not used in this step
  // ------------------------------------------------------------
  /*
  // byte_scrambler u_scr_tx ( ... );
  // PreambleInserter u_preamble_ins ( ... );
  // tx_packetizer   u_tx_pkt ( ... );
  // rx_depacketizer u_rx_depkt ( ... );
  // PreambleCorrelator u_pcorr ( ... );
  // byte_scrambler u_scr_rx ( ... );
  */

  // ------------------------------------------------------------
  // Scoreboard: PRBS bytes vs slicer bytes (handshake-aligned)
  // ------------------------------------------------------------
  byte unsigned tx_q[$];
  int mismatches = 0;

  always_ff @(posedge clk) begin
    if (prbs_tvalid && prbs_tready)
      tx_q.push_back(prbs_tdata);
  end

  always_ff @(posedge clk) begin
    if (sl_out_valid && sl_out_ready) begin
      if (tx_q.size() == 0) begin
        $display("[%0t] RX byte with empty TX queue!", $time);
        mismatches++;
      end else begin
        byte unsigned exp = tx_q.pop_front();
        if (sl_out_data !== exp) begin
          $display("[%0t] MISMATCH exp=%02x got=%02x", $time, exp, sl_out_data);
          mismatches++;
        end
      end
    end
  end

  // ------------------------------------------------------------
  // AXI-Lite write tasks (Vivado-safe; hold VALID until READY)
  // ------------------------------------------------------------
  task automatic axil_write_mapper(input byte addr, input logic [31:0] data);
  begin
    m_awaddr <= addr; m_awvalid <= 1; m_wdata <= data; m_wstrb <= 4'hF; m_wvalid <= 1;
    do @(posedge s_axi_aclk); while (!(m_awready && m_wready));
    m_awvalid <= 0;  m_wvalid <= 0;
    do @(posedge s_axi_aclk); while (!m_bvalid);
    m_bready <= 1; @(posedge s_axi_aclk); m_bready <= 0;
  end endtask

  task automatic axil_write_de(input byte addr, input logic [31:0] data);
  begin
    de_awaddr <= addr; de_awvalid <= 1; de_wdata <= data; de_wstrb <= 4'hF; de_wvalid <= 1;
    do @(posedge s_axi_aclk); while (!(de_awready && de_wready));
    de_awvalid <= 0;  de_wvalid <= 0;
    do @(posedge s_axi_aclk); while (!de_bvalid);
    de_bready <= 1; @(posedge s_axi_aclk); de_bready <= 0;
  end endtask

  task automatic axil_write_dd(input byte addr, input logic [31:0] data);
  begin
    dd_awaddr <= addr; dd_awvalid <= 1; dd_wdata <= data; dd_wstrb <= 4'hF; dd_wvalid <= 1;
    do @(posedge s_axi_aclk); while (!(dd_awready && dd_wready));
    dd_awvalid <= 0;  dd_wvalid <= 0;
    do @(posedge s_axi_aclk); while (!dd_bvalid);
    dd_bready <= 1; @(posedge s_axi_aclk); dd_bready <= 0;
  end endtask

  task automatic axil_write_sl(input byte addr, input logic [31:0] data);
  begin
    sl_awaddr <= addr; sl_awvalid <= 1; sl_wdata <= data; sl_wstrb <= 4'hF; sl_wvalid <= 1;
    do @(posedge s_axi_aclk); while (!(sl_awready && sl_wready));
    sl_awvalid <= 0;  sl_wvalid <= 0;
    do @(posedge s_axi_aclk); while (!sl_bvalid);
    sl_bready <= 1; @(posedge s_axi_aclk); sl_bready <= 0;
  end endtask

  task automatic axil_write_prbs(input byte addr8, input logic [31:0] data);
    logic [5:0] a6;
  begin
    a6 = addr8[5:0];
    prbs_awaddr <= a6; prbs_awvalid <= 1; prbs_wdata <= data; prbs_wstrb <= 4'hF; prbs_wvalid <= 1;
    do @(posedge s_axi_aclk); while (!(prbs_awready && prbs_wready));
    prbs_awvalid <= 0;  prbs_wvalid <= 0;
    do @(posedge s_axi_aclk); while (!prbs_bvalid);
    prbs_bready <= 1; @(posedge s_axi_aclk); prbs_bready <= 0;
  end endtask

  // tie off unused AR on all slaves to avoid Xs
  initial begin
    m_araddr='0;  m_arvalid=0;  m_rready=0;
    de_araddr='0; de_arvalid=0; de_rready=0;
    dd_araddr='0; dd_arvalid=0; dd_rready=0;
    sl_araddr='0; sl_arvalid=0; sl_rready=0;
    prbs_araddr='0; prbs_arvalid=0; prbs_rready=0;
  end

  // ------------------------------------------------------------
  // Programming sequence (BPSK + DBPSK so diff cancels)
  // ------------------------------------------------------------
  initial begin
    // default low at t=0
    {m_awvalid,m_wvalid,m_bready,m_arvalid,m_rready} = '0;
    {de_awvalid,de_wvalid,de_bready,de_arvalid,de_rready} = '0;
    {dd_awvalid,dd_wvalid,dd_bready,dd_arvalid,dd_rready} = '0;
    {sl_awvalid,sl_wvalid,sl_bready,sl_arvalid,sl_rready} = '0;
    {prbs_awvalid,prbs_wvalid,prbs_bready,prbs_arvalid,prbs_rready} = '0;
    m_awaddr=0; m_wdata=0; m_wstrb=0;
    de_awaddr=0; de_wdata=0; de_wstrb=0;
    dd_awaddr=0; dd_wdata=0; dd_wstrb=0;
    sl_awaddr=0; sl_wdata=0; sl_wstrb=0;
    prbs_awaddr=0; prbs_wdata=0; prbs_wstrb=0;

    wait (s_axi_aresetn); @(posedge s_axi_aclk);

    // Mapper: ENABLE=1, BYPASS=1 (force BPSK on I), AMC_OVERRIDE=1 → 0x00000103
    axil_write_mapper(8'h00, 32'h0000_0103);

    // Diff Enc/Dec: ENABLE=1, MODE=DBPSK (0), SW_RESET pulse → 0x00000005
    axil_write_de(8'h00, 32'h0000_0005);
    axil_write_dd(8'h00, 32'h0000_0005);

    // Slicer: ENABLE=1, BYPASS=1 (BPSK decisions), AMC_OVERRIDE=1 → 0x00000103
    axil_write_sl(8'h00, 32'h0000_0103);

    // PRBS: SEED, FRAME_LEN, then CTRL (ENABLE=1 | MODE=PRBS31). 0x31 matches your prior runs.
    axil_write_prbs(8'h08, 32'h0000_0001);                         // SEED=1
    axil_write_prbs(8'h0C, {16'd0, PAYLOAD_BYTES[15:0]});          // FRMLEN=payload bytes
    axil_write_prbs(8'h00, 32'h0000_0031);                         // CTRL: ENABLE=1, MODE=3 (PRBS31)
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
        // let two PRBS frames flow through
        int frames_seen = 0;
        forever begin
          @(posedge clk);
          if (prbs_tvalid && prbs_tready && prbs_tlast) frames_seen++;
          if (frames_seen >= N_FRAMES) begin
            repeat (2000) @(posedge clk); // drain pipeline
            $display("[TB] Mismatches=%0d", mismatches);
            if (mismatches==0) $display("[TB] *** PASS (PRBS→BPSK map→DBPSK enc/dec→BPSK slice) ***");
            else               $display("[TB] *** FAIL (%0d mismatches) ***", mismatches);
            #20 $finish;
          end
        end
      end
    join_any
    disable fork;
  end

endmodule

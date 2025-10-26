// tb_sdr_chain_prbs.sv (fixed)
// - Replaced `int unsigned` with `logic [31:0]`
// - Moved all declarations before statements
// - Separated `diff` declaration from its assignment

`timescale 1ns/1ps

module tb_sdr_chain_prbs;
  // ---------------------------------------------------------------------------
  // Clock / Reset
  // ---------------------------------------------------------------------------
  logic clk = 0;
  always #5 clk = ~clk; // 100 MHz

  logic rst_n = 0;

  // ---------------------------------------------------------------------------
  // DUT: sdr_chain (64-bit AXIS)
  // ---------------------------------------------------------------------------
  localparam int SDR_AXIL_AW = 12; // sdr_chain addr width
  // AXI-Lite (sdr_chain)
  logic [SDR_AXIL_AW-1:0] sc_awaddr, sc_araddr;
  logic sc_awvalid, sc_awready;
  logic [31:0] sc_wdata;
  logic [3:0]  sc_wstrb;
  logic        sc_wvalid, sc_wready;
  logic [1:0]  sc_bresp;
  logic        sc_bvalid, sc_bready;
  logic        sc_arvalid, sc_arready;
  logic [31:0] sc_rdata;
  logic [1:0]  sc_rresp;
  logic        sc_rvalid, sc_rready;

  // AXIS ALT (64-bit from PRBS packer)
  logic [63:0] sc_s_alt_tdata;
  logic [7:0]  sc_s_alt_tkeep;
  logic        sc_s_alt_tvalid;
  logic        sc_s_alt_tready;
  logic        sc_s_alt_tlast;

  // AXIS RX (unused in this TB)
  logic [63:0] sc_s_rx_tdata   = '0;
  logic [7:0]  sc_s_rx_tkeep   = '0;
  logic        sc_s_rx_tvalid  = 1'b0;
  logic        sc_s_rx_tready;
  logic        sc_s_rx_tlast   = 1'b0;

  // AXIS TX (sink)
  logic [63:0] sc_m_tx_tdata;
  logic [7:0]  sc_m_tx_tkeep;
  logic        sc_m_tx_tvalid;
  logic        sc_m_tx_tready = 1'b1;
  logic        sc_m_tx_tlast;

  sdr_chain u_sdr_chain (
    .clk   (clk),
    .rst_n (rst_n),

    // AXI-Lite
    .s_axil_awaddr (sc_awaddr),
    .s_axil_awvalid(sc_awvalid),
    .s_axil_awready(sc_awready),
    .s_axil_wdata  (sc_wdata),
    .s_axil_wstrb  (sc_wstrb),
    .s_axil_wvalid (sc_wvalid),
    .s_axil_wready (sc_wready),
    .s_axil_bresp  (sc_bresp),
    .s_axil_bvalid (sc_bvalid),
    .s_axil_bready (sc_bready),
    .s_axil_araddr (sc_araddr),
    .s_axil_arvalid(sc_arvalid),
    .s_axil_arready(sc_arready),
    .s_axil_rdata  (sc_rdata),
    .s_axil_rresp  (sc_rresp),
    .s_axil_rvalid (sc_rvalid),
    .s_axil_rready (sc_rready),
    ._saxi_params_unused(),

    // AXIS RX (unused)
    .s_axis_rx_tdata (sc_s_rx_tdata),
    .s_axis_rx_tkeep (sc_s_rx_tkeep),
    .s_axis_rx_tvalid(sc_s_rx_tvalid),
    .s_axis_rx_tready(sc_s_rx_tready),
    .s_axis_rx_tlast (sc_s_rx_tlast),

    // AXIS ALT (from PRBS packer)
    .s_axis_alt_tdata (sc_s_alt_tdata),
    .s_axis_alt_tkeep (sc_s_alt_tkeep),
    .s_axis_alt_tvalid(sc_s_alt_tvalid),
    .s_axis_alt_tready(sc_s_alt_tready),
    .s_axis_alt_tlast (sc_s_alt_tlast),

    // AXIS TX (to sink)
    .m_axis_tx_tdata (sc_m_tx_tdata),
    .m_axis_tx_tkeep (sc_m_tx_tkeep),
    .m_axis_tx_tvalid(sc_m_tx_tvalid),
    .m_axis_tx_tready(sc_m_tx_tready),
    .m_axis_tx_tlast (sc_m_tx_tlast),
    ._maxis_params_unused()
  );

  // ---------------------------------------------------------------------------
  // PRBS source (8-bit AXIS master with AXI-Lite)
  // ---------------------------------------------------------------------------
  localparam int PRBS_AXIL_AW = 6;

  // AXI-Lite (prbs)
  logic [PRBS_AXIL_AW-1:0] pr_awaddr, pr_araddr;
  logic pr_awvalid, pr_awready;
  logic [31:0] pr_wdata;
  logic [3:0]  pr_wstrb;
  logic        pr_wvalid, pr_wready;
  logic [1:0]  pr_bresp;
  logic        pr_bvalid, pr_bready;
  logic        pr_arvalid, pr_arready;
  logic [31:0] pr_rdata;
  logic [1:0]  pr_rresp;
  logic        pr_rvalid, pr_rready;

  // AXIS (8-bit)
  logic [7:0]  pr_m_tdata;
  logic        pr_m_tvalid;
  logic        pr_m_tready;
  logic        pr_m_tlast;

  prbs_axi_stream u_prbs (
    .clk   (clk),
    .rst_n (rst_n),

    // AXI-Lite
    .s_axil_awaddr (pr_awaddr),
    .s_axil_awvalid(pr_awvalid),
    .s_axil_awready(pr_awready),
    .s_axil_wdata  (pr_wdata),
    .s_axil_wstrb  (pr_wstrb),
    .s_axil_wvalid (pr_wvalid),
    .s_axil_wready (pr_wready),
    .s_axil_bresp  (pr_bresp),
    .s_axil_bvalid (pr_bvalid),
    .s_axil_bready (pr_bready),
    .s_axil_araddr (pr_araddr),
    .s_axil_arvalid(pr_arvalid),
    .s_axil_arready(pr_arready),
    .s_axil_rdata  (pr_rdata),
    .s_axil_rresp  (pr_rresp),
    .s_axil_rvalid (pr_rvalid),
    .s_axil_rready (pr_rready),

    // AXIS master (8-bit)
    .m_axis_tdata  (pr_m_tdata),
    .m_axis_tvalid (pr_m_tvalid),
    .m_axis_tready (pr_m_tready),
    .m_axis_tlast  (pr_m_tlast)
  );

  // ---------------------------------------------------------------------------
  // Simple AXIS 8 -> 64 width packer (behavioral)
  // ---------------------------------------------------------------------------
  axis_8to64_packer u_pack (
    .aclk    (clk),
    .aresetn (rst_n),

    .s_tdata (pr_m_tdata),
    .s_tvalid(pr_m_tvalid),
    .s_tready(pr_m_tready),
    .s_tlast (pr_m_tlast),

    .m_tdata (sc_s_alt_tdata),
    .m_tkeep (sc_s_alt_tkeep),
    .m_tvalid(sc_s_alt_tvalid),
    .m_tready(sc_s_alt_tready),
    .m_tlast (sc_s_alt_tlast)
  );

  // ---------------------------------------------------------------------------
  // AXI-Lite helper tasks
  // ---------------------------------------------------------------------------
  task automatic axil_write_sdr(input [SDR_AXIL_AW-1:0] addr, input [31:0] data);
    begin
      sc_awaddr  <= addr;
      sc_wdata   <= data;
      sc_wstrb   <= 4'hF;
      sc_awvalid <= 1'b1;
      sc_wvalid  <= 1'b1;
      sc_bready  <= 1'b1;
      @(posedge clk);
      wait (sc_awready); @(posedge clk); sc_awvalid <= 1'b0;
      wait (sc_wready ); @(posedge clk); sc_wvalid  <= 1'b0;
      wait (sc_bvalid ); @(posedge clk); sc_bready  <= 1'b0;
    end
  endtask

  task automatic axil_read_sdr(input [SDR_AXIL_AW-1:0] addr, output [31:0] data);
    begin
      sc_araddr  <= addr;
      sc_arvalid <= 1'b1;
      sc_rready  <= 1'b1;
      @(posedge clk);
      wait (sc_arready); @(posedge clk); sc_arvalid <= 1'b0;
      wait (sc_rvalid ); data = sc_rdata; @(posedge clk); sc_rready <= 1'b0;
    end
  endtask

  task automatic axil_write_prbs(input [PRBS_AXIL_AW-1:0] addr, input [31:0] data);
    begin
      pr_awaddr  <= addr;
      pr_wdata   <= data;
      pr_wstrb   <= 4'hF;
      pr_awvalid <= 1'b1;
      pr_wvalid  <= 1'b1;
      pr_bready  <= 1'b1;
      @(posedge clk);
      wait (pr_awready); @(posedge clk); pr_awvalid <= 1'b0;
      wait (pr_wready ); @(posedge clk); pr_wvalid  <= 1'b0;
      wait (pr_bvalid ); @(posedge clk); pr_bready  <= 1'b0;
    end
  endtask

  task automatic axil_read_prbs(input [PRBS_AXIL_AW-1:0] addr, output [31:0] data);
    begin
      pr_araddr  <= addr;
      pr_arvalid <= 1'b1;
      pr_rready  <= 1'b1;
      @(posedge clk);
      wait (pr_arready); @(posedge clk); pr_arvalid <= 1'b0;
      wait (pr_rvalid ); data = pr_rdata; @(posedge clk); pr_rready <= 1'b0;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Test sequence
  // ---------------------------------------------------------------------------
  localparam [SDR_AXIL_AW-1:0] SDR_CTRL      = 12'h000;
  localparam [SDR_AXIL_AW-1:0] SDR_STATUS    = 12'h004;
  localparam [SDR_AXIL_AW-1:0] SDR_BYTES_TX  = 12'h010;
  localparam [SDR_AXIL_AW-1:0] SDR_FRMS_TX   = 12'h014;

  localparam [PRBS_AXIL_AW-1:0] PRBS_CTRL   = 6'h00;
  localparam [PRBS_AXIL_AW-1:0] PRBS_STATUS = 6'h04;
  localparam [PRBS_AXIL_AW-1:0] PRBS_SEED   = 6'h08;
  localparam [PRBS_AXIL_AW-1:0] PRBS_FLEN   = 6'h0C;
  localparam [PRBS_AXIL_AW-1:0] PRBS_BCNT   = 6'h18;
  localparam [PRBS_AXIL_AW-1:0] PRBS_BITCNT = 6'h1C;

  // Decls moved before statements:
  logic [31:0] sdr_bytes, sdr_frames, prbs_bytes, status_after;
  int          diff;

  initial begin
    // Defaults
    sc_awaddr = '0; sc_awvalid = 0; sc_wdata = 0; sc_wstrb = 4'h0; sc_wvalid = 0; sc_bready = 0;
    sc_araddr = '0; sc_arvalid = 0; sc_rready = 0;

    pr_awaddr = '0; pr_awvalid = 0; pr_wdata = 0; pr_wstrb = 4'h0; pr_wvalid = 0; pr_bready = 0;
    pr_araddr = '0; pr_arvalid = 0; pr_rready = 0;

    // Reset
    rst_n = 0;
    repeat (10) @(posedge clk);
    rst_n = 1;
    repeat (10) @(posedge clk);

    // --- Configure PRBS: continuous, PRBS31, enable ---
    axil_write_prbs(PRBS_FLEN, 32'd0);            // FRAME_LEN_BYTES=0 -> continuous (no TLAST)
    axil_write_prbs(PRBS_SEED, 32'hACE1_1234);    // optional
    axil_write_prbs(PRBS_CTRL, (3<<4) | 1);       // MODE=3(PRBS31), ENABLE=1

    // --- Configure sdr_chain: SRC_SEL=ALT (1), ENABLE=1 ---
    axil_write_sdr(SDR_CTRL, 32'h0000_0011);      // [7:4]=1, [0]=1

    // Let it run a bit
    repeat (2000) @(posedge clk);

    // Read counters
    axil_read_sdr (SDR_BYTES_TX, sdr_bytes);
    axil_read_sdr (SDR_FRMS_TX,  sdr_frames);
    axil_read_prbs(PRBS_BCNT,    prbs_bytes);

    $display("[TB] SDR_BYTES_TX = %0d", sdr_bytes);
    $display("[TB] SDR_FRMS_TX  = %0d", sdr_frames);
    $display("[TB] PRBS_BYTECNT = %0d", prbs_bytes);

    // Basic checks
    if (sdr_bytes == 0) begin
      $fatal(1, "[TB] ERROR: sdr_chain BYTES_TX did not increment.");
    end

    // The packer may hold up to 7 residual bytes when we stop sampling.
    diff = (prbs_bytes > sdr_bytes) ? (prbs_bytes - sdr_bytes) : (sdr_bytes - prbs_bytes);
    if (diff > 7) begin
      $fatal(1, "[TB] ERROR: Byte counters diverged by %0d (>7).", diff);
    end else begin
      $display("[TB] PASS: Byte counters consistent (diff=%0d).", diff);
    end

    // Clear RUNNING and re-read (optional)
    axil_write_sdr(SDR_STATUS, 32'h1); // W1C
    axil_read_sdr(SDR_STATUS, status_after);
    if (status_after[0] !== 1'b0) $fatal(1, "[TB] ERROR: RUNNING sticky bit did not clear.");

    $display("[TB] All checks passed. Finishing.");
    #50;
    $finish;
  end

  // Optional: simple assertion
  property no_rx_when_alt;
    @(posedge clk) disable iff (!rst_n)
      sc_m_tx_tvalid && sc_m_tx_tready |-> (sc_s_rx_tvalid === 1'b0);
  endproperty
  assert property (no_rx_when_alt);

endmodule


// -----------------------------------------------------------------------------
// Axis 8->64 packer (behavioral for simulation)
// -----------------------------------------------------------------------------
module axis_8to64_packer (
  input  logic        aclk,
  input  logic        aresetn,

  input  logic [7:0]  s_tdata,
  input  logic        s_tvalid,
  output logic        s_tready,
  input  logic        s_tlast,

  output logic [63:0] m_tdata,
  output logic [7:0]  m_tkeep,
  output logic        m_tvalid,
  input  logic        m_tready,
  output logic        m_tlast
);
  logic [63:0] data_q;
  logic [7:0]  keep_q;
  logic [2:0]  idx_q;       // 0..7
  logic        out_valid_q;
  logic        out_last_q;

  assign m_tdata  = data_q;
  assign m_tkeep  = keep_q;
  assign m_tvalid = out_valid_q;
  assign m_tlast  = out_last_q;

  // Accept input only when we're not holding an output word
  assign s_tready = aresetn && !out_valid_q;

  wire push = s_tvalid && s_tready;
  wire pop  = out_valid_q && m_tready;

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      data_q      <= '0;
      keep_q      <= '0;
      idx_q       <= 3'd0;
      out_valid_q <= 1'b0;
      out_last_q  <= 1'b0;
    end else begin
      // Consume output when downstream ready
      if (pop) begin
        out_valid_q <= 1'b0;
        out_last_q  <= 1'b0;
        data_q      <= '0;
        keep_q      <= '0;
        idx_q       <= 3'd0;
      end

      // Pack incoming byte
      if (push) begin
        data_q[idx_q*8 +: 8] <= s_tdata;
        keep_q[idx_q]        <= 1'b1;

        // Decide if this completes an output word
        if (s_tlast || (idx_q == 3'd7)) begin
          out_valid_q <= 1'b1;
          out_last_q  <= s_tlast;      // propagate frame boundary if present
          // idx_q will be reset on pop
        end else begin
          idx_q <= idx_q + 3'd1;
        end
      end
    end
  end
endmodule

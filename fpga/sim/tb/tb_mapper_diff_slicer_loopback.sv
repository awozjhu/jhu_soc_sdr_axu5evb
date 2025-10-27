/*-----------------------------------------------------------------------------
  Testbench: tb_mapper_diff_slicer_loopback
  Purpose:
    File-driven loopback that exercises the full chain using golden input bytes.
    The mapper converts bytes→bits→Q1.15 symbols; the diff-decoder converts
    symbols→phase-increments; the diff-encoder reconstructs symbols; the
    slicer converts symbols→bits→bytes. Output CSV should match input CSV.

  Topology:
      CSV (bytes)
        → mapper
        → diff_decoder
        → diff_encoder
        → slicer
        → CSV (bytes)

  Stimulus (input CSV):
    - Path set below (absolute or relative)
    - Format with header: "byte_idx,data,tlast"
    - Generator guarantees K*frameLen is byte-aligned (TLAST aligns to bytes)

  Protocol / conventions:
    - AXIS-like: valid/ready/last only
    - Mapper/Slicer bit packing is LITTLE-ENDIAN
    - Q1.15 for I/Q
    - QPSK Gray (b0=sign(I), b1=sign(Q)); slicer thresholds at 0

  AXI-Lite CTRL writes:
    - mapper, slicer: 0x0000_0111 (ENABLE=1, MODE=QPSK, AMC_OVERRIDE=1, BYPASS=0)
    - diff_decoder, diff_encoder (MODE = DQPSK):
        write 0x0000_0014 (SW_RESET|MODE) then 0x0000_0011 (ENABLE|MODE)

  End-of-test:
    - When captured byte count equals sent byte count → PASS and finish
-----------------------------------------------------------------------------*/
`timescale 1ns/1ps

module tb_mapper_diff_slicer_loopback;

  // ===== Clocks / Reset (single domain for datapath + AXI-Lite) =====
  logic clk_bb = 1'b0, rst_n = 1'b0;
  logic s_axi_aclk = 1'b0, s_axi_aresetn = 1'b0;

  always #5 clk_bb     = ~clk_bb;     // 100 MHz
  always #5 s_axi_aclk = ~s_axi_aclk; // 100 MHz

  initial begin
    repeat (10) @(posedge clk_bb);
    rst_n         = 1'b1;
    s_axi_aresetn = 1'b1;
  end

  // ===== Mapper byte in =====
  logic        m_in_valid, m_in_ready, m_in_last;
  logic [7:0]  m_in_data;

  // ===== Mapper symbols out =====
  logic        map_sym_valid, map_sym_ready, map_sym_last;
  logic [31:0] map_sym_data;

  // ===== Diff decoder (symbols → increments) =====
  logic        dec_in_valid, dec_in_ready, dec_in_last;
  logic [31:0] dec_in_data;

  logic        inc_valid, inc_ready, inc_last;
  logic [31:0] inc_data;

  // ===== Diff encoder (increments → symbols) =====
  logic        enc_in_valid, enc_in_ready, enc_in_last;
  logic [31:0] enc_in_data;

  logic        enc_sym_valid, enc_sym_ready, enc_sym_last;
  logic [31:0] enc_sym_data;

  // ===== Slicer bytes out =====
  logic        s_out_valid, s_out_ready, s_out_last;
  logic [7:0]  s_out_data;

  // Wire the chain
  assign dec_in_valid = map_sym_valid;
  assign dec_in_data  = map_sym_data;
  assign dec_in_last  = map_sym_last;
  assign map_sym_ready = dec_in_ready;

  assign enc_in_valid = inc_valid;
  assign enc_in_data  = inc_data;
  assign enc_in_last  = inc_last;
  assign inc_ready    = enc_in_ready;

  assign enc_sym_ready = s_in_ready;

  // Slicer symbol input wires
  logic        s_in_valid, s_in_ready, s_in_last;
  logic [31:0] s_in_data;

  assign s_in_valid = enc_sym_valid;
  assign s_in_data  = enc_sym_data;
  assign s_in_last  = enc_sym_last;

  // AMC (ignored by mapper/slicer because AMC_OVERRIDE=1)
  logic [2:0] amc_mode_i = 3'd1;  // QPSK
  logic       amc_mode_valid_i = 1'b0;

  // ===== AXI-Lite: mapper =====
  logic [7:0]  m_awaddr;  logic m_awvalid;  logic m_awready;
  logic [31:0] m_wdata;   logic [3:0] m_wstrb; logic m_wvalid; logic m_wready;
  logic [1:0]  m_bresp;   logic m_bvalid;  logic m_bready;
  logic [7:0]  m_araddr;  logic m_arvalid; logic m_arready;
  logic [31:0] m_rdata;   logic [1:0] m_rresp; logic m_rvalid; logic m_rready;

  // ===== AXI-Lite: slicer =====
  logic [7:0]  s_awaddr;  logic s_awvalid;  logic s_awready;
  logic [31:0] s_wdata;   logic [3:0] s_wstrb; logic s_wvalid; logic s_wready;
  logic [1:0]  s_bresp;   logic s_bvalid;  logic s_bready;
  logic [7:0]  s_araddr;  logic s_arvalid; logic s_arready;
  logic [31:0] s_rdata;   logic [1:0] s_rresp; logic s_rvalid; logic s_rready;

  // ===== AXI-Lite: diff encoder =====
  logic [7:0]  e_awaddr;  logic e_awvalid;  logic e_awready;
  logic [31:0] e_wdata;   logic [3:0] e_wstrb; logic e_wvalid; logic e_wready;
  logic [1:0]  e_bresp;   logic e_bvalid;  logic e_bready;
  logic [7:0]  e_araddr;  logic e_arvalid; logic e_arready;
  logic [31:0] e_rdata;   logic [1:0] e_rresp; logic e_rvalid; logic e_rready;

  // ===== AXI-Lite: diff decoder =====
  logic [7:0]  d_awaddr;  logic d_awvalid;  logic d_awready;
  logic [31:0] d_wdata;   logic [3:0] d_wstrb; logic d_wvalid; logic d_wready;
  logic [1:0]  d_bresp;   logic d_bvalid;  logic d_bready;
  logic [7:0]  d_araddr;  logic d_arvalid; logic d_arready;
  logic [31:0] d_rdata;   logic [1:0] d_rresp; logic d_rvalid; logic d_rready;

  // ===== DUTs =====
  mapper u_mapper (
    .clk_bb(clk_bb), .rst_n(rst_n),
    .in_valid(m_in_valid), .in_ready(m_in_ready), .in_data(m_in_data), .in_last(m_in_last),
    .out_valid(map_sym_valid), .out_ready(map_sym_ready), .out_data(map_sym_data), .out_last(map_sym_last),
    .amc_mode_i(amc_mode_i), .amc_mode_valid_i(amc_mode_valid_i),
    .s_axi_aclk(s_axi_aclk), .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(m_awaddr), .s_axi_awvalid(m_awvalid), .s_axi_awready(m_awready),
    .s_axi_wdata(m_wdata), .s_axi_wstrb(m_wstrb), .s_axi_wvalid(m_wvalid), .s_axi_wready(m_wready),
    .s_axi_bresp(m_bresp), .s_axi_bvalid(m_bvalid), .s_axi_bready(m_bready),
    .s_axi_araddr(m_araddr), .s_axi_arvalid(m_arvalid), .s_axi_arready(m_arready),
    .s_axi_rdata(m_rdata), .s_axi_rresp(m_rresp), .s_axi_rvalid(m_rvalid), .s_axi_rready(m_rready)
  );

  diff_decoder u_ddec (
    .clk_bb(clk_bb), .rst_n(rst_n),
    .in_valid(dec_in_valid), .in_ready(dec_in_ready), .in_data(dec_in_data), .in_last(dec_in_last),
    .out_valid(inc_valid), .out_ready(inc_ready), .out_data(inc_data), .out_last(inc_last),
    .s_axi_aclk(s_axi_aclk), .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(d_awaddr), .s_axi_awvalid(d_awvalid), .s_axi_awready(d_awready),
    .s_axi_wdata(d_wdata), .s_axi_wstrb(d_wstrb), .s_axi_wvalid(d_wvalid), .s_axi_wready(d_wready),
    .s_axi_bresp(d_bresp), .s_axi_bvalid(d_bvalid), .s_axi_bready(d_bready),
    .s_axi_araddr(d_araddr), .s_axi_arvalid(d_arvalid), .s_axi_arready(d_arready),
    .s_axi_rdata(d_rdata), .s_axi_rresp(d_rresp), .s_axi_rvalid(d_rvalid), .s_axi_rready(d_rready)
  );

  diff_encoder u_denc (
    .clk_bb(clk_bb), .rst_n(rst_n),
    .in_valid(enc_in_valid), .in_ready(enc_in_ready), .in_data(enc_in_data), .in_last(enc_in_last),
    .out_valid(enc_sym_valid), .out_ready(enc_sym_ready), .out_data(enc_sym_data), .out_last(enc_sym_last),
    .s_axi_aclk(s_axi_aclk), .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(e_awaddr), .s_axi_awvalid(e_awvalid), .s_axi_awready(e_awready),
    .s_axi_wdata(e_wdata), .s_axi_wstrb(e_wstrb), .s_axi_wvalid(e_wvalid), .s_axi_wready(e_wready),
    .s_axi_bresp(e_bresp), .s_axi_bvalid(e_bvalid), .s_axi_bready(e_bready),
    .s_axi_araddr(e_araddr), .s_axi_arvalid(e_arvalid), .s_axi_arready(e_arready),
    .s_axi_rdata(e_rdata), .s_axi_rresp(e_rresp), .s_axi_rvalid(e_rvalid), .s_axi_rready(e_rready)
  );

  slicer u_slicer (
    .clk_bb(clk_bb), .rst_n(rst_n),
    .in_valid(s_in_valid), .in_ready(s_in_ready), .in_data(s_in_data), .in_last(s_in_last),
    .out_valid(s_out_valid), .out_ready(s_out_ready), .out_data(s_out_data), .out_last(s_out_last),
    .amc_mode_i(amc_mode_i), .amc_mode_valid_i(amc_mode_valid_i),
    .s_axi_aclk(s_axi_aclk), .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(s_awaddr), .s_axi_awvalid(s_awvalid), .s_axi_awready(s_awready),
    .s_axi_wdata(s_wdata), .s_axi_wstrb(s_wstrb), .s_axi_wvalid(s_wvalid), .s_axi_wready(s_wready),
    .s_axi_bresp(s_bresp), .s_axi_bvalid(s_bvalid), .s_axi_bready(s_bready),
    .s_axi_araddr(s_araddr), .s_axi_arvalid(s_arvalid), .s_axi_arready(s_arready),
    .s_axi_rdata(s_rdata), .s_axi_rresp(s_rresp), .s_axi_rvalid(s_rvalid), .s_axi_rready(s_rready)
  );

  // ===== TB defaults =====
  initial begin
    // Streams
    m_in_valid=0; m_in_data=0; m_in_last=0;
    s_out_ready=1;

    // AXI-Lite defaults
    m_awaddr='0; m_awvalid=0; m_wdata='0; m_wstrb='0; m_wvalid=0; m_bready=0;
    m_araddr='0; m_arvalid=0; m_rready=0;

    s_awaddr='0; s_awvalid=0; s_wdata='0; s_wstrb='0; s_wvalid=0; s_bready=0;
    s_araddr='0; s_arvalid=0; s_rready=0;

    e_awaddr='0; e_awvalid=0; e_wdata='0; e_wstrb='0; e_wvalid=0; e_bready=0;
    e_araddr='0; e_arvalid=0; e_rready=0;

    d_awaddr='0; d_awvalid=0; d_wdata='0; d_wstrb='0; d_wvalid=0; d_bready=0;
    d_araddr='0; d_arvalid=0; d_rready=0;
  end

  // ===== AXI-Lite write helpers (hold valids across one extra edge) =====
  task axi_write_m (input byte addr, input int unsigned data);
    begin
      m_awaddr  <= addr;   m_awvalid <= 1'b1;
      m_wdata   <= data;   m_wstrb   <= 4'hF; m_wvalid <= 1'b1;
      wait (m_awready && m_wready); @(posedge s_axi_aclk);
      m_awvalid <= 1'b0;   m_wvalid  <= 1'b0;
      m_bready  <= 1'b1;   wait (m_bvalid); @(posedge s_axi_aclk); m_bready <= 1'b0;
    end
  endtask

  task axi_write_s (input byte addr, input int unsigned data);
    begin
      s_awaddr  <= addr;   s_awvalid <= 1'b1;
      s_wdata   <= data;   s_wstrb   <= 4'hF; s_wvalid <= 1'b1;
      wait (s_awready && s_wready); @(posedge s_axi_aclk);
      s_awvalid <= 1'b0;   s_wvalid  <= 1'b0;
      s_bready  <= 1'b1;   wait (s_bvalid); @(posedge s_axi_aclk); s_bready <= 1'b0;
    end
  endtask

  task axi_write_e (input byte addr, input int unsigned data);
    begin
      e_awaddr  <= addr;   e_awvalid <= 1'b1;
      e_wdata   <= data;   e_wstrb   <= 4'hF; e_wvalid <= 1'b1;
      wait (e_awready && e_wready); @(posedge s_axi_aclk);
      e_awvalid <= 1'b0;   e_wvalid  <= 1'b0;
      e_bready  <= 1'b1;   wait (e_bvalid); @(posedge s_axi_aclk); e_bready <= 1'b0;
    end
  endtask

  task axi_write_d (input byte addr, input int unsigned data);
    begin
      d_awaddr  <= addr;   d_awvalid <= 1'b1;
      d_wdata   <= data;   d_wstrb   <= 4'hF; d_wvalid <= 1'b1;
      wait (d_awready && d_wready); @(posedge s_axi_aclk);
      d_awvalid <= 1'b0;   d_wvalid  <= 1'b0;
      d_bready  <= 1'b1;   wait (d_bvalid); @(posedge s_axi_aclk); d_bready <= 1'b0;
    end
  endtask

  // ===== AXI-Lite configuration for all four DUTs =====
  initial begin
    @(posedge s_axi_aresetn); repeat(2) @(posedge s_axi_aclk);

    // mapper, slicer: ENABLE=1, MODE=QPSK, AMC_OVERRIDE=1, BYPASS=0  (0x111)
    axi_write_m(8'h00, 32'h0000_0111);
    axi_write_s(8'h00, 32'h0000_0111);

    // diff decoder: MODE=DQPSK, SW_RESET→ENABLE
    axi_write_d(8'h00, 32'h0000_0014);  // SW_RESET | MODE(1<<4)
    axi_write_d(8'h00, 32'h0000_0011);  // ENABLE   | MODE(1<<4)

    // diff encoder: MODE=DQPSK, SW_RESET→ENABLE
    axi_write_e(8'h00, 32'h0000_0014);  // SW_RESET | MODE(1<<4)
    axi_write_e(8'h00, 32'h0000_0011);  // ENABLE   | MODE(1<<4)
  end

  // ===== File I/O =====
  // Set this to your absolute path if you want:
  string  csv_in_path  = "C:/Vivado/sdr_project_git/jhu_soc_sdr_axu5evb/fpga/sim/tb/golden/mapper_in_bytes.csv";
  string  csv_out_path = "slicer_out_bytes_with_diff.csv";

  integer fd_in, fd_out;
  string  line_buf;
  int     line_rc;
  int     stim_idx, stim_data, stim_tlast;
  int     bytes_in_total, bytes_out_total;
  bit     sending_done;

  // Drive one byte into mapper (module-scope task; no locals inside blocks)
  task drive_one_byte(input int idx, input [7:0] data_b, input bit last_b);
    begin
      @(posedge clk_bb);
      while (!m_in_ready) @(posedge clk_bb);
      m_in_data  = data_b;
      m_in_last  = last_b;
      m_in_valid = 1'b1;
      @(posedge clk_bb);
      m_in_valid = 1'b0;
      bytes_in_total = bytes_in_total + 1;
    end
  endtask

  // === Reader → Mapper ===
  initial begin
    bytes_in_total = 0; sending_done = 0;

    fd_in = $fopen(csv_in_path, "r");
    if (fd_in == 0) $fatal(1, "[TB] Failed to open input CSV: %s", csv_in_path);

    fd_out = $fopen(csv_out_path, "w");
    if (fd_out == 0) $fatal(1, "[TB] Failed to open output CSV: %s", csv_out_path);
    $fwrite(fd_out, "byte_idx,data,tlast\n");
    bytes_out_total = 0;

    // Skip header once (the file has one)
    line_rc = $fgets(line_buf, fd_in);

    // Main loop — $fgets + $sscanf to avoid EOF spin
    for (;;) begin
      line_rc = $fgets(line_buf, fd_in);
      if (line_rc == 0) break; // EOF

      if ($sscanf(line_buf, "%d,%d,%d", stim_idx, stim_data, stim_tlast) == 3) begin
        drive_one_byte(stim_idx, stim_data[7:0], stim_tlast != 0);
      end
      // else skip malformed/blank lines
    end

    sending_done = 1;
    $fclose(fd_in);
    $display("[TB] Finished sending %0d input bytes.", bytes_in_total);
  end

  // === Capture ← Slicer ===
  always @(posedge clk_bb) begin
    if (s_out_valid && s_out_ready) begin
      $fwrite(fd_out, "%0d,%0d,%0d\n",
              bytes_out_total, s_out_data, s_out_last ? 1 : 0);
      bytes_out_total = bytes_out_total + 1;
    end
  end

  // === Finish when received everything sent ===
  initial begin
    wait (rst_n && s_axi_aresetn);
    forever begin
      @(posedge clk_bb);
      if (sending_done && (bytes_out_total == bytes_in_total)) begin
        repeat (8) @(posedge clk_bb);
        $display("[TB] PASS: bytes_in=%0d  bytes_out=%0d",
                 bytes_in_total, bytes_out_total);
        $fclose(fd_out);
        $finish;
      end
    end
  end

endmodule

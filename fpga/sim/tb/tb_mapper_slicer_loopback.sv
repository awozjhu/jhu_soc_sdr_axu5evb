/*-----------------------------------------------------------------------------
  Testbench: tb_mapper_slicer_loopback
  Purpose:
    File-driven loopback that exercises mapper.sv and slicer.sv together using
    golden input bytes. The mapper converts bytes→bits→Q1.15 symbols; the
    slicer converts symbols→bits→bytes. The captured output is written to a CSV
    with the same schema as the input.

  Topology:
      CSV (bytes) --> mapper --> (I,Q symbols) --> slicer --> CSV (bytes)

  Stimulus (input CSV):
    Path: golden/mapper_in_bytes.csv (or absolute path)
    Format (with header):
      byte_idx,data,tlast
      0,142,0
      1,027,0
      ...
    Notes:
      - data is 0..255
      - tlast is 0/1 and asserted on the last byte of each frame
      - The generator guarantees K*frameLen is a multiple of 8, so TLAST aligns
        to byte boundaries.

  Output capture (output CSV):
    Path: slicer_out_bytes.csv
    Format: identical schema (byte_idx,data,tlast), rows emitted in-order.

  Protocol / conventions:
    - Internal streams are AXIS-like: valid/ready/last only.
    - Bit packing is LITTLE-ENDIAN (first bit maps to bit 0 of a byte).
    - Q1.15 for I/Q samples.
    - QPSK Gray convention used by both blocks:
        b0 = sign(I), b1 = sign(Q). BYPASS forces BPSK (I-only).
      Threshold at zero is used in the slicer for sign decisions.

  AXI-Lite configuration (both DUTs):
    CTRL: ENABLE=1, BYPASS=0, MODE=QPSK(1), AMC_OVERRIDE=1.
    (Set MODE=0 if vectors are BPSK.)

  File I/O details:
    - Input file is read with $fgets + $sscanf to avoid EOF spin; one header
      line is skipped if present.
    - Each parsed row is presented for one cycle when mapper in_ready=1.
    - Slicer output bytes are recorded whenever out_valid && out_ready.

  End-of-test condition:
    - When all input bytes have been sent and the number of captured bytes
      equals the number sent, the test prints PASS and $finish.
    - Payload equality is expected; a scoreboard or post-sim diff can be used
      for strict per-row comparison if desired.

  Optional overrides (if supported by the TB):
    +CSV_IN=/path/to/mapper_in_bytes.csv
    +CSV_OUT=/path/to/slicer_out_bytes.csv
-----------------------------------------------------------------------------*/


`timescale 1ns/1ps

module tb_mapper_slicer_loopback;

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

  // ===== Mapper symbols → Slicer symbols =====
  logic        sym_valid, sym_ready, sym_last;
  logic [31:0] sym_data;

  // ===== Slicer bytes out =====
  logic        s_out_valid, s_out_ready, s_out_last;
  logic [7:0]  s_out_data;

  // Slicer symbol input wires
  logic        s_in_valid, s_in_ready, s_in_last;
  logic [31:0] s_in_data;

  assign s_in_valid = sym_valid;
  assign s_in_data  = sym_data;
  assign s_in_last  = sym_last;
  assign sym_ready  = s_in_ready;

  // AMC (ignored because AMC_OVERRIDE=1)
  logic [2:0] amc_mode_i = 3'd1;
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

  // ===== DUTs =====
  mapper u_mapper (
    .clk_bb(clk_bb), .rst_n(rst_n),
    .in_valid(m_in_valid), .in_ready(m_in_ready), .in_data(m_in_data), .in_last(m_in_last),
    .out_valid(sym_valid), .out_ready(sym_ready), .out_data(sym_data), .out_last(sym_last),
    .amc_mode_i(amc_mode_i), .amc_mode_valid_i(amc_mode_valid_i),
    .s_axi_aclk(s_axi_aclk), .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(m_awaddr), .s_axi_awvalid(m_awvalid), .s_axi_awready(m_awready),
    .s_axi_wdata(m_wdata), .s_axi_wstrb(m_wstrb), .s_axi_wvalid(m_wvalid), .s_axi_wready(m_wready),
    .s_axi_bresp(m_bresp), .s_axi_bvalid(m_bvalid), .s_axi_bready(m_bready),
    .s_axi_araddr(m_araddr), .s_axi_arvalid(m_arvalid), .s_axi_arready(m_arready),
    .s_axi_rdata(m_rdata), .s_axi_rresp(m_rresp), .s_axi_rvalid(m_rvalid), .s_axi_rready(m_rready)
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
    m_in_valid=0; m_in_data=0; m_in_last=0;
    s_out_ready=1;
    m_awaddr='0; m_awvalid=0; m_wdata='0; m_wstrb='0; m_wvalid=0; m_bready=0;
    m_araddr='0; m_arvalid=0; m_rready=0;
    s_awaddr='0; s_awvalid=0; s_wdata='0; s_wstrb='0; s_wvalid=0; s_bready=0;
    s_araddr='0; s_arvalid=0; s_rready=0;
  end

  // ===== AXI-Lite CTRL: ENABLE=1, MODE=QPSK(1), AMC_OVERRIDE=1, BYPASS=0 =====
  // CTRL value: 0x0000_0111
  initial begin
    @(posedge s_axi_aresetn); repeat(2) @(posedge s_axi_aclk);

    m_awaddr=8'h00; m_awvalid=1; m_wdata=32'h0000_0111; m_wstrb=4'hF; m_wvalid=1;
    wait (m_awready && m_wready); @(posedge s_axi_aclk);
    m_awvalid=0; m_wvalid=0; m_bready=1; wait (m_bvalid); @(posedge s_axi_aclk); m_bready=0;

    s_awaddr=8'h00; s_awvalid=1; s_wdata=32'h0000_0111; s_wstrb=4'hF; s_wvalid=1;
    wait (s_awready && s_wready); @(posedge s_axi_aclk);
    s_awvalid=0; s_wvalid=0; s_bready=1; wait (s_bvalid); @(posedge s_axi_aclk); s_bready=0;
  end

  // ===== File I/O =====
  // Set this to your absolute path if you want:
  string  csv_in_path  = "C:/Vivado/sdr_project_git/jhu_soc_sdr_axu5evb/fpga/sim/tb/golden/mapper_in_bytes.csv";
  string  csv_out_path = "slicer_out_bytes.csv";

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

    // Skip header once (the file you showed has one)
    line_rc = $fgets(line_buf, fd_in);

    // Main loop — use $fgets + $sscanf to always advance the file pointer
    for (;;) begin
      line_rc = $fgets(line_buf, fd_in);
      if (line_rc == 0) break; // EOF

      if ($sscanf(line_buf, "%d,%d,%d", stim_idx, stim_data, stim_tlast) == 3) begin
        drive_one_byte(stim_idx, stim_data[7:0], stim_tlast != 0);
      end
      // else: skip blank/malformed lines and keep going
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

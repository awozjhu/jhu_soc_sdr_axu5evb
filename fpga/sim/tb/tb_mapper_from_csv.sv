`timescale 1ns/1ps
module tb_mapper_from_csv;

  //================ USER CONFIG (hard-coded) ================
  localparam bit    USE_STATIC     = 1'b1; // use absolute path below
  localparam string IN_CSV_STATIC  = "C:/Vivado/sdr_project_git/jhu_soc_sdr_axu5evb/fpga/sim/tb/golden/mapper_in_bytes.csv";
  localparam string OUT_CSV_PATH   = "mapper_out_syms.csv";
  localparam bit    CFG_MODE_QPSK  = 1'b1; // 1=QPSK, 0=BPSK
  localparam bit    CFG_BYPASS     = 1'b0; // 1=force BPSK

  //================ Clock / Reset ===========================
  logic clk = 0; always #5 clk = ~clk; // 100 MHz
  logic rst_n         = 1'b0;
  logic s_axi_aresetn = 1'b0;

  //================ Stream I/O ==============================
  logic        in_valid, in_ready, in_last;
  logic [7:0]  in_data;

  logic        out_valid, out_ready, out_last;
  logic [31:0] out_data;

  //================ AMC (unused) ============================
  logic [2:0]  amc_mode_i       = 3'd0;
  logic        amc_mode_valid_i = 1'b0;

  //================ AXI-Lite wires ==========================
  logic [7:0]  s_axi_awaddr;  logic s_axi_awvalid;  logic s_axi_awready;
  logic [31:0] s_axi_wdata;   logic [3:0]  s_axi_wstrb; logic s_axi_wvalid; logic s_axi_wready;
  logic [1:0]  s_axi_bresp;   logic s_axi_bvalid;   logic s_axi_bready;
  logic [7:0]  s_axi_araddr;  logic s_axi_arvalid;  logic s_axi_arready;
  logic [31:0] s_axi_rdata;   logic [1:0]  s_axi_rresp; logic s_axi_rvalid; logic s_axi_rready;

  //================ DUT =====================================
  mapper dut (
    .clk_bb(clk), .rst_n(rst_n),
    .in_valid(in_valid), .in_ready(in_ready), .in_data(in_data), .in_last(in_last),
    .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data), .out_last(out_last),
    .amc_mode_i(amc_mode_i), .amc_mode_valid_i(amc_mode_valid_i),
    .s_axi_aclk(clk), .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready)
  );

  //================ Types FIRST, then uses ==================
  typedef struct packed { byte data; bit last; } in_rec_t; // <-- typedef comes first

  in_rec_t in_bytes[$];   // uses typedef
  in_rec_t rec_tmp;       // temp record for pushes
  int      num_bytes;

  //================ File/parse state (module-scope) =========
  string in_csv_used;
  int    fd_in, fd_out;
  string line;
  int    a_val, b_val, c_val, n_fields, rows, pushed;
  bit    saw_tlast1;

  //================ Driver/capture counters =================
  int i_drive, got_syms, I_word, Q_word;
  int K_bits_per_sym, expected_syms;
  int unsigned ctrl_reg;

  //================ AXI-Lite write ==========================
  task axi_write (input byte addr, input int unsigned data);
    @(posedge clk);
    s_axi_awaddr  <= addr; s_axi_awvalid <= 1'b1;
    s_axi_wdata   <= data; s_axi_wstrb   <= 4'hF; s_axi_wvalid <= 1'b1;
    do @(posedge clk); while (!(s_axi_awready && s_axi_wready));
    s_axi_awvalid <= 1'b0; s_axi_wvalid <= 1'b0;
    s_axi_bready  <= 1'b1; @(posedge clk); while (!s_axi_bvalid) @(posedge clk);
    s_axi_bready  <= 1'b0;
  endtask

  //================ Open CSV (absolute first, then relatives)
  task open_in_csv();
    in_csv_used = ""; fd_in = 0;
    if (USE_STATIC) begin
      fd_in = $fopen(IN_CSV_STATIC, "r");
      if (fd_in) in_csv_used = IN_CSV_STATIC;
    end
    if (!fd_in) begin
      if (!fd_in) begin fd_in=$fopen("golden/mapper_in_bytes.csv","r");           if (fd_in) in_csv_used="golden/mapper_in_bytes.csv"; end
      if (!fd_in) begin fd_in=$fopen("../golden/mapper_in_bytes.csv","r");        if (fd_in) in_csv_used="../golden/mapper_in_bytes.csv"; end
      if (!fd_in) begin fd_in=$fopen("../../golden/mapper_in_bytes.csv","r");     if (fd_in) in_csv_used="../../golden/mapper_in_bytes.csv"; end
      if (!fd_in) begin fd_in=$fopen("sim/tb/golden/mapper_in_bytes.csv","r");    if (fd_in) in_csv_used="sim/tb/golden/mapper_in_bytes.csv"; end
      if (!fd_in) begin fd_in=$fopen("mapper_in_bytes.csv","r");                  if (fd_in) in_csv_used="mapper_in_bytes.csv"; end
    end
    if (!fd_in) $fatal(1, "Could not open mapper_in_bytes.csv. Edit IN_CSV_STATIC.");
    $display("[TB] Using input CSV: %s", in_csv_used);
  endtask

  //================ Load/parse CSV (use %d only) ============
  // Accepts: idx,data,tlast | data,tlast | data
  task load_input_csv();
    rows = 0; pushed = 0; saw_tlast1 = 0; in_bytes.delete();

    while ($fgets(line, fd_in)) begin
      rows++;

      // 3 fields
      n_fields = $sscanf(line, "%d,%d,%d", a_val, b_val, c_val);
      if (n_fields == 3) begin
        rec_tmp.data = byte'(b_val & 8'hFF);
        rec_tmp.last = bit'(c_val != 0);
        in_bytes.push_back(rec_tmp);
        if (c_val != 0) saw_tlast1 = 1;
        pushed++; continue;
      end

      // 2 fields (heuristic)
      n_fields = $sscanf(line, "%d,%d", a_val, b_val);
      if (n_fields == 2) begin
        if (b_val <= 1) begin
          rec_tmp.data = byte'(a_val & 8'hFF);
          rec_tmp.last = bit'(b_val != 0);
          if (b_val != 0) saw_tlast1 = 1;
        end else begin
          rec_tmp.data = byte'(b_val & 8'hFF);
          rec_tmp.last = 1'b0;
        end
        in_bytes.push_back(rec_tmp);
        pushed++; continue;
      end

      // 1 field
      n_fields = $sscanf(line, "%d", a_val);
      if (n_fields == 1) begin
        rec_tmp.data = byte'(a_val & 8'hFF);
        rec_tmp.last = 1'b0;
        in_bytes.push_back(rec_tmp);
        pushed++; continue;
      end

      // else: header/blank → ignore
    end
    $fclose(fd_in);

    if (pushed == 0) $fatal(1, "Input CSV has no data rows (rows read=%0d).", rows);
    if (!saw_tlast1) begin
      in_bytes[$-1].last = 1'b1; // single frame if no TLAST column
      $display("[TB] No TLAST in CSV; forcing TLAST on final byte.");
    end

    num_bytes = in_bytes.size();
    $display("[TB] Parsed %0d bytes.", num_bytes);
  endtask

  //================ AXIS Driver =============================
  task drive_input();
    i_drive = 0; in_valid = 1'b0; in_data = '0; in_last = 1'b0;
    wait (rst_n && s_axi_aresetn); @(posedge clk);

    if (i_drive < num_bytes) begin
      in_data  <= in_bytes[i_drive].data;
      in_last  <= in_bytes[i_drive].last;
      in_valid <= 1'b1;
    end

    while (i_drive < num_bytes) begin
      @(posedge clk);
      if (in_valid && in_ready) begin
        i_drive++;
        if (i_drive < num_bytes) begin
          in_data  <= in_bytes[i_drive].data;
          in_last  <= in_bytes[i_drive].last;
          in_valid <= 1'b1;
        end else begin
          in_valid <= 1'b0;
          in_last  <= 1'b0;
        end
      end
    end
  endtask

  //================ Output Capture ==========================
  task capture_output_and_finish();
    fd_out = $fopen(OUT_CSV_PATH, "w");
    if (!fd_out) $fatal(1, "Failed to open output CSV: %s", OUT_CSV_PATH);
    $fwrite(fd_out, "sym_idx,I,Q,tlast\n");

    got_syms = 0; out_ready = 1'b0;
    wait (rst_n && s_axi_aresetn); @(posedge clk);
    out_ready = 1'b1;

    while (got_syms < expected_syms) begin
      @(posedge clk);
      if (out_valid && out_ready) begin
        I_word = $signed(out_data[31:16]);
        Q_word = $signed(out_data[15:0]);
        $fwrite(fd_out, "%0d,%0d,%0d,%0d\n", got_syms, I_word, Q_word, out_last ? 1 : 0);
        got_syms++;
      end
    end

    repeat (6) @(posedge clk);
    $fclose(fd_out);
    $display("[TB] Wrote %0d symbols to %s", got_syms, OUT_CSV_PATH);
    $finish;
  endtask

  //================ Main ====================================
  initial begin
    // Default AXI-Lite signals
    s_axi_awaddr='0; s_axi_awvalid=0; s_axi_wdata='0; s_axi_wstrb=4'h0; s_axi_wvalid=0;
    s_axi_bready=0; s_axi_araddr='0; s_axi_arvalid=0; s_axi_rready=0; out_ready=1'b0;

    open_in_csv();
    load_input_csv();

    // Bits/symbol & expected symbols
    if (CFG_BYPASS) K_bits_per_sym = 1; else K_bits_per_sym = (CFG_MODE_QPSK ? 2 : 1);
    if (((num_bytes*8) % K_bits_per_sym) != 0)
      $fatal(1, "Input length not divisible by K (bytes=%0d, K=%0d)", num_bytes, K_bits_per_sym);
    expected_syms = (num_bytes*8)/K_bits_per_sym;

    $display("[TB] bytes=%0d  K=%0d  expected_syms=%0d  MODE_QPSK=%0d  BYPASS=%0d",
             num_bytes, K_bits_per_sym, expected_syms, CFG_MODE_QPSK, CFG_BYPASS);

    // Reset
    rst_n=0; s_axi_aresetn=0; repeat(10) @(posedge clk);
    rst_n=1; s_axi_aresetn=1; repeat(5) @(posedge clk);

    // CTRL: AMC_OVERRIDE=1, MODE, BYPASS, ENABLE
    ctrl_reg = (1<<8) | (CFG_MODE_QPSK ? (1<<4) : 0) | (CFG_BYPASS ? (1<<1) : 0);
    axi_write(8'h00, ctrl_reg | (1<<2)); // SW_RESET
    axi_write(8'h00, ctrl_reg);          // clear SW_RESET
    axi_write(8'h00, ctrl_reg | 32'h1);  // ENABLE

    fork
      drive_input();
      capture_output_and_finish();
    join
  end

endmodule

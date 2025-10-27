`timescale 1ns/1ps
/*-----------------------------------------------------------------------------
  tb_diff_encdec_loopback.sv  (encoder→decoder loopback)
  - Minimal, robust handshake:
      * push waits for in_ready, holds valid exactly 1 cycle
      * decoder out_ready held 1 the whole test
  - Flow: increments --> diff_encoder --> symbols --> diff_decoder --> increments
  - Checks: decoder output == original increments (I,Q) and TLAST matches
-----------------------------------------------------------------------------*/
module tb_diff_encdec_loopback;

  // ---------------- Clocks/Reset ----------------
  logic clk_bb = 1'b0, rst_n = 1'b0;
  logic s_axi_aclk = 1'b0, s_axi_aresetn = 1'b0;
  always #5 clk_bb     = ~clk_bb;     // 100 MHz
  always #5 s_axi_aclk = ~s_axi_aclk; // 100 MHz

  initial begin
    repeat (10) @(posedge clk_bb);
    rst_n         = 1'b1;
    s_axi_aresetn = 1'b1;
  end

  // ---------------- Q1.15 constants ----------------
  localparam logic signed [15:0] P1 = 16'sd32767;   // +1.0
  localparam logic signed [15:0] M1 = -16'sd32767;  // -1.0
  localparam logic signed [15:0] Z0 = 16'sd0;

  // ---------------- Encoder byte-stream-like IN (increments) ----------------
  logic        in_valid, in_ready, in_last;
  logic [31:0] in_data;

  // ---------------- Encoder symbols → Decoder symbols ----------------
  logic        enc_out_valid, enc_out_ready, enc_out_last;
  logic [31:0] enc_out_data;

  // ---------------- Decoder increments OUT (should equal input) -------------
  logic        dec_out_valid, dec_out_ready, dec_out_last;
  logic [31:0] dec_out_data;

  // ---------------- AXI-Lite: encoder ----------------
  logic [7:0]  enc_awaddr;  logic enc_awvalid;  logic enc_awready;
  logic [31:0] enc_wdata;   logic [3:0] enc_wstrb; logic enc_wvalid; logic enc_wready;
  logic [1:0]  enc_bresp;   logic enc_bvalid;  logic enc_bready;
  logic [7:0]  enc_araddr;  logic enc_arvalid; logic enc_arready;
  logic [31:0] enc_rdata;   logic [1:0] enc_rresp; logic enc_rvalid; logic enc_rready;

  // ---------------- AXI-Lite: decoder ----------------
  logic [7:0]  dec_awaddr;  logic dec_awvalid;  logic dec_awready;
  logic [31:0] dec_wdata;   logic [3:0] dec_wstrb; logic dec_wvalid; logic dec_wready;
  logic [1:0]  dec_bresp;   logic dec_bvalid;  logic dec_bready;
  logic [7:0]  dec_araddr;  logic dec_arvalid; logic dec_arready;
  logic [31:0] dec_rdata;   logic [1:0] dec_rresp; logic dec_rvalid; logic dec_rready;

  // ---------------- Instantiate DUTs ----------------
  diff_encoder u_denc (
    .clk_bb(clk_bb),
    .rst_n(rst_n),

    .in_valid(in_valid),
    .in_ready(in_ready),
    .in_data(in_data),
    .in_last(in_last),

    .out_valid(enc_out_valid),
    .out_ready(enc_out_ready),
    .out_data(enc_out_data),
    .out_last(enc_out_last),

    .s_axi_aclk(s_axi_aclk),
    .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(enc_awaddr),
    .s_axi_awvalid(enc_awvalid),
    .s_axi_awready(enc_awready),
    .s_axi_wdata(enc_wdata),
    .s_axi_wstrb(enc_wstrb),
    .s_axi_wvalid(enc_wvalid),
    .s_axi_wready(enc_wready),
    .s_axi_bresp(enc_bresp),
    .s_axi_bvalid(enc_bvalid),
    .s_axi_bready(enc_bready),
    .s_axi_araddr(enc_araddr),
    .s_axi_arvalid(enc_arvalid),
    .s_axi_arready(enc_arready),
    .s_axi_rdata(enc_rdata),
    .s_axi_rresp(enc_rresp),
    .s_axi_rvalid(enc_rvalid),
    .s_axi_rready(enc_rready)
  );

  diff_decoder u_ddec (
    .clk_bb(clk_bb),
    .rst_n(rst_n),

    .in_valid(enc_out_valid),
    .in_ready(enc_out_ready),
    .in_data(enc_out_data),
    .in_last(enc_out_last),

    .out_valid(dec_out_valid),
    .out_ready(dec_out_ready),
    .out_data(dec_out_data),
    .out_last(dec_out_last),

    .s_axi_aclk(s_axi_aclk),
    .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(dec_awaddr),
    .s_axi_awvalid(dec_awvalid),
    .s_axi_awready(dec_awready),
    .s_axi_wdata(dec_wdata),
    .s_axi_wstrb(dec_wstrb),
    .s_axi_wvalid(dec_wvalid),
    .s_axi_wready(dec_wready),
    .s_axi_bresp(dec_bresp),
    .s_axi_bvalid(dec_bvalid),
    .s_axi_bready(dec_bready),
    .s_axi_araddr(dec_araddr),
    .s_axi_arvalid(dec_arvalid),
    .s_axi_arready(dec_arready),
    .s_axi_rdata(dec_rdata),
    .s_axi_rresp(dec_rresp),
    .s_axi_rvalid(dec_rvalid),
    .s_axi_rready(dec_rready)
  );

  // ---------------- TB defaults ----------------
  initial begin
    // Stream side
    in_valid = 1'b0; in_last = 1'b0; in_data = 32'h0;
    dec_out_ready = 1'b1;   // keep decoder's output ready
    // Encoder→Decoder link uses enc_out_ready = decoder in_ready via instance wiring

    // AXI-Lite defaults
    enc_awaddr='0; enc_awvalid=1'b0; enc_wdata='0; enc_wstrb='0; enc_wvalid=1'b0; enc_bready=1'b0;
    enc_araddr='0; enc_arvalid=1'b0; enc_rready=1'b0;

    dec_awaddr='0; dec_awvalid=1'b0; dec_wdata='0; dec_wstrb='0; dec_wvalid=1'b0; dec_bready=1'b0;
    dec_araddr='0; dec_arvalid=1'b0; dec_rready=1'b0;
  end

  // ---------------- AXI-Lite helpers (encoder/decoder) ----------------
  task axi_write_ctrl_enc(input [2:0] mode_bits, input bit do_sw_reset, input bit do_enable);
    reg [31:0] ctrl;
    begin
      ctrl = 32'h0; ctrl[0]=do_enable; ctrl[2]=do_sw_reset; ctrl[6:4]=mode_bits;
      enc_awaddr  <= 8'h00; enc_awvalid <= 1'b1;
      enc_wdata   <= ctrl;  enc_wstrb   <= 4'hF; enc_wvalid <= 1'b1;
      wait (enc_awready && enc_wready); @(posedge s_axi_aclk);
      enc_awvalid <= 1'b0; enc_wvalid <= 1'b0;
      enc_bready  <= 1'b1; wait (enc_bvalid); @(posedge s_axi_aclk); enc_bready <= 1'b0;
    end
  endtask

  task axi_write_ctrl_dec(input [2:0] mode_bits, input bit do_sw_reset, input bit do_enable);
    reg [31:0] ctrl;
    begin
      ctrl = 32'h0; ctrl[0]=do_enable; ctrl[2]=do_sw_reset; ctrl[6:4]=mode_bits;
      dec_awaddr  <= 8'h00; dec_awvalid <= 1'b1;
      dec_wdata   <= ctrl;  dec_wstrb   <= 4'hF; dec_wvalid <= 1'b1;
      wait (dec_awready && dec_wready); @(posedge s_axi_aclk);
      dec_awvalid <= 1'b0; dec_wvalid <= 1'b0;
      dec_bready  <= 1'b1; wait (dec_bvalid); @(posedge s_axi_aclk); dec_bready <= 1'b0;
    end
  endtask

  // ---------------- Simplest push: wait-ready → 1-cycle valid ----------------
  task push_symbol(input logic signed [15:0] inc_I, input logic signed [15:0] inc_Q, input bit last_b);
    begin
      // Wait for encoder ready
      @(posedge clk_bb);
      while (!in_ready) @(posedge clk_bb);
      // Drive exactly 1 beat
      in_data  <= {inc_I, inc_Q};
      in_last  <= last_b;
      in_valid <= 1'b1;
      @(posedge clk_bb);
      in_valid <= 1'b0;
    end
  endtask

  // ---------------- Push + expect decoder echoes increment -------------------
  integer pass_cnt, fail_cnt, step_id;
  task push_and_expect_echo(input logic signed [15:0] inc_I, input logic signed [15:0] inc_Q, input bit last_b);
    begin
      push_symbol(inc_I, inc_Q, last_b);

      // Wait for decoder output (enc→dec latency absorbed)
      while (!(dec_out_valid && dec_out_ready)) @(posedge clk_bb);

      // Compare to original increment
      if ($signed(dec_out_data[31:16]) !== inc_I ||
          $signed(dec_out_data[15:0])  !== inc_Q ||
          (dec_out_last !== last_b)) begin
        $display("[TB][FAIL] step=%0d  ddec={%0d,%0d} last=%0b  exp={%0d,%0d} last=%0b",
                 step_id,
                 $signed(dec_out_data[31:16]), $signed(dec_out_data[15:0]), dec_out_last,
                 inc_I, inc_Q, last_b);
        fail_cnt = fail_cnt + 1;
      end else begin
        pass_cnt = pass_cnt + 1;
      end

      step_id = step_id + 1;
      @(posedge clk_bb); // allow pipeline to clear
    end
  endtask

  // ---------------- Test sequence (minimal) ----------------
  initial begin
    pass_cnt = 0; fail_cnt = 0; step_id = 0;

    // Wait for resets, give a couple S_AXI clocks
    wait (rst_n && s_axi_aresetn);
    repeat (2) @(posedge s_axi_aclk);

    // ---- DBPSK path: SW_RESET→ENABLE on both ----
    axi_write_ctrl_enc(3'd0, /*sw_reset*/1'b1, /*enable*/1'b0);
    axi_write_ctrl_dec(3'd0, /*sw_reset*/1'b1, /*enable*/1'b0);
    axi_write_ctrl_enc(3'd0, /*sw_reset*/1'b0, /*enable*/1'b1);
    axi_write_ctrl_dec(3'd0, /*sw_reset*/1'b0, /*enable*/1'b1);

    // Three simple increments (TLAST on the third)
    push_and_expect_echo( P1, Z0, 1'b0 ); // +1   → echo +1
    push_and_expect_echo( M1, Z0, 1'b0 ); // -1   → echo -1
    push_and_expect_echo( M1, Z0, 1'b1 ); // -1   → echo -1, TLAST=1

    // ---- DQPSK path: SW_RESET→ENABLE on both ----
    axi_write_ctrl_enc(3'd1, /*sw_reset*/1'b1, /*enable*/1'b0);
    axi_write_ctrl_dec(3'd1, /*sw_reset*/1'b1, /*enable*/1'b0);
    axi_write_ctrl_enc(3'd1, /*sw_reset*/1'b0, /*enable*/1'b1);
    axi_write_ctrl_dec(3'd1, /*sw_reset*/1'b0, /*enable*/1'b1);

    // Four 90° increments
    push_and_expect_echo( Z0, P1, 1'b0 ); // +j
    push_and_expect_echo( Z0, P1, 1'b0 ); // +j
    push_and_expect_echo( Z0, P1, 1'b0 ); // +j
    push_and_expect_echo( Z0, P1, 1'b1 ); // +j  (TLAST)

    // ---- Report ----
    $display("[TB] DONE: pass=%0d  fail=%0d", pass_cnt, fail_cnt);
    if (fail_cnt == 0) begin
      $display("[TB] PASS");
      $finish;
    end else begin
      $fatal(1, "[TB] FAIL with %0d mismatches", fail_cnt);
    end
  end

endmodule

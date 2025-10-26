`timescale 1ns/1ps
/*-----------------------------------------------------------------------------
  tb_diff_encoder_basic.sv  (simplified)
  - Minimal, robust handshake:
      * in_ready gated push (valid held exactly 1 cycle)
      * out_ready held 1 the whole test
      * no backpressure, no extra monitors
-----------------------------------------------------------------------------*/
module tb_diff_encoder_basic;

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

  // ---------------- DUT I/O ----------------
  logic        in_valid, in_ready, in_last;
  logic [31:0] in_data;

  logic        out_valid, out_ready, out_last;
  logic [31:0] out_data;

  // -------------- AXI-Lite -----------------
  logic [7:0]  awaddr;  logic awvalid;  logic awready;
  logic [31:0] wdata;   logic [3:0] wstrb; logic wvalid; logic wready;
  logic [1:0]  bresp;   logic bvalid;  logic bready;
  logic [7:0]  araddr;  logic arvalid; logic arready;
  logic [31:0] rdata;   logic [1:0] rresp; logic rvalid; logic rready;

  // ---------------- Instantiate DUT ----------------
  diff_encoder u_denc (
    .clk_bb(clk_bb),
    .rst_n(rst_n),

    .in_valid(in_valid),
    .in_ready(in_ready),
    .in_data(in_data),
    .in_last(in_last),

    .out_valid(out_valid),
    .out_ready(out_ready),
    .out_data(out_data),
    .out_last(out_last),

    .s_axi_aclk(s_axi_aclk),
    .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(awaddr),
    .s_axi_awvalid(awvalid),
    .s_axi_awready(awready),
    .s_axi_wdata(wdata),
    .s_axi_wstrb(wstrb),
    .s_axi_wvalid(wvalid),
    .s_axi_wready(wready),
    .s_axi_bresp(bresp),
    .s_axi_bvalid(bvalid),
    .s_axi_bready(bready),
    .s_axi_araddr(araddr),
    .s_axi_arvalid(arvalid),
    .s_axi_arready(arready),
    .s_axi_rdata(rdata),
    .s_axi_rresp(rresp),
    .s_axi_rvalid(rvalid),
    .s_axi_rready(rready)
  );

  // ---------------- TB defaults ----------------
  initial begin
    in_valid = 1'b0; in_last = 1'b0; in_data = 32'h0;
    out_ready = 1'b1;   // keep ready asserted — simplest path
    awaddr='0; awvalid=1'b0; wdata='0; wstrb='0; wvalid=1'b0; bready=1'b0;
    araddr='0; arvalid=1'b0; rready=1'b0;
  end

  // ---------------- Q1.15 constants ----------------
  localparam logic signed [15:0] P1 = 16'sd32767;   // +1.0
  localparam logic signed [15:0] M1 = -16'sd32767;  // -1.0
  localparam logic signed [15:0] Z0 = 16'sd0;

  // ---------------- Expected tracking ----------------
  logic signed [15:0] exp_prev_I, exp_prev_Q;
  logic signed [15:0] exp_next_I, exp_next_Q;

  integer pass_cnt, fail_cnt, step_id;

  // ---------------- AXI-Lite helpers ----------------
  task axi_write_ctrl(input [2:0] mode_bits, input bit do_sw_reset, input bit do_enable);
    reg [31:0] ctrl;
    begin
      ctrl = 32'h0;
      ctrl[0]   = do_enable;      // ENABLE
      ctrl[2]   = do_sw_reset;    // SW_RESET
      ctrl[6:4] = mode_bits;      // MODE

      awaddr  <= 8'h00; awvalid <= 1'b1;
      wdata   <= ctrl;  wstrb   <= 4'hF; wvalid <= 1'b1;

      // handshake + hold one extra edge (matches slave's do_write)
      wait (awready && wready);
      @(posedge s_axi_aclk);
      awvalid <= 1'b0;
      wvalid  <= 1'b0;

      bready  <= 1'b1;
      wait (bvalid);
      @(posedge s_axi_aclk);
      bready  <= 1'b0;
    end
  endtask

  // ---------------- Expected calculator (axial only) ----------------
  task compute_expected(
    input logic signed [15:0] inc_I,
    input logic signed [15:0] inc_Q
  );
    begin
      if (inc_I==P1 && inc_Q==Z0) begin                // +1
        exp_next_I = exp_prev_I;   exp_next_Q = exp_prev_Q;
      end else if (inc_I==M1 && inc_Q==Z0) begin       // -1
        exp_next_I = -exp_prev_I;  exp_next_Q = -exp_prev_Q;
      end else if (inc_I==Z0 && inc_Q==P1) begin       // +j
        exp_next_I = -exp_prev_Q;  exp_next_Q =  exp_prev_I;
      end else if (inc_I==Z0 && inc_Q==M1) begin       // -j
        exp_next_I =  exp_prev_Q;  exp_next_Q = -exp_prev_I;
      end else begin
        $fatal(1, "[TB] compute_expected: non-axial increment not supported.");
      end
    end
  endtask

  // ---------------- Simplest push: wait-ready → 1-cycle valid ----------------
  task push_symbol(input logic signed [15:0] inc_I, input logic signed [15:0] inc_Q, input bit last_b);
    begin
      // Wait for in_ready=1 at a posedge
      @(posedge clk_bb);
      while (!in_ready) @(posedge clk_bb);

      // Drive and hold valid for exactly 1 cycle (handshake occurs next edge)
      in_data  <= {inc_I, inc_Q};
      in_last  <= last_b;
      in_valid <= 1'b1;
      @(posedge clk_bb);
      in_valid <= 1'b0;
    end
  endtask

  // ---------------- Push + expect one output ----------------
  task push_and_expect(input logic signed [15:0] inc_I, input logic signed [15:0] inc_Q, input bit last_b);
    begin
      compute_expected(inc_I, inc_Q);
      push_symbol(inc_I, inc_Q, last_b);

      // Wait for output handshake (out_ready is 1, so this is just wait out_valid)
      while (!(out_valid && out_ready)) @(posedge clk_bb);

      // Check and advance expected state
      if ($signed(out_data[31:16]) !== exp_next_I ||
          $signed(out_data[15:0])  !== exp_next_Q ||
          (out_last !== last_b)) begin
        $display("[TB][FAIL] step=%0d  got={%0d,%0d} last=%0b  exp={%0d,%0d} last=%0b",
                 step_id, $signed(out_data[31:16]), $signed(out_data[15:0]), out_last,
                 exp_next_I, exp_next_Q, last_b);
        fail_cnt = fail_cnt + 1;
      end else begin
        pass_cnt = pass_cnt + 1;
      end

      exp_prev_I = exp_next_I;
      exp_prev_Q = exp_next_Q;
      step_id    = step_id + 1;

      // allow one cycle for DUT to clear hold_valid and raise in_ready again
      @(posedge clk_bb);
    end
  endtask

  // ---------------- Test sequence (minimal) ----------------
  initial begin
    pass_cnt = 0; fail_cnt = 0; step_id = 0;

    // Wait for resets, give a couple S_AXI clocks
    wait (rst_n && s_axi_aresetn);
    repeat (2) @(posedge s_axi_aclk);

    // ---- DBPSK: SW_RESET → ENABLE ----
    axi_write_ctrl(3'd0, /*sw_reset*/1'b1, /*enable*/1'b0);
    axi_write_ctrl(3'd0, /*sw_reset*/1'b0, /*enable*/1'b1);
    exp_prev_I = P1;  exp_prev_Q = Z0;

    // Three simple symbols (TLAST on the third)
    push_and_expect( P1, Z0, 1'b0 ); // +1   → (1,0)
    push_and_expect( M1, Z0, 1'b0 ); // -1   → (-1,0)
    push_and_expect( M1, Z0, 1'b1 ); // -1   → (1,0), TLAST=1

    // ---- DQPSK: SW_RESET → ENABLE ----
    axi_write_ctrl(3'd1, /*sw_reset*/1'b1, /*enable*/1'b0);
    axi_write_ctrl(3'd1, /*sw_reset*/1'b0, /*enable*/1'b1);
    exp_prev_I = P1;  exp_prev_Q = Z0;

    // One clean 90° rotation series (no backpressure)
    push_and_expect( Z0, P1, 1'b0 ); // (1,0) * j  = (0,1)
    push_and_expect( Z0, P1, 1'b0 ); // (0,1) * j  = (-1,0)
    push_and_expect( Z0, P1, 1'b0 ); // (-1,0)* j  = (0,-1)
    push_and_expect( Z0, P1, 1'b1 ); // (0,-1)* j  = (1,0), TLAST=1

    $display("[TB] DONE: pass=%0d  fail=%0d", pass_cnt, fail_cnt);
    if (fail_cnt == 0) begin
      $display("[TB] PASS");
      $finish;
    end else begin
      $fatal(1, "[TB] FAIL with %0d mismatches", fail_cnt);
    end
  end

endmodule

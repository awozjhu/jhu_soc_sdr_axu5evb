`timescale 1ns/1ps
/*-----------------------------------------------------------------------------
  tb_diff_encdec_loopback.sv  (encoder→decoder loopback)
  - No AXI-Lite transactions; CSRs are tied off.
  - Flow: increments --> diff_encoder --> symbols --> diff_decoder --> increments
  - Checks: decoder output == original increments (I,Q) and TLAST matches
  - Multiple frames: TLAST marks end of each frame.
-----------------------------------------------------------------------------*/
module tb_diff_encdec_loopback;

  // ---------------- Clocks/Reset ----------------
  logic clk_bb      = 1'b0;
  logic rst_n       = 1'b0;
  logic s_axi_aclk  = 1'b0;
  logic s_axi_aresetn = 1'b0;

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

  // ---------------- Test parameters (frames) ----------------
  localparam int N_FRAMES        = 4;
  localparam int SYMS_PER_FRAME  = 16;  // symbols per "packet"

  // ---------------- Encoder IN (increments) ----------------
  logic        in_valid, in_ready, in_last;
  logic [31:0] in_data;

  // ---------------- Encoder symbols → Decoder symbols ----------------
  logic        enc_out_valid, enc_out_ready, enc_out_last;
  logic [31:0] enc_out_data;

  // ---------------- Decoder increments OUT (should equal input) -------------
  logic        dec_out_valid, dec_out_ready, dec_out_last;
  logic [31:0] dec_out_data;

  // ---------------- Instantiate DUTs ----------------
  diff_encoder u_denc (
    .clk_bb   (clk_bb),
    .rst_n    (rst_n),

    .in_valid (in_valid),
    .in_ready (in_ready),
    .in_data  (in_data),
    .in_last  (in_last),

    .out_valid(enc_out_valid),
    .out_ready(enc_out_ready),
    .out_data (enc_out_data),
    .out_last (enc_out_last),

    // AXI-Lite tied off
    .s_axi_aclk    (s_axi_aclk),
    .s_axi_aresetn (s_axi_aresetn),
    .s_axi_awaddr  (8'd0),
    .s_axi_awvalid (1'b0),
    .s_axi_awready (/* unused */),
    .s_axi_wdata   (32'd0),
    .s_axi_wstrb   (4'd0),
    .s_axi_wvalid  (1'b0),
    .s_axi_wready  (/* unused */),
    .s_axi_bresp   (/* unused */),
    .s_axi_bvalid  (/* unused */),
    .s_axi_bready  (1'b0),
    .s_axi_araddr  (8'd0),
    .s_axi_arvalid (1'b0),
    .s_axi_arready (/* unused */),
    .s_axi_rdata   (/* unused */),
    .s_axi_rresp   (/* unused */),
    .s_axi_rvalid  (/* unused */),
    .s_axi_rready  (1'b0)
  );

  diff_decoder u_ddec (
    .clk_bb   (clk_bb),
    .rst_n    (rst_n),

    .in_valid (enc_out_valid),
    .in_ready (enc_out_ready),
    .in_data  (enc_out_data),
    .in_last  (enc_out_last),

    // no frame_start usage in this TB
    .frame_start_i(1'b0),

    .out_valid(dec_out_valid),
    .out_ready(dec_out_ready),
    .out_data (dec_out_data),
    .out_last (dec_out_last),

    // AXI-Lite tied off
    .s_axi_aclk    (s_axi_aclk),
    .s_axi_aresetn (s_axi_aresetn),
    .s_axi_awaddr  (8'd0),
    .s_axi_awvalid (1'b0),
    .s_axi_awready (/* unused */),
    .s_axi_wdata   (32'd0),
    .s_axi_wstrb   (4'd0),
    .s_axi_wvalid  (1'b0),
    .s_axi_wready  (/* unused */),
    .s_axi_bresp   (/* unused */),
    .s_axi_bvalid  (/* unused */),
    .s_axi_bready  (1'b0),
    .s_axi_araddr  (8'd0),
    .s_axi_arvalid (1'b0),
    .s_axi_arready (/* unused */),
    .s_axi_rdata   (/* unused */),
    .s_axi_rresp   (/* unused */),
    .s_axi_rvalid  (/* unused */),
    .s_axi_rready  (1'b0)
  );

  // ---------------- TB defaults ----------------
  initial begin
    in_valid      = 1'b0;
    in_last       = 1'b0;
    in_data       = 32'h0;
    dec_out_ready = 1'b1;   // keep decoder's output ready
  end

  // ---------------- Simplest push: wait-ready → 1-cycle valid ----------------
  task push_symbol(
    input logic signed [15:0] inc_I,
    input logic signed [15:0] inc_Q,
    input bit                 last_b
  );
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
  task push_and_expect_echo(
    input logic signed [15:0] inc_I,
    input logic signed [15:0] inc_Q,
    input bit                 last_b
  );
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
                 $signed(dec_out_data[31:16]),
                 $signed(dec_out_data[15:0]),
                 dec_out_last,
                 inc_I, inc_Q, last_b);
        fail_cnt = fail_cnt + 1;
      end else begin
        pass_cnt = pass_cnt + 1;
      end

      step_id = step_id + 1;
      @(posedge clk_bb); // allow pipeline to clear
    end
  endtask

  // ---------------- Test sequence: multiple frames ----------------
  int frame, sym;
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    step_id  = 0;

    wait (rst_n && s_axi_aresetn);
    repeat (2) @(posedge clk_bb);

    $display("[TB] Starting diff_enc/dec loopback with %0d frames, %0d symbols each",
             N_FRAMES, SYMS_PER_FRAME);



    for (frame = 0; frame < N_FRAMES; frame++) begin
      $display("[TB] Frame %0d", frame);
      for (sym = 0; sym < SYMS_PER_FRAME; sym++) begin
        logic signed [15:0] inc_I, inc_Q;
        bit last_b;

        // Simple rotating pattern over the 4 key phasors
        case (sym % 4)
          0: begin inc_I = P1; inc_Q = Z0; end   // +1
          1: begin inc_I = M1; inc_Q = Z0; end   // -1
          2: begin inc_I = Z0; inc_Q = P1; end   // +j
          default: begin inc_I = Z0; inc_Q = M1; end // -j
        endcase

        last_b = (sym == SYMS_PER_FRAME-1); // TLAST on last symbol of frame

        push_and_expect_echo(inc_I, inc_Q, last_b);
      end

      // Optional gap between frames
      @(posedge clk_bb);
    end

    $display("[TB] DONE: pass=%0d  fail=%0d", pass_cnt, fail_cnt);
    if (fail_cnt == 0) begin
      $display("[TB] PASS");
      $finish;
    end else begin
      $fatal(1, "[TB] FAIL with %0d mismatches", fail_cnt);
    end
  end

endmodule

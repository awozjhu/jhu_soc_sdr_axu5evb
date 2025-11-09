`timescale 1ns/1ps
module tb_pi_pc_loopback;

  // ---- Params ----
  localparam int CLK_PER_NS    = 4;     // 250 MHz
  localparam int PREAMBLE_LEN  = 64;
  localparam int F0_SYMS       = 12;    // payload symbols for frame 0
  localparam int F1_SYMS       = 1;     // single-beat frame (edge)
  localparam int F2_SYMS       = 20;    // payload symbols for frame 2

  // Q1.15 constants
  localparam logic signed [15:0] ONE = 16'sd32767;
  localparam logic signed [15:0] Z   = 16'sd0;

  // ---- Clock / Reset ----
  logic clk = 0; always #(CLK_PER_NS/2.0) clk = ~clk;
  logic rst_n;
  initial begin
    rst_n = 0;
    repeat (10) @(posedge clk);
    rst_n = 1;
  end

  // ---- Wires between blocks ----
  // TB source → PI
  logic        src_tvalid, src_tready, src_tlast;
  logic [31:0] src_tdata;

  // PI → PC
  logic        pi_tvalid, pi_tready, pi_tlast;
  logic [31:0] pi_tdata;

  // PC → sink
  logic        pc_tvalid, pc_tready, pc_tlast;
  logic [31:0] pc_tdata;
  logic        frame_start;

  assign pc_tready = 1'b1; // always-accept

  // ---- DUTs ----
  PreambleInserter #(.PREAMBLE_LEN(PREAMBLE_LEN)) u_pi (
    .aclk(clk), .aresetn(rst_n),
    .s_axis_tvalid(src_tvalid), .s_axis_tready(src_tready),
    .s_axis_tdata (src_tdata),  .s_axis_tlast (src_tlast),
    .m_axis_tvalid(pi_tvalid),  .m_axis_tready(pi_tready),
    .m_axis_tdata (pi_tdata),   .m_axis_tlast (pi_tlast)
  );

  // NOTE: after patching correlator for time-reversal & 128-bit mag^2,
  // you can choose a sensible threshold. For quick bring-up, start low.
  localparam int CORR_THR_BOOT = 32'd100_000_000; // conservative, adjust up after see pulse
  PreambleCorrelator #(.PREAMBLE_LEN(PREAMBLE_LEN),
                       .CORR_THRESHOLD(CORR_THR_BOOT)) u_pc (
    .clk(clk), .rst_n(rst_n),
    .s_axis_tvalid(pi_tvalid), .s_axis_tready(pi_tready),
    .s_axis_tdata (pi_tdata),  .s_axis_tlast (pi_tlast),
    .m_axis_tvalid(pc_tvalid), .m_axis_tready(pc_tready),
    .m_axis_tdata (pc_tdata),  .m_axis_tlast (pc_tlast),
    .frame_start(frame_start)
  );

  // ---- Simple source: diff-encoder-like unit-magnitude rotations ----
  typedef struct packed { logic signed [15:0] i,q; } iq16_t;

  function automatic iq16_t rot90(input iq16_t a);
    iq16_t r; r.i = -a.q; r.q = a.i; return r;
  endfunction

  task automatic send_frame(input int n_syms);
    iq16_t s; s.i = ONE; s.q = Z;  // start ∠0°
    for (int k = 0; k < n_syms; k++) begin
      if (k != 0) s = rot90(s);    // step +90° each symbol
      src_tdata  <= {s.i, s.q};
      src_tlast  <= (k == n_syms-1);
      src_tvalid <= 1'b1;
      // wait for handshake
      do @(posedge clk); while (!src_tready);
      @(posedge clk);               // keep high one more cycle for clean waves
      src_tvalid <= 1'b0;
      src_tlast  <= 1'b0;
      src_tdata  <= 32'h0;
      @(posedge clk);               // optional gap
    end
    repeat (8) @(posedge clk);      // inter-frame gap
  endtask

  // ---- Drive three frames ----
  initial begin
    wait(rst_n);
    $display("[%0t] start", $time);
    send_frame(F0_SYMS);
    send_frame(F1_SYMS);
    send_frame(F2_SYMS);
    repeat (100) @(posedge clk);
    $display("[%0t] done", $time);
    $finish;
  end

  // ---- Breadcrumb prints ----
  initial begin
    forever begin
      @(posedge clk);
      if (src_tvalid && src_tready) $display("%0t SRC→PI   %s", $time, src_tlast?"TLAST":"");
      if (pi_tvalid && pi_tready)   $display("%0t PI→PC    %s", $time, pi_tlast ?"TLAST":"");
      if (pc_tvalid && pc_tready)   $display("%0t PC→SINK  %s", $time, pc_tlast ?"TLAST":"");
      if (frame_start)              $display("%0t *** frame_start ***", $time);
    end
  end

  // Uncomment for VCD
  // initial begin
  //   $dumpfile("pi_pc_loop.vcd");
  //   $dumpvars(0, tb_pi_pc_loopback);
  // end

endmodule

`timescale 1ns/1ps
module tb_pi_pc_loopback_csv;

  //-------------- params ---------------
  localparam int CLK_PER_NS   = 4;     // 250 MHz
  localparam int PREAMBLE_LEN = 64;
  localparam int F0_SYMS      = 12;
  localparam int F1_SYMS      = 1;
  localparam int F2_SYMS      = 20;

  // Q1.15 constants
  localparam logic signed [15:0] ONE = 16'sd32767;
  localparam logic signed [15:0] Z   = 16'sd0;

  //-------------- clock/reset ----------
  logic clk = 0; always #(CLK_PER_NS/2.0) clk = ~clk;
  logic rst_n;
  initial begin
    rst_n = 0;
    repeat (10) @(posedge clk);
    rst_n = 1;
  end

  //-------------- stream wires ---------
  // SRC → PI (payload into PreambleInserter)
  logic        src_tvalid, src_tready, src_tlast;
  logic [31:0] src_tdata;

  // PI → PC
  logic        pi_tvalid, pi_tready, pi_tlast;
  logic [31:0] pi_tdata;

  // PC → SINK
  logic        pc_tvalid, pc_tready, pc_tlast;
  logic [31:0] pc_tdata;
  logic        frame_start;

  assign pc_tready = 1'b1; // accept everything for logging

  //-------------- DUTs -----------------
  PreambleInserter #(.PREAMBLE_LEN(PREAMBLE_LEN)) u_pi (
    .aclk(clk), .aresetn(rst_n),
    .s_axis_tvalid(src_tvalid), .s_axis_tready(src_tready),
    .s_axis_tdata (src_tdata),  .s_axis_tlast (src_tlast),
    .m_axis_tvalid(pi_tvalid),  .m_axis_tready(pi_tready),
    .m_axis_tdata (pi_tdata),   .m_axis_tlast (pi_tlast)
  );

  // Use your latest correlator (with time-reverse, 128-bit mag², guard)
  // You can tune CORR_THRESHOLD as needed.
  PreambleCorrelator #(
    .PREAMBLE_LEN(PREAMBLE_LEN)
  ) u_pc (
    .clk(clk), .rst_n(rst_n),
    .s_axis_tvalid(pi_tvalid), .s_axis_tready(pi_tready),
    .s_axis_tdata (pi_tdata),  .s_axis_tlast (pi_tlast),
    .m_axis_tvalid(pc_tvalid), .m_axis_tready(pc_tready),
    .m_axis_tdata (pc_tdata),  .m_axis_tlast (pc_tlast),
    .frame_start(frame_start)
  );

  //-------------- CSV logging ----------
  integer f_in, f_out;

  // frame & beat counters for input and output sides
  int in_frame_idx  = 0;
  int in_beat_idx   = 0;
  int out_frame_idx = 0;
  int out_beat_idx  = 0;

  // open files & headers
  initial begin
    wait (rst_n);
    f_in  = $fopen("pi_input.csv",  "w");
    f_out = $fopen("pc_output.csv", "w");
    if (f_in == 0 || f_out == 0) begin
      $fatal(1, "Failed to open CSV files.");
    end
    // headers
    $fdisplay(f_in,  "time_ns,frame_idx,beat_idx,tvalid,tready,tlast,data_hex");
    $fdisplay(f_out, "time_ns,frame_idx,beat_idx,tvalid,tready,tlast,data_hex");
  end

  // log SRC→PI accepted beats
  always @(posedge clk) begin
    if (rst_n && src_tvalid && src_tready) begin
      $fdisplay(f_in, "%0t,%0d,%0d,%0d,%0d,%0d,%08h",
        $time, in_frame_idx, in_beat_idx, src_tvalid, src_tready, src_tlast, src_tdata);
      in_beat_idx++;
      if (src_tlast) begin
        in_frame_idx++;
        in_beat_idx = 0;
      end
    end
  end

  // log PC→SINK accepted beats
  always @(posedge clk) begin
    if (rst_n && pc_tvalid && pc_tready) begin
      $fdisplay(f_out, "%0t,%0d,%0d,%0d,%0d,%0d,%08h",
        $time, out_frame_idx, out_beat_idx, pc_tvalid, pc_tready, pc_tlast, pc_tdata);
      out_beat_idx++;
      if (pc_tlast) begin
        out_frame_idx++;
        out_beat_idx = 0;
      end
    end
  end

  // (optional) also log frame_start pulses to console for quick view
  always @(posedge clk) if (frame_start) $display("%0t *** frame_start ***", $time);

  // close files on finish
  final begin
    if (f_in)  $fclose(f_in);
    if (f_out) $fclose(f_out);
    $display("Wrote pi_input.csv and pc_output.csv");
  end

  //-------------- simple source --------
  typedef struct packed { logic signed [15:0] i,q; } iq16_t;
  function automatic iq16_t rot90(input iq16_t a);
    iq16_t r; r.i = -a.q; r.q = a.i; return r;
  endfunction

  task automatic send_frame(input int n_syms);
    iq16_t s; s.i = ONE; s.q = Z; // start at +1∠0°
    for (int k = 0; k < n_syms; k++) begin
      if (k != 0) s = rot90(s);    // step +90° each symbol
      src_tdata  <= {s.i, s.q};
      src_tlast  <= (k == n_syms-1);
      src_tvalid <= 1'b1;
      // wait for acceptance
      do @(posedge clk); while (!src_tready);
      @(posedge clk); // keep valid one more for clean waves
      src_tvalid <= 1'b0;
      src_tlast  <= 1'b0;
      src_tdata  <= 32'h0;
      @(posedge clk); // small gap
    end
    // inter-frame gap
    repeat (8) @(posedge clk);
  endtask

  //-------------- drive 3 frames -------
  initial begin
    wait (rst_n);
    $display("[%0t] start", $time);
    send_frame(F0_SYMS);
    send_frame(F1_SYMS);
    send_frame(F2_SYMS);
    repeat (100) @(posedge clk);
    $display("[%0t] done", $time);
    $finish;
  end

  //-------------- optional VCD ---------
  // initial begin
  //   $dumpfile("pi_pc_loop_csv.vcd");
  //   $dumpvars(0, tb_pi_pc_loopback_csv);
  // end

endmodule

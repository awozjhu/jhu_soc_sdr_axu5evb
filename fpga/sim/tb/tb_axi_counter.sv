`timescale 1ns/1ps

module tb_axis_counter_src;

  // ---------------------------------------------------------------------------
  // Parameters
  // ---------------------------------------------------------------------------
  localparam int CLK_PER_NS = 10;   // 100 MHz
  localparam int FRAME_LEN  = 8;    // small frame for easy viewing

  // ---------------------------------------------------------------------------
  // Clock / Reset
  // ---------------------------------------------------------------------------
  logic clk = 0;
  always #(CLK_PER_NS/2.0) clk = ~clk;

  logic rst_n;
  initial begin
    rst_n = 1'b0;
    // hold reset low for a few clock cycles
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end

  // ---------------------------------------------------------------------------
  // DUT I/O
  // ---------------------------------------------------------------------------
  logic        enable;
  logic [7:0]  m_axis_tdata;
  logic        m_axis_tvalid;
  logic        m_axis_tready;
  logic        m_axis_tlast;

  // ---------------------------------------------------------------------------
  // DUT: axis_counter_src
  // ---------------------------------------------------------------------------
  axis_counter_src #(
    .FRAME_LEN (FRAME_LEN)
  ) dut (
    .clk           (clk),
    .rst_n         (rst_n),

    .enable        (enable),

    .m_axis_tdata  (m_axis_tdata),
    .m_axis_tvalid (m_axis_tvalid),
    .m_axis_tready (m_axis_tready),
    .m_axis_tlast  (m_axis_tlast)
  );

  // ---------------------------------------------------------------------------
  // Stimulus
  // ---------------------------------------------------------------------------
  initial begin
    // Defaults
    enable        = 1'b0;
    m_axis_tready = 1'b0;

    // Wait for reset deassertion (synchronous)
    @(posedge rst_n);
    repeat (5) @(posedge clk);

    // Start streaming: enable source, assert ready
    enable        = 1'b1;
    m_axis_tready = 1'b1;

    // Run with ready=1 for a while
    repeat (20) @(posedge clk);

    // Apply backpressure for a few cycles
    m_axis_tready = 1'b0;
    repeat (10) @(posedge clk);
    m_axis_tready = 1'b1;

    // Run a bit more
    repeat (20) @(posedge clk);

    // Stop
    enable        = 1'b0;
    repeat (10) @(posedge clk);

    $finish;
  end

  // ---------------------------------------------------------------------------
  // Simple logging
  // ---------------------------------------------------------------------------
  initial begin
    $display("Time   rst_n en  tvalid tready tlast  tdata");
    $monitor("%0t  %b    %b   %b      %b      %b   0x%02h",
             $time, rst_n, enable,
             m_axis_tvalid, m_axis_tready, m_axis_tlast,
             m_axis_tdata);
  end

  // Optional: VCD dump
  initial begin
    $dumpfile("tb_axis_counter_src.vcd");
    $dumpvars(0, tb_axis_counter_src);
  end

endmodule

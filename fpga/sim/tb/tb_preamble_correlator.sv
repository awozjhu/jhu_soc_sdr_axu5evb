// tb_preamble_correlator.sv

module tb_preamble_correlator;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_n;

  initial begin
    rst_n = 0;
    repeat (5) @(posedge clk);
    rst_n = 1;
  end

  logic        s_valid, s_ready, s_last;
  logic [31:0] s_data;

  logic        m_valid, m_ready, m_last;
  logic [31:0] m_data;

  logic        frame_start;

  int sym_idx;

  PreambleCorrelator dut (
    .clk(clk), .rst_n(rst_n),
    .s_axis_tvalid(s_valid), .s_axis_tready(s_ready),
    .s_axis_tdata(s_data), .s_axis_tlast(s_last),
    .m_axis_tvalid(m_valid), .m_axis_tready(m_ready),
    .m_axis_tdata(m_data), .m_axis_tlast(m_last),
    .frame_start(frame_start)
  );

  initial begin
    s_valid = 0; s_data = 0; s_last = 0; m_ready = 1;
    @(posedge rst_n); @(posedge clk);

    sym_idx = 0;

    repeat (64) begin
    @(posedge clk);
    s_valid <= 1;
    case (sym_idx % 4)
        0: s_data <= 32'h5A82_5A82;
        1: s_data <= 32'h5A82_A57E;
        2: s_data <= 32'hA57E_5A82;
        3: s_data <= 32'hA57E_A57E;
    endcase
    sym_idx++;
    end

    repeat (10) @(posedge clk);
    $finish;
  end
endmodule

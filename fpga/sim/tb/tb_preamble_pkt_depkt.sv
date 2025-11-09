`timescale 1ns/1ps

module tb_preamble_pkt_depkt;

  // ------------------------------------------------------------
  // Clock / Reset (single domain for all DUTs)
  // ------------------------------------------------------------
  reg clk = 0;
  always #5 clk = ~clk;  // 100 MHz

  reg rst_n;
  reg aresetn;
  initial begin
    rst_n   = 0;
    aresetn = 0;
    repeat (5) @(posedge clk);
    rst_n   = 1;
    aresetn = 1;
  end

  // ------------------------------------------------------------
  // Params / knobs
  // ------------------------------------------------------------
  localparam int PREAMBLE_LEN  = 64;
  localparam int PAYLOAD_WORDS = 5;

  localparam logic [15:0] P = 16'h5A82;
  localparam logic [15:0] N = 16'hA57E;

  // ------------------------------------------------------------
  // AXIS: Source → PreambleInserter
  // ------------------------------------------------------------
  reg         s_tvalid;
  wire        s_tready;
  reg  [31:0] s_tdata;
  reg         s_tlast;

  // ------------------------------------------------------------
  // PreambleInserter → Packetizer (link A)
  wire        a_tvalid;
  wire        a_tready;
  wire [31:0] a_tdata;
  wire        a_tlast;

  // ------------------------------------------------------------
  // Packetizer → Depacketizer (link B)
  wire        b_tvalid;
  wire        b_tready;
  wire [31:0] b_tdata;
  wire        b_tlast;

  // ------------------------------------------------------------
  // Depacketizer → PreambleCorrelator
  wire        mc_tvalid;
  wire        mc_tready;
  wire [31:0] mc_tdata;
  wire        mc_tlast;

  // ------------------------------------------------------------
  // PreambleCorrelator → Sink
  wire        m_tvalid;
  reg         m_tready;
  wire [31:0] m_tdata;
  wire        m_tlast;
  wire        frame_start;

  initial m_tready = 1'b1;

  // ------------------------------------------------------------
  // DUTs
  // ------------------------------------------------------------
  PreambleInserter #(.PREAMBLE_LEN(PREAMBLE_LEN)) u_pre (
    .aclk(clk),
    .aresetn(aresetn),
    .s_axis_tvalid(s_tvalid),
    .s_axis_tready(s_tready),
    .s_axis_tdata(s_tdata),
    .s_axis_tlast(s_tlast),
    .m_axis_tvalid(a_tvalid),
    .m_axis_tready(a_tready),
    .m_axis_tdata(a_tdata),
    .m_axis_tlast(a_tlast)
  );

  tx_packetizer #(.DATA_WIDTH(32)) u_pkt (
    .clk(clk),
    .rst_n(rst_n),
    .s_axis_tdata(a_tdata),
    .s_axis_tvalid(a_tvalid),
    .s_axis_tready(a_tready),
    .s_axis_tlast(a_tlast),
    .m_axis_tdata(b_tdata),
    .m_axis_tvalid(b_tvalid),
    .m_axis_tready(b_tready),
    .m_axis_tlast(b_tlast)
  );

  rx_depacketizer #(.DATA_WIDTH(32)) u_depkt (
    .clk(clk),
    .rst_n(rst_n),
    .s_axis_tdata(b_tdata),
    .s_axis_tvalid(b_tvalid),
    .s_axis_tready(b_tready),
    .s_axis_tlast(b_tlast),
    .m_axis_tdata(mc_tdata),
    .m_axis_tvalid(mc_tvalid),
    .m_axis_tready(mc_tready),
    .m_axis_tlast(mc_tlast)
  );

  PreambleCorrelator u_corr (
    .clk(clk),
    .rst_n(rst_n),
    .s_axis_tvalid(mc_tvalid),
    .s_axis_tready(mc_tready),
    .s_axis_tdata(mc_tdata),
    .s_axis_tlast(mc_tlast),
    .m_axis_tvalid(m_tvalid),
    .m_axis_tready(m_tready),
    .m_axis_tdata(m_tdata),
    .m_axis_tlast(m_tlast),
    .frame_start(frame_start)
  );


// ================= DEBUG PROBES =================
// Put these below the DUTs, above the scoreboard

// Limit how long we print
integer dbg_cycles = 0;
always @(posedge clk) if (rst_n) dbg_cycles <= dbg_cycles + 1;

// A) After PreambleInserter (A-link: a_t*)
always @(posedge clk) begin
  if (rst_n && a_tvalid && a_tready && dbg_cycles < 200)
    $display("A %0t  a=%h  a_last=%b", $time, a_tdata, a_tlast);
end

// B) After Packetizer, skipping the 3 header beats (B-link: b_t*)
integer hdr_skipped = 0;
always @(posedge clk) begin
  if (rst_n && b_tvalid && b_tready) begin
    if (hdr_skipped < 3) hdr_skipped = hdr_skipped + 1;
    else if (dbg_cycles < 200)
      $display("B %0t  b=%h  b_last=%b", $time, b_tdata, b_tlast);
  end
end

// M) After Depacketizer output (M-link: m_t*)
always @(posedge clk) begin
  if (rst_n && m_tvalid && m_tready && dbg_cycles < 200)
    $display("M %0t  m=%h  m_last=%b", $time, m_tdata, m_tlast);
end
// =============== END DEBUG PROBES ===============


  // ------------------------------------------------------------
  // Stimulus: payload (5 words) → PreambleInserter
  // ------------------------------------------------------------
  reg [31:0] payload [0:PAYLOAD_WORDS-1];
  integer tx_idx;

  initial begin
    payload[0] = 32'h1111_2222;
    payload[1] = 32'h3333_4444;
    payload[2] = 32'h5555_6666;
    payload[3] = 32'h7777_8888;
    payload[4] = 32'h9999_AAAA;

    s_tvalid = 1'b0;
    s_tdata  = '0;
    s_tlast  = 1'b0;

    @(posedge aresetn); @(posedge clk);
    s_tvalid = 1'b1;
    tx_idx   = 0;
    s_tdata  = payload[tx_idx];
    s_tlast  = (tx_idx == PAYLOAD_WORDS-1);

    while (tx_idx < PAYLOAD_WORDS) begin
      @(posedge clk);
      if (s_tvalid && s_tready) begin
        tx_idx = tx_idx + 1;
        if (tx_idx < PAYLOAD_WORDS) begin
          s_tdata = payload[tx_idx];
          s_tlast = (tx_idx == PAYLOAD_WORDS-1);
        end else begin
          s_tvalid = 1'b0;
          s_tlast  = 1'b0;
        end
      end
    end
  end

  // ------------------------------------------------------------
  // Expected preamble generator (matches inserter’s ROM pattern)
  //  sequence: {P,P}, {P,N}, {N,P}, {N,N} repeating (I,Q pairs)
  // ------------------------------------------------------------
  function automatic [31:0] pre_sym(input int idx);
    int sel;
    begin
      sel = idx % 4;
      case (sel)
        0: pre_sym = {P, P};
        1: pre_sym = {P, N};
        2: pre_sym = {N, P};
        default: pre_sym = {N, N};
      endcase
    end
  endfunction

  // ------------------------------------------------------------
  // Scoreboard: depacketizer output must equal:
  //   first PREAMBLE_LEN beats  -> expected preamble
  //   then PAYLOAD_WORDS beats  -> original payload[]
  //   TLAST only on final payload beat
  // ------------------------------------------------------------
  integer out_count;
  integer pre_seen;
  integer pay_seen;
  integer idx;

  initial begin
    out_count = 0;
    pre_seen  = 0;
    pay_seen  = 0;

    @(posedge rst_n);

    forever begin
      @(posedge clk);
      if (m_tvalid && m_tready) begin
        out_count = out_count + 1;

        if (pre_seen < PREAMBLE_LEN) begin
          // Expect preamble, no TLAST
          if (m_tdata !== pre_sym(pre_seen))
            $fatal(1, "PREAMBLE MISM: idx=%0d got=%h exp=%h",
                      pre_seen, m_tdata, pre_sym(pre_seen));
          if (m_tlast !== 1'b0)
            $fatal(1, "TLAST during preamble at idx=%0d", pre_seen);
          pre_seen = pre_seen + 1;
        end else begin
          // Payload
          idx = pay_seen;
          if (idx >= PAYLOAD_WORDS)
            $fatal(1, "Too many payload words: idx=%0d", idx);

          if (m_tdata !== payload[idx])
            $fatal(1, "PAYLOAD MISM: idx=%0d got=%h exp=%h",
                      idx, m_tdata, payload[idx]);

          if (idx < PAYLOAD_WORDS-1) begin
            if (m_tlast !== 1'b0)
              $fatal(1, "TLAST early at payload idx=%0d", idx);
          end else begin
            if (m_tlast !== 1'b1)
              $fatal(1, "TLAST missing on final payload word");
          end

          pay_seen = pay_seen + 1;

          // Done when final payload beat transfers
          if (pay_seen == PAYLOAD_WORDS && m_tlast) begin
            $display("PASS: preamble=%0d payload=%0d (header stripped OK)",
                     pre_seen, pay_seen);
            $finish;
          end
        end
      end
    end
  end

  // ------------------------------------------------------------
  // Timeout
  // ------------------------------------------------------------
  initial begin
    #200000;
    $fatal(1, "ERROR: timeout");
  end

endmodule

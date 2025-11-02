`timescale 1ns/1ps

module tb_preamble_inserter_simple;

  // ------------------------------------------------------------
  // Clock / Reset
  // ------------------------------------------------------------
  logic aclk = 0;
  always #5 aclk = ~aclk;  // 100 MHz

  logic aresetn;
  initial begin
    aresetn = 0;
    repeat (5) @(posedge aclk);
    aresetn = 1;
  end

  // ------------------------------------------------------------
  // AXIS-like signals
  // ------------------------------------------------------------
  // Upstream (to DUT)
  logic         s_tvalid;
  logic         s_tready;
  logic [31:0]  s_tdata;
  logic         s_tlast;

  // Downstream (from DUT)
  logic         m_tvalid;
  logic         m_tready;
  logic [31:0]  m_tdata;
  logic         m_tlast;

  // === Toggle this to stress back-pressure ===
  localparam bit RANDOM_BACKPRESSURE = 1'b0;

  // Keep downstream ready OR randomize it
  initial m_tready = 1'b1;
  always @(posedge aclk) if (aresetn && RANDOM_BACKPRESSURE) m_tready <= $urandom_range(0,1);

  // ------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------
  localparam int PREAMBLE_LEN   = 64;
  localparam int PAYLOAD_WORDS  = 5;

  PreambleInserter #(
    .PREAMBLE_LEN(PREAMBLE_LEN)
  ) dut (
    .aclk          (aclk),
    .aresetn       (aresetn),
    .s_axis_tvalid (s_tvalid),
    .s_axis_tready (s_tready),
    .s_axis_tdata  (s_tdata),
    .s_axis_tlast  (s_tlast),
    .m_axis_tvalid (m_tvalid),
    .m_axis_tready (m_tready),
    .m_axis_tdata  (m_tdata),
    .m_axis_tlast  (m_tlast)
  );

  // ------------------------------------------------------------
  // Payload source (5 words, TLAST on final word)
  // ------------------------------------------------------------
  logic [31:0] payload [0:PAYLOAD_WORDS-1];

  initial begin
    payload[0] = 32'h1111_2222;
    payload[1] = 32'h3333_4444;
    payload[2] = 32'h5555_6666;
    payload[3] = 32'h7777_8888;
    payload[4] = 32'h9999_AAAA;
  end

  int tx_idx;

  // Drive one frame; first word immediately after reset; advance on handshake
  initial begin
    s_tvalid = 0;
    s_tdata  = '0;
    s_tlast  = 0;

    @(posedge aresetn);
    @(posedge aclk);

    s_tvalid = 1'b1;
    tx_idx   = 0;
    s_tdata  = payload[tx_idx];
    s_tlast  = (tx_idx == PAYLOAD_WORDS-1);

    while (tx_idx < PAYLOAD_WORDS) begin
      @(posedge aclk);
      if (s_tvalid && s_tready) begin
        tx_idx++;
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
  // Scoreboard / Monitors
  // ------------------------------------------------------------
  int out_count;
  int preamble_seen;
  int payload_seen;

  // Count ALL input handshakes, and snapshot the count at payload start
  int in_handshakes_total;
  int in_hs_at_payload_start;
  bit payload_started;

  logic [31:0] recvd_payload [0:PAYLOAD_WORDS-1];

  // Pre-declare pay_idx to avoid automatic/static warnings
  int pay_idx;

  initial begin
    out_count              = 0;
    preamble_seen          = 0;
    payload_seen           = 0;
    in_handshakes_total    = 0;
    in_hs_at_payload_start = 0;
    payload_started        = 0;

    // Clear payload capture (avoids X's in waveform)
    for (int i=0;i<PAYLOAD_WORDS;i++) recvd_payload[i] = '0;

    @(posedge aresetn);

    forever begin
      @(posedge aclk);

      // Count every input handshake
      if (s_tvalid && s_tready)
        in_handshakes_total++;

      // Output handshake
      if (m_tvalid && m_tready) begin
        out_count++;

        // First PREAMBLE_LEN outputs are preamble (TLAST must be 0; s_tready must be 0)
        if (out_count <= PREAMBLE_LEN) begin
          preamble_seen++;
          if (m_tlast !== 1'b0)
            $fatal(1, "ERROR: TLAST asserted during preamble at out_count=%0d", out_count);
          if (s_tready !== 1'b0)
            $fatal(1, "ERROR: s_axis_tready went high during preamble at out_count=%0d", out_count);
        end
        // After preamble → payload
        else begin
          // Mark payload start (the first output beat after preamble)
          if (!payload_started) begin
            payload_started        = 1;
            in_hs_at_payload_start = in_handshakes_total;
          end

          pay_idx = payload_seen;
          if (pay_idx >= PAYLOAD_WORDS)
            $fatal(1, "ERROR: More output words than expected payload after preamble.");

          // Data must match
          if (m_tdata !== payload[pay_idx])
            $fatal(1, "ERROR: Payload mismatch @idx %0d: got 0x%8h exp 0x%8h",
                   pay_idx, m_tdata, payload[pay_idx]);

          // TLAST only on final payload word
          if (pay_idx < PAYLOAD_WORDS-1) begin
            if (m_tlast !== 1'b0)
              $fatal(1, "ERROR: TLAST asserted early @idx %0d", pay_idx);
          end else begin
            if (m_tlast !== 1'b1)
              $fatal(1, "ERROR: TLAST not asserted on final payload word");
          end

          recvd_payload[pay_idx] = m_tdata;
          payload_seen++;
        end

        // Finish when final payload beat (with TLAST) transfers
        if ((out_count >= PREAMBLE_LEN) && (payload_seen == PAYLOAD_WORDS) && m_tlast) begin
        // int payload_hs = in_handshakes_total - in_hs_at_payload_start;
        // if (payload_hs != PAYLOAD_WORDS)
        //   $fatal(1, "ERROR: Payload input handshakes mismatch: saw %0d, expected %0d",
        //          payload_hs, PAYLOAD_WORDS);

        $display("PASS: Preamble=%0d, Payload=%0d, (handshake check disabled), RandomBP=%0b",
                preamble_seen, payload_seen, RANDOM_BACKPRESSURE);
        $finish;
        end

      end
    end
  end

  // ------------------------------------------------------------
  // Timeout (safety)
  // ------------------------------------------------------------
  initial begin
    #200000; // 200 us
    $fatal(1, "ERROR: Simulation timeout.");
  end

endmodule

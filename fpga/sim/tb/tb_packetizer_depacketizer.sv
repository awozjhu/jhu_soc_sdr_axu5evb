`timescale 1ns/1ps
module tb_pkt_loopback;

  // --------------------------------------------------------------------------
  // Parameters (match SDR chain)
  // --------------------------------------------------------------------------
  localparam int DATA_WIDTH     = 32;
  localparam int CLK_PERIOD     = 4;          // 250 MHz

  // No preamble in this TB: we only test "header added/removed around payload"
  localparam int PAYLOAD_BYTES  = 256;        // bytes per frame
  localparam bit USE_QPSK       = 1'b1;       // 1→QPSK(K=2), 0→BPSK(K=1)
  localparam int K_BITS_PER_SYM = (USE_QPSK ? 2 : 1);
  localparam int PAYLOAD_WORDS  = (PAYLOAD_BYTES*8)/K_BITS_PER_SYM; // 256*8/2=1024

  // We're only sending payload words; packetizer will add its own 3-word header
  localparam int TOTAL_WORDS    = PAYLOAD_WORDS;

  // *** NEW: number of packets/frames to send
  localparam int N_FRAMES       = 4;

  // Synthesize packetizer for worst-case (BPSK: 64 + 256*8 = 2112) + margin
  localparam int MAX_FRAME_WORDS = 2112 + 64;

  // --------------------------------------------------------------------------
  // Clock and reset
  // --------------------------------------------------------------------------
  reg clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  reg rst_n = 0;
  initial begin
    rst_n = 0;
    repeat (10) @(posedge clk);
    rst_n = 1;
  end

  // --------------------------------------------------------------------------
  // AXIS connections
  // --------------------------------------------------------------------------
  reg  [DATA_WIDTH-1:0] s_axis_tdata  = '0;
  reg                   s_axis_tvalid = 1'b0;
  wire                  s_axis_tready;
  reg                   s_axis_tlast  = 1'b0;

  wire [DATA_WIDTH-1:0] link_tdata;
  wire                  link_tvalid;
  wire                  link_tready;   // driven by rx_depacketizer
  wire                  link_tlast;

  wire [DATA_WIDTH-1:0] m_axis_tdata;
  wire                  m_axis_tvalid;
  reg                   m_axis_tready = 1'b1;
  wire                  m_axis_tlast;

  // --------------------------------------------------------------------------
  // DUTs
  // --------------------------------------------------------------------------
  tx_packetizer #(
    .DATA_WIDTH      (DATA_WIDTH),
    .MAX_FRAME_WORDS (MAX_FRAME_WORDS) // sized for BPSK worst case
  )  u_tx (
    .clk            (clk),
    .rst_n          (rst_n),
    .s_axis_tdata   ( s_axis_tdata ),
    .s_axis_tvalid  ( s_axis_tvalid ),
    .s_axis_tready  ( s_axis_tready ),
    .s_axis_tlast   ( s_axis_tlast ),
    .m_axis_tdata   ( link_tdata ),
    .m_axis_tvalid  ( link_tvalid ),
    .m_axis_tready  ( link_tready ),
    .m_axis_tlast   ( link_tlast )
  );

  rx_depacketizer #(
    .DATA_WIDTH (DATA_WIDTH)
  ) u_rx (
    .clk            (clk),
    .rst_n          (rst_n),
    .s_axis_tdata   ( link_tdata ),
    .s_axis_tvalid  ( link_tvalid ),
    .s_axis_tready  ( link_tready ),   // RX drives this; don't tie off in TB
    .s_axis_tlast   ( link_tlast ),
    .m_axis_tdata   ( m_axis_tdata ),
    .m_axis_tvalid  ( m_axis_tvalid ),
    .m_axis_tready  ( m_axis_tready ),
    .m_axis_tlast   ( m_axis_tlast )
  );

  // --------------------------------------------------------------------------
  // Optional backpressure (after startup)
  // --------------------------------------------------------------------------
  integer num_cycles = 0;
  always @(posedge clk) begin
    if (!rst_n) begin
      num_cycles    <= 0;
      m_axis_tready <= 1'b1;
    end else begin
      num_cycles    <= num_cycles + 1;
      // After 200 cycles, randomly stall ~10% of the time
      if (num_cycles > 200)
        m_axis_tready <= ($urandom_range(0,9) != 0);
      else
        m_axis_tready <= 1'b1;
    end
  end

  // --------------------------------------------------------------------------
  // Drive N_FRAMES frames into packetizer: payload only (no preamble)
  // --------------------------------------------------------------------------
  initial begin : drive_frames
    int frame;
    int idx;

    wait (rst_n);
    repeat (8) @(posedge clk);

    $display("[%0t] Start: N_FRAMES=%0d, PAYLOAD_WORDS per frame=%0d",
             $time, N_FRAMES, PAYLOAD_WORDS);

    s_axis_tvalid = 1'b0;
    s_axis_tlast  = 1'b0;
    s_axis_tdata  = '0;

    for (frame = 0; frame < N_FRAMES; frame++) begin
      $display("[%0t] TX: starting frame %0d", $time, frame);
      idx = 0;

      // Send one frame of TOTAL_WORDS payload beats
      while (idx < TOTAL_WORDS) begin
        // payload pattern; same pattern each frame, TLAST marks boundary
        s_axis_tdata  <= {16'hBEEF, idx[15:0]};
        s_axis_tlast  <= (idx == TOTAL_WORDS-1);
        s_axis_tvalid <= 1'b1;

        @(posedge clk);
        if (s_axis_tvalid && s_axis_tready) begin
          idx <= idx + 1;
        end
      end

      // Deassert between frames (1 cycle gap is fine, could be 0 too)
      s_axis_tvalid <= 1'b0;
      s_axis_tlast  <= 1'b0;
      @(posedge clk);
    end

    $display("[%0t] TX: finished sending %0d frames", $time, N_FRAMES);
  end

  // --------------------------------------------------------------------------
  // Collect RX output
  // --------------------------------------------------------------------------
  integer recv_cnt = 0;
  always @(posedge clk) begin
    if (rst_n && m_axis_tvalid && m_axis_tready) begin
      recv_cnt <= recv_cnt + 1;
      if (m_axis_tlast) begin
        $display("[%0t] RX TLAST at payload word #%0d", $time, recv_cnt);
      end
    end
  end

  // --------------------------------------------------------------------------
  // CSV logging: packetizer input and depacketizer output (payload only)
  // --------------------------------------------------------------------------
  integer f_pkt_in, f_dep_out;
  integer in_idx, out_idx;

  initial begin
    f_pkt_in  = $fopen("pkt_in.csv",  "w");
    f_dep_out = $fopen("dep_out.csv", "w");
    if (!f_pkt_in || !f_dep_out) $fatal(1, "Failed to open CSV output(s).");

    $fdisplay(f_pkt_in,  "time_ns,idx,tvalid,tready,tlast,data_hex");
    $fdisplay(f_dep_out, "time_ns,idx,tvalid,tready,tlast,data_hex");

    in_idx  = 0;
    out_idx = 0;
  end

  // Log every accepted input beat into the packetizer (payload in)
  always @(posedge clk) begin
    if (rst_n && s_axis_tvalid && s_axis_tready) begin
      $fdisplay(f_pkt_in, "%0t,%0d,%0d,%0d,%0d,%08h",
                $time, in_idx, s_axis_tvalid, s_axis_tready, s_axis_tlast, s_axis_tdata);
      in_idx <= in_idx + 1;
    end
  end

  // Log every produced output beat from the depacketizer (payload out)
  always @(posedge clk) begin
    if (rst_n && m_axis_tvalid && m_axis_tready) begin
      $fdisplay(f_dep_out, "%0t,%0d,%0d,%0d,%0d,%08h",
                $time, out_idx, m_axis_tvalid, m_axis_tready, m_axis_tlast, m_axis_tdata);
      out_idx <= out_idx + 1;
    end
  end

  // --------------------------------------------------------------------------
  // Finish when all frames drained from depacketizer
  // --------------------------------------------------------------------------
  initial begin
    wait (rst_n);
    wait (recv_cnt == TOTAL_WORDS * N_FRAMES);
    repeat (10) @(posedge clk);
    $display("=== DONE: Received %0d payload words (expected %0d) ===",
             recv_cnt, TOTAL_WORDS * N_FRAMES);
    $fclose(f_pkt_in);
    $fclose(f_dep_out);
    $finish;
  end


endmodule

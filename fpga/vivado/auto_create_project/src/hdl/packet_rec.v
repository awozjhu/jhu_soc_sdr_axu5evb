// -----------------------------------------------------------------------------
// packet_rec  (GT RX -> AXI-Stream payload, “raw streamer” version)
//   - Replaces original header/seq/checksum parser.
//   - Uses word_align to produce rx_data_align / rx_ctrl_align.
//   - Treats gt_rx_ctrl == 4'b0000 as DATA, anything else as CONTROL / IDLE.
//   - A contiguous run of DATA beats is turned into one AXIS frame:
//        * First DATA word after CONTROL: start of frame (tvalid=1, tlast=0)
//        * Last DATA word just before CONTROL: tvalid=1, tlast=1
//   - Assumes m_axis_tready is essentially always 1; does not backpressure GT.
//   - packet_cnt_o increments once per reconstructed frame.
//   - error_packet_cnt_o is kept at 0 (no checksum/seq checking in this mode).
// -----------------------------------------------------------------------------
module packet_rec(
    input               rst,
    input               rx_clk,
    input  [31:0]       rx_data,
    input  [3:0]        rx_ctrl,

    output [31:0]       rx_data_align,
    output [3:0]        rx_ctrl_align,
    output [31:0]       packet_cnt_o,
    output [31:0]       error_packet_cnt_o,

    // AXI-Stream-style payload output (to rx_cdc_fifo)
    output [31:0]       m_axis_tdata,
    output              m_axis_tvalid,
    input               m_axis_tready,
    output              m_axis_tlast
);

  // ---------------------------------------------------------------------------
  // Word-aligner (unchanged interface)
  // ---------------------------------------------------------------------------
  wire [31:0] rx_data_align_int;
  wire [3:0]  rx_ctrl_align_int;

  assign rx_data_align  = rx_data_align_int;
  assign rx_ctrl_align  = rx_ctrl_align_int;

  word_align word_align_m0 (
      .rst           (rst),
      .rx_clk        (rx_clk),
      .gt_rx_data    (rx_data),
      .gt_rx_ctrl    (rx_ctrl),
      .rx_data_align (rx_data_align_int),
      .rx_ctrl_align (rx_ctrl_align_int)
  );

  // ---------------------------------------------------------------------------
  // Simple frame reconstruction based on DATA vs CONTROL
  // ---------------------------------------------------------------------------
  wire [31:0] gt_rx_data = rx_data_align_int;
  wire [3:0]  gt_rx_ctrl = rx_ctrl_align_int;

  wire is_data  = (gt_rx_ctrl == 4'b0000);
  wire is_ctrl  = (gt_rx_ctrl != 4'b0000);

  // One-word "hold" buffer so we can mark TLAST on the final data word
  reg  [31:0] hold_data;
  reg         hold_valid;
  reg         in_frame;

  // AXIS master regs
  reg  [31:0] m_axis_tdata_r;
  reg         m_axis_tvalid_r;
  reg         m_axis_tlast_r;

  assign m_axis_tdata  = m_axis_tdata_r;
  assign m_axis_tvalid = m_axis_tvalid_r;
  assign m_axis_tlast  = m_axis_tlast_r;

  // Packet counters
  reg [31:0] packet_cnt;
  reg [31:0] error_packet_cnt; // remains 0 in this simple mode

  assign packet_cnt_o       = packet_cnt;
  assign error_packet_cnt_o = error_packet_cnt;

  // ---------------------------------------------------------------------------
  // Main RX logic
  //
  // Notes:
  //   - We assume m_axis_tready is 1 in steady-state; we do not stall GT.
  //   - When a DATA word arrives:
  //       * If no hold_valid: just stash it.
  //       * If hold_valid: emit previous hold_data (tlast=0), then stash new.
  //   - When a CONTROL word arrives:
  //       * If in_frame and hold_valid: emit hold_data with tlast=1, end frame.
  // ---------------------------------------------------------------------------
  always @(posedge rx_clk or posedge rst) begin
    if (rst) begin
      hold_data       <= 32'd0;
      hold_valid      <= 1'b0;
      in_frame        <= 1'b0;

      m_axis_tdata_r  <= 32'd0;
      m_axis_tvalid_r <= 1'b0;
      m_axis_tlast_r  <= 1'b0;

      packet_cnt      <= 32'd0;
      error_packet_cnt<= 32'd0;
    end else begin
      // Default: no AXIS beat this cycle
      m_axis_tvalid_r <= 1'b0;
      m_axis_tlast_r  <= 1'b0;

      // We do not use m_axis_tready to throttle GT; it is assumed 1.
      // (This matches the behavior/assumptions of the original packet_rec.)
      if (is_data) begin
        if (!hold_valid) begin
          // First data word of a new frame (or after long idle)
          hold_data  <= gt_rx_data;
          hold_valid <= 1'b1;
          in_frame   <= 1'b1;
        end else begin
          // We already have a previous data word → emit it (not last)
          if (m_axis_tready) begin
            m_axis_tdata_r  <= hold_data;
            m_axis_tvalid_r <= 1'b1;
            m_axis_tlast_r  <= 1'b0;

            // New word becomes the held one
            hold_data  <= gt_rx_data;
            hold_valid <= 1'b1;
          end
          // If m_axis_tready were ever 0, we'd "want" to stall here, but
          // system-level design should keep it high to avoid drops.
        end
      end else if (is_ctrl) begin
        // Control / idle beat: if we're in a frame and have a held word,
        // treat that held word as the last data of this frame.
        if (in_frame && hold_valid) begin
          if (m_axis_tready) begin
            m_axis_tdata_r  <= hold_data;
            m_axis_tvalid_r <= 1'b1;
            m_axis_tlast_r  <= 1'b1;
            hold_valid      <= 1'b0;
            in_frame        <= 1'b0;

            // Count a completed frame
            packet_cnt      <= packet_cnt + 1'b1;
          end
          // Again, if m_axis_tready were 0 here, we can't actually stall GT,
          // so in practice keep it high.
        end else begin
          // Idle or multiple controls between frames: nothing to do
          in_frame   <= 1'b0;
          hold_valid <= hold_valid; // unchanged
        end
      end
    end
  end

endmodule

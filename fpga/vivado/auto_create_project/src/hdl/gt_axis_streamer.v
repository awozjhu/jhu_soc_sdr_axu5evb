// -----------------------------------------------------------------------------
// gt_axis_streamer (Verilog-2001)
//   - Bridges AXI-Stream frames to 8b/10b GT user interface.
//   - Framing:
//       * IDLE  : continuous K28.5 commas on all 4 bytes
//       * SOF   : one cycle of K28.5 on all 4 bytes
//       * FRAME : payload words (all data) until TLAST
//   - AXIS in:   s_axis_tdata[31:0], tvalid/tready/tlast
//   - GT out:    gt_tx_data[31:0], gt_tx_ctrl[3:0]
//                 gt_tx_ctrl[n] = 1 → corresponding byte is K-char (control)
// -----------------------------------------------------------------------------
module gt_axis_streamer
(
  input         clk,           // GT user clock (e.g. tx0_clk)
  input         rst,           // active-high synchronous reset

  // AXI-Stream in (from TX CDC FIFO)
  input  [31:0] s_axis_tdata,
  input         s_axis_tvalid,
  output        s_axis_tready,
  input         s_axis_tlast,

  // GT user interface out (to gt_example_top)
  output reg [31:0] gt_tx_data,
  output reg [3:0]  gt_tx_ctrl
);

// K28.5 control code (standard 8b/10b)
localparam [7:0] K28_5 = 8'hBC;

// Byte 0 = K, bytes 1..3 = 0x00 data
localparam [31:0] IDLE_WORD = {8'h00, 8'h00, 8'h00, K28_5};
localparam [3:0]  IDLE_CTRL = 4'b0001;   // only byte0 is K

localparam [31:0] SOF_WORD  = {8'h00, 8'h00, 8'h00, K28_5};
localparam [3:0]  SOF_CTRL  = 4'b0001;


  // ---------------------------------------------------------------------------
  // Simple 1-word buffer for AXIS input (decouples AXIS from link timing)
  // ---------------------------------------------------------------------------
  reg [31:0] buf_data;
  reg        buf_last;
  reg        buf_valid;

  // We only accept a new word when the buffer is empty
  assign s_axis_tready = ~buf_valid;

  // ---------------------------------------------------------------------------
  // FSM: IDLE (commas) → SOF (1 cycle K) → SEND (payload) → IDLE
  // ---------------------------------------------------------------------------
  localparam [1:0]
    ST_IDLE = 2'b00,
    ST_SOF  = 2'b01,
    ST_SEND = 2'b10;

  reg [1:0] state;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      // State / buffer reset
      state      <= ST_IDLE;
      buf_valid  <= 1'b0;
      buf_data   <= 32'h0;
      buf_last   <= 1'b0;

      // Drive IDLE on reset
      gt_tx_data <= IDLE_WORD;
      gt_tx_ctrl <= IDLE_CTRL;
    end else begin
      // -----------------------------------------------------------------------
      // Capture new AXIS word into buffer when available and empty
      // -----------------------------------------------------------------------
      if (s_axis_tvalid && s_axis_tready) begin
        buf_data  <= s_axis_tdata;
        buf_last  <= s_axis_tlast;
        buf_valid <= 1'b1;
      end

      // -----------------------------------------------------------------------
      // FSM
      // -----------------------------------------------------------------------
      case (state)
        // -------------------------------------------------------
        // IDLE: send continuous commas until we have a buffered word
        // -------------------------------------------------------
        ST_IDLE: begin
          gt_tx_data <= IDLE_WORD;
          gt_tx_ctrl <= IDLE_CTRL;

          if (buf_valid) begin
            // First word of a new frame is buffered
            state <= ST_SOF;
          end
        end

        // -------------------------------------------------------
        // SOF: send 1 cycle of K28.5 to mark start-of-frame
        // -------------------------------------------------------
        ST_SOF: begin
          gt_tx_data <= SOF_WORD;
          gt_tx_ctrl <= SOF_CTRL;

          // Next cycle we start transmitting payload
          state <= ST_SEND;
        end

        // -------------------------------------------------------
        // SEND: transmit payload words when buffer has data
        // -------------------------------------------------------
        ST_SEND: begin
          if (buf_valid) begin
            // Drive current payload word as 32b DATA (no control chars)
            gt_tx_data <= buf_data;
            gt_tx_ctrl <= 4'b0000;

            // Consume this buffered word
            buf_valid <= 1'b0;

            // If this was the last word of the frame, go back to IDLE
            if (buf_last) begin
              state <= ST_IDLE;
            end else begin
              state <= ST_SEND; // wait for next buffered word
            end
          end else begin
            // No payload ready yet: keep link alive with commas while waiting
            gt_tx_data <= IDLE_WORD;
            gt_tx_ctrl <= IDLE_CTRL;
            state      <= ST_SEND;
          end
        end

        default: begin
          state      <= ST_IDLE;
          gt_tx_data <= IDLE_WORD;
          gt_tx_ctrl <= IDLE_CTRL;
        end
      endcase
    end
  end

endmodule

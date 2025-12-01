module tx_packetizer #(
  parameter int DATA_WIDTH      = 32,
  // MAX_FRAME_WORDS sized for worst case BPSK:
  // PREAMBLE_LEN=64 + PAYLOAD_BYTES(256)*8/K(1)=2048 → total 2112 (plus margin)
  parameter int MAX_FRAME_WORDS = 2112 // MAX_FRAME_WORDS sized for worst case BPSK: PREAMBLE_LEN=64 + PAYLOAD_BYTES(256)*8/K(1)=2048 → total 2112 (plus margin) to allow dynamic QPSK/BPSK
)(
  input  logic                  clk,
  input  logic                  rst_n,
  // AXIS in
  input  logic [DATA_WIDTH-1:0] s_axis_tdata,
  input  logic                  s_axis_tvalid,
  output logic                  s_axis_tready,
  input  logic                  s_axis_tlast,
  // AXIS out
  output logic [DATA_WIDTH-1:0] m_axis_tdata,
  output logic                  m_axis_tvalid,
  input  logic                  m_axis_tready,
  output logic                  m_axis_tlast
);

  // -------- Header constants (12 bytes = 3 words) --------
  // localparam logic [15:0] SYNC_WORD  = 16'hA5A5;
  localparam logic [15:0] STAT_WORD  = 16'hA5A5;
  localparam logic [7:0]  HEADER_LEN = 8'd8;     // bytes after SYNC
  localparam logic [3:0]  MODE_VAL   = 4'h1;
  localparam logic [3:0]  FLAGS_VAL  = 4'h0;
  // localparam logic [31:0] RESERVED   = 32'hdead_beef;
  localparam logic [31:0] SYNC_WORD   = 32'hdead_beef;

  // -------- State --------
  typedef enum logic [1:0] {IDLE, COLLECT, SEND_HEADER, SEND_PAYLOAD} state_t;
  state_t state, next_state;

  // -------- Buffers / counters --------
  // HINT: tell Vivado to use block RAM
  (* ram_style = "block" *)
  logic [DATA_WIDTH-1:0] payload_buf [0:MAX_FRAME_WORDS-1];

  localparam int PTR_W = $clog2(MAX_FRAME_WORDS);
  logic [PTR_W:0]  wr_ptr;              // writes during COLLECT
  logic [PTR_W:0]  rd_ptr;              // reads during PAYLOAD
  logic [1:0]      hdr_idx;             // 0..2 during SEND_HEADER
  logic [15:0]     payload_length;      // number of payload beats
  logic [15:0]     seq_num;

  // -------- Outgoing staging (valid/ready-friendly) --------
  logic [DATA_WIDTH-1:0] next_tdata;
  logic                  next_tvalid, next_tlast;

  // ================= AXIS master output register =================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_axis_tvalid <= 1'b0;
      m_axis_tdata  <= '0;
      m_axis_tlast  <= 1'b0;
    end else if (!m_axis_tvalid || m_axis_tready) begin
      m_axis_tvalid <= next_tvalid;
      m_axis_tdata  <= next_tvalid ? next_tdata : '0;
      m_axis_tlast  <= next_tvalid ? next_tlast : 1'b0;
    end
    // else: hold when stalled
  end

  // ===================== State register =====================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      state <= IDLE;
    else
      state <= next_state;
  end

  // ===================== RAM write port ONLY =====================
  // IMPORTANT: no reset in this process so Vivado can infer BRAM.
  always_ff @(posedge clk) begin
    if ((state == IDLE || state == COLLECT) && s_axis_tvalid && s_axis_tready) begin
      payload_buf[wr_ptr] <= s_axis_tdata;
    end
  end

  // ===================== Sequential updates (no RAM writes) =====================
  // All pointer/counter updates and control. This one can have reset.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr         <= '0;
      rd_ptr         <= '0;
      hdr_idx        <= 2'd0;
      payload_length <= 16'd0;
      seq_num        <= 16'd0;
    end else begin
      // Accept input beats (but NOT the RAM write – that’s in its own block)
      if ((state == IDLE || state == COLLECT) && s_axis_tvalid && s_axis_tready) begin
        wr_ptr         <= wr_ptr + 1;
        payload_length <= payload_length + 1;
        if (s_axis_tlast) begin
          // frame end collected
          seq_num <= seq_num + 16'd1;
        end
      end

      // Header progression (advance only on output handshake)
      if (state == SEND_HEADER && m_axis_tvalid && m_axis_tready) begin
        hdr_idx <= hdr_idx + 2'd1;
        if (hdr_idx == 2) begin
          hdr_idx <= 2'd0;
          rd_ptr  <= '0;           // prepare for payload reads
        end
      end

      // Payload progression (advance only on output handshake)
      if (state == SEND_PAYLOAD && m_axis_tvalid && m_axis_tready) begin
        rd_ptr <= rd_ptr + 1;
        if (rd_ptr == payload_length - 1) begin
          // frame done → clear for next frame
          rd_ptr         <= '0;
          wr_ptr         <= '0;
          payload_length <= 16'd0;
        end
      end
    end
  end

  // ===================== Combinational next logic =====================
  always_comb begin
    // defaults
    next_state    = state;
    s_axis_tready = 1'b0;
    next_tvalid   = 1'b0;
    next_tdata    = '0;
    next_tlast    = 1'b0;

    unique case (state)
      // ---- Accept first beat immediately ----
      IDLE: begin
        s_axis_tready = 1'b1;
        if (s_axis_tvalid) begin
          if (s_axis_tlast)  next_state = SEND_HEADER; // single-beat frame
          else               next_state = COLLECT;
        end
      end

      // ---- Collect entire frame so we know length ----
      COLLECT: begin
        s_axis_tready = 1'b1;
        if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
          next_state = SEND_HEADER;                // have full length
        end
      end

      // ---- Emit 3-word header, one beat per handshake ----
      SEND_HEADER: begin
        if (!m_axis_tvalid || m_axis_tready) begin
          next_tvalid = 1'b1;
          unique case (hdr_idx)
            // 2'd0: next_tdata = {SYNC_WORD, HEADER_LEN, {MODE_VAL, FLAGS_VAL}};
            // 2'd1: next_tdata = {seq_num,   payload_length};
            // 2'd2: next_tdata = RESERVED;

            2'd0: next_tdata = SYNC_WORD;
            2'd1: next_tdata = {seq_num,   payload_length};
            2'd2: next_tdata = {STAT_WORD, HEADER_LEN, {MODE_VAL, FLAGS_VAL}};

          endcase
          // tlast is ONLY for last payload beat, never for header
          next_tlast = 1'b0;

          // advance state after 3rd header beat handshake
          if (hdr_idx == 2 && (m_axis_tvalid ? m_axis_tready : 1'b1)) begin
            next_state = SEND_PAYLOAD;
          end
        end
      end

      // ---- Stream buffered payload ----
      SEND_PAYLOAD: begin
        if (!m_axis_tvalid || m_axis_tready) begin
          next_tvalid = 1'b1;
          next_tdata  = payload_buf[rd_ptr];           // async read is OK
          next_tlast  = (rd_ptr == payload_length - 1);
          if (next_tlast) begin
            next_state = IDLE;
          end
        end
      end

      default: next_state = IDLE;
    endcase
  end

endmodule

// -----------------------------------------------------------------------------
// axis_conv_encoder_wrap
//   AXIS wrapper around Xilinx "convolution_0" encoder IP
//   - 8-bit data in / 8-bit data out
//   - TLAST is tracked with a small FIFO (handshake-aware), so it stays
//     aligned even with variable latency and backpressure.
//   - dbg_in_frame_bytes  : bytes per input frame (between TLASTs)
//   - dbg_out_frame_bytes : bytes per output frame (between TLASTs)
// -----------------------------------------------------------------------------
module axis_conv_encoder_wrap #(
  parameter int TLAST_FIFO_DEPTH = 16   // must exceed encoder pipeline depth
)(
  input  logic        clk,
  input  logic        rst_n,

  // AXIS in
  input  logic [7:0]  s_axis_tdata,
  input  logic        s_axis_tvalid,
  output logic        s_axis_tready,
  input  logic        s_axis_tlast,

  // AXIS out
  output logic [7:0]  m_axis_tdata,
  output logic        m_axis_tvalid,
  input  logic        m_axis_tready,
  output logic        m_axis_tlast,

  // Debug: frame byte counts
  output logic [15:0] dbg_in_frame_bytes,
  output logic [15:0] dbg_out_frame_bytes
);

  // ----------------- Underlying conv encoder IP -----------------
  logic [7:0] enc_s_tdata;
  logic       enc_s_tvalid, enc_s_tready;
  logic [7:0] enc_m_tdata;
  logic       enc_m_tvalid, enc_m_tready;

  convolution_0 u_conv (
    .aclk             (clk),
    .aresetn          (rst_n),
    .s_axis_data_tdata(enc_s_tdata),
    .s_axis_data_tvalid(enc_s_tvalid),
    .s_axis_data_tready(enc_s_tready),
    .m_axis_data_tdata(enc_m_tdata),
    .m_axis_data_tvalid(enc_m_tvalid),
    .m_axis_data_tready(enc_m_tready)
  );

  // Straight-through AXIS for data/valid/ready
  assign enc_s_tdata  = s_axis_tdata;
  assign enc_s_tvalid = s_axis_tvalid;
  assign s_axis_tready = enc_s_tready;

  assign m_axis_tdata  = enc_m_tdata;
  assign m_axis_tvalid = enc_m_tvalid;
  assign enc_m_tready  = m_axis_tready;

  // ----------------- TLAST FIFO (handshake-aware) -----------------

  localparam int FIFO_AW = $clog2(TLAST_FIFO_DEPTH);

  logic [TLAST_FIFO_DEPTH-1:0] tlast_mem;
  logic [FIFO_AW:0]            wr_ptr, rd_ptr;
  logic [FIFO_AW:0]            fifo_level;

  wire in_fire  = s_axis_tvalid & s_axis_tready;
  wire out_fire = m_axis_tvalid & m_axis_tready;

  // Write TLAST bit when we accept an input byte
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr     <= '0;
      rd_ptr     <= '0;
      fifo_level <= '0;
      m_axis_tlast <= 1'b0;
    end else begin
      // push on input handshake
      if (in_fire) begin
        tlast_mem[wr_ptr[FIFO_AW-1:0]] <= s_axis_tlast;
        wr_ptr <= wr_ptr + 1'b1;
      end

      // pop on output handshake
      if (out_fire) begin
        m_axis_tlast <= tlast_mem[rd_ptr[FIFO_AW-1:0]];
        rd_ptr       <= rd_ptr + 1'b1;
      end else begin
        // deassert when not doing a transfer
        m_axis_tlast <= 1'b0;
      end

      // book-keeping (optional; no overflow check here)
      case ({in_fire, out_fire})
        2'b10: fifo_level <= fifo_level + 1'b1;
        2'b01: fifo_level <= fifo_level - 1'b1;
        default: ; // same level
      endcase
    end
  end

  // ----------------- Debug frame byte counters -----------------

  logic [15:0] in_count, out_count;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      in_count          <= '0;
      out_count         <= '0;
      dbg_in_frame_bytes  <= '0;
      dbg_out_frame_bytes <= '0;
    end else begin
      // Input side: count bytes until TLAST
      if (in_fire) begin
        in_count <= in_count + 16'd1;
        if (s_axis_tlast) begin
          dbg_in_frame_bytes <= in_count + 16'd1;
          in_count           <= '0;
        end
      end

      // Output side: TLAST from FIFO
      if (out_fire) begin
        out_count <= out_count + 16'd1;
        if (m_axis_tlast) begin
          dbg_out_frame_bytes <= out_count + 16'd1;
          out_count           <= '0;
        end
      end
    end
  end

  // Optional safety asserts
  // synopsys translate_off
  always_ff @(posedge clk) begin
    if (fifo_level == TLAST_FIFO_DEPTH && in_fire && !out_fire)
      $warning("axis_conv_encoder_wrap TLAST FIFO overflow risk");
    if (fifo_level == '0 && out_fire && !in_fire)
      $warning("axis_conv_encoder_wrap TLAST FIFO underflow risk");
  end
  // synopsys translate_on

endmodule

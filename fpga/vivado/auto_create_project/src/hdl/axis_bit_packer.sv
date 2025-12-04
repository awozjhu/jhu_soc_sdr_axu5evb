// -----------------------------------------------------------------------------
// axis_bit_packer.sv
//
// - Consumes 1 decoded bit per cycle from Viterbi (bit 0 of s_axis_tdata).
// - Packs 8 bits into a byte (LSB-first) and outputs on an AXIS byte stream.
// - Asserts TLAST every FRAME_BYTES bytes (continuous frames).
//
// Assumes Viterbi is producing one data bit per cycle on m_axis_data_tdata[0].
// Connect Viterbi -> packer -> PRBS monitor.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module axis_bit_packer #(
  parameter int FRAME_BYTES = 256  // TLAST every FRAME_BYTES bytes (0 = never)
)(
  input  logic        clk,
  input  logic        rst_n,

  // AXIS IN: from Viterbi decoder
  input  logic [7:0]  s_axis_tdata,   // only bit 0 is used
  input  logic        s_axis_tvalid,
  output logic        s_axis_tready,
  input  logic        s_axis_tlast,   // unused, but kept for completeness

  // AXIS OUT: to PRBS monitor (byte stream)
  output logic [7:0]  m_axis_tdata,
  output logic        m_axis_tvalid,
  input  logic        m_axis_tready,
  output logic        m_axis_tlast
);

  // bit buffer and counters
  logic [7:0] byte_shift;
  logic [2:0] bit_cnt;          // 0..7 bits collected
  logic [15:0] byte_cnt;        // bytes per frame

  // convenient wires
  wire bit_in       = s_axis_tdata[0];
  wire in_fire      = s_axis_tvalid && s_axis_tready;
  wire byte_complete= in_fire && (bit_cnt == 3'd7);

  // next-byte value if this bit is accepted (LSB-first packing)
  wire [7:0] next_byte = {bit_in, byte_shift[7:1]};

  // Backpressure: we must *not* accept a bit that would complete a byte
  // if we still have an unconsumed output byte.
  always_comb begin
    if (byte_complete && m_axis_tvalid && !m_axis_tready)
      s_axis_tready = 1'b0;
    else
      s_axis_tready = 1'b1;
  end

  // Sequential logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      byte_shift   <= 8'h00;
      bit_cnt      <= 3'd0;
      byte_cnt     <= 16'd0;
      m_axis_tdata <= 8'h00;
      m_axis_tvalid<= 1'b0;
      m_axis_tlast <= 1'b0;
    end else begin
      // default: clear valid/last when accepted
      if (m_axis_tvalid && m_axis_tready) begin
        m_axis_tvalid <= 1'b0;
        m_axis_tlast  <= 1'b0;
      end

      // take a new bit when allowed
      if (in_fire) begin
        byte_shift <= next_byte;

        if (bit_cnt == 3'd7)
          bit_cnt <= 3'd0;
        else
          bit_cnt <= bit_cnt + 3'd1;
      end

      // when a full byte is formed, present it on AXIS out
      if (byte_complete) begin
        if (!m_axis_tvalid || m_axis_tready) begin
          m_axis_tdata  <= next_byte;
          m_axis_tvalid <= 1'b1;

          // TLAST generation (every FRAME_BYTES bytes if enabled)
          if (FRAME_BYTES != 0) begin
            m_axis_tlast <= (byte_cnt == FRAME_BYTES-1);
          end else begin
            m_axis_tlast <= 1'b0;
          end
        end

        // Update byte counter regardless of backpressure (we only got here
        // when we accepted the bit that finished the byte).
        if (FRAME_BYTES != 0) begin
          if (byte_cnt == FRAME_BYTES-1)
            byte_cnt <= 16'd0;
          else
            byte_cnt <= byte_cnt + 16'd1;
        end
      end
    end
  end

endmodule

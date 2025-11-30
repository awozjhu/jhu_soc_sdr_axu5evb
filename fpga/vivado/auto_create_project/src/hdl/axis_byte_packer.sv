// -----------------------------------------------------------------------------
// axis_byte_packer
//   - Packs BITS_PER_SYM bits from each input beat (from slicer) into full bytes.
//   - BITS_PER_SYM = 1 (BPSK)  → 8 symbols per output byte
//                 = 2 (QPSK)  → 4 symbols per output byte
//   - AXIS in :  s_axis_tdata[7:0], only [BITS_PER_SYM-1:0] are used.
//   - AXIS out:  m_axis_tdata[7:0] full packed bytes.
//   - Requirement: frame length in symbols must be a multiple of SYMS_PER_BYTE.
//                  If TLAST is not aligned, a sim-time error is raised.
// -----------------------------------------------------------------------------
module axis_byte_packer #(
  parameter int BITS_PER_SYM = 2    // 1 for BPSK, 2 for QPSK
)(
  input  logic        clk,
  input  logic        rst_n,

  // AXIS in  (from slicer)
  input  logic [7:0]  s_axis_tdata,
  input  logic        s_axis_tvalid,
  output logic        s_axis_tready,
  input  logic        s_axis_tlast,

  // AXIS out (to descrambler / BER checker)
  output logic [7:0]  m_axis_tdata,
  output logic        m_axis_tvalid,
  input  logic        m_axis_tready,
  output logic        m_axis_tlast
);

  // ---------------------------------------------------------------------------
  // Static configuration
  // ---------------------------------------------------------------------------
  localparam int SYMS_PER_BYTE = 8 / BITS_PER_SYM;
  localparam int CNT_W         = (SYMS_PER_BYTE <= 1) ? 1 :
                                 (SYMS_PER_BYTE <= 2) ? 1 :
                                 (SYMS_PER_BYTE <= 4) ? 2 : 3;

  // Simple guard: only support 1 or 2 bits per symbol in this version
  // synopsys translate_off
  initial begin
    if (BITS_PER_SYM != 1 && BITS_PER_SYM != 2) begin
      $error("axis_byte_packer: BITS_PER_SYM must be 1 or 2 in this implementation.");
    end
  end
  // synopsys translate_on

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------
  logic [7:0]       acc;        // byte accumulator
  logic [CNT_W-1:0] sym_cnt;    // 0 .. SYMS_PER_BYTE-1
  logic             acc_last;   // TLAST seen for this byte-in-progress

  // Output register
  logic [7:0]       out_data_r;
  logic             out_valid_r;
  logic             out_last_r;

  assign m_axis_tdata  = out_data_r;
  assign m_axis_tvalid = out_valid_r;
  assign m_axis_tlast  = out_last_r;

  // ---------------------------------------------------------------------------
  // Handshake: ready when we're not about to overflow the output register
  // ---------------------------------------------------------------------------
  wire finishing_byte = (sym_cnt == SYMS_PER_BYTE-1);

  always_comb begin
    // Default: ready
    s_axis_tready = 1'b1;

    // If accepting this symbol would finish a byte AND the output register is
    // still full and not being consumed, deassert ready.
    if (finishing_byte && out_valid_r && !m_axis_tready) begin
      s_axis_tready = 1'b0;
    end
  end

  // ---------------------------------------------------------------------------
  // Sequential logic
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acc         <= 8'h00;
      sym_cnt     <= '0;
      acc_last    <= 1'b0;

      out_data_r  <= 8'h00;
      out_valid_r <= 1'b0;
      out_last_r  <= 1'b0;
    end else begin
      // Consume output beat when downstream ready
      if (out_valid_r && m_axis_tready) begin
        out_valid_r <= 1'b0;
      end

      // Accept an input symbol
      if (s_axis_tvalid && s_axis_tready) begin
        // Capture TLAST associated with this symbol group
        acc_last <= s_axis_tlast;

        // Place bits into accumulator at position based on sym_cnt
        if (BITS_PER_SYM == 2) begin
          // QPSK: 2 bits per symbol → 4 symbols per byte
          case (sym_cnt)
            2'd0: acc[1:0] <= s_axis_tdata[1:0];
            2'd1: acc[3:2] <= s_axis_tdata[1:0];
            2'd2: acc[5:4] <= s_axis_tdata[1:0];
            2'd3: acc[7:6] <= s_axis_tdata[1:0];
            default: ; // unreachable
          endcase
        end else begin
          // BPSK: 1 bit per symbol → 8 symbols per byte
          // (only use bit 0)
          case (sym_cnt)
            3'd0: acc[0] <= s_axis_tdata[0];
            3'd1: acc[1] <= s_axis_tdata[0];
            3'd2: acc[2] <= s_axis_tdata[0];
            3'd3: acc[3] <= s_axis_tdata[0];
            3'd4: acc[4] <= s_axis_tdata[0];
            3'd5: acc[5] <= s_axis_tdata[0];
            3'd6: acc[6] <= s_axis_tdata[0];
            3'd7: acc[7] <= s_axis_tdata[0];
            default: ; // unreachable
          endcase
        end

        // If this finishes a byte, push it to the output register
        if (finishing_byte) begin
          if (!out_valid_r || m_axis_tready) begin
            out_data_r  <= acc;
            out_last_r  <= s_axis_tlast;  // require alignment in sim
            out_valid_r <= 1'b1;
          end
          // Reset accumulator for next byte
          sym_cnt <= '0;
          acc     <= 8'h00;
          acc_last <= 1'b0;
        end else begin
          // Not yet a full byte → bump symbol count
          sym_cnt <= sym_cnt + 1'b1;
        end

        // If TLAST asserted, clear partial state for next frame.
        if (s_axis_tlast) begin
          sym_cnt  <= '0;
          acc      <= 8'h00;
          acc_last <= 1'b0;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Sim-time check: TLAST must land on a byte boundary (optional but nice)
  // ---------------------------------------------------------------------------
  // synopsys translate_off
  always_ff @(posedge clk) begin
    if (rst_n && s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
      if (sym_cnt != SYMS_PER_BYTE-1) begin
        $error("axis_byte_packer: TLAST not aligned to byte boundary (sym_cnt=%0d)", sym_cnt);
      end
    end
  end
  // synopsys translate_on

endmodule

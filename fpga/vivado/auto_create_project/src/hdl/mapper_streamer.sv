// -----------------------------------------------------------------------------
// mapper.sv – Streaming BPSK/QPSK symbol mapper (no AXI-Lite, no TLAST in)
// -----------------------------------------------------------------------------
// - Bytes in (8b, LSB-first within each byte) --> {I,Q} out in Q1.15.
// - QPSK Gray: 00:(+,+), 01:(-,+), 11:(-,-), 10:(+,-).
// - Frameing: TLAST is generated internally after FRAME_BYTES input bytes
//   worth of bits have been consumed (taking into account BPSK/QPSK).
// - Mode selection is via amc_mode_i[0]: 0=BPSK, 1=QPSK (when valid).
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module mapper_streamer #(
  // Q1.15 amplitudes
  parameter logic signed [15:0] AMP_BPSK    = 16'sd32767, // ±1.0
  parameter logic signed [15:0] AMP_QPSK    = 16'sd23170, // ±1/√2
  // Number of input bytes per "frame" for TLAST generation
  parameter int                 FRAME_BYTES = 256
)(
  input  logic        clk_bb,
  input  logic        rst_n,

  // -------- internal "AXIS-like" bitstream in (8-bit) --------
  input  logic        in_valid,
  output logic        in_ready,
  input  logic [7:0]  in_data,

  // -------- internal "AXIS-like" symbols out: {I[15:0],Q[15:0]} --------
  output logic        out_valid,
  input  logic        out_ready,
  output logic [31:0] out_data,   // {I[15:0], Q[15:0]}
  output logic        out_last,

  // Optional AMC-selected mode (only bit[0] used today: 0=BPSK, 1=QPSK)
  input  logic [2:0]  amc_mode_i,
  input  logic        amc_mode_valid_i
);

  // ===========================================================================
  // Local types/params
  // ===========================================================================
  typedef logic signed [15:0] iq_comp_t;

  localparam int FRAME_BITS   = FRAME_BYTES * 8;
  localparam int FRAME_BITS_W = $clog2(FRAME_BITS + 1);

  // ===========================================================================
  // Mode selection: 0=BPSK, 1=QPSK
  // ===========================================================================
  logic eff_qpsk;  // 0=BPSK, 1=QPSK

  always_comb begin
    if (amc_mode_valid_i) eff_qpsk = amc_mode_i[0];
    else                  eff_qpsk = 1'b1;    // default QPSK
  end

  // ===========================================================================
  // Bit buffer & frame-bit counter
  // ===========================================================================
  logic [7:0]          bit_buf;
  logic [3:0]          bits_avail;       // 0..8 bits currently in bit_buf

  // Counts how many bits remain in the *current* frame.
  // TLAST asserted on the symbol that consumes the final K bits.
  logic [FRAME_BITS_W-1:0] bits_left;

  // ===========================================================================
  // One-symbol hold register
  // ===========================================================================
  iq_comp_t   hold_I, hold_Q;
  logic       hold_last, hold_valid;
  logic [1:0] hold_bits_used;

  // ===========================================================================
  // Bits-per-symbol helper: K = 1 for BPSK, 2 for QPSK
  // ===========================================================================
  logic need2;
  logic [1:0] K;

  always_comb begin
    need2 = eff_qpsk;        // QPSK uses 2 bits, BPSK uses 1
    K     = need2 ? 2'd2 : 2'd1;
  end

  // Ready to accept a new byte when the buffer is empty and we are not
  // holding a symbol that still needs to be sent.
  assign in_ready  = (bits_avail == 4'd0) && (~hold_valid);

  // Output signals from hold register
  assign out_valid = hold_valid;
  assign out_data  = {hold_I, hold_Q};
  assign out_last  = hold_last;

  // ===========================================================================
  // Mapping function (same as old mapper)
  // ===========================================================================
  function automatic void map_bits_to_iq (
      input  logic       qpsk,
      input  logic       b0,
      input  logic       b1,
      output iq_comp_t   i,
      output iq_comp_t   q
  );
    if (!qpsk) begin
      // BPSK on I, Q=0
      i = (b0 == 1'b0) ? AMP_BPSK : -AMP_BPSK;
      q = '0;
    end else begin
      unique case ({b1,b0}) // Gray QPSK
        2'b00: begin i =  AMP_QPSK; q =  AMP_QPSK; end // (+,+)
        2'b01: begin i = -AMP_QPSK; q =  AMP_QPSK; end // (-,+)
        2'b11: begin i = -AMP_QPSK; q = -AMP_QPSK; end // (-,-)
        2'b10: begin i =  AMP_QPSK; q = -AMP_QPSK; end // (+,-)
        default: begin i = '0; q = '0; end
      endcase
    end
  endfunction

  // ===========================================================================
  // Datapath / handshakes
  // ===========================================================================
  always_ff @(posedge clk_bb or negedge rst_n) begin
    if (!rst_n) begin
      bit_buf        <= '0;
      bits_avail     <= 4'd0;

      bits_left      <= FRAME_BITS;

      hold_I         <= '0;
      hold_Q         <= '0;
      hold_last      <= 1'b0;
      hold_valid     <= 1'b0;
      hold_bits_used <= 2'd0;
    end else begin
      // ----------------------------------------------------------
      // Accept an input byte into the bit buffer
      // ----------------------------------------------------------
      if (in_valid && in_ready) begin
        bit_buf    <= in_data;   // LSB-first usage
        bits_avail <= 4'd8;
      end

      // ----------------------------------------------------------
      // Generate a symbol when possible (fill hold_*)
      // ----------------------------------------------------------
      if (!hold_valid && (bits_avail >= K) && (bits_left >= K)) begin
        iq_comp_t i_tmp, q_tmp;
        logic     b0, b1;

        b0 = bit_buf[0];
        b1 = need2 ? bit_buf[1] : 1'b0;

        map_bits_to_iq(eff_qpsk, b0, b1, i_tmp, q_tmp);

        hold_I         <= i_tmp;
        hold_Q         <= q_tmp;
        hold_bits_used <= K;

        // TLAST when this symbol consumes the last K bits of the frame
        hold_last      <= (bits_left == K);
        hold_valid     <= 1'b1;
      end

      // ----------------------------------------------------------
      // Downstream handshake: consume held symbol
      // ----------------------------------------------------------
      if (hold_valid && out_ready) begin
        hold_valid <= 1'b0;

        // consume bits from the local byte buffer
        bit_buf    <= bit_buf >> hold_bits_used;
        bits_avail <= bits_avail - hold_bits_used;

        // update frame bit counter
        if (hold_last) begin
          // Finished a frame; reload for next one
          bits_left <= FRAME_BITS;
        end else begin
          bits_left <= bits_left - hold_bits_used;
        end
      end
    end
  end

  // synopsys translate_off
  initial begin
    assert(AMP_BPSK == 16'sd32767)
      else $error("AMP_BPSK must be 32767 (Q1.15)");
    assert(AMP_QPSK == 16'sd23170)
      else $error("AMP_QPSK should be ~23170 (Q1.15)");
  end
  // synopsys translate_on

endmodule

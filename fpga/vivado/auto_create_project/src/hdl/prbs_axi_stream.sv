// -----------------------------------------------------------------------------
// axis_prbs_src.sv
//
// AXI-Stream PRBS byte source (no AXI-Lite).
// - 8-bit tdata, PRBS31 by default.
// - One byte per accepted beat (tvalid & tready).
// - Little-endian inside each byte: first PRBS bit -> tdata[0].
// - Backpressure-safe: if stalled, tvalid stays high and data/tlast hold.
// - In the no-stall case (tready always 1), tvalid is a 1-cycle pulse per beat.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module axis_prbs_src #(
  // LFSR parameters (default: PRBS31 with x^31 + x^28 + 1)
  parameter int LFSR_W          = 31,
  parameter int TAP_A           = 30,     // bit index for tap A
  parameter int TAP_B           = 27,     // bit index for tap B
  parameter logic [LFSR_W-1:0] INIT_SEED  = {{(LFSR_W-1){1'b0}}, 1'b1},

  // Framing: 0 => continuous (TLAST never asserted)
  parameter int FRAME_LEN_BYTES = 0
)(
  input  logic        clk,
  input  logic        rst_n,

  // Simple enable (1 = generate stream, 0 = idle)
  input  logic        enable,

  // AXI-Stream master
  output logic [7:0]  m_axis_tdata,
  output logic        m_axis_tvalid,
  input  logic        m_axis_tready,
  output logic        m_axis_tlast
);

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------
  logic [LFSR_W-1:0] lfsr_q;
  logic [7:0]        data_q;
  logic              tvalid_q;
  logic [31:0]       bytes_in_frame_q; // simple 32-bit counter

  // Handshake helper
  wire fire = m_axis_tvalid && m_axis_tready;

  // ---------------------------------------------------------------------------
  // LFSR helpers
  // ---------------------------------------------------------------------------
  function automatic logic [LFSR_W-1:0] next_lfsr(
    input logic [LFSR_W-1:0] cur
  );
    logic fb;
    fb        = cur[TAP_A] ^ cur[TAP_B];
    next_lfsr = {cur[LFSR_W-2:0], fb};
  endfunction

  // Generate next byte (8 bits) and updated LFSR in one shot
  task automatic gen_next_byte(
    input  logic [LFSR_W-1:0] cur_state,
    output logic [LFSR_W-1:0] new_state,
    output logic [7:0]        new_byte
  );
    logic [LFSR_W-1:0] tmp;
    int i;
    begin
      tmp      = cur_state;
      new_byte = '0;
      for (i = 0; i < 8; i++) begin
        new_byte[i] = tmp[0];        // little-endian: first bit -> bit0
        tmp        = next_lfsr(tmp); // advance LFSR one bit
      end
      new_state = tmp;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Main sequential logic
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // Seed LFSR (coerce zero to 1)
      if (INIT_SEED == '0)
        lfsr_q <= {{(LFSR_W-1){1'b0}}, 1'b1};
      else
        lfsr_q <= INIT_SEED;

      data_q           <= '0;
      tvalid_q         <= 1'b0;
      bytes_in_frame_q <= 32'd0;
    end else begin
      if (!enable) begin
        // Idle: no stream
        tvalid_q         <= 1'b0;
        bytes_in_frame_q <= 32'd0;
        // Keep LFSR state so restart continues sequence if you like
      end else begin
        if (tvalid_q) begin
          // We have a byte waiting on the bus
          if (m_axis_tready) begin
            // Handshake this cycle; drop tvalid for the next cycle
            tvalid_q <= 1'b0;

            // Update frame counter on accepted beat
            if (FRAME_LEN_BYTES > 0) begin
              if (bytes_in_frame_q == FRAME_LEN_BYTES-1)
                bytes_in_frame_q <= 32'd0;
              else
                bytes_in_frame_q <= bytes_in_frame_q + 32'd1;
            end else begin
              bytes_in_frame_q <= 32'd0;
            end
          end
          // else: stalled -> hold data_q, tvalid_q, bytes_in_frame_q as-is
        end else begin
          // No pending data: generate next byte
          logic [LFSR_W-1:0] lfsr_next;
          logic [7:0]        byte_next;

          gen_next_byte(lfsr_q, lfsr_next, byte_next);

          lfsr_q   <= lfsr_next;
          data_q   <= byte_next;
          tvalid_q <= 1'b1; // will be visible in the *next* cycle on the pins
          // bytes_in_frame_q updated only when the byte is actually accepted
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Outputs
  // ---------------------------------------------------------------------------
  assign m_axis_tdata  = data_q;
  assign m_axis_tvalid = tvalid_q;

  // TLAST: asserted with the last byte of the frame.
  // Because bytes_in_frame_q only updates on fire, TLAST is stable under stall.
  assign m_axis_tlast =
    (FRAME_LEN_BYTES > 0) ?
      (tvalid_q && (bytes_in_frame_q == FRAME_LEN_BYTES-1)) :
      1'b0;

endmodule

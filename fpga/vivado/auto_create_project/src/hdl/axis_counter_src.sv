// -----------------------------------------------------------------------------
// axis_counter_src.sv
//
// Simple AXI-Stream byte counter for debug.
// - 8-bit tdata counts up on each valid+ready handshake.
// - No AXI-Lite / software registers.
// - Optional frame length parameter to generate TLAST pulses.
//
// Ports
//   clk, rst_n          : clock and active-low reset
//   enable              : when 1, drive the stream; when 0, hold tvalid=0
//   m_axis_tdata[7:0]   : incrementing counter value
//   m_axis_tvalid       : asserted when data is valid
//   m_axis_tready       : backpressure from downstream
//   m_axis_tlast        : TLAST pulse at end of frame (if FRAME_LEN > 0)
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module axis_counter_src #(
  parameter int FRAME_LEN = 0  // bytes per frame; 0 => never assert TLAST
)(
  input  logic        clk,
  input  logic        rst_n,

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
  logic [7:0]            cnt_reg;
  logic [7:0]            beat_cnt;   // for TLAST when FRAME_LEN > 0
  logic                  tvalid_reg;
  logic                  tlast_reg;

  // ---------------------------------------------------------------------------
  // AXIS source logic
  // - When enabled, always try to present data (tvalid=1).
  // - Increment counter on each accepted beat (tvalid & tready).
  // - Optional frame counter for TLAST generation.
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_reg    <= '0;
      beat_cnt   <= '0;
      tvalid_reg <= 1'b0;
      tlast_reg  <= 1'b0;
    end else begin
      // Default TLAST deasserted unless we explicitly set it
      tlast_reg <= 1'b0;

      if (!enable) begin
        // When disabled, stop driving the stream
        tvalid_reg <= 1'b0;
        beat_cnt   <= beat_cnt; // don't care, but keep stable
      end else begin
        // Enabled: always try to send data
        tvalid_reg <= 1'b1;

        if (tvalid_reg && m_axis_tready) begin
          // Successful transfer: advance counter
          cnt_reg <= cnt_reg + 8'd1;

          // Frame/TLAST handling if FRAME_LEN is used
          if (FRAME_LEN > 0) begin
            if (beat_cnt == FRAME_LEN-1) begin
              beat_cnt  <= '0;
              tlast_reg <= 1'b1;    // TLAST on this beat
            end else begin
              beat_cnt <= beat_cnt + 8'd1;
            end
          end
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Output assignments
  // ---------------------------------------------------------------------------
  assign m_axis_tdata  = cnt_reg;
  assign m_axis_tvalid = tvalid_reg;
  assign m_axis_tlast  = (FRAME_LEN > 0) ? tlast_reg : 1'b0;

endmodule

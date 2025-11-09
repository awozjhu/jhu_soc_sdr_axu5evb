// preamble_correlator.sv

module PreambleCorrelator #(
  parameter int          PREAMBLE_LEN   = 64,
  // CHANGED: widen threshold to 128-bit and set a realistic default (~2e21).
  parameter logic [127:0] CORR_THRESHOLD = 128'd2000000000000000000000
) (
  input  logic         clk,
  input  logic         rst_n,

  // AXIS in
  input  logic         s_axis_tvalid,
  output logic         s_axis_tready,
  input  logic [31:0]  s_axis_tdata,  // {I[15:0], Q[15:0]} Q1.15
  input  logic         s_axis_tlast,

  // AXIS out
  output logic         m_axis_tvalid,
  input  logic         m_axis_tready,
  output logic [31:0]  m_axis_tdata,
  output logic         m_axis_tlast,

  // Frame start pulse
  output logic         frame_start
);

  typedef struct packed {
    logic signed [15:0] i;
    logic signed [15:0] q;
  } iq_t;

  iq_t preamble_rom [0:PREAMBLE_LEN-1];
  initial begin
    for (int i = 0; i < PREAMBLE_LEN; i++) begin
      case (i % 4)
        0: preamble_rom[i] = '{i: 16'sh5A82, q: 16'sh5A82};
        1: preamble_rom[i] = '{i: 16'sh5A82, q: 16'shA57E};
        2: preamble_rom[i] = '{i: 16'shA57E, q: 16'sh5A82};
        3: preamble_rom[i] = '{i: 16'shA57E, q: 16'shA57E};
      endcase
    end
  end

  // Shift register for incoming samples
  iq_t window [0:PREAMBLE_LEN-1];
  logic [$clog2(PREAMBLE_LEN+1):0] sample_count;
  logic window_valid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sample_count <= 0;
    end else if (s_axis_tvalid && s_axis_tready) begin
      if (sample_count < PREAMBLE_LEN)
        sample_count <= sample_count + 1;
    end
  end

  assign window_valid = (sample_count >= PREAMBLE_LEN);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < PREAMBLE_LEN; i++) begin
        window[i] <= '{i: 0, q: 0};
      end
    end else if (s_axis_tvalid && s_axis_tready) begin
      for (int i = PREAMBLE_LEN-1; i > 0; i--) begin
        window[i] <= window[i-1];
      end
      window[0].i <= s_axis_tdata[31:16];
      window[0].q <= s_axis_tdata[15:0];
    end
  end

  // Simple streaming FIFO passthrough
  assign s_axis_tready = m_axis_tready;
  assign m_axis_tvalid = s_axis_tvalid;
  assign m_axis_tdata  = s_axis_tdata;
  assign m_axis_tlast  = s_axis_tlast;

  // Correlation logic
  logic signed [63:0] corr_i, corr_q;
  logic        [127:0] mag_sq;       // 128-bit to avoid overflow

  always_comb begin
    corr_i = 0;
    corr_q = 0;
    for (int i = 0; i < PREAMBLE_LEN; i++) begin
      // time-reverse the template (matched filter)
      corr_i += window[i].i * preamble_rom[PREAMBLE_LEN-1-i].i
              + window[i].q * preamble_rom[PREAMBLE_LEN-1-i].q;
      corr_q += window[i].q * preamble_rom[PREAMBLE_LEN-1-i].i
              - window[i].i * preamble_rom[PREAMBLE_LEN-1-i].q;
    end
    mag_sq = ($unsigned(corr_i) * $unsigned(corr_i))
           + ($unsigned(corr_q) * $unsigned(corr_q));
  end

  // Detection + one-shot guard
  logic above_thresh, above_thresh_d;
  logic armed;

  assign above_thresh = window_valid &&
                        (mag_sq > CORR_THRESHOLD) &&
                        s_axis_tvalid && s_axis_tready;

  // edge detect of above_thresh
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) above_thresh_d <= 1'b0;
    else        above_thresh_d <= above_thresh;
  end
  wire rise = above_thresh & ~above_thresh_d;

  // NEW: arm once per frame; re-arm on TLAST
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      armed <= 1'b1;
    end else if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
      armed <= 1'b1;     // re-arm at end of frame
    end else if (rise) begin
      armed <= 1'b0;     // disarm after first detection
    end
  end

  // single-cycle pulse, once per frame
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) frame_start <= 1'b0;
    else        frame_start <= rise & armed;
  end

endmodule

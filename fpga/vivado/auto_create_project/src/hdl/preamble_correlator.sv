// preamble_correlator_pipelined.sv
module PreambleCorrelator #(
  parameter int           PREAMBLE_LEN    = 64,  // assumed power-of-two
  parameter logic [127:0] CORR_THRESHOLD  = 128'd2000000000000000000000
) (
  input  logic         clk,
  input  logic         rst_n,

  // AXIS in
  input  logic         s_axis_tvalid,
  output logic         s_axis_tready,
  input  logic [31:0]  s_axis_tdata,  // {I[15:0], Q[15:0]} Q1.15
  input  logic         s_axis_tlast,

  // AXIS out (unchanged latency vs original)
  output logic         m_axis_tvalid,
  input  logic         m_axis_tready,
  output logic [31:0]  m_axis_tdata,
  output logic         m_axis_tlast,

  // Frame start pulse (logically aligned to same sample, delayed by pipeline)
  output logic         frame_start
);

  // ---------------------------------------------------------------------------
  // IQ type and preamble ROM (as before)
  // ---------------------------------------------------------------------------
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

  // ---------------------------------------------------------------------------
  // Input sample window (shift register) – unchanged
  // ---------------------------------------------------------------------------
  iq_t window [0:PREAMBLE_LEN-1];
  logic [$clog2(PREAMBLE_LEN+1):0] sample_count;
  logic window_valid;

  wire sample_beat = s_axis_tvalid && s_axis_tready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sample_count <= '0;
    end else if (sample_beat) begin
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
    end else if (sample_beat) begin
      for (int i = PREAMBLE_LEN-1; i > 0; i--) begin
        window[i] <= window[i-1];
      end
      window[0].i <= s_axis_tdata[31:16];
      window[0].q <= s_axis_tdata[15:0];
    end
  end

  // ---------------------------------------------------------------------------
  // Simple streaming passthrough (unchanged)
  // ---------------------------------------------------------------------------
  assign s_axis_tready = m_axis_tready;
  assign m_axis_tvalid = s_axis_tvalid;
  assign m_axis_tdata  = s_axis_tdata;
  assign m_axis_tlast  = s_axis_tlast;

  // ---------------------------------------------------------------------------
  // Pipelined correlation
  //   - Stage 0: 64 parallel complex MACs -> lvl0_i/q
  //   - Stages 1..6: adder tree 64->1 (each level registered)
  //   - Stages 7..9: mag^2 pipeline (corr_i^2 + corr_q^2)
  //
  //   Total pipeline latency from valid window sample to mag_sq: 10 cycles.
  // ---------------------------------------------------------------------------

  localparam int L0 = PREAMBLE_LEN;       // 64
  localparam int L1 = (L0+1)/2;           // 32
  localparam int L2 = (L1+1)/2;           // 16
  localparam int L3 = (L2+1)/2;           // 8
  localparam int L4 = (L3+1)/2;           // 4
  localparam int L5 = (L4+1)/2;           // 2
  localparam int L6 = (L5+1)/2;           // 1

  // Per-tap partial sums
  logic signed [63:0] lvl0_i [0:L0-1];
  logic signed [63:0] lvl0_q [0:L0-1];

  // Adder levels
  logic signed [63:0] lvl1_i [0:L1-1];
  logic signed [63:0] lvl1_q [0:L1-1];

  logic signed [63:0] lvl2_i [0:L2-1];
  logic signed [63:0] lvl2_q [0:L2-1];

  logic signed [63:0] lvl3_i [0:L3-1];
  logic signed [63:0] lvl3_q [0:L3-1];

  logic signed [63:0] lvl4_i [0:L4-1];
  logic signed [63:0] lvl4_q [0:L4-1];

  logic signed [63:0] lvl5_i [0:L5-1];
  logic signed [63:0] lvl5_q [0:L5-1];

  logic signed [63:0] corr_i;   // final sum
  logic signed [63:0] corr_q;

  // Valid pipeline to track which outputs are meaningful
  localparam int CORR_PIPE_STAGES = 10;
  logic [CORR_PIPE_STAGES-1:0] corr_valid_pipe;

  // Stage 0: 64 complex MACs from window & preamble_rom
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < L0; i++) begin
        lvl0_i[i] <= '0;
        lvl0_q[i] <= '0;
      end
      corr_valid_pipe <= '0;
    end else begin
      // advance valid pipeline
      corr_valid_pipe[0] <= sample_beat && window_valid;
      for (int s = 1; s < CORR_PIPE_STAGES; s++) begin
        corr_valid_pipe[s] <= corr_valid_pipe[s-1];
      end

      if (sample_beat && window_valid) begin
        for (int i = 0; i < L0; i++) begin
          // time-reversed template: PREAMBLE_LEN-1-i
          iq_t w = window[i];
          iq_t p = preamble_rom[PREAMBLE_LEN-1-i];

          // real:  Iw*Ip + Qw*Qp
          // imag:  Qw*Ip - Iw*Qp
          lvl0_i[i] <= w.i * p.i + w.q * p.q;
          lvl0_q[i] <= w.q * p.i - w.i * p.q;
        end
      end
    end
  end

  // Helper function: pairwise add one level
  function automatic logic signed [63:0] add_or_passthrough(
      input logic signed [63:0] a,
      input logic signed [63:0] b,
      input logic               has_b
  );
    if (has_b) add_or_passthrough = a + b;
    else       add_or_passthrough = a;
  endfunction

  // Level 1: 64 -> 32
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < L1; i++) begin
        lvl1_i[i] <= '0;
        lvl1_q[i] <= '0;
      end
    end else if (corr_valid_pipe[0]) begin
      for (int i = 0; i < L1; i++) begin
        int idx0 = 2*i;
        int idx1 = 2*i + 1;
        lvl1_i[i] <= add_or_passthrough(lvl0_i[idx0], lvl0_i[idx1], (idx1 < L0));
        lvl1_q[i] <= add_or_passthrough(lvl0_q[idx0], lvl0_q[idx1], (idx1 < L0));
      end
    end
  end

  // Level 2: 32 -> 16
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < L2; i++) begin
        lvl2_i[i] <= '0;
        lvl2_q[i] <= '0;
      end
    end else if (corr_valid_pipe[1]) begin
      for (int i = 0; i < L2; i++) begin
        int idx0 = 2*i;
        int idx1 = 2*i + 1;
        lvl2_i[i] <= add_or_passthrough(lvl1_i[idx0], lvl1_i[idx1], (idx1 < L1));
        lvl2_q[i] <= add_or_passthrough(lvl1_q[idx0], lvl1_q[idx1], (idx1 < L1));
      end
    end
  end

  // Level 3: 16 -> 8
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < L3; i++) begin
        lvl3_i[i] <= '0;
        lvl3_q[i] <= '0;
      end
    end else if (corr_valid_pipe[2]) begin
      for (int i = 0; i < L3; i++) begin
        int idx0 = 2*i;
        int idx1 = 2*i + 1;
        lvl3_i[i] <= add_or_passthrough(lvl2_i[idx0], lvl2_i[idx1], (idx1 < L2));
        lvl3_q[i] <= add_or_passthrough(lvl2_q[idx0], lvl2_q[idx1], (idx1 < L2));
      end
    end
  end

  // Level 4: 8 -> 4
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < L4; i++) begin
        lvl4_i[i] <= '0;
        lvl4_q[i] <= '0;
      end
    end else if (corr_valid_pipe[3]) begin
      for (int i = 0; i < L4; i++) begin
        int idx0 = 2*i;
        int idx1 = 2*i + 1;
        lvl4_i[i] <= add_or_passthrough(lvl3_i[idx0], lvl3_i[idx1], (idx1 < L3));
        lvl4_q[i] <= add_or_passthrough(lvl3_q[idx0], lvl3_q[idx1], (idx1 < L3));
      end
    end
  end

  // Level 5: 4 -> 2
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < L5; i++) begin
        lvl5_i[i] <= '0;
        lvl5_q[i] <= '0;
      end
    end else if (corr_valid_pipe[4]) begin
      for (int i = 0; i < L5; i++) begin
        int idx0 = 2*i;
        int idx1 = 2*i + 1;
        lvl5_i[i] <= add_or_passthrough(lvl4_i[idx0], lvl4_i[idx1], (idx1 < L4));
        lvl5_q[i] <= add_or_passthrough(lvl4_q[idx0], lvl4_q[idx1], (idx1 < L4));
      end
    end
  end

  // Level 6: 2 -> 1 (final corr_i/corr_q)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      corr_i <= '0;
      corr_q <= '0;
    end else if (corr_valid_pipe[5]) begin
      corr_i <= add_or_passthrough(lvl5_i[0], lvl5_i[1], (L5 > 1));
      corr_q <= add_or_passthrough(lvl5_q[0], lvl5_q[1], (L5 > 1));
    end
  end

  // ---------------------------------------------------------------------------
  // Magnitude-squared pipeline (3 stages)
  // ---------------------------------------------------------------------------
  logic signed [63:0] corr_i_s, corr_q_s;
  logic [127:0]       mag_i, mag_q;
  logic [127:0]       mag_sq;

  // Stage 7: register corr_i/corr_q
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      corr_i_s <= '0;
      corr_q_s <= '0;
    end else if (corr_valid_pipe[6]) begin
      corr_i_s <= corr_i;
      corr_q_s <= corr_q;
    end
  end

  // Stage 8: squares
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mag_i <= '0;
      mag_q <= '0;
    end else if (corr_valid_pipe[7]) begin
      mag_i <= corr_i_s * corr_i_s;
      mag_q <= corr_q_s * corr_q_s;
    end
  end

  // Stage 9: sum of squares
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mag_sq <= '0;
    end else if (corr_valid_pipe[8]) begin
      mag_sq <= mag_i + mag_q;
    end
  end

  // ---------------------------------------------------------------------------
  // Detection + one-shot guard (same behavior as before,
  // but gated by corr_valid_pipe[9] instead of window_valid/sample_beat).
  // ---------------------------------------------------------------------------
  logic above_thresh, above_thresh_d;
  logic armed;

  assign above_thresh = corr_valid_pipe[9] && (mag_sq > CORR_THRESHOLD);

  // edge detect of above_thresh
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) above_thresh_d <= 1'b0;
    else        above_thresh_d <= above_thresh;
  end

  wire rise = above_thresh & ~above_thresh_d;

  // Arm once per frame; re-arm on TLAST (original behavior)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      armed <= 1'b1;
    end else if (sample_beat && s_axis_tlast) begin
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

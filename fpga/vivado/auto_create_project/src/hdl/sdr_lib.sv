/*------------------------------------------------------------------------------
 PRBS AXI-Stream Generator (CDR-aligned) — quick guide
 • Purpose: Generate a deterministic PRBS7/15/23/31 byte stream for link bring-up/BER.
 • Core: Single 31-bit LFSR; taps per MODE; SEED=0 coerced to 1 (avoid lock-up).
 • Packing: Byte-packed, little-endian inside the byte (first bit → tdata[0]).
            LFSR/packer stalls while (tvalid && !tready) → no skipped/dup bits.
 • Framing: FRAME_LEN_BYTES=0 → continuous (no TLAST).
            FRAME_LEN_BYTES=N → TLAST on every Nth *accepted* byte; counter reloads
            after TLAST handshake.
 • AXI-Lite:
     CTRL @0x00   : ENABLE, SW_RESET (one-shot), MODE[6:4], CLEAR (one-shot)
     STATUS @0x04 : R/W1C sticky RUNNING (set on first handshake),
                    sticky DONE (set on TLAST handshake)
     SEED @0x08   : 31-bit seed (0→1)
     FRMLEN @0x0C : frame length in bytes (0 = continuous)
     BYTE/ BIT @0x18/0x1C : increment only on (tvalid && tready)
 • Reset/Clear: SW_RESET re-seeds & restarts framing; CLEAR zeros counters.
   Both safe while enabled and deterministic.
------------------------------------------------------------------------------*/

// prbs_axi_stream.sv (CDR-aligned)
// BASE offsets: 0x00 CTRL, 0x04 STATUS (R/W1C), 0x08 SEED, 0x0C FRAME_LEN_BYTES,
//               0x18 BYTE_COUNT (RO), 0x1C BIT_COUNT (RO)
// MODE (CTRL[6:4]): 0=PRBS7,1=PRBS15,2=PRBS23,3=PRBS31
// AXIS: always BYTE-PACKED (tdata[7:0]), little-endian inside byte.
// TLAST asserted on FRAME_LEN_BYTES-1 (handshaken). If FRAME_LEN_BYTES==0 => continuous, no TLAST.

`timescale 1ns/1ps
module prbs_axi_stream #(
  parameter int AXIL_ADDR_WIDTH = 6, // 64B aperture is enough for 0x1C
  parameter int AXIL_DATA_WIDTH = 32
)(
  input  wire                        clk,
  input  wire                        rst_n,

  // AXI4-Lite
  input  wire [AXIL_ADDR_WIDTH-1:0]  s_axil_awaddr,
  input  wire                        s_axil_awvalid,
  output logic                       s_axil_awready,
  input  wire [AXIL_DATA_WIDTH-1:0]  s_axil_wdata,
  input  wire [AXIL_DATA_WIDTH/8-1:0]s_axil_wstrb,
  input  wire                        s_axil_wvalid,
  output logic                       s_axil_wready,
  output logic [1:0]                 s_axil_bresp,
  output logic                       s_axil_bvalid,
  input  wire                        s_axil_bready,
  input  wire [AXIL_ADDR_WIDTH-1:0]  s_axil_araddr,
  input  wire                        s_axil_arvalid,
  output logic                       s_axil_arready,
  output logic [AXIL_DATA_WIDTH-1:0] s_axil_rdata,
  output logic [1:0]                 s_axil_rresp,
  output logic                       s_axil_rvalid,
  input  wire                        s_axil_rready,

  // AXI-Stream master
  output logic [7:0]                 m_axis_tdata,
  output logic                       m_axis_tvalid,
  input  wire                        m_axis_tready,
  output logic                       m_axis_tlast
);

  // -----------------------------
  // Register map (CDR)
  // -----------------------------
  localparam CTRL_ADDR       = 6'h00;
  localparam STATUS_ADDR     = 6'h04;
  localparam SEED_ADDR       = 6'h08;
  localparam FRMLEN_ADDR     = 6'h0C;
  localparam BYTECOUNT_ADDR  = 6'h18;
  localparam BITCOUNT_ADDR   = 6'h1C;

  // CTRL fields
  logic        ctrl_enable;
  logic [2:0]  ctrl_mode;           // [6:4]
  logic        sw_reset_pulse;      // one-shot derived from CTRL write
  logic        clear_pulse;         // one-shot derived from CTRL write

  // Config
  logic [30:0] csr_seed;            // 31-bit used; coerced non-zero
  logic [15:0] csr_frame_len_bytes; // 0 => continuous (no TLAST)

  // STATUS (sticky, R/W1C)
  logic st_running;      // [0]
  logic st_diag_ovun;    // [2] (diag; stays 0 in this impl unless extended)
  logic st_done;         // [8] frame complete (TLAST handshaken)

  // Results
  logic [31:0] byte_count;          // accepted bytes
  logic [31:0] bit_count;           // accepted bits (= bytes*8)

  // AXI-Lite plumbing
  logic aw_hs, w_hs, ar_hs;
  assign aw_hs = s_axil_awvalid & s_axil_awready;
  assign w_hs  = s_axil_wvalid  & s_axil_wready;
  assign ar_hs = s_axil_arvalid & s_axil_arready;

  // Accept write when both address & data are valid
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) s_axil_awready <= 1'b0;
    else        s_axil_awready <= (~s_axil_awready) & s_axil_awvalid & s_axil_wvalid;
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) s_axil_wready <= 1'b0;
    else        s_axil_wready <= (~s_axil_wready) & s_axil_awvalid & s_axil_wvalid;
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axil_bvalid <= 1'b0; s_axil_bresp <= 2'b00;
    end else begin
      if (aw_hs & w_hs) begin
        s_axil_bvalid <= 1'b1; s_axil_bresp <= 2'b00;
      end else if (s_axil_bvalid & s_axil_bready) begin
        s_axil_bvalid <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) s_axil_arready <= 1'b0;
    else        s_axil_arready <= (~s_axil_arready) & s_axil_arvalid;
  end

  // Optional: read upper bits once to quiet "bits not read" lint on wdata/wstrb
  wire _lint_axil_unused_reads = &{1'b0, s_axil_wdata[31:16], s_axil_wstrb[3:2]};

  // pipeline regs
  logic fire_evt_q, last_fire_evt_q;

  // -----------------------------
  // CSRs (single writer for sticky bits; counters handled elsewhere)
  // -----------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_enable          <= 1'b0;
      ctrl_mode            <= 3'd3;          // PRBS31 default
      sw_reset_pulse       <= 1'b0;
      clear_pulse          <= 1'b0;

      csr_seed             <= 31'd1;         // non-zero default
      csr_frame_len_bytes  <= 16'd0;         // continuous by default

      st_running           <= 1'b0;
      st_diag_ovun         <= 1'b0;
      st_done              <= 1'b0;
    end else begin
      // one-shots clear by default
      sw_reset_pulse <= 1'b0;
      clear_pulse    <= 1'b0;

      // WRITE decode
      if (aw_hs & w_hs) begin
        unique case (s_axil_awaddr[5:0])
          CTRL_ADDR: begin
            if (s_axil_wstrb[0]) begin
              ctrl_enable <= s_axil_wdata[0];
              if (s_axil_wdata[2]) sw_reset_pulse <= 1'b1;          // SW_RESET one-shot
              ctrl_mode   <= s_axil_wdata[6:4];
              if (s_axil_wdata[15]) clear_pulse <= 1'b1;            // CLEAR one-shot
            end
          end
          SEED_ADDR: begin
            csr_seed <= s_axil_wdata[30:0];                          // zero coerced later
          end
          FRMLEN_ADDR: begin
            if (s_axil_wstrb[1] | s_axil_wstrb[0]) csr_frame_len_bytes <= s_axil_wdata[15:0];
          end
          STATUS_ADDR: begin
            // R/W1C: writing '1' clears the sticky bit(s)
            if (s_axil_wstrb[0]) begin
              if (s_axil_wdata[0]) st_running  <= 1'b0;
              if (s_axil_wdata[2]) st_diag_ovun<= 1'b0;
              if (s_axil_wdata[8]) st_done     <= 1'b0;
            end
          end
          default: ;
        endcase
      end

      // --- sticky set logic comes ONLY from event pulses ---
      if (sw_reset_pulse) begin
        st_running <= 1'b0;
        st_done    <= 1'b0;
      end else begin
        if (fire_evt_q)      st_running <= 1'b1;   // set on first accepted transfer
        if (last_fire_evt_q) st_done    <= 1'b1;   // set when TLAST handshakes
      end
    end
  end

  // READ mux
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axil_rvalid <= 1'b0; s_axil_rresp <= 2'b00; s_axil_rdata <= '0;
    end else begin
      if (ar_hs) begin
        s_axil_rvalid <= 1'b1; s_axil_rresp <= 2'b00;
        unique case (s_axil_araddr[5:0])
          CTRL_ADDR      : s_axil_rdata <= {16'd0, 8'd0, ctrl_mode, 1'b0/*bit3*/, ctrl_enable};
          STATUS_ADDR    : s_axil_rdata <= {23'd0, st_done, 7'd0, st_diag_ovun, 1'b0/*bit1*/, st_running};
          SEED_ADDR      : s_axil_rdata <= {1'b0, csr_seed};
          FRMLEN_ADDR    : s_axil_rdata <= {16'd0, csr_frame_len_bytes};
          BYTECOUNT_ADDR : s_axil_rdata <= byte_count;
          BITCOUNT_ADDR  : s_axil_rdata <= bit_count;
          default        : s_axil_rdata <= 32'hDEADBEEF;
        endcase
      end else if (s_axil_rvalid & s_axil_rready) begin
        s_axil_rvalid <= 1'b0;
      end
    end
  end

  // -----------------------------
  // PRBS core (always byte-packed)
  // -----------------------------
  // tap selection (5-bit indices are sufficient: 0..30)
  logic [4:0] tap_a, tap_b;
  always_comb begin
    unique case (ctrl_mode)
      3'd0: begin tap_a=5;  tap_b=4;  end // PRBS7:  (6,5)
      3'd1: begin tap_a=13; tap_b=12; end // PRBS15: (14,13)
      3'd2: begin tap_a=21; tap_b=16; end // PRBS23: (22,17)
      default: begin tap_a=29; tap_b=26; end // PRBS31: (30,27)
    endcase
  end

  // LFSR & packer
  logic [30:0] lfsr_q;
  wire         feedback_bit = lfsr_q[tap_a] ^ lfsr_q[tap_b];
  wire [30:0]  seed_fixed   = (csr_seed == 31'd0) ? 31'd1 : csr_seed;

  logic [2:0]  bit_cnt;
  logic [7:0]  byte_shift;

  // frame counter: counts "bytes remaining in this frame"
  logic [15:0] frame_cnt_q;
  wire         use_frames = (csr_frame_len_bytes != 16'd0);

  // Output registers for current byte
  logic        vld_q;
  logic [7:0]  data_q;
  logic        last_q;   // TLAST for *this* byte, held stable while stalled

  // Handshake
  wire fire = vld_q & m_axis_tready;
  // Event wires for CSR sticky updates and counters
  wire fire_evt      = fire;
  wire last_fire_evt = fire & use_frames & last_q;

  // ADD: register the events by one cycle
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fire_evt_q      <= 1'b0;
      last_fire_evt_q <= 1'b0;
    end else begin
      fire_evt_q      <= fire_evt;
      last_fire_evt_q <= last_fire_evt;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lfsr_q      <= 31'd1;
      bit_cnt     <= 3'd0;
      byte_shift  <= 8'd0;

      vld_q       <= 1'b0;
      data_q      <= 8'd0;
      last_q      <= 1'b0;

      frame_cnt_q <= 16'd0;          // 0 means "not in a frame yet" when use_frames=1
    end else begin
      if (sw_reset_pulse) begin
        // Reset datapath to a clean start of frame
        lfsr_q      <= seed_fixed;
        bit_cnt     <= 3'd0;
        byte_shift  <= 8'd0;
        vld_q       <= 1'b0;
        last_q      <= 1'b0;
        frame_cnt_q <= csr_frame_len_bytes;   // start with N bytes remaining (or 0 if continuous)
      end else if (ctrl_enable) begin
        // Build the next byte only when we're not holding one for output.
        if (!vld_q) begin
          // Shift one PRBS bit per cycle into the next bit position (little-endian in byte)
          byte_shift[bit_cnt] <= lfsr_q[0];
          lfsr_q              <= {lfsr_q[29:0], feedback_bit};
          bit_cnt             <= bit_cnt + 3'd1;

          if (bit_cnt == 3'd7) begin
            // A full byte is ready — present it and compute TLAST for THIS byte now.
            data_q <= {lfsr_q[0], byte_shift[6:0]};
            vld_q  <= 1'b1;

            if (use_frames) begin
              // Effective remaining count for this byte:
              //   - if 0, frames were just enabled; treat as starting a new frame length N.
              //   - last if remaining==1.
              if (frame_cnt_q == 16'd0)
                last_q <= (csr_frame_len_bytes == 16'd1);
              else
                last_q <= (frame_cnt_q == 16'd1);
            end else begin
              last_q <= 1'b0;
            end
          end
        end

        // When the consumer takes the byte, update frame state.
        if (fire) begin
          if (use_frames) begin
            if (last_q) begin
              // Finished a frame on this handshake; reload to N for the next frame
              frame_cnt_q <= csr_frame_len_bytes;
            end else begin
              // Mid-frame byte consumed
              if (frame_cnt_q == 16'd0)
                // Frames just became enabled: this consumed byte is byte #1 -> remaining = N-1
                frame_cnt_q <= (csr_frame_len_bytes > 16'd0) ? (csr_frame_len_bytes - 16'd1) : 16'd0;
              else
                frame_cnt_q <= frame_cnt_q - 16'd1;
            end
          end

          vld_q <= 1'b0;  // allow building the next byte
        end
      end else begin
        vld_q <= 1'b0;
      end
    end
  end

  // Dedicated counter block (single writer; clears beat increments)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      byte_count <= 32'd0;
      bit_count  <= 32'd0;
    end else if (sw_reset_pulse | clear_pulse) begin
      byte_count <= 32'd0;
      bit_count  <= 32'd0;
    end else if (fire_evt) begin
      byte_count <= byte_count + 32'd1;
      bit_count  <= bit_count  + 32'd8;
    end
  end

  // AXIS outputs
  assign m_axis_tdata  = data_q;
  assign m_axis_tvalid = vld_q;
  assign m_axis_tlast  = use_frames ? last_q : 1'b0;

endmodule

// mapper.sv (self-contained)
// BPSK/QPSK symbol mapper with AXI4-Lite control and internal vld/rdy/last.
// - Bits in (8b, LSB-first within each byte) --> {I,Q} out in Q1.15.
// - QPSK Gray: 00:(+,+), 01:(-,+), 11:(-,-), 10:(+,-).
// - BYPASS forces BPSK (I-only) regardless of MODE.
//
// CSRs (word-aligned, base offset local to this block):
//   0x00 CTRL  : [0]=ENABLE, [1]=BYPASS, [2]=SW_RESET(one-shot),
//                [6:4]=MODE (0=BPSK, 1=QPSK), [8]=AMC_OVERRIDE (1=use local MODE)
//   0x04 STATUS: [0]=RUNNING (R/W1C), [2]=OVERFLOW (R/W1C)
//
// Notes:
// - AXI-Lite is assumed in the same clk domain (clk_bb). If not, add CDC.
// - Internal stream is AXIS-like: valid/ready/last only.

/*------------------------------------------------------------------------------
-  Symbol Mapper (mapper.sv)
-  ------------------------------------------------------------------------------
-  Purpose
-    Convert a byte-wide bitstream (AXIS-like, LSB-first per byte) into
-    complex baseband symbols in Q1.15 fixed-point. Supports BPSK and
-    Gray-coded QPSK. Optional BYPASS forces BPSK (I-only).
-
-  Interfaces
-    clk_bb, rst_n                       : datapath clock/reset
-    in_*  (valid,ready,data[7:0],last)  : input bits, 8 per beat, LSB-first
-    out_* (valid,ready,data[31:0],last) : output symbols; out_data = {I[15:0],Q[15:0]}
-    amc_mode_i[2:0], amc_mode_valid_i   : optional external mode (only bit[0] used)
-    AXI4-Lite slave                      : CTRL/STATUS registers (same clock domain)
-
-  Register Map (word-aligned)
-    0x00 CTRL
-         [0]  ENABLE          : 1=enable datapath
-         [1]  BYPASS          : 1=force BPSK (I-only) regardless of MODE
-         [2]  SW_RESET        : one-shot; clears internal buffers/holds
-         [6:4]MODE            : 0=BPSK, 1=QPSK (others reserved)
-         [8]  AMC_OVERRIDE    : 1=use local MODE; 0=use amc_mode_i when valid
-    0x04 STATUS (R/W1C bits)
-         [0]  RUNNING         : set after first symbol handshake on out_*
-         [2]  OVERFLOW        : set if upstream asserted in_valid when !in_ready
-
-  Operation
-    • Byte intake / bit buffer:
-        - Accepts a new input byte only when the internal bit buffer is empty and
-          the output hold register is free. This keeps frame TLAST aligned to byte
-          boundaries.
-        - Bits are consumed LSB-first from the buffer.
-
-    • Symbol formation:
-        - K = 1 (BPSK) or 2 (QPSK) bits per symbol.
-        - For BPSK: use b0 = current LSB; map I = ±AMP_BPSK, Q = 0.
-        - For QPSK (Gray):
-              Bit pair per symbol is [b0,b1] taken LSB-first from the buffer.
-              Q sign ← b0 (0 ⇒ +, 1 ⇒ −)
-              I sign ← b1 (0 ⇒ +, 1 ⇒ −)
-              Mapping: 00:(+,+), 01:(−,+), 11:(−,−), 10:(+,-)
-          Output amplitudes: AMP_BPSK=±32767, AMP_QPSK=±23170 (≈±1/√2 in Q1.15).
-
-    • TLAST propagation:
-        - in_last is latched with the current byte. out_last is asserted on the
-          symbol that consumes the final remaining bits of that byte (i.e., when
-          the buffer becomes empty after that symbol). This marks the end of the
-          frame at a symbol boundary.
-
-    • Handshakes:
-        - in_ready  = ENABLE & (bit buffer empty) & (output hold not valid).
-        - out_valid pulses when a symbol is ready; data transfers on out_valid &
-          out_ready.
-        - OVERFLOW sets if in_valid asserted when in_ready=0.
-
-    • Mode selection:
-        - If AMC_OVERRIDE=1, use CTRL.MODE; else, when amc_mode_valid_i=1, use
-          amc_mode_i[0] (0=BPSK, 1=QPSK).
-
-    • Reset / status:
-        - SW_RESET (CTRL[2]) is a one-shot that clears internal state.
-        - RUNNING sets after the first successful output transfer.
-        - STATUS bits are R/W1C.
-
-  Notes
-    - Q1.15 outputs are packed as {I[15:0], Q[15:0]} on out_data.
-    - Design assumes AXI-Lite and datapath share clk_bb; add CDC if not.
-------------------------------------------------------------------------------*/




`timescale 1ns/1ps

module mapper #(
  // Q1.15 amplitudes
  parameter logic signed [15:0] AMP_BPSK = 16'sd32767, // ±1.0
  parameter logic signed [15:0] AMP_QPSK = 16'sd23170  // ±1/sqrt(2)
)(
  input  logic clk_bb,
  input  logic rst_n,

  // -------- internal "AXIS-like" bitstream in (8-bit) --------
  input  logic        in_valid,
  output logic        in_ready,
  input  logic [7:0]  in_data,
  input  logic        in_last,

  // -------- internal "AXIS-like" symbols out: {I[15:0],Q[15:0]} --------
  output logic        out_valid,
  input  logic        out_ready,
  output logic [31:0] out_data,   // {I[15:0], Q[15:0]}
  output logic        out_last,

  // Optional AMC-selected mode (only bit[0] used today: 0=BPSK, 1=QPSK)
  input  logic [2:0]  amc_mode_i,
  input  logic        amc_mode_valid_i,

  // ------------------------- AXI4-Lite (CSR) ------------------------------
  input  logic        s_axi_aclk,
  input  logic        s_axi_aresetn,
  // write address
  input  logic [7:0]  s_axi_awaddr,
  input  logic        s_axi_awvalid,
  output logic        s_axi_awready,
  // write data
  input  logic [31:0] s_axi_wdata,
  input  logic [3:0]  s_axi_wstrb,
  input  logic        s_axi_wvalid,
  output logic        s_axi_wready,
  // write resp
  output logic [1:0]  s_axi_bresp,
  output logic        s_axi_bvalid,
  input  logic        s_axi_bready,
  // read address
  input  logic [7:0]  s_axi_araddr,
  input  logic        s_axi_arvalid,
  output logic        s_axi_arready,
  // read data
  output logic [31:0] s_axi_rdata,
  output logic [1:0]  s_axi_rresp,
  output logic        s_axi_rvalid,
  input  logic        s_axi_rready
);

  // =========================================================================
  // Local types/params
  // =========================================================================
  typedef logic signed [15:0] iq_comp_t;
  localparam int IQ_W      = 16;
  localparam int SYM_AXI_W = 32;

  // =========================================================================
  // CSRs
  // =========================================================================
  // CTRL
  logic        ctrl_enable;
  logic        ctrl_bypass;
  logic        ctrl_sw_reset;    // one-shot
  logic [2:0]  ctrl_mode;        // 0=BPSK, 1=QPSK
  logic        ctrl_amc_override;

  // STATUS sticky bits
  logic        st_running;       // set once first symbol emitted; R/W1C
  logic        st_overflow;      // set if upstream overdrives when not ready; R/W1C

  // AXI-Lite simple/robust always-ready slave
  logic [7:0]  awaddr_hold;
  logic        have_write;       // AW and W seen in this beat
  logic        do_write;
  logic [7:0]  araddr_hold;
  logic        do_read;

  // Write path
  always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
      s_axi_awready   <= 1'b1;
      s_axi_wready    <= 1'b1;
      s_axi_bvalid    <= 1'b0;
      s_axi_bresp     <= 2'b00;
      awaddr_hold     <= 8'h00;
      have_write      <= 1'b0;

      s_axi_arready   <= 1'b1;
      s_axi_rvalid    <= 1'b0;
      s_axi_rresp     <= 2'b00;
      s_axi_rdata     <= 32'h0;
      araddr_hold     <= 8'h00;

      // CTRL defaults
      ctrl_enable       <= 1'b0;
      ctrl_bypass       <= 1'b0;
      ctrl_sw_reset     <= 1'b0;
      ctrl_mode         <= 3'd1;   // default QPSK
      ctrl_amc_override <= 1'b1;   // default: use local MODE

      st_running        <= 1'b0;
      st_overflow       <= 1'b0;
    end else begin
      // -------- write address/data capture (always-ready) ----------
      if (s_axi_awvalid) awaddr_hold <= s_axi_awaddr;
      have_write <= s_axi_awvalid & s_axi_wvalid & ~s_axi_bvalid;
      do_write   <= have_write;  // 1-cycle pulse

      if (do_write) begin
        unique case (awaddr_hold[7:2]) // word aligned
          6'h00: begin // CTRL
            if (s_axi_wstrb[0]) begin
              ctrl_enable       <= s_axi_wdata[0];
              ctrl_bypass       <= s_axi_wdata[1];
              ctrl_sw_reset     <= s_axi_wdata[2];  // one-shot below
              ctrl_mode         <= s_axi_wdata[6:4];
              ctrl_amc_override <= s_axi_wdata[8];
            end
          end
          6'h01: begin // STATUS R/W1C
            if (s_axi_wstrb[0]) begin
              if (s_axi_wdata[0]) st_running  <= 1'b0;
              if (s_axi_wdata[2]) st_overflow <= 1'b0;
            end
          end
          default: ;
        endcase
        s_axi_bvalid <= 1'b1;
        s_axi_bresp  <= 2'b00;
      end else if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end

      // -------- read address / data ----------
      do_read <= s_axi_arvalid & ~s_axi_rvalid;
      if (do_read) begin
        araddr_hold <= s_axi_araddr;
        unique case (s_axi_araddr[7:2])
          6'h00: s_axi_rdata <= {23'd0, ctrl_amc_override, 1'b0, ctrl_mode, ctrl_sw_reset, ctrl_bypass, ctrl_enable};
          6'h01: s_axi_rdata <= {29'd0, st_overflow, 1'b0, st_running};
          default: s_axi_rdata <= 32'h0000_0000;
        endcase
        s_axi_rresp  <= 2'b00;
        s_axi_rvalid <= 1'b1;
      end else if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
      end

      // -------- self-clear SW_RESET ----------
      if (ctrl_sw_reset) ctrl_sw_reset <= 1'b0;
    end
  end

  // =========================================================================
  // Datapath
  // =========================================================================
  // Effective mode: AMC override == 1 -> use ctrl_mode; else use amc_mode_i (if valid)
  logic eff_qpsk;  // 0=BPSK, 1=QPSK
  logic [2:0] mode_sel;

  always_comb begin
    if (ctrl_amc_override)       mode_sel = ctrl_mode;
    else if (amc_mode_valid_i)   mode_sel = amc_mode_i;
    else                         mode_sel = ctrl_mode;
    eff_qpsk = mode_sel[0];
  end

  // Bit buffer (we refill only when empty to keep TLAST at byte boundaries)
  logic [7:0] bit_buf;
  logic [3:0] bits_avail;     // 0..8
  logic       last_pending;   // TLAST associated with current bit_buf

  // Hold register for one symbol beat
  iq_comp_t   hold_I, hold_Q;
  logic       hold_last, hold_valid;
  logic [1:0] hold_bits_used;

  // Combinational helper: how many bits needed this symbol?
  logic need2;
  logic [1:0] K;
  always_comb begin
    need2 = (ctrl_bypass) ? 1'b0 : eff_qpsk;
    K     = need2 ? 2'd2 : 2'd1;
  end

  // Ready to accept a new byte when buffer empty and output hold free
  assign in_ready  = ctrl_enable & (bits_avail == 4'd0) & (~hold_valid);

  // Output signals
  assign out_valid = hold_valid;
  assign out_data  = {hold_I, hold_Q};  // {I[15:0], Q[15:0]}
  assign out_last  = hold_last;

  // Mapping function
  function automatic void map_bits_to_iq (
      input  logic bypass, input logic qpsk,
      input  logic b0, input logic b1,
      output iq_comp_t i, output iq_comp_t q
  );
    if (bypass || !qpsk) begin
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

  // Datapath / handshakes
  always_ff @(posedge clk_bb or negedge rst_n) begin
    if (!rst_n) begin
      bit_buf        <= '0;
      bits_avail     <= 4'd0;
      last_pending   <= 1'b0;

      hold_I         <= '0;
      hold_Q         <= '0;
      hold_last      <= 1'b0;
      hold_valid     <= 1'b0;
      hold_bits_used <= 2'd0;

      st_running     <= 1'b0;
      st_overflow    <= 1'b0;
    end else begin
      // Local soft reset
      if (ctrl_sw_reset) begin
        bit_buf        <= '0;
        bits_avail     <= 4'd0;
        last_pending   <= 1'b0;
        hold_valid     <= 1'b0;
      end

      // Accept an input byte
      if (in_valid && in_ready) begin
        bit_buf      <= in_data;   // LSB-first usage
        bits_avail   <= 4'd8;
        last_pending <= in_last;
      end else if (in_valid && !in_ready) begin
        st_overflow  <= 1'b1;      // upstream violated ready
      end

      // Generate a symbol when possible
      if (!hold_valid && ctrl_enable && (bits_avail >= K)) begin
        iq_comp_t i_tmp, q_tmp;
        logic b0, b1;
        b0 = bit_buf[0];
        b1 = need2 ? bit_buf[1] : 1'b0;

        // $display("[MAPPER] using (b0,b1)=%0d,%0d  bits_avail=%0d  t=%0t", b0, b1, bits_avail, $time);
        map_bits_to_iq(ctrl_bypass, eff_qpsk, b0, b1, i_tmp, q_tmp);

        hold_I         <= i_tmp;
        hold_Q         <= q_tmp;
        hold_bits_used <= K;
        hold_last      <= (last_pending && (bits_avail == K));
        hold_valid     <= 1'b1;
      end

      // Downstream handshake
      if (hold_valid && out_ready) begin
        hold_valid  <= 1'b0;
        // consume bits
        bit_buf     <= bit_buf >> hold_bits_used;
        bits_avail  <= bits_avail - hold_bits_used;
        if (hold_last) last_pending <= 1'b0;
        st_running  <= 1'b1;
      end
    end
  end

  // Synthesis-time sanity
  // synopsys translate_off
  initial begin
    assert(AMP_BPSK == 16'sd32767) else $error("AMP_BPSK must be 32767 (Q1.15)");
    assert(AMP_QPSK == 16'sd23170) else $error("AMP_QPSK should be ~23170 (Q1.15)");
  end
  // synopsys translate_on

endmodule


// -----------------------------------------------------------------------------
// diff_encoder.sv (self-contained)
// Differential encoder for DBPSK/DQPSK.
// - AXIS In : phase-increment phasors {I,Q} in Q1.15 (e.g., 0°, ±90°, 180°)
// - AXIS Out: previous_symbol × increment (complex multiply), Q1.15
// - Reset state: prev = (32767, 0). TLAST propagated.
// - AXI-Lite: CTRL [0]=ENABLE, [2]=SW_RESET (prev←(1,0)), [6:4]=MODE (0=DBPSK,1=DQPSK)
//              STATUS [0]=RUNNING
// Notes:
// * No local declarations inside procedural blocks. No SV functions.
// * Fast-path for 0/±90/180° increments to avoid amplitude creep.
// * Generic fixed-point multiply (round + sat) used if inputs are non-axial.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module diff_encoder #(
  parameter logic signed [15:0] ONE_Q15 = 16'sd32767   // +1.0 in Q1.15
)(
  input  logic clk_bb,
  input  logic rst_n,

  // -------- AXIS-like symbols in: {I[15:0],Q[15:0]} (phase increments) ------
  input  logic        in_valid,
  output logic        in_ready,
  input  logic [31:0] in_data,     // {I[15:0], Q[15:0]} signed Q1.15 phasor
  input  logic        in_last,

  // -------- AXIS-like symbols out: {I[15:0],Q[15:0]} ------------------------
  output logic        out_valid,
  input  logic        out_ready,
  output logic [31:0] out_data,    // {I[15:0], Q[15:0]} signed Q1.15
  output logic        out_last,

  // ------------------------- AXI4-Lite (CSR) --------------------------------
  input  logic        s_axi_aclk,
  input  logic        s_axi_aresetn,
  // write address
  input  logic [7:0]  s_axi_awaddr,
  input  logic        s_axi_awvalid,
  output logic        s_axi_awready,
  // write data
  input  logic [31:0] s_axi_wdata,
  input  logic [3:0]  s_axi_wstrb,
  input  logic        s_axi_wvalid,
  output logic        s_axi_wready,
  // write resp
  output logic [1:0]  s_axi_bresp,
  output logic        s_axi_bvalid,
  input  logic        s_axi_bready,
  // read address
  input  logic [7:0]  s_axi_araddr,
  input  logic        s_axi_arvalid,
  output logic        s_axi_arready,
  // read data
  output logic [31:0] s_axi_rdata,
  output logic [1:0]  s_axi_rresp,
  output logic        s_axi_rvalid,
  input  logic        s_axi_rready
);

  // ===========================================================================
  // Types / params
  // ===========================================================================
  typedef logic signed [15:0] iq16_t;
  typedef logic signed [31:0] i32_t;
  typedef logic signed [32:0] i33_t;

  localparam i33_t ROUND_CONST = 33'sd16384;  // 2^14 for Q1.15 rounding

  // ===========================================================================
  // CSRs (AXI-Lite always-ready style, like mapper/slicer)
  // ===========================================================================
  logic        ctrl_enable;
  logic        ctrl_sw_reset;       // one-shot
  logic [2:0]  ctrl_mode;           // 0=DBPSK, 1=DQPSK

  logic        st_running;          // R/W1C

  logic [7:0]  awaddr_hold;
  logic        have_write;
  logic        do_write;
  logic [7:0]  araddr_hold;
  logic        do_read;

  always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
      s_axi_awready   <= 1'b1;
      s_axi_wready    <= 1'b1;
      s_axi_bvalid    <= 1'b0;
      s_axi_bresp     <= 2'b00;
      awaddr_hold     <= 8'h00;
      have_write      <= 1'b0;

      s_axi_arready   <= 1'b1;
      s_axi_rvalid    <= 1'b0;
      s_axi_rresp     <= 2'b00;
      s_axi_rdata     <= 32'h0;
      araddr_hold     <= 8'h00;

      ctrl_enable     <= 1'b0;
      ctrl_sw_reset   <= 1'b0;
      ctrl_mode       <= 3'd1;   // default DQPSK

      st_running      <= 1'b0;
    end else begin
      if (s_axi_awvalid) awaddr_hold <= s_axi_awaddr;
      have_write <= s_axi_awvalid & s_axi_wvalid & ~s_axi_bvalid;
      do_write   <= have_write;

      if (do_write) begin
        unique case (awaddr_hold[7:2]) // word aligned
          6'h00: begin // CTRL
            if (s_axi_wstrb[0]) begin
              ctrl_enable   <= s_axi_wdata[0];
              ctrl_sw_reset <= s_axi_wdata[2];  // self-clears below
              ctrl_mode     <= s_axi_wdata[6:4];
            end
          end
          6'h01: begin // STATUS R/W1C
            if (s_axi_wstrb[0]) begin
              if (s_axi_wdata[0]) st_running <= 1'b0;
            end
          end
          default: ;
        endcase
        s_axi_bvalid <= 1'b1;
        s_axi_bresp  <= 2'b00;
      end else if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end

      do_read <= s_axi_arvalid & ~s_axi_rvalid;
      if (do_read) begin
        araddr_hold <= s_axi_araddr;
        unique case (s_axi_araddr[7:2])
          6'h00: s_axi_rdata <= {25'd0, ctrl_mode, 1'b0, ctrl_sw_reset, 1'b0, ctrl_enable};
          6'h01: s_axi_rdata <= {31'd0, st_running};
          default: s_axi_rdata <= 32'h0000_0000;
        endcase
        s_axi_rresp  <= 2'b00;
        s_axi_rvalid <= 1'b1;
      end else if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
      end

      if (ctrl_sw_reset) ctrl_sw_reset <= 1'b0; // one-shot
    end
  end

  // ===========================================================================
  // Datapath
  // ===========================================================================
  // Mode
  logic eff_dqpsk;
  always_comb begin
    eff_dqpsk = ctrl_mode[0];
  end

  // State: previous output symbol (Q1.15)
  iq16_t prev_I;
  iq16_t prev_Q;

  // Input unpack (phasor), and DBPSK coercion
  iq16_t in_I_raw;
  iq16_t in_Q_raw;
  iq16_t inc_I;     // effective increment used
  iq16_t inc_Q;

  assign in_I_raw = in_data[31:16];
  assign in_Q_raw = in_data[15:0];

  always_comb begin
    if (eff_dqpsk) begin
      inc_I = in_I_raw;
      inc_Q = in_Q_raw;
    end else begin
      // DBPSK: restrict to ±1 on real axis based on sign of I
      inc_I = in_I_raw[15] ? -ONE_Q15 : ONE_Q15;
      inc_Q = 16'sd0;
    end
  end

  // Fast-path classification for ideal axial phasors
  logic inc_is_p1, inc_is_m1, inc_is_pj, inc_is_mj;
  always_comb begin
    inc_is_p1 = (inc_I ==  ONE_Q15) && (inc_Q == 16'sd0);
    inc_is_m1 = (inc_I == -ONE_Q15) && (inc_Q == 16'sd0);
    inc_is_pj = (inc_I == 16'sd0)    && (inc_Q ==  ONE_Q15);
    inc_is_mj = (inc_I == 16'sd0)    && (inc_Q == -ONE_Q15);
  end

  // Generic complex multiply (prev × inc), fixed-point round & saturate
  // Intermediates (declared at module scope)
  i32_t p_re_re;
  i32_t p_im_im;
  i32_t p_re_im;
  i32_t p_im_re;
  i33_t acc_re;
  i33_t acc_im;
  i33_t acc_re_rnd;
  i33_t acc_im_rnd;
  logic signed [16:0] out_re_17;
  logic signed [16:0] out_im_17;
  iq16_t calc_out_I_generic;
  iq16_t calc_out_Q_generic;

  always_comb begin
    p_re_re = $signed(prev_I) * $signed(inc_I);
    p_im_im = $signed(prev_Q) * $signed(inc_Q);
    p_re_im = $signed(prev_I) * $signed(inc_Q);
    p_im_re = $signed(prev_Q) * $signed(inc_I);

    acc_re = $signed(p_re_re) - $signed(p_im_im);  // 33b guard
    acc_im = $signed(p_re_im) + $signed(p_im_re);

    // Signed round-to-nearest before >> 15:
    // add +2^14 for >=0, add -(2^14) for <0  → (x + sign?(-ROUND_CONST):ROUND_CONST)
    acc_re_rnd = acc_re + (acc_re[32] ? -ROUND_CONST : ROUND_CONST);
    acc_im_rnd = acc_im + (acc_im[32] ? -ROUND_CONST : ROUND_CONST);

    // Arithmetic shift by 15 (Q1.15)
    out_re_17 = acc_re_rnd >>> 15;  // 17 bits to check saturation
    out_im_17 = acc_im_rnd >>> 15;

    // Saturate to 16-bit signed
    if (out_re_17 > 17'sd32767) calc_out_I_generic = 16'sd32767;
    else if (out_re_17 < -17'sd32768) calc_out_I_generic = -16'sd32768;
    else calc_out_I_generic = out_re_17[15:0];

    if (out_im_17 > 17'sd32767) calc_out_Q_generic = 16'sd32767;
    else if (out_im_17 < -17'sd32768) calc_out_Q_generic = -16'sd32768;
    else calc_out_Q_generic = out_im_17[15:0];
  end

  // Fast-path outputs (no multipliers; exact rotations)
  iq16_t calc_out_I_fast;
  iq16_t calc_out_Q_fast;
  logic  use_fast;

  always_comb begin
    use_fast = (inc_is_p1 | inc_is_m1 | inc_is_pj | inc_is_mj);

    // Default hold (won't be used if use_fast=1)
    calc_out_I_fast = prev_I;
    calc_out_Q_fast = prev_Q;

    if (inc_is_p1) begin
      // +1 ∠0° : out = prev
      calc_out_I_fast = prev_I;
      calc_out_Q_fast = prev_Q;
    end else if (inc_is_m1) begin
      // -1 ∠180° : out = -prev
      calc_out_I_fast = -prev_I;
      calc_out_Q_fast = -prev_Q;
    end else if (inc_is_pj) begin
      // +j ∠+90° : out = prev × j = {-prev_Q, +prev_I}
      calc_out_I_fast = -prev_Q;
      calc_out_Q_fast =  prev_I;
    end else if (inc_is_mj) begin
      // -j ∠-90° : out = prev × (-j) = {+prev_Q, -prev_I}
      calc_out_I_fast =  prev_Q;
      calc_out_Q_fast = -prev_I;
    end
  end

  // Output hold regs
  iq16_t hold_I;
  iq16_t hold_Q;
  logic  hold_last;
  logic  hold_valid;

  // Ready/valid
  assign in_ready  = ctrl_enable & (~hold_valid);
  assign out_valid = hold_valid;
  assign out_data  = {hold_I, hold_Q};
  assign out_last  = hold_last;

  // Datapath / handshakes
  always_ff @(posedge clk_bb or negedge rst_n) begin
    if (!rst_n) begin
      prev_I      <= ONE_Q15;  // (1,0)
      prev_Q      <= 16'sd0;

      hold_I      <= '0;
      hold_Q      <= '0;
      hold_last   <= 1'b0;
      hold_valid  <= 1'b0;

      st_running  <= 1'b0;
    end else begin
      // Local soft reset
      if (ctrl_sw_reset) begin
        prev_I     <= ONE_Q15;
        prev_Q     <= 16'sd0;
        hold_valid <= 1'b0;
      end

      // Accept a new phasor increment (one symbol)
      if (in_valid && in_ready) begin
        if (use_fast) begin
          hold_I <= calc_out_I_fast;
          hold_Q <= calc_out_Q_fast;
        end else begin
          hold_I <= calc_out_I_generic;
          hold_Q <= calc_out_Q_generic;
        end
        hold_last  <= in_last;
        hold_valid <= 1'b1;
      end

      // Downstream handshake: commit output and advance state
      if (hold_valid && out_ready) begin
        hold_valid <= 1'b0;
        prev_I     <= hold_I;
        prev_Q     <= hold_Q;
        st_running <= 1'b1;
      end
    end
  end

  // Synthesis-time sanity
  // synopsys translate_off
  initial begin
    assert(ONE_Q15 == 16'sd32767) else $error("ONE_Q15 must be 32767 (Q1.15 +1.0)");
  end
  // synopsys translate_on

endmodule


// -----------------------------------------------------------------------------
// Module: PreambleInserter
// Purpose:
//   Inserts a fixed QPSK preamble of length PREAMBLE_LEN (symbols) at the
//   *start of each frame* before forwarding the payload. Frames are delineated
//   by the upstream TLAST on the payload stream.
//
// Interface (AXI4-Stream):
//   - Slave  (s_axis_*): payload source (QPSK symbols, 32b {I[15:0],Q[15:0]})
//   - Master (m_axis_*): to next stage (preamble + payload)
//
// AXI4-Stream Handshake Rules (followed here strictly):
//   - Transfer occurs on a cycle only when TVALID && TREADY == 1.
//   - Master (us) holds TVALID high and keeps TDATA/TLAST *stable* until sink
//     raises TREADY and the transfer completes.
//   - Slave side (our s_axis_*) must not consume data unless we raise TREADY,
//     and only on a handshake.
//
// High-level behavior:
//   1) IDLE:
//        *Wait ready* for the first payload beat of a new frame.
//        On handshake, we CAPTURE that first beat (hold registers)
//        and then move to INSERT.
//   2) INSERT:
//        Emit PREAMBLE_LEN symbols from ROM (no TLAST), stalling payload input.
//   3) FORWARD_HOLD:
//        Output the captured first payload beat (with backpressure).
//        If that beat had TLAST, frame ends immediately (tiny frame).
//   4) FORWARD_PASS:
//        Transparent pass-through for the remainder of the payload until TLAST.
//        Back to IDLE.
// -----------------------------------------------------------------------------
module PreambleInserter #(
    parameter int PREAMBLE_LEN = 64
) (
    input  logic          aclk,
    input  logic          aresetn,

    // AXI4-Stream slave input (payload source)
    input  logic          s_axis_tvalid,
    output logic          s_axis_tready,
    input  logic [31:0]   s_axis_tdata,   // {I[15:0], Q[15:0]} in Q1.15
    input  logic          s_axis_tlast,   // payload end-of-frame

    // AXI4-Stream master output (to next stage)
    output logic          m_axis_tvalid,
    input  logic          m_axis_tready,
    output logic [31:0]   m_axis_tdata,   // {I[15:0], Q[15:0]} in Q1.15
    output logic          m_axis_tlast    // end-of-frame (from payload only)
);

    // -----------------------------
    // PREAMBLE ROM (Q1.15 QPSK)
    //   32-bit word packs I then Q: {I[15:0], Q[15:0]}
    //   Sequence cycles: (+,+), (+,−), (−,+), (−,−)
    //   P ≈ +0.7071, N ≈ −0.7071
    // -----------------------------
    localparam logic [15:0] P = 16'h5A82; // +0.7071 -> +23170
    localparam logic [15:0] N = 16'hA57E; // -0.7071 -> -23170

    logic [31:0] preamble_mem [0:PREAMBLE_LEN-1];

    initial begin : init_preamble
        // Repeat the 4-point QPSK pattern to fill PREAMBLE_LEN entries.
        for (int i = 0; i < PREAMBLE_LEN; i++) begin
            unique case (i % 4)
                0: preamble_mem[i] = {P, P};
                1: preamble_mem[i] = {P, N};
                2: preamble_mem[i] = {N, P};
                default: preamble_mem[i] = {N, N};
            endcase
        end
    end

    // -----------------------------
    // FSM & Bookkeeping
    // -----------------------------
    typedef enum logic [1:0] {
        IDLE,          // waiting & capturing first payload beat
        INSERT,        // emitting preamble (no TLAST)
        FORWARD_HOLD,  // output the captured first beat
        FORWARD_PASS   // transparent pass-through for rest of frame
    } state_t;

    state_t state, next_state;

    // Counter width derived from preamble length
    localparam int CNT_W = (PREAMBLE_LEN <= 1) ? 1 : $clog2(PREAMBLE_LEN);
    logic [CNT_W-1:0] preamble_count; // counts accepted preamble symbols

    // First payload beat captured at SOF
    logic [31:0] hold_data;
    logic        hold_last;
    logic        hold_valid;

    // ----------------------------------------
    // Sequential: state, counters, and holding
    // ----------------------------------------
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state           <= IDLE;
            preamble_count  <= '0;
            hold_data       <= '0;
            hold_last       <= 1'b0;
            hold_valid      <= 1'b0;
        end else begin
            state <= next_state;

            // Count accepted preamble beats (only on handshake)
            if (state == INSERT && m_axis_tvalid && m_axis_tready)
                preamble_count <= preamble_count + 1'b1;

            // Reset counter when entering INSERT
            if (state != INSERT && next_state == INSERT)
                preamble_count <= '0;

            // Capture first payload beat at frame start (SOF) on handshake
            if (state == IDLE && s_axis_tvalid && s_axis_tready) begin
                hold_data  <= s_axis_tdata;
                hold_last  <= s_axis_tlast;
                hold_valid <= 1'b1;
            end

            // After we successfully output the held beat, clear the flag
            if (state == FORWARD_HOLD && m_axis_tvalid && m_axis_tready)
                hold_valid <= 1'b0;
        end
    end

    // ----------------------------------------
    // Combinational: outputs & next-state
    // ----------------------------------------
    always_comb begin
        // Defaults
        s_axis_tready = 1'b0;
        m_axis_tvalid = 1'b0;
        m_axis_tdata  = 32'h0000_0000;
        m_axis_tlast  = 1'b0;
        next_state    = state;

        unique case (state)

            // -------------------------------------------------
            // IDLE
            //   - We ASSERT s_axis_tready to avoid deadlock with
            //     "polite" masters that only drive TVALID when TREADY=1.
            //   - On handshake, we CAPTURE the first payload beat to
            //     hold while we emit the preamble.
            // -------------------------------------------------
            IDLE: begin
                s_axis_tready = 1'b1; // FIX: was 0 → could deadlock with polite masters
                if (s_axis_tvalid) begin
                    // handshake implied by TREADY=1
                    next_state = INSERT;
                end
            end

            // -------------------------------------------------
            // INSERT
            //   - Emit preamble from ROM (no TLAST).
            //   - Stall the payload input (s_axis_tready=0).
            //   - Honor backpressure on the master side: hold the same
            //     preamble word until m_axis_tready goes high.
            // -------------------------------------------------
            INSERT: begin
                s_axis_tready = 1'b0;              // hold off payload until preamble sent
                m_axis_tvalid = 1'b1;              // always have preamble to send
                m_axis_tdata  = preamble_mem[preamble_count];
                m_axis_tlast  = 1'b0;              // preamble never asserts TLAST

                if (m_axis_tready) begin
                    if (preamble_count == PREAMBLE_LEN-1) begin
                        // last preamble symbol accepted; next beat to output is the held payload
                        next_state = FORWARD_HOLD;
                    end
                end
            end

            // -------------------------------------------------
            // FORWARD_HOLD
            //   - Output the captured first payload beat (the one that
            //     triggered us to start the preamble).
            //   - Only after that beat is accepted do we start draining
            //     the live payload stream.
            // -------------------------------------------------
            FORWARD_HOLD: begin
                m_axis_tvalid = hold_valid;        // present held beat
                m_axis_tdata  = hold_data;
                m_axis_tlast  = hold_last;

                // Drain input only *after* we emitted the held beat
                s_axis_tready = m_axis_tready && !hold_valid;

                if (m_axis_tready && hold_valid) begin
                    // If the frame was a single-beat frame, we're done
                    next_state = hold_last ? IDLE : FORWARD_PASS;
                end
            end

            // -------------------------------------------------
            // FORWARD_PASS
            //   - Transparent pass-through of the remainder of payload.
            //   - Backpressure propagates naturally (TREADY mirrors).
            // -------------------------------------------------
            FORWARD_PASS: begin
                s_axis_tready = m_axis_tready;
                m_axis_tvalid = s_axis_tvalid;
                m_axis_tdata  = s_axis_tdata;
                m_axis_tlast  = s_axis_tlast;

                if (s_axis_tvalid && m_axis_tready && s_axis_tlast)
                    next_state = IDLE; // frame complete
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule

module tx_packetizer #(
  parameter int DATA_WIDTH = 32,
  parameter int MAX_FRAME_WORDS = 1024
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
  localparam logic [15:0] SYNC_WORD  = 16'hA5A5;
  localparam logic [7:0]  HEADER_LEN = 8'd8;     // bytes after SYNC
  localparam logic [3:0]  MODE_VAL   = 4'h1;
  localparam logic [3:0]  FLAGS_VAL  = 4'h0;
  localparam logic [31:0] RESERVED   = 32'h0000_0000;

  // -------- State --------
  typedef enum logic [1:0] {IDLE, COLLECT, SEND_HEADER, SEND_PAYLOAD} state_t;
  state_t state, next_state;

  // -------- Buffers / counters --------
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

  // =============== Output register (AXIS master pattern) ===============
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
    // else: hold current data/last when stalled
  end

  // ===================== State register =====================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      state <= IDLE;
    else
      state <= next_state;
  end

  // ===================== Sequential updates =====================
  // Do *all* pointer/counter writes on handshakes only.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr         <= '0;
      rd_ptr         <= '0;
      hdr_idx        <= 2'd0;
      payload_length <= 16'd0;
      seq_num        <= 16'd0;
    end else begin
      // Accept input beats
      if ((state == IDLE || state == COLLECT) && s_axis_tvalid && s_axis_tready) begin
        payload_buf[wr_ptr] <= s_axis_tdata;
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
    next_state   = state;
    s_axis_tready= 1'b0;
    next_tvalid  = 1'b0;
    next_tdata   = '0;
    next_tlast   = 1'b0;

    unique case (state)
      // ---- Accept first beat immediately ----
      IDLE: begin
        s_axis_tready = 1'b1;                      // <- critical fix
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
            2'd0: begin
              next_tdata = {SYNC_WORD, HEADER_LEN, {MODE_VAL, FLAGS_VAL}};
            end
            2'd1: begin
              next_tdata = {seq_num, payload_length};
            end
            2'd2: begin
              next_tdata = RESERVED;
            end
          endcase
          // tlast is ONLY for last payload beat, never for header
          next_tlast = 1'b0;

          // advance state after 3rd header beat handshake (handled in seq block)
          if (hdr_idx == 2 && (m_axis_tvalid ? m_axis_tready : 1'b1)) begin
            // on the cycle hdr_idx==2 issues, seq block will reset hdr_idx and rd_ptr
            // move to payload next
            next_state = SEND_PAYLOAD;
          end
        end
      end

      // ---- Stream buffered payload ----
      SEND_PAYLOAD: begin
        if (!m_axis_tvalid || m_axis_tready) begin
          next_tvalid = 1'b1;
          next_tdata  = payload_buf[rd_ptr];
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

// rx_depacketizer.sv
module rx_depacketizer #(
    parameter int DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // AXIS input (from packetizer)
    input  logic [DATA_WIDTH-1:0]  s_axis_tdata,
    input  logic                   s_axis_tvalid,
    output logic                   s_axis_tready,
    input  logic                   s_axis_tlast,

    // AXIS output (payload only)
    output logic [DATA_WIDTH-1:0]  m_axis_tdata,
    output logic                   m_axis_tvalid,
    input  logic                   m_axis_tready,
    output logic                   m_axis_tlast
);

    typedef enum logic [1:0] { HDR, FWD_PAYLOAD } state_t;
    state_t state, next_state;

    // 3 header words: 0,1,2
    logic [1:0]  header_count;

    // Parsed fields (optional/debug)
    logic [15:0] sync_word;
    logic [7:0]  header_len;
    logic [3:0]  mode;
    logic [3:0]  flags;
    logic [15:0] seq_num;
    logic [15:0] payload_length;

    // Payload counter
    logic [15:0] payload_count;

    // Output staging
    logic [DATA_WIDTH-1:0] send_data;
    logic                  send_valid;
    logic                  send_last;
    logic                  last_now;

    // Hold outputs until accepted
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tvalid <= 1'b0;
            m_axis_tdata  <= '0;
            m_axis_tlast  <= 1'b0;
        end else if (!m_axis_tvalid || m_axis_tready) begin
            m_axis_tvalid <= send_valid;
            m_axis_tdata  <= send_valid ? send_data : '0;
            m_axis_tlast  <= send_valid ? send_last : 1'b0;
        end
        // else: hold
    end

    // State & counters (sequential)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= HDR;
            header_count  <= 2'd0;
            payload_count <= 16'd0;
            sync_word     <= 16'h0000;
            header_len    <= 8'h00;
            mode          <= 4'h0;
            flags         <= 4'h0;
            seq_num       <= 16'h0000;
            payload_length<= 16'h0000;
        end else begin
            state <= next_state;

            // Header consumption
            if (state == HDR && s_axis_tvalid && s_axis_tready) begin
                unique case (header_count)
                    2'd0: begin
                        sync_word  <= s_axis_tdata[31:16];
                        header_len <= s_axis_tdata[15:8];
                        mode       <= s_axis_tdata[7:4];
                        flags      <= s_axis_tdata[3:0];
                    end
                    2'd1: begin
                        seq_num        <= s_axis_tdata[31:16];
                        payload_length <= s_axis_tdata[15:0];
                    end
                    default: ; // 2 -> reserved
                endcase
                header_count <= header_count + 2'd1;
            end

            // Reset counters when returning to HDR
            if (next_state == HDR && state != HDR) begin
                header_count  <= 2'd0;
                payload_count <= 16'd0;
            end

            // Reset payload_count exactly when entering FWD_PAYLOAD
            if (state == HDR && next_state == FWD_PAYLOAD) begin
                payload_count <= 16'd0;
            end

            // Payload word count (only when we actually consume input)
            if (state == FWD_PAYLOAD && s_axis_tvalid && s_axis_tready) begin
                payload_count <= payload_count + 16'd1;
            end
        end
    end

    // FSM (combinational)
    always_comb begin
        // Defaults
        next_state    = state;
        s_axis_tready = 1'b0;
        send_valid    = 1'b0;
        send_data     = '0;
        send_last     = 1'b0;

        unique case (state)
            // ----- Eat (and drop) 3 header words -----
            HDR: begin
                s_axis_tready = 1'b1; // always ready for header
                if (s_axis_tvalid) begin
                    if (header_count == 2'd2) begin
                        // After 3rd header word: either go straight back to HDR (0-len)
                        // or start forwarding payload.
                        next_state = (payload_length == 16'd0) ? HDR : FWD_PAYLOAD;
                    end
                end
            end

            // ----- Forward payload -----
            FWD_PAYLOAD: begin
                // one-beat elastic coupling
                if (!m_axis_tvalid || m_axis_tready) begin
                    s_axis_tready = 1'b1;

                    if (s_axis_tvalid) begin
                        send_valid = 1'b1;
                        send_data  = s_axis_tdata;

                        // Robust last detection: length OR incoming TLAST OR zero-length
                        last_now = (payload_length == 16'd0) ||
                                ((payload_count + 1) == payload_length) ||
                                s_axis_tlast;

                        send_last  = last_now;
                        if (last_now) next_state = HDR;
                    end
                end
                // else stalled: deassert s_axis_tready, hold outputs
            end

            default: next_state = HDR;
        endcase
    end

endmodule


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


// -----------------------------------------------------------------------------
// diff_decoder.sv  — Differential decoder for DBPSK/DQPSK
//   • AXIS In  : encoded symbols {I[15:0], Q[15:0]} (Q1.15, signed)
//   • AXIS Out : phase increments d[k] = y[k] * conj(y[k-1])  (Q1.15, signed)
//   • Reset state (and SW_RESET): prev_y = (32767, 0) so first output is d[0]=y[0]
//   • TLAST propagated
//   • AXI-Lite CSRs (word-aligned):
//        0x00 CTRL   : [0]=ENABLE, [2]=SW_RESET(one-shot), [6:4]=MODE (0=DBPSK, 1=DQPSK)
//        0x04 STATUS : [0]=RUNNING (R/W1C)
//   • Vivado-friendly coding: no locals inside procedural blocks, no SV functions.
//   • Fast-path when y[k] is exactly {±1,0} or {0,±1} to avoid amplitude creep.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module diff_decoder #(
  parameter logic signed [15:0] ONE_Q15 = 16'sd32767   // +1.0 in Q1.15
)(
  input  logic clk_bb,
  input  logic rst_n,

  // -------- AXIS-like encoded symbols in: {I[15:0], Q[15:0]} ----------------
  input  logic        in_valid,
  output logic        in_ready,
  input  logic [31:0] in_data,     // {I[15:0], Q[15:0]} signed Q1.15
  input  logic        in_last,

  input logic frame_start_i,  // asserted 1 clk on new frame (from PreambleCorrelator)

  // -------- AXIS-like increments out: {I[15:0], Q[15:0]} --------------------
  output logic        out_valid,
  input  logic        out_ready,
  output logic [31:0] out_data,    // {I[15:0], Q[15:0]} signed Q1.15
  output logic        out_last,

  // ------------------------- AXI4-Lite (CSR) --------------------------------
  input  logic        s_axi_aclk,
  input  logic        s_axi_aresetn,
  // write address
  input  logic [7:0]  s_axi_awaddr,
  input  logic        s_axi_awvalid,
  output logic        s_axi_awready,
  // write data
  input  logic [31:0] s_axi_wdata,
  input  logic [3:0]  s_axi_wstrb,
  input  logic        s_axi_wvalid,
  output logic        s_axi_wready,
  // write resp
  output logic [1:0]  s_axi_bresp,
  output logic        s_axi_bvalid,
  input  logic        s_axi_bready,
  // read address
  input  logic [7:0]  s_axi_araddr,
  input  logic        s_axi_arvalid,
  output logic        s_axi_arready,
  // read data
  output logic [31:0] s_axi_rdata,
  output logic [1:0]  s_axi_rresp,
  output logic        s_axi_rvalid,
  input  logic        s_axi_rready
);

  // ===========================================================================
  // Types / temps (module scope)
  // ===========================================================================
  typedef logic signed [15:0] iq16_t;
  typedef logic signed [31:0] i32_t;
  typedef logic signed [32:0] i33_t;

  localparam i33_t ROUND_CONST = 33'sd16384; // 2^14 for round-to-nearest

  // ===========================================================================
  // CSRs — always-ready AXI-Lite
  // ===========================================================================
  logic        ctrl_enable;
  logic        ctrl_sw_reset;       // one-shot
  logic [2:0]  ctrl_mode;           // 0=DBPSK, 1=DQPSK (exposed for symmetry)

  logic        st_running;          // R/W1C

  logic [7:0]  awaddr_hold;
  logic        have_write;
  logic        do_write;
  logic [7:0]  araddr_hold;
  logic        do_read;

  always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
      s_axi_awready   <= 1'b1;
      s_axi_wready    <= 1'b1;
      s_axi_bvalid    <= 1'b0;
      s_axi_bresp     <= 2'b00;
      awaddr_hold     <= 8'h00;
      have_write      <= 1'b0;

      s_axi_arready   <= 1'b1;
      s_axi_rvalid    <= 1'b0;
      s_axi_rresp     <= 2'b00;
      s_axi_rdata     <= 32'h0;
      araddr_hold     <= 8'h00;

      ctrl_enable     <= 1'b0;
      ctrl_sw_reset   <= 1'b0;
      ctrl_mode       <= 3'd1;   // default DQPSK

      st_running      <= 1'b0;
    end else begin
      if (s_axi_awvalid) awaddr_hold <= s_axi_awaddr;
      have_write <= s_axi_awvalid & s_axi_wvalid & ~s_axi_bvalid;
      do_write   <= have_write; // pulse

      if (do_write) begin
        unique case (awaddr_hold[7:2])
          6'h00: begin // CTRL
            if (s_axi_wstrb[0]) begin
              ctrl_enable   <= s_axi_wdata[0];
              ctrl_sw_reset <= s_axi_wdata[2];  // self-clears below
              ctrl_mode     <= s_axi_wdata[6:4];
            end
          end
          6'h01: begin // STATUS R/W1C
            if (s_axi_wstrb[0]) begin
              if (s_axi_wdata[0]) st_running <= 1'b0;
            end
          end
          default: ;
        endcase
        s_axi_bvalid <= 1'b1;
        s_axi_bresp  <= 2'b00;
      end else if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end

      do_read <= s_axi_arvalid & ~s_axi_rvalid;
      if (do_read) begin
        araddr_hold <= s_axi_araddr;
        unique case (s_axi_araddr[7:2])
          6'h00: s_axi_rdata <= {25'd0, ctrl_mode, 1'b0, ctrl_sw_reset, 1'b0, ctrl_enable};
          6'h01: s_axi_rdata <= {31'd0, st_running};
          default: s_axi_rdata <= 32'h0000_0000;
        endcase
        s_axi_rresp  <= 2'b00;
        s_axi_rvalid <= 1'b1;
      end else if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
      end

      if (ctrl_sw_reset) ctrl_sw_reset <= 1'b0;
    end
  end

  // ===========================================================================
  // Datapath: y[k] * conj(y[k-1])
  // ===========================================================================
  // Previous encoded symbol y[k-1]
  iq16_t prev_I;
  iq16_t prev_Q;

  // Input unpack (encoded y[k])
  iq16_t y_I_in;
  iq16_t y_Q_in;
  assign y_I_in = in_data[31:16];
  assign y_Q_in = in_data[15:0];

  // Fast-path detect when y[k] is exactly axis-aligned
  logic y_is_p1, y_is_m1, y_is_pj, y_is_mj;
  always_comb begin
    y_is_p1 = (y_I_in ==  ONE_Q15) && (y_Q_in == 16'sd0);
    y_is_m1 = (y_I_in == -ONE_Q15) && (y_Q_in == 16'sd0);
    y_is_pj = (y_I_in == 16'sd0)    && (y_Q_in ==  ONE_Q15);
    y_is_mj = (y_I_in == 16'sd0)    && (y_Q_in == -ONE_Q15);
  end

  // Generic complex multiply: d = y * conj(prev)
  // d_re = yI*prevI + yQ*prevQ
  // d_im = yQ*prevI - yI*prevQ
  i32_t p_yI_prevI;
  i32_t p_yQ_prevQ;
  i32_t p_yQ_prevI;
  i32_t p_yI_prevQ;
  i33_t acc_re;
  i33_t acc_im;
  i33_t acc_re_rnd;
  i33_t acc_im_rnd;
  logic signed [16:0] d_re_17;
  logic signed [16:0] d_im_17;
  iq16_t d_I_generic;
  iq16_t d_Q_generic;

  always_comb begin
    p_yI_prevI = $signed(y_I_in) * $signed(prev_I);
    p_yQ_prevQ = $signed(y_Q_in) * $signed(prev_Q);
    p_yQ_prevI = $signed(y_Q_in) * $signed(prev_I);
    p_yI_prevQ = $signed(y_I_in) * $signed(prev_Q);

    acc_re = $signed(p_yI_prevI) + $signed(p_yQ_prevQ);
    acc_im = $signed(p_yQ_prevI) - $signed(p_yI_prevQ);

    acc_re_rnd = acc_re + (acc_re[32] ? -ROUND_CONST : ROUND_CONST);
    acc_im_rnd = acc_im + (acc_im[32] ? -ROUND_CONST : ROUND_CONST);

    d_re_17 = acc_re_rnd >>> 15;
    d_im_17 = acc_im_rnd >>> 15;

    if (d_re_17 > 17'sd32767)       d_I_generic = 16'sd32767;
    else if (d_re_17 < -17'sd32768) d_I_generic = -16'sd32768;
    else                            d_I_generic = d_re_17[15:0];

    if (d_im_17 > 17'sd32767)       d_Q_generic = 16'sd32767;
    else if (d_im_17 < -17'sd32768) d_Q_generic = -16'sd32768;
    else                            d_Q_generic = d_im_17[15:0];
  end

  // Fast-path when y is axis-aligned:
  //  y=+1 : d =  conj(prev)       = { prev_I, -prev_Q}
  //  y=-1 : d = -conj(prev)       = {-prev_I,  prev_Q}
  //  y=+j : d =  j*conj(prev)     = { prev_Q,  prev_I}
  //  y=-j : d = -j*conj(prev)     = {-prev_Q, -prev_I}
  iq16_t d_I_fast;
  iq16_t d_Q_fast;
  logic  use_fast;

  always_comb begin
    use_fast = (y_is_p1 | y_is_m1 | y_is_pj | y_is_mj);

    d_I_fast = prev_I; // default (overwritten below)
    d_Q_fast = prev_Q;

    if (y_is_p1) begin
      d_I_fast =  prev_I;
      d_Q_fast = -prev_Q;
    end else if (y_is_m1) begin
      d_I_fast = -prev_I;
      d_Q_fast =  prev_Q;
    end else if (y_is_pj) begin
      d_I_fast =  prev_Q;
      d_Q_fast =  prev_I;
    end else if (y_is_mj) begin
      d_I_fast = -prev_Q;
      d_Q_fast = -prev_I;
    end
  end

// edge detect frame_start 
  logic fs_d;
  always_ff @(posedge clk_bb or negedge rst_n) begin
    if (!rst_n) begin
      fs_d <= 1'b0;
    end else begin
      fs_d <= frame_start_i;
    end
  end

  logic fs_rise = frame_start_i & ~fs_d;

  // Hold registers for one output beat and a latch of y[k] for prev update
  iq16_t hold_I;
  iq16_t hold_Q;
  logic  hold_last;
  logic  hold_valid;

  iq16_t latched_yI;
  iq16_t latched_yQ;

  assign in_ready  = ctrl_enable & (~hold_valid);
  assign out_valid = hold_valid;
  assign out_data  = {hold_I, hold_Q};
  assign out_last  = hold_last;

  // Sequential
  always_ff @(posedge clk_bb or negedge rst_n) begin
    if (!rst_n) begin
      prev_I      <= ONE_Q15;  // y[-1] = (1,0)
      prev_Q      <= 16'sd0;

      hold_I      <= '0;
      hold_Q      <= '0;
      hold_last   <= 1'b0;
      hold_valid  <= 1'b0;

      latched_yI  <= 16'sd0;
      latched_yQ  <= 16'sd0;

      st_running  <= 1'b0;
    end else begin
      // Local soft reset
      if (ctrl_sw_reset || fs_rise) begin
        prev_I     <= ONE_Q15;
        prev_Q     <= ONE_Q15;
        // prev_Q     <= 16'sd0;
        hold_valid <= 1'b0;
      end

      // Accept an input symbol and compute d[k]
      if (in_valid && in_ready) begin
        if (use_fast) begin
          hold_I <= d_I_fast;
          hold_Q <= d_Q_fast;
        end else begin
          hold_I <= d_I_generic;
          hold_Q <= d_Q_generic;
        end
        hold_last  <= in_last;
        hold_valid <= 1'b1;

        // Latch y[k] for next-step prev update
        latched_yI <= y_I_in;
        latched_yQ <= y_Q_in;
      end

      // Downstream handshake: commit output and advance prev=y[k]
      if (hold_valid && out_ready) begin
        hold_valid <= 1'b0;
        prev_I     <= latched_yI;
        prev_Q     <= latched_yQ;
        st_running <= 1'b1;
      end
    end
  end

  // synopsys translate_off
  initial begin
    assert(ONE_Q15 == 16'sd32767) else $error("ONE_Q15 must be 32767 (Q1.15 +1.0)");
  end
  // synopsys translate_on

endmodule

// -----------------------------------------------------------------------------
// slicer.sv (self-contained)
// BPSK/QPSK symbol slicer with AXI4-Lite control and internal vld/rdy/last.
// - Symbols in: {I[15:0], Q[15:0]} (Q1.15, signed), one symbol per beat.
// - Bytes out : bits packed LSB-first. TLAST asserted on last output byte
//               (generator ensures K*frameLen is byte-aligned).
// - QPSK Gray per project convention: bit0 = sign(I), bit1 = sign(Q).
// - BYPASS forces BPSK decisions (I-only) regardless of MODE.
//
// CSRs (word-aligned, base offset local to this block):
//   0x00 CTRL  : [0]=ENABLE, [1]=BYPASS, [2]=SW_RESET(one-shot),
//                [6:4]=MODE (0=BPSK, 1=QPSK), [8]=AMC_OVERRIDE (1=use local MODE)
//   0x04 STATUS: [0]=RUNNING (R/W1C), [2]=OVERFLOW (R/W1C)
//   0x18 RESULT0: byte_count (RO; W* clears to 0 for convenience)
//
// Notes:
// - AXI-Lite assumed in same clk domain (clk_bb). If not, add CDC.
// - Internal streams are AXIS-like: valid/ready/last only.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module slicer #(
  parameter integer BYTE_COUNT_W = 32
)(
  input  logic clk_bb,
  input  logic rst_n,

  // -------- internal "AXIS-like" symbols in: {I[15:0],Q[15:0]} --------
  input  logic        in_valid,
  output logic        in_ready,
  input  logic [31:0] in_data,     // {I[15:0], Q[15:0]}
  input  logic        in_last,

  // -------- internal "AXIS-like" bytes out (LSB-first) --------
  output logic        out_valid,
  input  logic        out_ready,
  output logic [7:0]  out_data,
  output logic        out_last,

  // Optional AMC-selected mode (only bit[0] used today: 0=BPSK, 1=QPSK)
  input  logic [2:0]  amc_mode_i,
  input  logic        amc_mode_valid_i,

  // ------------------------- AXI4-Lite (CSR) ------------------------------
  input  logic        s_axi_aclk,
  input  logic        s_axi_aresetn,
  // write address
  input  logic [7:0]  s_axi_awaddr,
  input  logic        s_axi_awvalid,
  output logic        s_axi_awready,
  // write data
  input  logic [31:0] s_axi_wdata,
  input  logic [3:0]  s_axi_wstrb,
  input  logic        s_axi_wvalid,
  output logic        s_axi_wready,
  // write resp
  output logic [1:0]  s_axi_bresp,
  output logic        s_axi_bvalid,
  input  logic        s_axi_bready,
  // read address
  input  logic [7:0]  s_axi_araddr,
  input  logic        s_axi_arvalid,
  output logic        s_axi_arready,
  // read data
  output logic [31:0] s_axi_rdata,
  output logic [1:0]  s_axi_rresp,
  output logic        s_axi_rvalid,
  input  logic        s_axi_rready
);

  // =========================================================================
  // CSR registers / AXI-Lite (always-ready style, like mapper)
  // =========================================================================
  logic        ctrl_enable;
  logic        ctrl_bypass;
  logic        ctrl_sw_reset;    // one-shot
  logic [2:0]  ctrl_mode;        // 0=BPSK, 1=QPSK
  logic        ctrl_amc_override;

  logic        st_running;       // set once first byte emitted; R/W1C
  logic        st_overflow;      // set if upstream violates ready; R/W1C

  logic [BYTE_COUNT_W-1:0] byte_count; // RESULT0

  logic [7:0]  awaddr_hold;
  logic        have_write;
  logic        do_write;
  logic [7:0]  araddr_hold;
  logic        do_read;

  always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
      s_axi_awready   <= 1'b1;
      s_axi_wready    <= 1'b1;
      s_axi_bvalid    <= 1'b0;
      s_axi_bresp     <= 2'b00;
      awaddr_hold     <= 8'h00;
      have_write      <= 1'b0;

      s_axi_arready   <= 1'b1;
      s_axi_rvalid    <= 1'b0;
      s_axi_rresp     <= 2'b00;
      s_axi_rdata     <= 32'h0;
      araddr_hold     <= 8'h00;

      ctrl_enable       <= 1'b0;
      ctrl_bypass       <= 1'b0;
      ctrl_sw_reset     <= 1'b0;
      ctrl_mode         <= 3'd1;   // default QPSK
      ctrl_amc_override <= 1'b1;   // default: use local MODE

      st_running        <= 1'b0;
      st_overflow       <= 1'b0;
      byte_count        <= {BYTE_COUNT_W{1'b0}};
    end else begin
      if (s_axi_awvalid) awaddr_hold <= s_axi_awaddr;
      have_write <= s_axi_awvalid & s_axi_wvalid & ~s_axi_bvalid;
      do_write   <= have_write;  // 1-cycle pulse

      if (do_write) begin
        unique case (awaddr_hold[7:2]) // word aligned
          6'h00: begin // CTRL
            if (s_axi_wstrb[0]) begin
              ctrl_enable       <= s_axi_wdata[0];
              ctrl_bypass       <= s_axi_wdata[1];
              ctrl_sw_reset     <= s_axi_wdata[2];  // one-shot below
              ctrl_mode         <= s_axi_wdata[6:4];
              ctrl_amc_override <= s_axi_wdata[8];
            end
          end
          6'h01: begin // STATUS R/W1C
            if (s_axi_wstrb[0]) begin
              if (s_axi_wdata[0]) st_running  <= 1'b0;
              if (s_axi_wdata[2]) st_overflow <= 1'b0;
            end
          end
          6'h06: begin // RESULT0 (optional clear-on-write)
            if (s_axi_wstrb != 4'b0000) byte_count <= {BYTE_COUNT_W{1'b0}};
          end
          default: ;
        endcase
        s_axi_bvalid <= 1'b1;
        s_axi_bresp  <= 2'b00;
      end else if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end

      do_read <= s_axi_arvalid & ~s_axi_rvalid;
      if (do_read) begin
        araddr_hold <= s_axi_araddr;
        unique case (s_axi_araddr[7:2])
          6'h00: s_axi_rdata <= {23'd0, ctrl_amc_override, 1'b0, ctrl_mode, ctrl_sw_reset, ctrl_bypass, ctrl_enable};
          6'h01: s_axi_rdata <= {29'd0, st_overflow, 1'b0, st_running};
          6'h06: s_axi_rdata <= {{(32-BYTE_COUNT_W){1'b0}}, byte_count};
          default: s_axi_rdata <= 32'h0000_0000;
        endcase
        s_axi_rresp  <= 2'b00;
        s_axi_rvalid <= 1'b1;
      end else if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
      end

      if (ctrl_sw_reset) ctrl_sw_reset <= 1'b0;
    end
  end

  // =========================================================================
  // Datapath: symbol → bits (LSB-first) → byte packer
  // =========================================================================
  // Effective mode: AMC override == 1 -> use ctrl_mode; else use amc_mode_i (if valid)
  logic [2:0] mode_sel;
  logic       eff_qpsk;
  logic       need2;
  logic [1:0] K;

  always_comb begin
    if (ctrl_amc_override)       mode_sel = ctrl_mode;
    else if (amc_mode_valid_i)   mode_sel = amc_mode_i;
    else                         mode_sel = ctrl_mode;

    eff_qpsk = mode_sel[0];
    need2    = (~ctrl_bypass) & eff_qpsk; // BYPASS forces BPSK
    K        = need2 ? 2'd2 : 2'd1;
  end

  // Symbol input split and sign → bits (b0 from I, b1 from Q)
  logic signed [15:0] I_in;
  logic signed [15:0] Q_in;
  logic               calc_b0;
  logic               calc_b1;

  assign I_in = in_data[31:16];
  assign Q_in = in_data[15:0];

  always_comb begin
    // Sign threshold at 0 (Q1.15). I<0 → bit1, else 0. Same for Q.
    calc_b0 = I_in[15];               // 1 if negative
    calc_b1 = need2 ? Q_in[15] : 1'b0;
  end

  // Byte packer
  logic [7:0] byte_buf;
  logic [3:0] bits_filled;            // 0..8
  logic [3:0] sum_bits;
  logic       would_make_full;
  logic       pipeline_blocked;
  logic [7:0] next_byte_fill;
  logic       frame_last_pending;
  logic       this_last_for_byte;

  always_comb begin
    sum_bits         = bits_filled + K;
    would_make_full  = (sum_bits == 4'd8);
    pipeline_blocked = (out_valid & ~out_ready);

    // Precompute what the byte would look like after inserting new bits
    next_byte_fill   = byte_buf;
    next_byte_fill[bits_filled] = calc_b0;
    if (need2) next_byte_fill[bits_filled + 1] = calc_b1;

    // TLAST for this output byte (generator guarantees alignment)
    this_last_for_byte = would_make_full & (in_last | frame_last_pending);
  end

  // Ready to accept a symbol:
  // - Always OK if sum_bits < 8 (we just accumulate).
  // - If sum_bits == 8, we can only accept if the output byte path isn't blocked.
  assign in_ready = ctrl_enable &
                    ( (sum_bits < 4'd8) | ( (sum_bits == 4'd8) & ~pipeline_blocked ) );

  always_ff @(posedge clk_bb or negedge rst_n) begin
    if (!rst_n) begin
      byte_buf            <= 8'h00;
      bits_filled         <= 4'd0;
      frame_last_pending  <= 1'b0;

      out_valid           <= 1'b0;
      out_data            <= 8'h00;
      out_last            <= 1'b0;

      st_running          <= 1'b0;
      st_overflow         <= 1'b0;
    end else begin
      // Local soft reset for datapath
      if (ctrl_sw_reset) begin
        byte_buf           <= 8'h00;
        bits_filled        <= 4'd0;
        frame_last_pending <= 1'b0;
        out_valid          <= 1'b0;
      end

      // Overflow sticky if upstream violates ready
      if (in_valid && !in_ready) begin
        st_overflow <= 1'b1;
      end

      // Accept a symbol
      if (in_valid && in_ready) begin
        // Track frame boundary if we haven't yet produced the last byte
        if (in_last) frame_last_pending <= 1'b1;

        if (would_make_full) begin
          // Emit a full byte immediately
          out_data            <= next_byte_fill;
          out_valid           <= 1'b1;
          out_last            <= this_last_for_byte;

          // Reset accumulator for next byte
          byte_buf            <= 8'h00;
          bits_filled         <= 4'd0;
          frame_last_pending  <= 1'b0; // consumed with this byte
        end else begin
          // Accumulate bits into partial byte
          byte_buf    <= next_byte_fill;
          bits_filled <= bits_filled + K;
        end
      end

      // Downstream handshake for output byte
      if (out_valid && out_ready) begin
        out_valid  <= 1'b0;
        st_running <= 1'b1;
        byte_count <= byte_count + {{(BYTE_COUNT_W-1){1'b0}}, 1'b1};
      end
    end
  end

endmodule

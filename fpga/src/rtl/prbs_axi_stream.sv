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


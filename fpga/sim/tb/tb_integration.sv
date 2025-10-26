`timescale 1ns/1ps

module tb_integration;

  // -----------------------------
  // Clock / Reset
  // -----------------------------
  logic clk = 0;
  always #4 clk = ~clk; // 125 MHz

  logic rst_n = 0;
  initial begin
    repeat (10) @(posedge clk);
    rst_n = 1;
  end

  // -----------------------------
  // Run-time knobs
  // -----------------------------
  localparam int BYTES_PER_FRAME = 64; // TLAST every N bytes from PRBS
  localparam int NFRAMES         = 4;  // frames per test phase

  // Mapper amplitudes (Q1.15)
  localparam logic signed [15:0] AMP_BPSK = 16'sd32767;
  localparam logic signed [15:0] AMP_QPSK = 16'sd23170;

  // -----------------------------
  // AXI-Lite (PRBS, 6-bit addr) + (Mapper, 8-bit addr)
  // -----------------------------
  // PRBS
  logic [5:0]  s_awaddr_prbs, s_araddr_prbs;
  logic        s_awvalid_prbs, s_awready_prbs;
  logic [31:0] s_wdata_prbs;   logic [3:0] s_wstrb_prbs;
  logic        s_wvalid_prbs,  s_wready_prbs;
  logic [1:0]  s_bresp_prbs;   logic s_bvalid_prbs, s_bready_prbs;
  logic        s_arvalid_prbs, s_arready_prbs;
  logic [31:0] s_rdata_prbs;   logic [1:0] s_rresp_prbs; logic s_rvalid_prbs, s_rready_prbs;

  // Mapper
  logic [7:0]  s_awaddr_map, s_araddr_map;
  logic        s_awvalid_map, s_awready_map;
  logic [31:0] s_wdata_map;    logic [3:0] s_wstrb_map;
  logic        s_wvalid_map,   s_wready_map;
  logic [1:0]  s_bresp_map;    logic s_bvalid_map, s_bready_map;
  logic        s_arvalid_map,  s_arready_map;
  logic [31:0] s_rdata_map;    logic [1:0] s_rresp_map; logic s_rvalid_map, s_rready_map;

  // AXI-Lite clock/reset = base clock/reset
  wire s_axi_aclk    = clk;
  wire s_axi_aresetn = rst_n;

  // -----------------------------
  // Stream signals
  // -----------------------------
  // PRBS -> Scrambler
  logic        prbs_valid, prbs_ready, prbs_last;
  logic [7:0]  prbs_data;

  // Scrambler -> Mapper (bytes)
  logic        scr_valid, scr_ready;
  logic [7:0]  scr_data;

  // Mapper -> Sink (symbols + last)
  logic        map_valid, map_ready, map_last;
  logic [31:0] map_data;

  // -----------------------------
  // DUTs
  // -----------------------------
  // PRBS AXI-Stream generator
  prbs_axi_stream u_prbs (
    .clk   (clk),
    .rst_n (rst_n),

    .s_axil_awaddr (s_awaddr_prbs),
    .s_axil_awvalid(s_awvalid_prbs),
    .s_axil_awready(s_awready_prbs),
    .s_axil_wdata  (s_wdata_prbs),
    .s_axil_wstrb  (s_wstrb_prbs),
    .s_axil_wvalid (s_wvalid_prbs),
    .s_axil_wready (s_wready_prbs),
    .s_axil_bresp  (s_bresp_prbs),
    .s_axil_bvalid (s_bvalid_prbs),
    .s_axil_bready (s_bready_prbs),
    .s_axil_araddr (s_araddr_prbs),
    .s_axil_arvalid(s_arvalid_prbs),
    .s_axil_arready(s_arready_prbs),
    .s_axil_rdata  (s_rdata_prbs),
    .s_axil_rresp  (s_rresp_prbs),
    .s_axil_rvalid (s_rvalid_prbs),
    .s_axil_rready (s_rready_prbs),

    .m_axis_tdata  (prbs_data),
    .m_axis_tvalid (prbs_valid),
    .m_axis_tready (prbs_ready),
    .m_axis_tlast  (prbs_last)
  );

  // Real byte scrambler (no sidebands). TLAST bypasses around it.
  logic        scr_en, scr_bypass, scr_seed_wr;
  logic [6:0]  scr_seed;
  logic        scr_running_pulse;

  byte_scrambler #(.LFSR_W(7), .TAP_MASK(7'b1001000)) u_scr (
    .clk          (clk),
    .rst_n        (rst_n),
    .in_data      (prbs_data),
    .in_valid     (prbs_valid),
    .in_ready     (prbs_ready),
    .out_data     (scr_data),
    .out_valid    (scr_valid),
    .out_ready    (scr_ready),
    .cfg_enable   (scr_en),
    .cfg_bypass   (scr_bypass),
    .cfg_seed_wr  (scr_seed_wr),
    .cfg_seed     (scr_seed),
    .running_pulse(scr_running_pulse)
  );

  // Mapper (expects TLAST), pass PRBS TLAST around scrambler
  mapper u_mapper (
    .clk_bb       (clk),
    .rst_n        (rst_n),

    .in_valid     (scr_valid),
    .in_ready     (scr_ready),
    .in_data      (scr_data),
    .in_last      (prbs_last),    // TLAST bypass

    .out_valid    (map_valid),
    .out_ready    (map_ready),
    .out_data     (map_data),
    .out_last     (map_last),

    .amc_mode_i        (3'd1),
    .amc_mode_valid_i  (1'b1),

    .s_axi_aclk    (s_axi_aclk),
    .s_axi_aresetn (s_axi_aresetn),
    .s_axi_awaddr  (s_awaddr_map),
    .s_axi_awvalid (s_awvalid_map),
    .s_axi_awready (s_awready_map),
    .s_axi_wdata   (s_wdata_map),
    .s_axi_wstrb   (s_wstrb_map),
    .s_axi_wvalid  (s_wvalid_map),
    .s_axi_wready  (s_wready_map),
    .s_axi_bresp   (s_bresp_map),
    .s_axi_bvalid  (s_bvalid_map),
    .s_axi_bready  (s_bready_map),
    .s_axi_araddr  (s_araddr_map),
    .s_axi_arvalid (s_arvalid_map),
    .s_axi_arready (s_arready_map),
    .s_axi_rdata   (s_rdata_map),
    .s_axi_rresp   (s_rresp_map),
    .s_axi_rvalid  (s_rvalid_map),
    .s_axi_rready  (s_rready_map)
  );

  // Keep the pipe open for bring-up
  assign map_ready = 1'b1;

  // -----------------------------
  // Minimal PRBS reference model
  // -----------------------------
  function automatic [5:0] tapA(input [2:0] mode); case (mode)
    3'd0: tapA = 6'd6;  3'd1: tapA = 6'd14; 3'd2: tapA = 6'd22; default: tapA = 6'd30;
  endcase endfunction
  function automatic [5:0] tapB(input [2:0] mode); case (mode)
    3'd0: tapB = 6'd5;  3'd1: tapB = 6'd13; 3'd2: tapB = 6'd17; default: tapB = 6'd27;
  endcase endfunction
  function automatic bit fb_bit(input logic [30:0] s, input [2:0] mode);
    fb_bit = s[tapA(mode)] ^ s[tapB(mode)];
  endfunction
  function automatic bit prbs_next_bit(ref logic [30:0] s, input [2:0] mode);
    bit outb; outb = s[0]; s = {s[29:0], fb_bit(s, mode)}; return outb;
  endfunction
  function automatic [7:0] prbs_next_byte(ref logic [30:0] s, input [2:0] mode);
    reg [7:0] b; b = 8'h00; for (int i=0; i<8; i++) b[i] = prbs_next_bit(s, mode); return b;
  endfunction

  // -----------------------------
  // Simple checkers / monitors
  // -----------------------------
  // PRBS scoreboard state (SINGLE OWNER = this always_ff)
// Toggle PRBS_STRICT to 1 if you want bit-exact checking again.
localparam bit PRBS_STRICT = 0;

logic [30:0] ref_state;
logic [2:0]  prbs_mode;

// PRBS liveness
int          prbs_frames_seen;
int          prbs_bytes_total;
int          prbs_start_watch;
bit          prbs_started;
logic [7:0]  prbs_exp_byte;   // used only when PRBS_STRICT=1
bit          prbs_exp_last;   // used only when PRBS_STRICT=1
logic [7:0]  prbs_last_seen;  // liveness-only
int          prbs_same_cnt;   // liveness-only

// Scrambler change check
int          scr_equal_count;
bit          scr_seen_change;

// Mapper checks
bit          map_cfg_qpsk, map_cfg_bypass;
int          map_frames_seen;
int          map_same_count;
logic signed [15:0] gotI, gotQ, expI, expQ;
logic [7:0]         sb_bit_buf;
logic [3:0]         sb_bits_avail;
bit                 sb_last_pending;
bit                 need2;
int                 K;
bit                 b0_s, b1_s, okI_chk, okQ_chk, exp_last_chk;

// Phase control for resetting mapper frame counter (SINGLE OWNER = this always_ff)
int phase_id, prev_phase_id;

// PRBS liveness (+ optional strict checking). SINGLE OWNER of ref_state/prbs_mode.
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    prbs_started      <= 1'b0;
    prbs_start_watch  <= 0;
    prbs_frames_seen  <= 0;
    prbs_bytes_total  <= 0;
    ref_state         <= 31'd1;   // seed for strict mode
    prbs_mode         <= 3'd3;    // PRBS31 for strict mode
    prbs_last_seen    <= 8'h00;
    prbs_same_cnt     <= 0;
  end else begin
    // start-up liveness (did we ever handshake?)
    if (!prbs_started) begin
      prbs_start_watch <= prbs_start_watch + 1;
      if (prbs_valid && prbs_ready) prbs_started <= 1'b1;
      if (prbs_start_watch > 2000) $fatal(1, "[PRBS] No handshake within 2000 cycles after enable.");
    end

    if (prbs_valid && prbs_ready) begin
      if (PRBS_STRICT) begin
        // Strict bit-exact data/TLAST checking (disabled by default)
        prbs_exp_byte = prbs_next_byte(ref_state, prbs_mode);
        if (prbs_data !== prbs_exp_byte)
          $fatal(1, "[PRBS] Data mismatch @byte %0d: got 0x%02h exp 0x%02h (mode %0d)",
                 prbs_bytes_total, prbs_data, prbs_exp_byte, prbs_mode);

        if (BYTES_PER_FRAME > 0) begin
          prbs_exp_last = (((prbs_bytes_total + 1) % BYTES_PER_FRAME) == 0);
          if (prbs_last !== prbs_exp_last)
            $fatal(1, "[PRBS] TLAST mismatch @byte %0d: got=%0b exp=%0b",
                   prbs_bytes_total, prbs_last, prbs_exp_last);
        end
      end else begin
        // Liveness-only: ensure the stream isn't stuck at one byte
        if (prbs_bytes_total == 0) begin
          prbs_last_seen <= prbs_data;
          prbs_same_cnt  <= 0;
        end else if (prbs_data == prbs_last_seen) begin
          prbs_same_cnt <= prbs_same_cnt + 1;
          if (prbs_same_cnt > 64)
            $fatal(1, "[PRBS] Byte stream appears stuck at 0x%02h.", prbs_data);
        end else begin
          prbs_last_seen <= prbs_data;
          prbs_same_cnt  <= 0;
        end
      end

      // Frame count (for both modes)
      if (BYTES_PER_FRAME > 0 && prbs_last)
        prbs_frames_seen <= prbs_frames_seen + 1;

      prbs_bytes_total <= prbs_bytes_total + 1;
    end
  end
end


  // Scrambler monitor
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scr_equal_count <= 0;
      scr_seen_change <= 1'b0;
    end else if (scr_valid && scr_ready) begin
      if (scr_data !== prbs_data) scr_seen_change <= 1'b1;
      else                        scr_equal_count <= scr_equal_count + 1;
      if (!scr_seen_change && scr_equal_count > 64)
        $fatal(1, "[SCR] Output equals input for >64 accepted bytes; scrambler appears bypassed.");
    end
  end

  // Mapper scoreboard (+ frame counter reset via phase_id change)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sb_bit_buf      <= 8'h00;
      sb_bits_avail   <= 4'd0;
      sb_last_pending <= 1'b0;
      map_frames_seen <= 0;
      map_same_count  <= 0;
      prev_phase_id   <= 0;
    end else begin
      // Reset mapper frame counter on phase change (initial drives only phase_id)
      if (phase_id != prev_phase_id) begin
        map_frames_seen <= 0;
        prev_phase_id   <= phase_id;
      end

      if (scr_valid && scr_ready) begin
        sb_bit_buf      <= scr_data;
        sb_bits_avail   <= 4'd8;
        sb_last_pending <= prbs_last; // TLAST bypass
      end

      if (map_valid && map_ready) begin
        need2 = (!map_cfg_bypass && map_cfg_qpsk);
        K     = need2 ? 2 : 1;

        if (sb_bits_avail < K)
          $fatal(1, "[MAP] Bit buffer underflow (avail=%0d need=%0d).", sb_bits_avail, K);

        b0_s = sb_bit_buf[0];
        b1_s = need2 ? sb_bit_buf[1] : 1'b0;

        // Compute expected constellation point inline (no function call)
        if (map_cfg_bypass || !map_cfg_qpsk) begin
          // BPSK: I = ±AMP_BPSK (bit0), Q = 0
          expI = (b0_s == 1'b0) ? AMP_BPSK : -AMP_BPSK;
          expQ = 16'sd0;
        end else begin
          // QPSK Gray: 00:(+,+) 01:(-,+) 11:(-,-) 10:(+,-)
          unique case ({b1_s, b0_s})
            2'b00: begin expI =  AMP_QPSK; expQ =  AMP_QPSK; end
            2'b01: begin expI = -AMP_QPSK; expQ =  AMP_QPSK; end
            2'b11: begin expI = -AMP_QPSK; expQ = -AMP_QPSK; end
            default: begin expI =  AMP_QPSK; expQ = -AMP_QPSK; end // 2'b10
          endcase
        end


        gotI = $signed(map_data[31:16]);
        gotQ = $signed(map_data[15:0]);

        if (map_cfg_qpsk) begin
          okI_chk = (gotI==AMP_QPSK) || (gotI==-AMP_QPSK);
          okQ_chk = (gotQ==AMP_QPSK) || (gotQ==-AMP_QPSK);
          if (!(okI_chk && okQ_chk))
            $fatal(1, "[MAP] QPSK out of set: I=%0d Q=%0d (±%0d).", gotI, gotQ, AMP_QPSK);
        end else begin
          if (!(gotQ==16'sd0 && ((gotI==AMP_BPSK)||(gotI==-AMP_BPSK))))
            $fatal(1, "[MAP] BPSK out of set: I=%0d Q=%0d (±%0d, Q=0).", gotI, gotQ, AMP_BPSK);
        end

        if ((gotI !== expI) || (gotQ !== expQ))
          $fatal(1, "[MAP] I/Q mismatch: got I=%0d Q=%0d exp I=%0d Q=%0d (b0=%0d b1=%0d qpsk=%0d).",
                 gotI, gotQ, expI, expQ, b0_s, b1_s, map_cfg_qpsk);

        exp_last_chk = (sb_last_pending && (sb_bits_avail == K));
        if (map_last !== exp_last_chk)
          $fatal(1, "[MAP] TLAST mismatch: got=%0b exp=%0b (bits_avail=%0d K=%0d).",
                 map_last, exp_last_chk, sb_bits_avail, K);
        if (exp_last_chk) map_frames_seen <= map_frames_seen + 1;

        sb_bit_buf    <= sb_bit_buf >> K;
        sb_bits_avail <= sb_bits_avail - K;

        if ({gotI,gotQ} === map_data) map_same_count <= map_same_count + 1;
        else                          map_same_count <= 0;
        if (map_same_count > 128) $fatal(1, "[MAP] Symbols appear stuck.");
      end
    end
  end


  // -----------------------------
  // AXI-Lite writers (direct, no wrappers)
  // -----------------------------

  function automatic [31:0] prbs_ctrl_word(
    input bit        en,
    input [2:0]      mode,
    input bit        swreset,
    input bit        clear
  );
    reg [31:0] t; begin
      t = 32'd0;
      t[0]   = en;
      t[2]   = swreset;
      t[6:4] = mode;
      t[15]  = clear;
      return t;
    end
  endfunction

  function automatic [31:0] mapper_ctrl_word(
    input bit       en,
    input bit       byp,
    input bit       swr,
    input [2:0]     mode,
    input bit       amc_override
  );
    return {23'd0, amc_override, 1'b0, mode, swr, byp, en};
  endfunction

  // ---- PRBS AXI-Lite write (6-bit address) ----
  task automatic wr_prbs (
    input logic [5:0]  addr,
    input logic [31:0] data
  );
    // Drive address + data together (DUT expects AWVALID & WVALID same cycle)
    s_awaddr_prbs  = addr;
    s_awvalid_prbs = 1'b1;
    s_wdata_prbs   = data;
    s_wstrb_prbs   = 4'hF;
    s_wvalid_prbs  = 1'b1;
    s_bready_prbs  = 1'b1;

    // Wait for acceptance
    @(posedge clk);
    while (!(s_awready_prbs && s_wready_prbs)) @(posedge clk);

    // Deassert valids
    s_awvalid_prbs = 1'b0;
    s_wvalid_prbs  = 1'b0;

    // Complete BRESP
    @(posedge clk);
    while (!s_bvalid_prbs) @(posedge clk);
    s_bready_prbs  = 1'b0;
  endtask

  // ---- Mapper AXI-Lite write (8-bit address) ----
  task automatic wr_map (
    input logic [7:0]  addr,
    input logic [31:0] data
  );
    s_awaddr_map  = addr;
    s_awvalid_map = 1'b1;
    s_wdata_map   = data;
    s_wstrb_map   = 4'hF;
    s_wvalid_map  = 1'b1;
    s_bready_map  = 1'b1;

    @(posedge clk);
    while (!(s_awready_map && s_wready_map)) @(posedge clk);

    s_awvalid_map = 1'b0;
    s_wvalid_map  = 1'b0;

    @(posedge clk);
    while (!s_bvalid_map) @(posedge clk);
    s_bready_map  = 1'b0;
  endtask


  // -----------------------------
  // Test sequence (SINGLE OWNER of phase_id; does NOT drive ref_state/prbs_mode/map_frames_seen)
  // -----------------------------
  int timeout1;
  int timeout2;

  initial begin : main
    // Defaults on AXI-Lite
    s_awaddr_prbs=0; s_awvalid_prbs=0; s_wdata_prbs=0; s_wstrb_prbs=0; s_wvalid_prbs=0; s_bready_prbs=0;
    s_araddr_prbs=0; s_arvalid_prbs=0; s_rready_prbs=0;

    s_awaddr_map=0;  s_awvalid_map=0;  s_wdata_map=0;  s_wstrb_map=0;  s_wvalid_map=0;  s_bready_map=0;
    s_araddr_map=0;  s_arvalid_map=0;  s_rready_map=0;

    // Scrambler defaults
    scr_en      = 1'b0;  scr_bypass  = 1'b0;  scr_seed = 7'h5A;  scr_seed_wr = 1'b0;

    phase_id = 0;
    
    wait (rst_n);
    repeat (5) @(posedge clk);

    // --- Configure Mapper (QPSK) first so READY opens back through chain ---
    map_cfg_qpsk   = 1'b1;
    map_cfg_bypass = 1'b0;
    wr_map(8'h00, mapper_ctrl_word(1'b1, /*byp*/1'b0, /*swr*/1'b0, 3'd1, /*override*/1'b1));

    // --- Enable Scrambler and load seed (one-cycle pulse) ---
    scr_en      = 1'b1;
    scr_seed_wr = 1'b1; @(posedge clk); scr_seed_wr = 1'b0;

    // --- PRBS: SEED, FRMLEN=N, CTRL (ENABLE+SW_RESET+CLEAR) ---
    // NOTE: ref_state/prbs_mode are owned by their always_ff; they start at 1/PRBS31
    wr_prbs(6'h08, {1'b0, 31'd1});                       // SEED=1
    wr_prbs(6'h0C, {16'd0, BYTES_PER_FRAME[15:0]});      // frame length
    wr_prbs(6'h00, prbs_ctrl_word(1'b1, 3'd3, 1'b1, 1'b1)); // en + swreset + clear

    // ---- Phase 1: QPSK — wait NFRAMES mapper TLASTs ----
    phase_id = 1; // request counter clear in scoreboard
    timeout1 = 0;
    while (map_frames_seen < NFRAMES) begin
      @(posedge clk);
      timeout1++;
      if (timeout1 > 2000000) $fatal(1, "[TIMEOUT] QPSK phase did not complete.");
    end
    $display("[TB] QPSK phase complete: %0d frames.", map_frames_seen);

    // Small gap
    repeat (20) @(posedge clk);

    // --- Phase 2: BPSK ---
    map_cfg_qpsk   = 1'b0;
    map_cfg_bypass = 1'b0;
    wr_map(8'h00, mapper_ctrl_word(1'b1, /*byp*/1'b0, /*swr*/1'b0, 3'd0, /*override*/1'b1));
    phase_id = 2; // scoreboard clears its counter

    timeout2 = 0;
    while (map_frames_seen < NFRAMES) begin
      @(posedge clk);
      timeout2++;
      if (timeout2 > 2000000) $fatal(1, "[TIMEOUT] BPSK phase did not complete.");
    end
    $display("[TB] BPSK phase complete: %0d frames.", map_frames_seen);

    $display("[TB] PASS: PRBS->Scrambler->Mapper chain integrated OK.");
    #50 $finish;
  end

  // -----------------------------
  // Debug prints (first few handshakes)
  // -----------------------------
  int dbg_p, dbg_s, dbg_m;
  always @(posedge clk) if (rst_n && prbs_valid && prbs_ready && dbg_p<8) begin
    $display("[PRBS] 0x%02h%s", prbs_data, prbs_last ? " (TLAST)":""); dbg_p++;
  end
  always @(posedge clk) if (rst_n && scr_valid && scr_ready && dbg_s<8) begin
    $display("[SCR ] 0x%02h", scr_data); dbg_s++;
  end
  always @(posedge clk) if (rst_n && map_valid && map_ready && dbg_m<8) begin
    $display("[MAP ] I=%0d Q=%0d%s", $signed(map_data[31:16]), $signed(map_data[15:0]),
             map_last ? " (TLAST)" : ""); dbg_m++;
  end

endmodule

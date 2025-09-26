// tb/prbs_axi_stream_tb.sv
// Self-checking testbench for prbs_axi_stream.sv
// - Drives AXI4-Lite to configure DUT
// - Consumes AXI-Stream output with randomized back-pressure
// - Scoreboards vs a reference PRBS generator (bit-accurate)
// - Checks TLAST periodicity and seed semantics
//
// Run (xsim example):
//   vlog prbs_axi_stream.sv tb/prbs_axi_stream_tb.sv
//   vsim -c tb_prbs_axi_stream -do "run -all; quit"   (ModelSim)
// or with Vivado xsim:
//   xvlog prbs_axi_stream.sv tb/prbs_axi_stream_tb.sv
//   xelab tb_prbs_axi_stream -s tb
//   xsim tb -runall

`timescale 1ns/1ps

module tb_prbs_axi_stream;
  // Clocking
  logic clk = 0; always #4 clk = ~clk; // 125 MHz baseband
  logic rst_n = 0;

  // AXI-Lite
  logic [5:0]  s_axil_awaddr;
  logic        s_axil_awvalid;
  logic        s_axil_awready;
  logic [31:0] s_axil_wdata;
  logic [3:0]  s_axil_wstrb;
  logic        s_axil_wvalid;
  logic        s_axil_wready;
  logic [1:0]  s_axil_bresp;
  logic        s_axil_bvalid;
  logic        s_axil_bready;
  logic [5:0]  s_axil_araddr;
  logic        s_axil_arvalid;
  logic        s_axil_arready;
  logic [31:0] s_axil_rdata;
  logic [1:0]  s_axil_rresp;
  logic        s_axil_rvalid;
  logic        s_axil_rready;

  // AXIS out
  logic [7:0]  m_axis_tdata;
  logic        m_axis_tvalid;
  logic        m_axis_tready;
  logic        m_axis_tlast;

  // DUT
  prbs_axi_stream dut (
    .clk(clk), .rst_n(rst_n),
    .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
    .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast)
  );

  // -----------------------------
  // Simple AXI-Lite Master Tasks
  // -----------------------------
  localparam CTRL_ADDR   = 6'h00;
  localparam SEED_ADDR   = 6'h04;
  localparam FRMLEN_ADDR = 6'h08;
  localparam STATUS_ADDR = 6'h0C;

  task axil_write(input [5:0] addr, input [31:0] data);
    begin
      @(posedge clk);
      s_axil_awaddr  <= addr;
      s_axil_wdata   <= data;
      s_axil_wstrb   <= 4'hF;
      s_axil_awvalid <= 1'b1;
      s_axil_wvalid  <= 1'b1;
      do @(posedge clk); while (!(s_axil_awready && s_axil_wready));
      s_axil_awvalid <= 1'b0;
      s_axil_wvalid  <= 1'b0;
      s_axil_bready  <= 1'b1;
      do @(posedge clk); while (!s_axil_bvalid);
      s_axil_bready  <= 1'b0;
    end
  endtask

  task axil_read(input [5:0] addr, output [31:0] data);
    begin
      @(posedge clk);
      s_axil_araddr  <= addr;
      s_axil_arvalid <= 1'b1;
      do @(posedge clk); while (!s_axil_arready);
      s_axil_arvalid <= 1'b0;
      s_axil_rready  <= 1'b1;
      do @(posedge clk); while (!s_axil_rvalid);
      data = s_axil_rdata;
      s_axil_rready  <= 1'b0;
    end
  endtask

  // -----------------------------
  // Reference PRBS (bit-level)
  // -----------------------------
  typedef enum int {PRBS7=0, PRBS15=1, PRBS23=2, PRBS31=3} prbs_e;
  prbs_e poly_sel;
  int poly_len;
  int tap_a, tap_b; // 0-based indices

  function void resolve_poly(input prbs_e sel);
    case(sel)
      PRBS7 : begin poly_len=7;  tap_a=6-1; tap_b=5-1; end
      PRBS15: begin poly_len=15; tap_a=14-1; tap_b=13-1; end
      PRBS23: begin poly_len=23; tap_a=22-1; tap_b=17-1; end
      default:begin poly_len=31; tap_a=30-1; tap_b=27-1; end
    endcase
  endfunction

  function bit prbs_next_bit(ref bit [30:0] state);
    bit fb;
    fb = state[tap_a] ^ state[tap_b];
    prbs_next_bit = state[0]; // DUT uses lfsr[0] as emitted bit
    state = {state[29:0], fb};
  endfunction

  // Scoreboard / monitor
  bit [30:0] ref_state;
  int        bytes_checked;
  int        mismatches;
  int        expected_frame_len = 257; // will program FRMLEN to this

  // Random back-pressure
  bit rand_ready;
  always @(posedge clk) begin
    rand_ready <= ($urandom_range(0,9) < 7); // ~70% ready
  end
  assign m_axis_tready = rand_ready;

  // Stimulus
  initial begin
    // init AXI-Lite
    s_axil_awaddr=0; s_axil_awvalid=0; s_axil_wdata=0; s_axil_wstrb=0; s_axil_wvalid=0; s_axil_bready=0;
    s_axil_araddr=0; s_axil_arvalid=0; s_axil_rready=0;

    // Reset
    repeat (5) @(posedge clk);
    rst_n = 1'b1; // async deassert
    @(posedge clk);

    // Test 1: PRBS31, byte mode, TLAST enabled, random back-pressure
    poly_sel = PRBS31; resolve_poly(poly_sel);
    ref_state = 31'h1; // same default seed as DUT

    // Program CTRL: enable=0, poly_sel=PRBS31, pack_bytes=1, tlast_en=1
    axil_write(CTRL_ADDR, 32'((1<<5)|(1<<4)|(poly_sel<<1)|0));
    // Set frame length
    axil_write(FRMLEN_ADDR, expected_frame_len);

    // Ensure seed is 1 (same as default)
    axil_write(SEED_ADDR, 1);

    // Enable
    axil_write(CTRL_ADDR, 32'((1<<5)|(1<<4)|(poly_sel<<1)|1));

    bytes_checked = 0; mismatches = 0;

    fork
      begin : consume_and_check
        // Consume ~10 frames
        int total_bytes = expected_frame_len * 10;
        int byte_idx_in_frame = 0;
        bit [7:0] expected_byte;

        while (bytes_checked < total_bytes) begin
          @(posedge clk);
          if (m_axis_tvalid && m_axis_tready) begin
            // Build expected byte (little-endian within byte)
            expected_byte = '0;
            for (int b=0; b<8; b++) begin
              expected_byte[b] = prbs_next_bit(ref_state);
            end
            if (m_axis_tdata !== expected_byte) begin
              $display("[ERR] Byte mismatch @%0t: got=0x%02h exp=0x%02h", $time, m_axis_tdata, expected_byte);
              mismatches++;
            end
            // TLAST check
            byte_idx_in_frame++;
            if (byte_idx_in_frame == expected_frame_len) begin
              if (!m_axis_tlast) begin
                $fatal(1, "TLAST not asserted at end of frame (byte %0d)", byte_idx_in_frame);
              end
              byte_idx_in_frame = 0;
            end else begin
              if (m_axis_tlast) begin
                $fatal(1, "TLAST asserted early at byte %0d", byte_idx_in_frame);
              end
            end
            bytes_checked++;
          end
        end
      end
    join

    if (mismatches==0) $display("[OK] PRBS31 byte-packed stream matched golden across %0d bytes", bytes_checked);
    else               $fatal(1, "[FAIL] %0d mismatches detected", mismatches);

    // Test 2: Seed write while enabled should NOT take effect (policy)
    // Try to write a new seed mid-stream
    axil_write(SEED_ADDR, 32'h1234567);
    // Consume a few more bytes and ensure continuity (no jump)
    int keep_check = 64;
    mismatches = 0;
    for (int i=0; i<keep_check; i++) begin
      @(posedge clk);
      if (m_axis_tvalid && m_axis_tready) begin
        bit [7:0] exp_b = '0; for (int b=0;b<8;b++) exp_b[b] = prbs_next_bit(ref_state);
        if (m_axis_tdata !== exp_b) mismatches++;
      end else i = i - 1; // wait until transfer
    end
    if (mismatches==0) $display("[OK] Seed write while enabled had no effect (as specified)");
    else               $fatal(1, "[FAIL] Stream discontinuity after illegal seed write");

    // Test 3: Disable, write zero-seed (auto-fix), re-enable and confirm deterministic restart
    // Disable
    axil_write(CTRL_ADDR, 32'((1<<5)|(1<<4)|(poly_sel<<1)|0));
    // Zero seed
    axil_write(SEED_ADDR, 0);
    // Re-enable
    axil_write(CTRL_ADDR, 32'((1<<5)|(1<<4)|(poly_sel<<1)|1));

    ref_state = 31'h1; // zero auto-fixed to 1
    // Check next 128 bytes
    mismatches = 0;
    int checked=0;
    while (checked<128) begin
      @(posedge clk);
      if (m_axis_tvalid && m_axis_tready) begin
        bit [7:0] exp_b = '0; for (int b=0;b<8;b++) exp_b[b] = prbs_next_bit(ref_state);
        if (m_axis_tdata !== exp_b) mismatches++;
        checked++;
      end
    end
    if (mismatches==0) $display("[OK] Deterministic restart after zero-seed (auto-fixed)");
    else               $fatal(1, "[FAIL] Restart sequence mismatch");

    $display("All tests completed OK.");
    #50 $finish;
  end

endmodule

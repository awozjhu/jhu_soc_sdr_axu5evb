`timescale 1ns/1ps

module tb_bb_chain_wrapper_no_fec;

  // ------------------------------------------------------------
  // Clock / Reset
  // ------------------------------------------------------------
  localparam real FAST_CLK_PERIOD_NS = 4.0; // 250 MHz
  localparam real SLOW_CLK_PERIOD_NS = 10.0; // 100 MHz
  localparam int  FRAME_WORDS   = 1150; // words per frame in test

  logic clk_slow = 0;
  logic clk_fast = 0;
  always #(FAST_CLK_PERIOD_NS/2.0) clk_fast = ~clk_fast;
  always #(SLOW_CLK_PERIOD_NS/2.0) clk_slow = ~clk_slow;

  logic rst_n;
  initial begin
    rst_n = 1'b0;
    repeat (20) @(posedge clk_slow);
    rst_n = 1'b1;
  end

  // ------------------------------------------------------------
  // DUT interface signals
  // ------------------------------------------------------------

  // TX side (from wrapper)
  wire [31:0] tx_pkt_tdata;
  wire        tx_pkt_tvalid;
  wire        tx_pkt_tready;
  wire        tx_pkt_tlast;

  // PRBS monitor (from wrapper)
  wire [7:0]  prbs_mon_tdata;
  wire        prbs_mon_tvalid;
  wire        prbs_mon_tlast;
  wire        prbs_mon_tready; // output from DUT

  // RX side input into wrapper (from packet_rec)
  wire [31:0] rx_sym_tdata;
  wire        rx_sym_tvalid;
  wire        rx_sym_tlast;
  wire        rx_sym_tready;   // output from DUT

  // Slicer output monitor (from wrapper)
  wire [7:0]  rx_byte_tdata;
  wire        rx_byte_tvalid;
  wire        rx_byte_tlast;
  wire        rx_byte_tready;

  // ------------------------------------------------------------
  // Debug wires from bb_wrapper
  // ------------------------------------------------------------
  wire [31:0] dbg_map_out_tdata;
  wire        dbg_map_out_tvalid;
  wire        dbg_map_out_tready;
  wire        dbg_map_out_tlast;

  wire [31:0] dbg_de_out_tdata;
  wire        dbg_de_out_tvalid;
  wire        dbg_de_out_tready;
  wire        dbg_de_out_tlast;

  // wire [31:0] dbg_pi_tdata;
  // wire        dbg_pi_tvalid;
  // wire        dbg_pi_tready;
  // wire        dbg_pi_tlast;

  wire [31:0] dbg_dep_tdata;
  wire        dbg_dep_tvalid;
  wire        dbg_dep_tready;
  wire        dbg_dep_tlast;

  // wire [31:0] dbg_pc_tdata;
  // wire        dbg_pc_tvalid;
  // wire        dbg_pc_tready;
  // wire        dbg_pc_tlast;
  // wire        dbg_frame_start;

  wire [31:0] dbg_dd_out_tdata;
  wire        dbg_dd_out_tvalid;
  wire        dbg_dd_out_tready;
  wire        dbg_dd_out_tlast;

  wire [31:0] dbg_sl_in_tdata;
  wire        dbg_sl_in_tvalid;
  wire        dbg_sl_in_tready;
  wire        dbg_sl_in_tlast;

  // ------------------------------------------------------------
  // Baseband wrapper instantiation
  // ------------------------------------------------------------
  bb_chain_wrapper_no_fec #(
    .PREAMBLE_LEN (64),
    .USE_QPSK     (1)
  ) dut (
    .clk           (clk_slow),
    .rst_n         (rst_n),

    // TX out (to packet_send)
    // .tx_pkt_tdata     (tx_pkt_tdata),
    // .tx_pkt_tvalid    (tx_pkt_tvalid),
    // .tx_pkt_tready    (tx_pkt_tready),
    // .tx_pkt_tlast     (tx_pkt_tlast),

    .tx_pkt_tdata     (tx_pkt_tdata),
    .tx_pkt_tvalid    (tx_pkt_tvalid),
    .tx_pkt_tready    (tx_pkt_tready),
    .tx_pkt_tlast     (tx_pkt_tlast),

    // PRBS monitor
    .prbs_mon_tdata   (prbs_mon_tdata),
    .prbs_mon_tvalid  (prbs_mon_tvalid),
    .prbs_mon_tlast   (prbs_mon_tlast),
    .prbs_mon_tready  (prbs_mon_tready),

    // RX symbols in (from packet_rec)
    .rx_sym_tdata     (rx_sym_tdata),
    .rx_sym_tvalid    (rx_sym_tvalid),
    .rx_sym_tready    (rx_sym_tready),
    .rx_sym_tlast     (rx_sym_tlast),

    // Slicer output bytes
    .rx_byte_tdata    (rx_byte_tdata),
    .rx_byte_tvalid   (rx_byte_tvalid),
    .rx_byte_tlast    (rx_byte_tlast),
    .rx_byte_tready   (rx_byte_tready),

    // Debug outputs
    .dbg_map_out_tdata (dbg_map_out_tdata),
    .dbg_map_out_tvalid(dbg_map_out_tvalid),
    .dbg_map_out_tready(dbg_map_out_tready),
    .dbg_map_out_tlast (dbg_map_out_tlast),

    .dbg_de_out_tdata  (dbg_de_out_tdata),
    .dbg_de_out_tvalid (dbg_de_out_tvalid),
    .dbg_de_out_tready (dbg_de_out_tready),
    .dbg_de_out_tlast  (dbg_de_out_tlast),

    // .dbg_pi_tdata      (dbg_pi_tdata),
    // .dbg_pi_tvalid     (dbg_pi_tvalid),
    // .dbg_pi_tready     (dbg_pi_tready),
    // .dbg_pi_tlast      (dbg_pi_tlast),

    .dbg_dep_tdata     (dbg_dep_tdata),
    .dbg_dep_tvalid    (dbg_dep_tvalid),
    .dbg_dep_tready    (dbg_dep_tready),
    .dbg_dep_tlast     (dbg_dep_tlast),

    // .dbg_pc_tdata      (dbg_pc_tdata),
    // .dbg_pc_tvalid     (dbg_pc_tvalid),
    // .dbg_pc_tready     (dbg_pc_tready),
    // .dbg_pc_tlast      (dbg_pc_tlast),
    // .dbg_frame_start   (dbg_frame_start),

    .dbg_dd_out_tdata  (dbg_dd_out_tdata),
    .dbg_dd_out_tvalid (dbg_dd_out_tvalid),
    .dbg_dd_out_tready (dbg_dd_out_tready),
    .dbg_dd_out_tlast  (dbg_dd_out_tlast),

    .dbg_sl_in_tdata   (dbg_sl_in_tdata),
    .dbg_sl_in_tvalid  (dbg_sl_in_tvalid),
    .dbg_sl_in_tready  (dbg_sl_in_tready),
    .dbg_sl_in_tlast   (dbg_sl_in_tlast)
  );


// ------------------------------------------------------------
  // PRBS checker instantiation
  // ------------------------------------------------------------

  wire [31:0] byte_errs;
  wire [31:0] bit_errs;

axis_prbs_mon prbs_chk (
  .clk              (clk_slow),
  .rst_n            (rst_n),
  .enable           (1'b1),

  .s_axis_tdata     (rx_byte_tdata),
  .s_axis_tvalid    (rx_byte_tvalid),
  .s_axis_tready    (rx_byte_tready),            // leave open if you want always-ready
  .s_axis_tlast     (rx_byte_tlast),

  .expected_byte    (),
  .byte_error_count (byte_errs),
  .bit_error_count  (bit_errs)
);


// ------------------------------------------------------------
  // AXIS FIFO CDC for RX side (cross-clock from packet_rec to wrapper)
  // ------------------------------------------------------------

  wire [31:0] s_axis_tdata_tx ;
  wire        s_axis_tvalid_tx;
  wire        s_axis_tlast_tx ;
  wire        s_axis_tready_tx;  // output to packet_rec

  wire [31:0] m_axis_tdata_tx;
  wire        m_axis_tvalid_tx;
  wire        m_axis_tlast_tx;
  wire        m_axis_tready_tx; // input from wrapper


axis_data_fifo_cdc tx_cdc_fifo (
  .s_axis_aresetn(rst_n),  // input wire s_axis_aresetn
  .s_axis_aclk(clk_slow),        // input wire s_axis_aclk
  .s_axis_tvalid(tx_pkt_tvalid),    // input wire s_axis_tvalid
  .s_axis_tready(tx_pkt_tready ),    // output wire s_axis_tready
  .s_axis_tdata(tx_pkt_tdata),      // input wire [31 : 0] s_axis_tdata
  .s_axis_tlast(tx_pkt_tlast),      // input wire s_axis_tlast

  .m_axis_aclk(clk_fast),        // input wire m_axis_aclk
  .m_axis_tvalid(m_axis_tvalid_tx),    // output wire m_axis_tvalid
  .m_axis_tready(m_axis_tready_tx),    // input wire m_axis_tready
  .m_axis_tdata(m_axis_tdata_tx),      // output wire [31 : 0] m_axis_tdata
  .m_axis_tlast(m_axis_tlast_tx)      // output wire m_axis_tlast
);


  // ------------------------------------------------------------
  // packet_send instantiation (TX side)
  // ------------------------------------------------------------
  wire [31:0] ps_gt_tx_data;
  wire [3:0]  ps_gt_tx_ctrl;
  // wire        tx_packet_done;

  // packet_send_axis_in u_packet_send (
  //   .rst              (~rst_n),          // active-high reset
  //   .tx_clk           (clk_fast),
  //   .tx_packet_req    (1'b1),            // always request packets in TB
  //   .tx_packet_len    (FRAME_WORDS[15:0]),
  //   .tx_packet_done   (tx_packet_done),
  //   .tx_packet_type   (8'h01),

  //   // Drive from wrapper packetizer
  //   // .tx_packet_data   (m_axis_tdata_tx),
  //   // .tx_packet_data_rd(m_axis_tready_tx),   // tready back into wrapper

  //   .s_axis_tdata(m_axis_tdata_tx),
  //   .s_axis_tvalid(m_axis_tvalid_tx),
  //   .s_axis_tready(m_axis_tready_tx),
  //   .s_axis_tlast(m_axis_tlast_tx),

  //   .gt_tx_data       (ps_gt_tx_data),
  //   .gt_tx_ctrl       (ps_gt_tx_ctrl)
  // );

 // gt axis streamer instantiation
  gt_axis_streamer u_gt_streamer (
    .clk          (clk_fast),
    .rst          (~rst_n),  // or an OR of this & your VIO reset

    .s_axis_tdata (m_axis_tdata_tx),
    .s_axis_tvalid(m_axis_tvalid_tx),
    .s_axis_tready(m_axis_tready_tx),
    .s_axis_tlast (m_axis_tlast_tx),

    .gt_tx_data   (ps_gt_tx_data),   // to gt_example_top.tx0_data / tx1_data
    .gt_tx_ctrl   (ps_gt_tx_ctrl)  // to gt_example_top.tx0_kchar / tx1_kchar
  );


  // ------------------------------------------------------------
  // packet_rec instantiation (RX side)
  // ------------------------------------------------------------
  wire [31:0] rx_data_align;
  wire [3:0]  rx_ctrl_align;
  wire [31:0] packet_cnt_o;
  wire [31:0] error_packet_cnt_o;

  wire [31:0] pr_m_axis_tdata;
  wire        pr_m_axis_tvalid;
  wire        pr_m_axis_tready;
  wire        pr_m_axis_tlast;


// GT DATA WORD ALIGNMENT
word_align u_word_align_rx0 (
    .rst          (~rst_n),
    .rx_clk       (clk_fast),
    .gt_rx_data   (ps_gt_tx_data),
    .gt_rx_ctrl   (ps_gt_tx_ctrl),
    .rx_data_align(rx_data_align),
    .rx_ctrl_align(rx_ctrl_align)
);


// -----------------------------
// RX SHIM
// -----------------------------
wire [31:0] shim_tdata;
wire        shim_tvalid;
wire        shim_tlast;
wire        shim_tready;

rx_axis_shim u_rx_axis_shim (
    .rst        (~rst_n),
    .rx_clk     (clk_fast),

    .rx_data    (rx_data_align),
    .rx_ctrl    (rx_ctrl_align),

    .m_axis_tdata (shim_tdata),
    .m_axis_tvalid(shim_tvalid),
    .m_axis_tready(shim_tready),
    .m_axis_tlast (shim_tlast)
);


// wire rx_overflow;
// wire [31:0] fifo_dout;
// wire fifo_rd_en;
// wire fifo_empty;


// -----------------------------
// RX PAYLOAD FIFO (BRAM)
// -----------------------------
// rx_payload_fifo #(
//     .DATA_WIDTH(32),
//     .DEPTH(2048)
// ) u_rx_fifo (
//     .clk           (clk_fast),
//     .rst           (~rst_n),

//     .din           (shim_tdata),
//     .wr_en         (shim_tvalid),   // <—— CORRECT
//     .full          (),
//     .overflow_flag (rx_overflow),

//     .dout          (fifo_dout),
//     .rd_en         (fifo_rd_en),
//     .empty         (fifo_empty)
// );

// // -----------------------------
// // FIFO → RX CDC FIFO
// // -----------------------------
// assign fifo_rd_en     = (!fifo_empty) && pr_m_axis_tready;
// assign pr_m_axis_tvalid = !fifo_empty;
// assign pr_m_axis_tdata  = fifo_dout;


  wire [31:0] m_axis_tdata_rx;
  wire        m_axis_tvalid_rx;
  wire        m_axis_tlast_rx;
  wire        m_axis_tready_rx; // input from wrapper

axis_data_fifo_cdc rx_cdc_fifo (
  .s_axis_aresetn(rst_n),  // input wire s_axis_aresetn
  .s_axis_aclk(clk_fast),        // input wire s_axis_aclk
  .s_axis_tvalid(shim_tvalid),    // input wire s_axis_tvalid
  .s_axis_tready(shim_tready ),    // output wire s_axis_tready
  .s_axis_tdata(shim_tdata),      // input wire [31 : 0] s_axis_tdata
  .s_axis_tlast(1'b0),      // input wire s_axis_tlast
  // .s_axis_tlast(pr_m_axis_tlast),      // input wire s_axis_tlast

  .m_axis_aclk(clk_slow),        // input wire m_axis_aclk
  .m_axis_tvalid(m_axis_tvalid_rx),    // output wire m_axis_tvalid
  .m_axis_tready(m_axis_tready_rx),    // input wire m_axis_tready
  .m_axis_tdata(m_axis_tdata_rx),      // output wire [31 : 0] m_axis_tdata
  .m_axis_tlast(m_axis_tlast_rx)      // output wire m_axis_tlast
);

  // Connect packet_rec payload AXIS into wrapper RX AXIS
  // assign rx_sym_tdata   = pr_m_axis_tdata;
  // assign rx_sym_tvalid  = pr_m_axis_tvalid;
  // assign rx_sym_tlast   = pr_m_axis_tlast;
  // assign pr_m_axis_tready = 1'b1;  // always ready at packet_rec output


    // Connect packet_rec payload AXIS into wrapper RX AXIS
  assign rx_sym_tdata   = m_axis_tdata_rx;
  assign rx_sym_tvalid  = m_axis_tvalid_rx;
  assign rx_sym_tlast   = m_axis_tlast_rx;
  assign m_axis_tready_rx = rx_sym_tready;

  // Always ready to consume slicer output in this TB
  // assign rx_byte_tready = 1'b1;

  // ------------------------------------------------------------
  // CSV logging
  // ------------------------------------------------------------

  integer f_prbs, f_map, f_de, f_pi, f_txpkt;
  integer f_dep, f_pc, f_dd, f_sl_in, f_sl_out;

  integer fr_prbs,  bt_prbs;
  integer fr_map,   bt_map;
  integer fr_de,    bt_de;
  integer fr_pi,    bt_pi;
  integer fr_tx,    bt_tx;
  integer fr_dep,   bt_dep;
  integer fr_pc,    bt_pc;
  integer fr_dd,    bt_dd;
  integer fr_slin,  bt_slin;
  integer fr_slout, bt_slout;

  initial begin
    f_prbs    = $fopen("prbs.csv",             "w");
    f_map     = $fopen("mapper_out.csv",       "w");
    f_de      = $fopen("diff_enc_out.csv",     "w");
    f_pi      = $fopen("preamble_ins_out.csv", "w");
    f_txpkt   = $fopen("tx_pkt.csv",           "w");
    f_dep     = $fopen("depacketizer_out.csv", "w");
    f_pc      = $fopen("pcorr_out.csv",        "w");
    f_dd      = $fopen("diff_dec_out.csv",     "w");
    f_sl_in   = $fopen("slicer_in.csv",        "w");
    f_sl_out  = $fopen("slicer_out.csv",       "w");

    $fdisplay(f_prbs,   "time_ns,frame_idx,beat_idx,tvalid,tready,tlast,data_hex");
    $fdisplay(f_map,    "time_ns,frame_idx,beat_idx,tvalid,tready,tlast,data_hex");
    $fdisplay(f_de,     "time_ns,frame_idx,beat_idx,tvalid,tready,tlast,data_hex");
    $fdisplay(f_pi,     "time_ns,frame_idx,beat_idx,tvalid,tready,tlast,data_hex");
    $fdisplay(f_txpkt,  "time_ns,frame_idx,beat_idx,tvalid,tready,tlast,data_hex");
    $fdisplay(f_dep,    "time_ns,frame_idx,beat_idx,tvalid,tready,tlast,data_hex");
    $fdisplay(f_pc,     "time_ns,frame_idx,beat_idx,tvalid,tready,tlast,data_hex");
    $fdisplay(f_dd,     "time_ns,frame_idx,beat_idx,tvalid,tready,tlast,data_hex");
    $fdisplay(f_sl_in,  "time_ns,frame_idx,beat_idx,tvalid,tready,tlast,data_hex");
    $fdisplay(f_sl_out, "time_ns,frame_idx,beat_idx,tvalid,tready,tlast,data_hex");

    fr_prbs  = 0; bt_prbs  = 0;
    fr_map   = 0; bt_map   = 0;
    fr_de    = 0; bt_de    = 0;
    fr_pi    = 0; bt_pi    = 0;
    fr_tx    = 0; bt_tx    = 0;
    fr_dep   = 0; bt_dep   = 0;
    fr_pc    = 0; bt_pc    = 0;
    fr_dd    = 0; bt_dd    = 0;
    fr_slin  = 0; bt_slin  = 0;
    fr_slout = 0; bt_slout = 0;
  end

  // PRBS (8-bit -> pad to 32)
  always @(posedge clk_slow) begin
    if (rst_n && prbs_mon_tvalid && prbs_mon_tready) begin
      $fdisplay(f_prbs, "%0t,%0d,%0d,%0d,%0d,%0d,%08h",
                $time, fr_prbs, bt_prbs,
                prbs_mon_tvalid, prbs_mon_tready, prbs_mon_tlast,
                {24'h0, prbs_mon_tdata});
      bt_prbs <= bt_prbs + 1;
      if (prbs_mon_tlast) begin
        fr_prbs <= fr_prbs + 1;
        bt_prbs <= 0;
      end
    end
  end

  // Mapper output
  always @(posedge clk_slow) begin
    if (rst_n && dbg_map_out_tvalid && dbg_map_out_tready) begin
      $fdisplay(f_map, "%0t,%0d,%0d,%0d,%0d,%0d,%08h",
                $time, fr_map, bt_map,
                dbg_map_out_tvalid, dbg_map_out_tready, dbg_map_out_tlast,
                dbg_map_out_tdata);
      bt_map <= bt_map + 1;
      if (dbg_map_out_tlast) begin
        fr_map <= fr_map + 1;
        bt_map <= 0;
      end
    end
  end

  // Diff encoder output
  always @(posedge clk_slow) begin
    if (rst_n && dbg_de_out_tvalid && dbg_de_out_tready) begin
      $fdisplay(f_de, "%0t,%0d,%0d,%0d,%0d,%0d,%08h",
                $time, fr_de, bt_de,
                dbg_de_out_tvalid, dbg_de_out_tready, dbg_de_out_tlast,
                dbg_de_out_tdata);
      bt_de <= bt_de + 1;
      if (dbg_de_out_tlast) begin
        fr_de <= fr_de + 1;
        bt_de <= 0;
      end
    end
  end

  // Preamble inserter output
  // always @(posedge clk_slow) begin
  //   if (rst_n && dbg_pi_tvalid && dbg_pi_tready) begin
  //     $fdisplay(f_pi, "%0t,%0d,%0d,%0d,%0d,%0d,%08h",
  //               $time, fr_pi, bt_pi,
  //               dbg_pi_tvalid, dbg_pi_tready, dbg_pi_tlast,
  //               dbg_pi_tdata);
  //     bt_pi <= bt_pi + 1;
  //     if (dbg_pi_tlast) begin
  //       fr_pi <= fr_pi + 1;
  //       bt_pi <= 0;
  //     end
  //   end
  // end

  // TX packetizer output
  always @(posedge clk_slow) begin
    if (rst_n && tx_pkt_tvalid && tx_pkt_tready) begin
      $fdisplay(f_txpkt, "%0t,%0d,%0d,%0d,%0d,%0d,%08h",
                $time, fr_tx, bt_tx,
                tx_pkt_tvalid, tx_pkt_tready, tx_pkt_tlast,
                tx_pkt_tdata);
      bt_tx <= bt_tx + 1;
      if (tx_pkt_tlast) begin
        fr_tx <= fr_tx + 1;
        bt_tx <= 0;
      end
    end
  end

  // Depacketizer output
  always @(posedge clk_slow) begin
    if (rst_n && dbg_dep_tvalid && dbg_dep_tready) begin
      $fdisplay(f_dep, "%0t,%0d,%0d,%0d,%0d,%0d,%08h",
                $time, fr_dep, bt_dep,
                dbg_dep_tvalid, dbg_dep_tready, dbg_dep_tlast,
                dbg_dep_tdata);
      bt_dep <= bt_dep + 1;
      if (dbg_dep_tlast) begin
        fr_dep <= fr_dep + 1;
        bt_dep <= 0;
      end
    end
  end

  // Preamble correlator output
  // always @(posedge clk_slow) begin
  //   if (rst_n && dbg_pc_tvalid && dbg_pc_tready) begin
  //     $fdisplay(f_pc, "%0t,%0d,%0d,%0d,%0d,%0d,%08h",
  //               $time, fr_pc, bt_pc,
  //               dbg_pc_tvalid, dbg_pc_tready, dbg_pc_tlast,
  //               dbg_pc_tdata);
  //     bt_pc <= bt_pc + 1;
  //     if (dbg_pc_tlast) begin
  //       fr_pc <= fr_pc + 1;
  //       bt_pc <= 0;
  //     end
  //   end
  // end

  // Diff decoder output
  always @(posedge clk_slow) begin
    if (rst_n && dbg_dd_out_tvalid && dbg_dd_out_tready) begin
      $fdisplay(f_dd, "%0t,%0d,%0d,%0d,%0d,%0d,%08h",
                $time, fr_dd, bt_dd,
                dbg_dd_out_tvalid, dbg_dd_out_tready, dbg_dd_out_tlast,
                dbg_dd_out_tdata);
      bt_dd <= bt_dd + 1;
      if (dbg_dd_out_tlast) begin
        fr_dd <= fr_dd + 1;
        bt_dd <= 0;
      end
    end
  end

  // Slicer input
  always @(posedge clk_slow) begin
    if (rst_n && dbg_sl_in_tvalid && dbg_sl_in_tready) begin
      $fdisplay(f_sl_in, "%0t,%0d,%0d,%0d,%0d,%0d,%08h",
                $time, fr_slin, bt_slin,
                dbg_sl_in_tvalid, dbg_sl_in_tready, dbg_sl_in_tlast,
                dbg_sl_in_tdata);
      bt_slin <= bt_slin + 1;
      if (dbg_sl_in_tlast) begin
        fr_slin <= fr_slin + 1;
        bt_slin <= 0;
      end
    end
  end

  // Slicer output (8-bit -> pad to 32)
  always @(posedge clk_slow) begin
    if (rst_n && rx_byte_tvalid && rx_byte_tready) begin
      $fdisplay(f_sl_out, "%0t,%0d,%0d,%0d,%0d,%0d,%08h",
                $time, fr_slout, bt_slout,
                rx_byte_tvalid, rx_byte_tready, rx_byte_tlast,
                {24'h0, rx_byte_tdata});
      bt_slout <= bt_slout + 1;
      if (rx_byte_tlast) begin
        fr_slout <= fr_slout + 1;
        bt_slout <= 0;
      end
    end
  end

  // ------------------------------------------------------------
  // Wave dump + finish
  // ------------------------------------------------------------
  initial begin
    $dumpfile("tb_bb_chain_wrapper_no_fec.vcd");
    $dumpvars(0, tb_bb_chain_wrapper_no_fec);

    #(200_000); // 200 us at 250 MHz
    $display("[%0t] Simulation finished", $time);

    $fclose(f_prbs);
    $fclose(f_map);
    $fclose(f_de);
    $fclose(f_pi);
    $fclose(f_txpkt);
    $fclose(f_dep);
    $fclose(f_pc);
    $fclose(f_dd);
    $fclose(f_sl_in);
    $fclose(f_sl_out);

    $finish;
  end

endmodule

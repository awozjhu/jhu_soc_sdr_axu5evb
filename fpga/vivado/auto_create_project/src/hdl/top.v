`timescale 1ns / 1ps
module top 
(
    
	input         sys_clk_p,
    input         sys_clk_n,
    output [0:0]  tx_disable,
    input         mgtrefclk_n,
    input         mgtrefclk_p,    
    input [1:0]   RXN_IN,
    input [1:0]   RXP_IN,
    output[1:0]   TXN_OUT,
    output[1:0]   TXP_OUT
);

wire 		tx0_clk;
wire 		gt0_txfsmresetdone;
wire 		gt0_rxfsmresetdone;
wire[31:0] 	tx0_data;
wire[3:0] 	tx0_kchar;
wire 		tx1_clk;
wire[31:0] 	tx1_data;
wire[3:0] 	tx1_kchar; 

wire 		rx0_clk;
wire[31:0] 	rx0_data;
wire[3:0] 	rx0_kchar;
wire 		rx1_clk;
wire[31:0] 	rx1_data;
wire[3:0] 	rx1_kchar; 


wire [31:0] bb_rx_axis_tdata ;
wire        bb_rx_axis_tvalid;
wire        bb_rx_axis_tlast ;
wire        bb_rx_axis_tready; 

wire [31:0] rx_axis_tdata ;
wire        rx_axis_tvalid;
wire        rx_axis_tlast ;
wire        rx_axis_tready; 


wire[31:0] 	data_tx;
wire[3:0] 	data_ctrl;
reg[7:0] 	cnt;
wire 		tx_packet_data_rd;
wire 		rx_clk;

wire sys_clk;

assign tx_disable = 1'b0 ;

assign rx_clk 	= rx0_clk;
assign tx0_data = data_tx;
assign tx0_kchar = data_ctrl;
assign tx1_data = data_tx;
assign tx1_kchar = data_ctrl;

	
always @ (posedge tx0_clk)
begin
    if(tx_packet_data_rd)
        cnt <= cnt + 8'd1;
    else
        cnt <= 8'd0;
end

IBUFGDS sys_clk_ibufgds
(
	.O  (sys_clk),           //200mhz
	.I  (sys_clk_p),
	.IB (sys_clk_n)
);


wire gt0_txfsmresetdone_w;
reset_0 tx_reset_m0 
(
   .slowest_sync_clk(tx0_clk),          // input wire slowest_sync_clk
   .ext_reset_in(gt0_txfsmresetdone),                  // input wire ext_reset_in
   .aux_reset_in(1'b0),                  // input wire aux_reset_in
   .mb_debug_sys_rst(1'b0),          // input wire mb_debug_sys_rst
   .dcm_locked(1'b1),                      // input wire dcm_locked
   .mb_reset(),                          // output wire mb_reset
   .bus_struct_reset(),          // output wire [0 : 0] bus_struct_reset
   .peripheral_reset(gt0_txfsmresetdone_w),          // output wire [0 : 0] peripheral_reset
   .interconnect_aresetn(),  // output wire [0 : 0] interconnect_aresetn
   .peripheral_aresetn()      // output wire [0 : 0] peripheral_aresetn
 );
 
 wire gt0_rxfsmresetdone_w;
reset_0 rx_reset_m0 
(
   .slowest_sync_clk(rx_clk),          // input wire slowest_sync_clk
   .ext_reset_in(gt0_rxfsmresetdone),                  // input wire ext_reset_in
   .aux_reset_in(1'b0),                  // input wire aux_reset_in
   .mb_debug_sys_rst(1'b0),          // input wire mb_debug_sys_rst
   .dcm_locked(1'b1),                      // input wire dcm_locked
   .mb_reset(),                          // output wire mb_reset
   .bus_struct_reset(),          // output wire [0 : 0] bus_struct_reset
   .peripheral_reset(gt0_rxfsmresetdone_w),          // output wire [0 : 0] peripheral_reset
   .interconnect_aresetn(),  // output wire [0 : 0] interconnect_aresetn
   .peripheral_aresetn()      // output wire [0 : 0] peripheral_aresetn
 );
 
wire clk_100Mhz;
sys_clock sys_clock_m0
(
   .clk_in1(sys_clk),
   .clk_out1(clk_100Mhz),  
   .locked()  

);     
 

// DEGUG VIO INSTANCE
wire vio_reset;
wire bb_rst_n;

// vio control knobs
wire [8:0] err_thresh;

// Using VIO for debug/manual reset control
vio_debug debug_vio_inst (
.clk (tx0_clk)
,.probe_in0 (1'b0)
,.probe_out0 (vio_reset)
,.probe_out1 (err_thresh)
);

// Baseband reset from VIO 
assign bb_rst_n = vio_reset; // hold in reset until vio releases


// ------------------------------------------------------------
// Baseband chain wrapper (TX and RX interface)
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

  // Slicer input monitor (from diff decoder)
  wire [31:0] rx_sl_in_tdata;
  wire        rx_sl_in_tvalid;
  wire        rx_sl_in_tready;
  wire        rx_sl_in_tlast;

  // Slicer output monitor (from wrapper)
  wire [7:0]  rx_byte_tdata;
  wire        rx_byte_tvalid;
  wire        rx_byte_tlast;
  wire        rx_byte_tready;

//   assign rx_byte_tready  = 1'b1; // slicer always ready to accept data

// ------------------------------------------------------------
// PRBS checker instantiation
// ------------------------------------------------------------

  wire [31:0] byte_errs;
  wire [31:0] bit_errs;

axis_prbs_mon prbs_chk (
  .clk              (clk_100Mhz),
  .rst_n            (bb_rst_n),
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
// Baseband wrapper instantiation
// ------------------------------------------------------------
  bb_chain_wrapper_no_fec #(
    .PREAMBLE_LEN (64),
    .USE_QPSK     (1)
  ) dut (
    .clk           (clk_100Mhz),
    .rst_n         (bb_rst_n),

    // control inputs 
    .err_thresh         (err_thresh),

    ///////////// TX out (to tx axis streamer)
    .tx_pkt_tdata     (tx_pkt_tdata),
    .tx_pkt_tvalid    (tx_pkt_tvalid),
    .tx_pkt_tready    (tx_pkt_tready),
    .tx_pkt_tlast     (tx_pkt_tlast),

    // PRBS monitor
    .prbs_mon_tdata   (prbs_mon_tdata),
    .prbs_mon_tvalid  (prbs_mon_tvalid),
    .prbs_mon_tlast   (prbs_mon_tlast),
    .prbs_mon_tready  (prbs_mon_tready),

    ///////////// RX symbols in (from rx axis shim)
    .rx_sym_tdata     (rx_axis_tdata),
    .rx_sym_tvalid    (rx_axis_tvalid),
    .rx_sym_tready    (rx_axis_tready),
    .rx_sym_tlast     (rx_axis_tlast),

    // Slicer output bytes
    .rx_byte_tdata    (rx_byte_tdata),
    .rx_byte_tvalid   (rx_byte_tvalid),
    .rx_byte_tlast    (rx_byte_tlast),
    .rx_byte_tready   (rx_byte_tready),

    // Debug outputs
    .dbg_map_out_tdata (),
    .dbg_map_out_tvalid(),
    .dbg_map_out_tready(),
    .dbg_map_out_tlast (),

    .dbg_de_out_tdata  (),
    .dbg_de_out_tvalid (),
    .dbg_de_out_tready (),
    .dbg_de_out_tlast  (),

    // .dbg_pi_tdata      (),
    // .dbg_pi_tvalid     (),
    // .dbg_pi_tready     (),
    // .dbg_pi_tlast      (),

    .dbg_dep_tdata     (),
    .dbg_dep_tvalid    (),
    .dbg_dep_tready    (),
    .dbg_dep_tlast     (),

    // .dbg_pc_tdata      (),
    // .dbg_pc_tvalid     (),
    // .dbg_pc_tready     (),
    // .dbg_pc_tlast      (),
    // .dbg_frame_start   (),

    .dbg_dd_out_tdata  (),
    .dbg_dd_out_tvalid (),
    .dbg_dd_out_tready (),
    .dbg_dd_out_tlast  (),

    .dbg_sl_in_tdata   (rx_sl_in_tdata),
    .dbg_sl_in_tvalid  (rx_sl_in_tvalid),
    .dbg_sl_in_tready  (rx_sl_in_tready),
    .dbg_sl_in_tlast   (rx_sl_in_tlast)
  );

// -------------------------------------------------------------------
// TX DATA PATH (to GT from baseband chain)
// -------------------------------------------------------------------
// Baseband TX chain wrapper (PRBS -> mapper -> diff enc -> tx_packetizer)

  wire [31:0] s_axis_tdata_tx ;
  wire        s_axis_tvalid_tx;
  wire        s_axis_tlast_tx ;
  wire        s_axis_tready_tx;  // output to packet_rec

  wire [31:0] m_axis_tdata_tx;
  wire        m_axis_tvalid_tx;
  wire        m_axis_tlast_tx;
  wire        m_axis_tready_tx; // input from wrapper

 // AXIS FIFO CDC for TX side (cross-clock from wrapper to gt streamer)
axis_data_fifo_cdc tx_cdc_fifo (
  .s_axis_aresetn(bb_rst_n),  // input wire s_axis_aresetn
  .s_axis_aclk(clk_100Mhz),        // input wire s_axis_aclk
  .s_axis_tvalid(tx_pkt_tvalid),    // input wire s_axis_tvalid
  .s_axis_tready(tx_pkt_tready ),    // output wire s_axis_tready
  .s_axis_tdata(tx_pkt_tdata),      // input wire [31 : 0] s_axis_tdata
  .s_axis_tlast(tx_pkt_tlast),      // input wire s_axis_tlast

  .m_axis_aclk(tx0_clk),        // input wire m_axis_aclk
  .m_axis_tvalid(m_axis_tvalid_tx),    // output wire m_axis_tvalid
  .m_axis_tready(m_axis_tready_tx),    // input wire m_axis_tready
  .m_axis_tdata(m_axis_tdata_tx),      // output wire [31 : 0] m_axis_tdata
  .m_axis_tlast(m_axis_tlast_tx)      // output wire m_axis_tlast
);

 // gt axis streamer instantiation
  gt_axis_streamer u_gt_streamer (
    .clk          (tx0_clk),
    .rst          (gt0_txfsmresetdone_w),  // or an OR of this & your VIO reset

    // Drive from wrapper packetizer
    .s_axis_tdata (m_axis_tdata_tx),
    .s_axis_tvalid(m_axis_tvalid_tx),
    .s_axis_tready(m_axis_tready_tx),
    .s_axis_tlast (m_axis_tlast_tx),

    .gt_tx_data   (data_tx),   // to gt_example_top.tx0_data / tx1_data
    .gt_tx_ctrl   (data_ctrl)  // to gt_example_top.tx0_kchar / tx1_kchar
  );


 // -------------------------------------------------------------------
 // RX DATA PATH (from GT to baseband chain)
 // -------------------------------------------------------------------

wire[31:0] rx0_data_align;
wire[3:0]  rx0_ctrl_align;

// GT DATA WORD ALIGNMENT
word_align u_word_align_rx0 (
    .rst          (gt0_rxfsmresetdone_w),
    .rx_clk       (rx_clk),
    .gt_rx_data   (rx0_data),
    .gt_rx_ctrl   (rx0_kchar),
    .rx_data_align(rx0_data_align),
    .rx_ctrl_align(rx0_ctrl_align)
);

// -----------------------------
// RX SHIM
// -----------------------------
wire [31:0] shim_tdata;
wire        shim_tvalid;
wire        shim_tlast;
wire        shim_tready;

rx_axis_shim u_rx_axis_shim (
    .rst        (gt0_rxfsmresetdone_w),
    .rx_clk     (rx_clk),

    .rx_data    (rx0_data_align),
    .rx_ctrl    (rx0_ctrl_align),

    .m_axis_tdata (shim_tdata),
    .m_axis_tvalid(shim_tvalid),
    .m_axis_tready(shim_tready),
    .m_axis_tlast (shim_tlast)
);

// RX FIFO CDC
axis_data_fifo_cdc rx_cdc_fifo (
//   .s_axis_aresetn(~gt0_rxfsmresetdone_w),  // input wire s_axis_aresetn
  .s_axis_aresetn(bb_rst_n),  // input wire s_axis_aresetn
  .s_axis_aclk(rx_clk),        // input wire s_axis_aclk
  .s_axis_tvalid(shim_tvalid),    // input wire s_axis_tvalid
  .s_axis_tready(shim_tready),    // output wire s_axis_tready
  .s_axis_tdata(shim_tdata),      // input wire [31 : 0] s_axis_tdata
  .s_axis_tlast(1'b0),      // input wire s_axis_tlast

  .m_axis_aclk(clk_100Mhz),        // input wire m_axis_aclk
  .m_axis_tvalid(rx_axis_tvalid),    // output wire m_axis_tvalid
  .m_axis_tready(rx_axis_tready),    // input wire m_axis_tready
  .m_axis_tdata(rx_axis_tdata),      // output wire [31 : 0] m_axis_tdata
  .m_axis_tlast(rx_axis_tlast)      // output wire m_axis_tlast
);

//-----------------------------------------------------------------------//
/////////////////////////// ILAs for debugging ////////////////////////////
//-----------------------------------------------------------------------//

// ILA Fast Clock (RX GT interface)
ila_0 gt_ila(
    .clk(rx_clk),
    .probe0(m_axis_tdata_tx), // 32 bit TX CDC fifo output
    .probe1({29'b0, m_axis_tlast_tx, m_axis_tready_tx, m_axis_tvalid_tx}), // 32 bit TX CDC fifo output
    .probe2(data_tx), // 32 bit streamer output
    .probe3(data_ctrl), // 4 bit streamer output
	.probe4(rx_axis_tdata), // 32 bit rx payload fifo output
    .probe5({30'b0, rx_axis_tready, rx_axis_tvalid} ), // 32 bit rx payload fifo output
    .probe6(shim_tdata), // 32 bit shim output
    .probe7({2'b0, shim_tready, shim_tvalid }), // 4 bit shim output
	.probe8(rx0_data), // 32 bit
	.probe9(rx0_data_align), // 32 bit
    .probe10(rx0_kchar), // 4 bit
	.probe11(rx0_ctrl_align) // 4 bit

);   

// ILA PRBS Data (TX end of baseband chain)
ila_1 tx_ila(
    .clk(clk_100Mhz),
    .probe0(prbs_mon_tdata), // 8 bit
    .probe1(prbs_mon_tvalid),
    .probe2(prbs_mon_tlast),
    .probe3(8'b0), // 8 bit
	.probe4(prbs_mon_tready),
    // 1 bit TX CDC FIFO ready output
    .probe5(tx_pkt_tready)
);  

// ILA Slicer Data (RX end of baseband chain)
ila_2 rx_ila(
    .clk(clk_100Mhz),
    .probe0(rx_byte_tdata), // 8 bit
    .probe1(rx_byte_tvalid),
    .probe2(rx_byte_tready),
    .probe3(rx_byte_tlast),
    // 4 bit misc. 
    .probe4(4'b0)
);  


// ILA Slicer Input Data (from diff decoder) will capture the raw symbols for writting to file
ila_3 rx_sym_capture(
    .clk(clk_100Mhz),
    .probe0(rx_sl_in_tdata), // 32 bit
    .probe1(rx_sl_in_tvalid),
    .probe2(rx_sl_in_tready),
    .probe3(rx_sl_in_tlast),
    // 4 bit misc. 
    .probe4(4'b0)
);  

// ILA Error Counts
ila_4 error_counts(
    .clk(clk_100Mhz),
    .probe0(byte_errs), // 32 bit
    .probe1(32'b0),
    .probe2(32'b0),
    .probe3(32'b0)
);  

// -------------------------------------------------------------------
// GT EXAMPLE (from Xilinx) TOP INSTANCE
// -------------------------------------------------------------------
gt_example_top gt_exdes_m0
    (
	
    .tx0_clk(tx0_clk),
    .gt0_txfsmresetdone(gt0_txfsmresetdone),
    .gt0_rxfsmresetdone(gt0_rxfsmresetdone),
    .tx0_data	(tx0_data),
    .tx0_kchar	(tx0_kchar),   
    .rx0_clk	(rx0_clk),
    .rx0_data	(rx0_data),
    .rx0_kchar	(rx0_kchar),

    .gt1_txfsmresetdone(),
    .gt1_rxfsmresetdone(),
    .tx1_data	(tx1_data),
    .tx1_kchar	(tx1_kchar),   
    .rx1_clk	(rx1_clk),
    .rx1_data	(rx1_data),
    .rx1_kchar	(rx1_kchar),   
                         
    .mgtrefclk_n(mgtrefclk_n),
    .mgtrefclk_p(mgtrefclk_p),
	.hb_gtwiz_reset_clk_freerun_in(sys_clk),
	.hb_gtwiz_reset_all_in(1'b0),
    .RXN_IN(RXN_IN),
    .RXP_IN(RXP_IN),
    .TXN_OUT(TXN_OUT),
    .TXP_OUT(TXP_OUT)
);
    
        
endmodule

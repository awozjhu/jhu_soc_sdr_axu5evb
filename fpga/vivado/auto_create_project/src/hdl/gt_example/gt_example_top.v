//------------------------------------------------------------------------------
//  (c) Copyright 2013-2018 Xilinx, Inc. All rights reserved.
//
//  This file contains confidential and proprietary information
//  of Xilinx, Inc. and is protected under U.S. and
//  international copyright and other intellectual property
//  laws.
//
//  DISCLAIMER
//  This disclaimer is not a license and does not grant any
//  rights to the materials distributed herewith. Except as
//  otherwise provided in a valid license issued to you by
//  Xilinx, and to the maximum extent permitted by applicable
//  law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
//  WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
//  AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
//  BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
//  INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
//  (2) Xilinx shall not be liable (whether in contract or tort,
//  including negligence, or under any other theory of
//  liability) for any loss or damage of any kind or nature
//  related to, arising under or in connection with these
//  materials, including for any direct, or any indirect,
//  special, incidental, or consequential loss or damage
//  (including loss of data, profits, goodwill, or any type of
//  loss or damage suffered as a result of any action brought
//  by a third party) even if such damage or loss was
//  reasonably foreseeable or Xilinx had been advised of the
//  possibility of the same.
//
//  CRITICAL APPLICATIONS
//  Xilinx products are not designed or intended to be fail-
//  safe, or for use in any application requiring fail-safe
//  performance, such as life-support or safety devices or
//  systems, Class III medical devices, nuclear facilities,
//  applications related to the deployment of airbags, or any
//  other applications that could lead to death, personal
//  injury, or severe property or environmental damage
//  (individually and collectively, "Critical
//  Applications"). Customer assumes the sole risk and
//  liability of any use of Xilinx products in Critical
//  Applications, subject only to applicable laws and
//  regulations governing limitations on product liability.
//
//  THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
//  PART OF THIS FILE AT ALL TIMES.
//------------------------------------------------------------------------------


`timescale 1ps/1ps

// =====================================================================================================================
// This example design top module instantiates the example design wrapper; slices vectored ports for per-channel
// assignment; and instantiates example resources such as buffers, pattern generators, and pattern checkers for core
// demonstration purposes
// =====================================================================================================================

module gt_example_top (

    // Differential reference clock inputs
input  wire mgtrefclk_p,
input  wire mgtrefclk_n,

//modify

input  wire [1:0]   RXN_IN,
input  wire [1:0]   RXP_IN,
output wire [1:0]   TXN_OUT,
output wire [1:0]   TXP_OUT, 

output 			tx0_clk,
output 			gt0_txfsmresetdone,
output 			gt0_rxfsmresetdone,
input[31:0] 	tx0_data,
input[3:0] 		tx0_kchar,
output 			rx0_clk,
output[31:0] 	rx0_data,
output[3:0] 	rx0_kchar,


output 			tx1_clk,
output 			gt1_txfsmresetdone,
output 			gt1_rxfsmresetdone,
input[31:0] 	tx1_data,
input[3:0] 		tx1_kchar,
output 			rx1_clk,
output[31:0] 	rx1_data,
output[3:0] 	rx1_kchar,
  // User-provided ports for reset helper block(s)
  input  wire hb_gtwiz_reset_clk_freerun_in,
  input  wire hb_gtwiz_reset_all_in

  // PRBS-based link status ports
//  input  wire link_down_latched_reset_in,
//  output wire link_status_out,
//  output reg  link_down_latched_out = 1'b1

);
//modify
wire link_down_latched_reset_in ;	
assign link_down_latched_reset_in = 1'b0 ;
wire link_status_out ;
reg  link_down_latched_out ;

  // Serial data ports for transceiver channel 0
  wire ch0_gthrxn_in ;
  wire ch0_gthrxp_in ;
  wire ch0_gthtxn_out;
  wire ch0_gthtxp_out;

  // Serial data ports for transceiver channel 1
  wire ch1_gthrxn_in ;
  wire ch1_gthrxp_in ;
  wire ch1_gthtxn_out;
  wire ch1_gthtxp_out;

  assign ch0_gthrxn_in = RXN_IN[0];
  assign ch1_gthrxn_in = RXN_IN[1];

  
  assign ch0_gthrxp_in = RXP_IN[0];
  assign ch1_gthrxp_in = RXP_IN[1];

  
  assign TXN_OUT[0] = ch0_gthtxn_out ;
  assign TXN_OUT[1] = ch1_gthtxn_out ;

  
  assign TXP_OUT[0] = ch0_gthtxp_out ;
  assign TXP_OUT[1] = ch1_gthtxp_out ;


  // ===================================================================================================================
  // PER-CHANNEL SIGNAL ASSIGNMENTS
  // ===================================================================================================================

  // The core and example design wrapper vectorize ports across all enabled transceiver channel and common instances for
  // simplicity and compactness. This example design top module assigns slices of each vector to individual, per-channel
  // signal vectors for use if desired. Signals which connect to helper blocks are prefixed "hb#", signals which connect
  // to transceiver common primitives are prefixed "cm#", and signals which connect to transceiver channel primitives
  // are prefixed "ch#", where "#" is the sequential resource number.

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] gthrxn_int;
  assign gthrxn_int[0:0] = ch0_gthrxn_in;
  assign gthrxn_int[1:1] = ch1_gthrxn_in;

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] gthrxp_int;
  assign gthrxp_int[0:0] = ch0_gthrxp_in;
  assign gthrxp_int[1:1] = ch1_gthrxp_in;

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] gthtxn_int;
  assign ch0_gthtxn_out = gthtxn_int[0:0];
  assign ch1_gthtxn_out = gthtxn_int[1:1];

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] gthtxp_int;
  assign ch0_gthtxp_out = gthtxp_int[0:0];
  assign ch1_gthtxp_out = gthtxp_int[1:1];

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtwiz_userclk_tx_reset_int;
  wire [0:0] hb0_gtwiz_userclk_tx_reset_int;
  assign gtwiz_userclk_tx_reset_int[0:0] = hb0_gtwiz_userclk_tx_reset_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtwiz_userclk_tx_srcclk_int;
  wire [0:0] hb0_gtwiz_userclk_tx_srcclk_int;
  assign hb0_gtwiz_userclk_tx_srcclk_int = gtwiz_userclk_tx_srcclk_int[0:0];

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtwiz_userclk_tx_usrclk_int;
  wire [0:0] hb0_gtwiz_userclk_tx_usrclk_int;
  assign hb0_gtwiz_userclk_tx_usrclk_int = gtwiz_userclk_tx_usrclk_int[0:0];

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtwiz_userclk_tx_usrclk2_int;
  wire [0:0] hb0_gtwiz_userclk_tx_usrclk2_int;
  assign hb0_gtwiz_userclk_tx_usrclk2_int = gtwiz_userclk_tx_usrclk2_int[0:0];

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtwiz_userclk_tx_active_int;
  wire [0:0] hb0_gtwiz_userclk_tx_active_int;
  assign hb0_gtwiz_userclk_tx_active_int = gtwiz_userclk_tx_active_int[0:0];

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtwiz_userclk_rx_reset_int;
  wire [0:0] hb0_gtwiz_userclk_rx_reset_int;
  assign gtwiz_userclk_rx_reset_int[0:0] = hb0_gtwiz_userclk_rx_reset_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtwiz_userclk_rx_srcclk_int;
  wire [0:0] hb0_gtwiz_userclk_rx_srcclk_int;
  assign hb0_gtwiz_userclk_rx_srcclk_int = gtwiz_userclk_rx_srcclk_int[0:0];

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtwiz_userclk_rx_usrclk_int;
  wire [0:0] hb0_gtwiz_userclk_rx_usrclk_int;
  assign hb0_gtwiz_userclk_rx_usrclk_int = gtwiz_userclk_rx_usrclk_int[0:0];

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtwiz_userclk_rx_usrclk2_int;
  wire [0:0] hb0_gtwiz_userclk_rx_usrclk2_int;
  assign hb0_gtwiz_userclk_rx_usrclk2_int = gtwiz_userclk_rx_usrclk2_int[0:0];

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtwiz_userclk_rx_active_int;
  wire [0:0] hb0_gtwiz_userclk_rx_active_int;
  assign hb0_gtwiz_userclk_rx_active_int = gtwiz_userclk_rx_active_int[0:0];

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtwiz_reset_clk_freerun_int;
  wire [0:0] hb0_gtwiz_reset_clk_freerun_int = 1'b0;
  assign gtwiz_reset_clk_freerun_int[0:0] = hb0_gtwiz_reset_clk_freerun_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtwiz_reset_all_int;
  wire [0:0] hb0_gtwiz_reset_all_int = 1'b0;
  assign gtwiz_reset_all_int[0:0] = hb0_gtwiz_reset_all_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtwiz_reset_tx_pll_and_datapath_int;
  wire [0:0] hb0_gtwiz_reset_tx_pll_and_datapath_int;
  assign gtwiz_reset_tx_pll_and_datapath_int[0:0] = hb0_gtwiz_reset_tx_pll_and_datapath_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtwiz_reset_tx_datapath_int;
  wire [0:0] hb0_gtwiz_reset_tx_datapath_int;
  assign gtwiz_reset_tx_datapath_int[0:0] = hb0_gtwiz_reset_tx_datapath_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtwiz_reset_rx_pll_and_datapath_int;
  wire [0:0] hb0_gtwiz_reset_rx_pll_and_datapath_int = 1'b0;
  assign gtwiz_reset_rx_pll_and_datapath_int[0:0] = hb0_gtwiz_reset_rx_pll_and_datapath_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtwiz_reset_rx_datapath_int;
  wire [0:0] hb0_gtwiz_reset_rx_datapath_int = 1'b0;
  assign gtwiz_reset_rx_datapath_int[0:0] = hb0_gtwiz_reset_rx_datapath_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtwiz_reset_rx_cdr_stable_int;
  wire [0:0] hb0_gtwiz_reset_rx_cdr_stable_int;
  assign hb0_gtwiz_reset_rx_cdr_stable_int = gtwiz_reset_rx_cdr_stable_int[0:0];

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtwiz_reset_tx_done_int;
  wire [0:0] hb0_gtwiz_reset_tx_done_int;
  assign hb0_gtwiz_reset_tx_done_int = gtwiz_reset_tx_done_int[0:0];

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtwiz_reset_rx_done_int;
  wire [0:0] hb0_gtwiz_reset_rx_done_int;
  assign hb0_gtwiz_reset_rx_done_int = gtwiz_reset_rx_done_int[0:0];

  //--------------------------------------------------------------------------------------------------------------------
  wire [63:0] gtwiz_userdata_tx_int;
  wire [31:0] hb0_gtwiz_userdata_tx_int;
  wire [31:0] hb1_gtwiz_userdata_tx_int;
  assign gtwiz_userdata_tx_int[31:0] = hb0_gtwiz_userdata_tx_int;
  assign gtwiz_userdata_tx_int[63:32] = hb1_gtwiz_userdata_tx_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [63:0] gtwiz_userdata_rx_int;
  wire [31:0] hb0_gtwiz_userdata_rx_int;
  wire [31:0] hb1_gtwiz_userdata_rx_int;
  assign hb0_gtwiz_userdata_rx_int = gtwiz_userdata_rx_int[31:0];
  assign hb1_gtwiz_userdata_rx_int = gtwiz_userdata_rx_int[63:32];

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] gtrefclk00_int;
  wire [0:0] cm0_gtrefclk00_int;
  assign gtrefclk00_int[0:0] = cm0_gtrefclk00_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] qpll0outclk_int;
  wire [0:0] cm0_qpll0outclk_int;
  assign cm0_qpll0outclk_int = qpll0outclk_int[0:0];

  //--------------------------------------------------------------------------------------------------------------------
  wire [0:0] qpll0outrefclk_int;
  wire [0:0] cm0_qpll0outrefclk_int;
  assign cm0_qpll0outrefclk_int = qpll0outrefclk_int[0:0];

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] rx8b10ben_int;
  wire [0:0] ch0_rx8b10ben_int = 1'b1;
  wire [0:0] ch1_rx8b10ben_int = 1'b1;
  assign rx8b10ben_int[0:0] = ch0_rx8b10ben_int;
  assign rx8b10ben_int[1:1] = ch1_rx8b10ben_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] rxbufreset_int;
  wire [0:0] ch0_rxbufreset_int = 1'b0;
  wire [0:0] ch1_rxbufreset_int = 1'b0;
  assign rxbufreset_int[0:0] = ch0_rxbufreset_int;
  assign rxbufreset_int[1:1] = ch1_rxbufreset_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] rxchbonden_int;
  wire [0:0] ch0_rxchbonden_int;
  wire [0:0] ch1_rxchbonden_int;
  assign rxchbonden_int[0:0] = ch0_rxchbonden_int;
  assign rxchbonden_int[1:1] = ch1_rxchbonden_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [9:0] rxchbondi_int;
  wire [4:0] ch0_rxchbondi_int;
  wire [4:0] ch1_rxchbondi_int;
  assign rxchbondi_int[4:0] = ch0_rxchbondi_int;
  assign rxchbondi_int[9:5] = ch1_rxchbondi_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [5:0] rxchbondlevel_int;
  wire [2:0] ch0_rxchbondlevel_int;
  wire [2:0] ch1_rxchbondlevel_int;
  assign rxchbondlevel_int[2:0] = ch0_rxchbondlevel_int;
  assign rxchbondlevel_int[5:3] = ch1_rxchbondlevel_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] rxchbondmaster_int;
  wire [0:0] ch0_rxchbondmaster_int;
  wire [0:0] ch1_rxchbondmaster_int;
  assign rxchbondmaster_int[0:0] = ch0_rxchbondmaster_int;
  assign rxchbondmaster_int[1:1] = ch1_rxchbondmaster_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] rxchbondslave_int;
  wire [0:0] ch0_rxchbondslave_int;
  wire [0:0] ch1_rxchbondslave_int;
  assign rxchbondslave_int[0:0] = ch0_rxchbondslave_int;
  assign rxchbondslave_int[1:1] = ch1_rxchbondslave_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] rxcommadeten_int;
  wire [0:0] ch0_rxcommadeten_int = 1'b1;
  wire [0:0] ch1_rxcommadeten_int = 1'b1;
  assign rxcommadeten_int[0:0] = ch0_rxcommadeten_int;
  assign rxcommadeten_int[1:1] = ch1_rxcommadeten_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] rxlpmen_int;
  wire [0:0] ch0_rxlpmen_int = 1'b0;
  wire [0:0] ch1_rxlpmen_int = 1'b0;
  assign rxlpmen_int[0:0] = ch0_rxlpmen_int;
  assign rxlpmen_int[1:1] = ch1_rxlpmen_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] rxmcommaalignen_int;
  wire [0:0] ch0_rxmcommaalignen_int = 1'b1;
  wire [0:0] ch1_rxmcommaalignen_int = 1'b1;
  assign rxmcommaalignen_int[0:0] = ch0_rxmcommaalignen_int;
  assign rxmcommaalignen_int[1:1] = ch1_rxmcommaalignen_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] rxpcommaalignen_int;
  wire [0:0] ch0_rxpcommaalignen_int = 1'b1;
  wire [0:0] ch1_rxpcommaalignen_int = 1'b1;
  assign rxpcommaalignen_int[0:0] = ch0_rxpcommaalignen_int;
  assign rxpcommaalignen_int[1:1] = ch1_rxpcommaalignen_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] tx8b10ben_int;
  wire [0:0] ch0_tx8b10ben_int = 1'b1;
  wire [0:0] ch1_tx8b10ben_int = 1'b1;
  assign tx8b10ben_int[0:0] = ch0_tx8b10ben_int;
  assign tx8b10ben_int[1:1] = ch1_tx8b10ben_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [31:0] txctrl0_int;
  wire [15:0] ch0_txctrl0_int;
  wire [15:0] ch1_txctrl0_int;
  assign txctrl0_int[15:0] = ch0_txctrl0_int;
  assign txctrl0_int[31:16] = ch1_txctrl0_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [31:0] txctrl1_int;
  wire [15:0] ch0_txctrl1_int;
  wire [15:0] ch1_txctrl1_int;
  assign txctrl1_int[15:0] = ch0_txctrl1_int;
  assign txctrl1_int[31:16] = ch1_txctrl1_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [15:0] txctrl2_int;
  wire [7:0] ch0_txctrl2_int;
  wire [7:0] ch1_txctrl2_int;
  assign txctrl2_int[7:0] = ch0_txctrl2_int;
  assign txctrl2_int[15:8] = ch1_txctrl2_int;

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] gtpowergood_int;
  wire [0:0] ch0_gtpowergood_int;
  wire [0:0] ch1_gtpowergood_int;
  assign ch0_gtpowergood_int = gtpowergood_int[0:0];
  assign ch1_gtpowergood_int = gtpowergood_int[1:1];

  //--------------------------------------------------------------------------------------------------------------------
  wire [5:0] rxbufstatus_int;
  wire [2:0] ch0_rxbufstatus_int;
  wire [2:0] ch1_rxbufstatus_int;
  assign ch0_rxbufstatus_int = rxbufstatus_int[2:0];
  assign ch1_rxbufstatus_int = rxbufstatus_int[5:3];

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] rxbyteisaligned_int;
  wire [0:0] ch0_rxbyteisaligned_int;
  wire [0:0] ch1_rxbyteisaligned_int;
  assign ch0_rxbyteisaligned_int = rxbyteisaligned_int[0:0];
  assign ch1_rxbyteisaligned_int = rxbyteisaligned_int[1:1];

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] rxbyterealign_int;
  wire [0:0] ch0_rxbyterealign_int;
  wire [0:0] ch1_rxbyterealign_int;
  assign ch0_rxbyterealign_int = rxbyterealign_int[0:0];
  assign ch1_rxbyterealign_int = rxbyterealign_int[1:1];

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] rxchanbondseq_int;
  wire [0:0] ch0_rxchanbondseq_int;
  wire [0:0] ch1_rxchanbondseq_int;
  assign ch0_rxchanbondseq_int = rxchanbondseq_int[0:0];
  assign ch1_rxchanbondseq_int = rxchanbondseq_int[1:1];

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] rxchanisaligned_int;
  wire [0:0] ch0_rxchanisaligned_int;
  wire [0:0] ch1_rxchanisaligned_int;
  assign ch0_rxchanisaligned_int = rxchanisaligned_int[0:0];
  assign ch1_rxchanisaligned_int = rxchanisaligned_int[1:1];

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] rxchanrealign_int;
  wire [0:0] ch0_rxchanrealign_int;
  wire [0:0] ch1_rxchanrealign_int;
  assign ch0_rxchanrealign_int = rxchanrealign_int[0:0];
  assign ch1_rxchanrealign_int = rxchanrealign_int[1:1];

  //--------------------------------------------------------------------------------------------------------------------
  wire [9:0] rxchbondo_int;
  wire [4:0] ch0_rxchbondo_int;
  wire [4:0] ch1_rxchbondo_int;
  assign ch0_rxchbondo_int = rxchbondo_int[4:0];
  assign ch1_rxchbondo_int = rxchbondo_int[9:5];

  //--------------------------------------------------------------------------------------------------------------------
  wire [3:0] rxclkcorcnt_int;
  wire [1:0] ch0_rxclkcorcnt_int;
  wire [1:0] ch1_rxclkcorcnt_int;
  assign ch0_rxclkcorcnt_int = rxclkcorcnt_int[1:0];
  assign ch1_rxclkcorcnt_int = rxclkcorcnt_int[3:2];

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] rxcommadet_int;
  wire [0:0] ch0_rxcommadet_int;
  wire [0:0] ch1_rxcommadet_int;
  assign ch0_rxcommadet_int = rxcommadet_int[0:0];
  assign ch1_rxcommadet_int = rxcommadet_int[1:1];

  //--------------------------------------------------------------------------------------------------------------------
  wire [31:0] rxctrl0_int;
  wire [15:0] ch0_rxctrl0_int;
  wire [15:0] ch1_rxctrl0_int;
  assign ch0_rxctrl0_int = rxctrl0_int[15:0];
  assign ch1_rxctrl0_int = rxctrl0_int[31:16];

  //--------------------------------------------------------------------------------------------------------------------
  wire [31:0] rxctrl1_int;
  wire [15:0] ch0_rxctrl1_int;
  wire [15:0] ch1_rxctrl1_int;
  assign ch0_rxctrl1_int = rxctrl1_int[15:0];
  assign ch1_rxctrl1_int = rxctrl1_int[31:16];

  //--------------------------------------------------------------------------------------------------------------------
  wire [15:0] rxctrl2_int;
  wire [7:0] ch0_rxctrl2_int;
  wire [7:0] ch1_rxctrl2_int;
  assign ch0_rxctrl2_int = rxctrl2_int[7:0];
  assign ch1_rxctrl2_int = rxctrl2_int[15:8];

  //--------------------------------------------------------------------------------------------------------------------
  wire [15:0] rxctrl3_int;
  wire [7:0] ch0_rxctrl3_int;
  wire [7:0] ch1_rxctrl3_int;
  assign ch0_rxctrl3_int = rxctrl3_int[7:0];
  assign ch1_rxctrl3_int = rxctrl3_int[15:8];

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] rxpmaresetdone_int;
  wire [0:0] ch0_rxpmaresetdone_int;
  wire [0:0] ch1_rxpmaresetdone_int;
  assign ch0_rxpmaresetdone_int = rxpmaresetdone_int[0:0];
  assign ch1_rxpmaresetdone_int = rxpmaresetdone_int[1:1];

  //--------------------------------------------------------------------------------------------------------------------
  wire [1:0] txpmaresetdone_int;
  wire [0:0] ch0_txpmaresetdone_int;
  wire [0:0] ch1_txpmaresetdone_int;
  assign ch0_txpmaresetdone_int = txpmaresetdone_int[0:0];
  assign ch1_txpmaresetdone_int = txpmaresetdone_int[1:1];


  // ===================================================================================================================
  // Channel Bonding logic
  // ===================================================================================================================
  //Connect the daisy chaining as appropriate for the protocol, below
  //connections are indicative and connect master lane to all the other lanes
  
   assign ch0_rxchbondi_int = 5'd0;
   assign ch0_rxchbonden_int = 1'b0;
   assign ch0_rxchbondlevel_int = 3'd1;
   assign ch0_rxchbondmaster_int = 1'b1;
   assign ch0_rxchbondslave_int = 1'b0;
   assign ch1_rxchbondi_int = ch0_rxchbondo_int;
   assign ch1_rxchbonden_int = 1'b0;
   assign ch1_rxchbondlevel_int = 3'd0;
   assign ch1_rxchbondmaster_int = 1'b0;
   assign ch1_rxchbondslave_int = 1'b1;
  // ===================================================================================================================
  // BUFFERS
  // ===================================================================================================================

  // Buffer the hb_gtwiz_reset_all_in input and logically combine it with the internal signal from the example
  // initialization block as well as the VIO-sourced reset
  wire hb_gtwiz_reset_all_vio_int;
  wire hb_gtwiz_reset_all_buf_int;
  wire hb_gtwiz_reset_all_init_int;
  wire hb_gtwiz_reset_all_int;

  IBUF ibuf_hb_gtwiz_reset_all_inst (
    .I (hb_gtwiz_reset_all_in),
    .O (hb_gtwiz_reset_all_buf_int)
  );

  assign hb_gtwiz_reset_all_int = hb_gtwiz_reset_all_buf_int || hb_gtwiz_reset_all_init_int || hb_gtwiz_reset_all_vio_int;

  // Globally buffer the free-running input clock
  wire hb_gtwiz_reset_clk_freerun_buf_int;

  BUFG bufg_clk_freerun_inst (
    .I (hb_gtwiz_reset_clk_freerun_in),
    .O (hb_gtwiz_reset_clk_freerun_buf_int)
  );

  // Instantiate a differential reference clock buffer for each reference clock differential pair in this configuration,
  // and assign the single-ended output of each differential reference clock buffer to the appropriate PLL input signal

  // Differential reference clock buffer for MGTREFCLK1_X0Y1
  wire mgtrefclk1_x0y1_int;
//modify
  IBUFDS_GTE4 #(
    .REFCLK_EN_TX_PATH  (1'b0),
    .REFCLK_HROW_CK_SEL (2'b00),
    .REFCLK_ICNTL_RX    (2'b00)
  ) IBUFDS_GTE4_MGTREFCLK1_X0Y1_INST (
    .I     (mgtrefclk_p),
    .IB    (mgtrefclk_n),
    .CEB   (1'b0),
    .O     (mgtrefclk1_x0y1_int),
    .ODIV2 ()
  );

  assign cm0_gtrefclk00_int = mgtrefclk1_x0y1_int;


  // ===================================================================================================================
  // USER CLOCKING RESETS
  // ===================================================================================================================

  // The TX user clocking helper block should be held in reset until the clock source of that block is known to be
  // stable. The following assignment is an example of how that stability can be determined, based on the selected TX
  // user clock source. Replace the assignment with the appropriate signal or logic to achieve that behavior as needed.
  assign hb0_gtwiz_userclk_tx_reset_int = ~(&txpmaresetdone_int);

  // The RX user clocking helper block should be held in reset until the clock source of that block is known to be
  // stable. The following assignment is an example of how that stability can be determined, based on the selected RX
  // user clock source. Replace the assignment with the appropriate signal or logic to achieve that behavior as needed.
  assign hb0_gtwiz_userclk_rx_reset_int = ~(&rxpmaresetdone_int);

//modify
assign tx0_clk 		= hb0_gtwiz_userclk_tx_usrclk2_int;
assign rx0_clk 		= hb0_gtwiz_userclk_rx_usrclk2_int;
assign rx0_data 	= hb0_gtwiz_userdata_rx_int;
assign rx0_kchar 	= ch0_rxctrl2_int;
assign gt0_txfsmresetdone = gtwiz_reset_tx_done_int;
assign gt0_rxfsmresetdone = gtwiz_reset_rx_done_int;


assign tx1_clk 		= hb0_gtwiz_userclk_tx_usrclk2_int;
assign rx1_clk 		= hb0_gtwiz_userclk_rx_usrclk2_int;
assign rx1_data 	= hb1_gtwiz_userdata_rx_int;
assign rx1_kchar 	= ch1_rxctrl2_int;
assign gt1_txfsmresetdone = gtwiz_reset_tx_done_int;
assign gt1_rxfsmresetdone = gtwiz_reset_rx_done_int;

assign hb0_gtwiz_userdata_tx_int = tx0_data ;
assign hb1_gtwiz_userdata_tx_int = tx1_data ;


assign ch0_txctrl2_int = tx0_kchar ;
assign ch1_txctrl2_int = tx1_kchar ;

assign ch0_txctrl0_int = 16'd0 ;
assign ch1_txctrl0_int = 16'd0 ;

assign ch0_txctrl1_int = 16'd0 ;
assign ch1_txctrl1_int = 16'd0 ;
//modify
  wire [1:0] prbs_match_int;
  // ===================================================================================================================
  // PRBS STIMULUS, CHECKING, AND LINK MANAGEMENT
  // ===================================================================================================================

  // PRBS stimulus
  // -------------------------------------------------------------------------------------------------------------------

 /*  // PRBS-based data stimulus module for transceiver channel 0
  (* DONT_TOUCH = "TRUE" *)
  gt_example_stimulus_8b10b example_stimulus_inst0 (
    .gtwiz_reset_all_in          (hb_gtwiz_reset_all_int || ~hb0_gtwiz_reset_rx_done_int ),
    .gtwiz_userclk_tx_usrclk2_in (hb0_gtwiz_userclk_tx_usrclk2_int),
    .gtwiz_userclk_tx_active_in  (hb0_gtwiz_userclk_tx_active_int),
    .txctrl0_out                 (ch0_txctrl0_int),
    .txctrl1_out                 (ch0_txctrl1_int),
    .txctrl2_out                 (ch0_txctrl2_int),
    .txdata_out                  (hb0_gtwiz_userdata_tx_int)
  );

  // PRBS-based data stimulus module for transceiver channel 1
  (* DONT_TOUCH = "TRUE" *)
  gt_example_stimulus_8b10b example_stimulus_inst1 (
    .gtwiz_reset_all_in          (hb_gtwiz_reset_all_int || ~hb0_gtwiz_reset_rx_done_int ),
    .gtwiz_userclk_tx_usrclk2_in (hb0_gtwiz_userclk_tx_usrclk2_int),
    .gtwiz_userclk_tx_active_in  (hb0_gtwiz_userclk_tx_active_int),
    .txctrl0_out                 (ch1_txctrl0_int),
    .txctrl1_out                 (ch1_txctrl1_int),
    .txctrl2_out                 (ch1_txctrl2_int),
    .txdata_out                  (hb1_gtwiz_userdata_tx_int)
  );

  // PRBS checking
  // -------------------------------------------------------------------------------------------------------------------

  // Declare a signal vector of PRBS match indicators, with one indicator bit per transceiver channel
  wire [1:0] prbs_match_int;

  // PRBS-based data checking module for transceiver channel 0
  gt_example_checking_8b10b example_checking_inst0 (
    .gtwiz_reset_all_in          (hb_gtwiz_reset_all_int || ~hb0_gtwiz_reset_rx_done_int ),
    .gtwiz_userclk_rx_usrclk2_in (hb0_gtwiz_userclk_rx_usrclk2_int),
    .gtwiz_userclk_rx_active_in  (hb0_gtwiz_userclk_rx_active_int),
    .rxctrl0_in                  (ch0_rxctrl0_int),
    .rxctrl1_in                  (ch0_rxctrl1_int),
    .rxctrl2_in                  (ch0_rxctrl2_int),
    .rxctrl3_in                  (ch0_rxctrl3_int),
    .rxdata_in                   (hb0_gtwiz_userdata_rx_int),
    .prbs_match_out              (prbs_match_int[0])
  );

  // PRBS-based data checking module for transceiver channel 1
  gt_example_checking_8b10b example_checking_inst1 (
    .gtwiz_reset_all_in          (hb_gtwiz_reset_all_int || ~hb0_gtwiz_reset_rx_done_int ),
    .gtwiz_userclk_rx_usrclk2_in (hb0_gtwiz_userclk_rx_usrclk2_int),
    .gtwiz_userclk_rx_active_in  (hb0_gtwiz_userclk_rx_active_int),
    .rxctrl0_in                  (ch1_rxctrl0_int),
    .rxctrl1_in                  (ch1_rxctrl1_int),
    .rxctrl2_in                  (ch1_rxctrl2_int),
    .rxctrl3_in                  (ch1_rxctrl3_int),
    .rxdata_in                   (hb1_gtwiz_userdata_rx_int),
    .prbs_match_out              (prbs_match_int[1])
  ); */

  // PRBS match and related link management
  // -------------------------------------------------------------------------------------------------------------------

  // Perform a bitwise NAND of all PRBS match indicators, creating a combinatorial indication of any PRBS mismatch
  // across all transceiver channels
  wire prbs_error_any_async = ~(&prbs_match_int);
  wire prbs_error_any_sync;

  // Synchronize the PRBS mismatch indicator the free-running clock domain, using a reset synchronizer with asynchronous
  // reset and synchronous removal
  (* DONT_TOUCH = "TRUE" *)
  gt_example_reset_synchronizer reset_synchronizer_prbs_match_all_inst (
    .clk_in (hb_gtwiz_reset_clk_freerun_buf_int),
    .rst_in (prbs_error_any_async),
    .rst_out(prbs_error_any_sync)
  );

  // Implement an example link status state machine using a simple leaky bucket mechanism. The link status indicates
  // the continual PRBS match status to both the top-level observer and the initialization state machine, while being
  // tolerant of occasional bit errors. This is an example and can be modified as necessary.
  localparam ST_LINK_DOWN = 1'b0;
  localparam ST_LINK_UP   = 1'b1;
  reg        sm_link      = ST_LINK_DOWN;
  reg [6:0]  link_ctr     = 7'd0;

  always @(posedge hb_gtwiz_reset_clk_freerun_buf_int) begin
    case (sm_link)
      // The link is considered to be down when the link counter initially has a value less than 67. When the link is
      // down, the counter is incremented on each cycle where all PRBS bits match, but reset whenever any PRBS mismatch
      // occurs. When the link counter reaches 67, transition to the link up state.
      ST_LINK_DOWN: begin
        if (prbs_error_any_sync !== 1'b0) begin
          link_ctr <= 7'd0;
        end
        else begin
          if (link_ctr < 7'd67)
            link_ctr <= link_ctr + 7'd1;
          else
            sm_link <= ST_LINK_UP;
        end
      end

      // When the link is up, the link counter is decreased by 34 whenever any PRBS mismatch occurs, but is increased by
      // only 1 on each cycle where all PRBS bits match, up to its saturation point of 67. If the link counter reaches
      // 0 (including rollover protection), transition to the link down state.
      ST_LINK_UP: begin
        if (prbs_error_any_sync !== 1'b0) begin
          if (link_ctr > 7'd33) begin
            link_ctr <= link_ctr - 7'd34;
            if (link_ctr == 7'd34)
              sm_link  <= ST_LINK_DOWN;
          end
          else begin
            link_ctr <= 7'd0;
            sm_link  <= ST_LINK_DOWN;
          end
        end
        else begin
          if (link_ctr < 7'd67)
            link_ctr <= link_ctr + 7'd1;
        end
      end
    endcase
  end

  // Synchronize the latched link down reset input and the VIO-driven signal into the free-running clock domain
  wire link_down_latched_reset_vio_int;
  wire link_down_latched_reset_sync;

  (* DONT_TOUCH = "TRUE" *)
  gt_example_bit_synchronizer bit_synchronizer_link_down_latched_reset_inst (
    .clk_in (hb_gtwiz_reset_clk_freerun_buf_int),
    .i_in   (link_down_latched_reset_in || link_down_latched_reset_vio_int),
    .o_out  (link_down_latched_reset_sync)
  );

  // Reset the latched link down indicator when the synchronized latched link down reset signal is high. Otherwise, set
  // the latched link down indicator upon losing link. This indicator is available for user reference.
  always @(posedge hb_gtwiz_reset_clk_freerun_buf_int) begin
    if (link_down_latched_reset_sync)
      link_down_latched_out <= 1'b0;
    else if (!sm_link)
      link_down_latched_out <= 1'b1;
  end

  // Assign the link status indicator to the top-level two-state output for user reference
  assign link_status_out = sm_link;


  // ===================================================================================================================
  // INITIALIZATION
  // ===================================================================================================================

  // Declare the receiver reset signals that interface to the reset controller helper block. For this configuration,
  // which uses the same PLL type for transmitter and receiver, the "reset RX PLL and datapath" feature is not used.
  wire hb_gtwiz_reset_rx_pll_and_datapath_int = 1'b0;
  wire hb_gtwiz_reset_rx_datapath_int;

  // Declare signals which connect the VIO instance to the initialization module for debug purposes
  wire       init_done_int;
  wire [3:0] init_retry_ctr_int;

  // Combine the receiver reset signals form the initialization module and the VIO to drive the appropriate reset
  // controller helper block reset input
  wire hb_gtwiz_reset_rx_pll_and_datapath_vio_int;
  wire hb_gtwiz_reset_rx_datapath_vio_int;
  wire hb_gtwiz_reset_rx_datapath_init_int;

  assign hb_gtwiz_reset_rx_datapath_int = hb_gtwiz_reset_rx_datapath_init_int || hb_gtwiz_reset_rx_datapath_vio_int;

  // The example initialization module interacts with the reset controller helper block and other example design logic
  // to retry failed reset attempts in order to mitigate bring-up issues such as initially-unavilable reference clocks
  // or data connections. It also resets the receiver in the event of link loss in an attempt to regain link, so please
  // note the possibility that this behavior can have the effect of overriding or disturbing user-provided inputs that
  // destabilize the data stream. It is a demonstration only and can be modified to suit your system needs.
  gt_example_init example_init_inst (
    .clk_freerun_in  (hb_gtwiz_reset_clk_freerun_buf_int),
    .reset_all_in    (hb_gtwiz_reset_all_int),
    .tx_init_done_in (gtwiz_reset_tx_done_int),
    .rx_init_done_in (gtwiz_reset_rx_done_int),
    .rx_data_good_in (sm_link),
    .reset_all_out   (hb_gtwiz_reset_all_init_int),
    .reset_rx_out    (hb_gtwiz_reset_rx_datapath_init_int),
    .init_done_out   (init_done_int),
    .retry_ctr_out   (init_retry_ctr_int)
  );


  // ===================================================================================================================
  // VIO FOR HARDWARE BRING-UP AND DEBUG
  // ===================================================================================================================

  // Synchronize gtpowergood into the free-running clock domain for VIO usage
  wire [1:0] gtpowergood_vio_sync;

  (* DONT_TOUCH = "TRUE" *)
  gt_example_bit_synchronizer bit_synchronizer_vio_gtpowergood_0_inst (
    .clk_in (hb_gtwiz_reset_clk_freerun_buf_int),
    .i_in   (gtpowergood_int[0]),
    .o_out  (gtpowergood_vio_sync[0])
  );

  (* DONT_TOUCH = "TRUE" *)
  gt_example_bit_synchronizer bit_synchronizer_vio_gtpowergood_1_inst (
    .clk_in (hb_gtwiz_reset_clk_freerun_buf_int),
    .i_in   (gtpowergood_int[1]),
    .o_out  (gtpowergood_vio_sync[1])
  );

  // Synchronize txpmaresetdone into the free-running clock domain for VIO usage
  wire [1:0] txpmaresetdone_vio_sync;

  (* DONT_TOUCH = "TRUE" *)
  gt_example_bit_synchronizer bit_synchronizer_vio_txpmaresetdone_0_inst (
    .clk_in (hb_gtwiz_reset_clk_freerun_buf_int),
    .i_in   (txpmaresetdone_int[0]),
    .o_out  (txpmaresetdone_vio_sync[0])
  );

  (* DONT_TOUCH = "TRUE" *)
  gt_example_bit_synchronizer bit_synchronizer_vio_txpmaresetdone_1_inst (
    .clk_in (hb_gtwiz_reset_clk_freerun_buf_int),
    .i_in   (txpmaresetdone_int[1]),
    .o_out  (txpmaresetdone_vio_sync[1])
  );

  // Synchronize rxpmaresetdone into the free-running clock domain for VIO usage
  wire [1:0] rxpmaresetdone_vio_sync;

  (* DONT_TOUCH = "TRUE" *)
  gt_example_bit_synchronizer bit_synchronizer_vio_rxpmaresetdone_0_inst (
    .clk_in (hb_gtwiz_reset_clk_freerun_buf_int),
    .i_in   (rxpmaresetdone_int[0]),
    .o_out  (rxpmaresetdone_vio_sync[0])
  );

  (* DONT_TOUCH = "TRUE" *)
  gt_example_bit_synchronizer bit_synchronizer_vio_rxpmaresetdone_1_inst (
    .clk_in (hb_gtwiz_reset_clk_freerun_buf_int),
    .i_in   (rxpmaresetdone_int[1]),
    .o_out  (rxpmaresetdone_vio_sync[1])
  );

  // Synchronize gtwiz_reset_tx_done into the free-running clock domain for VIO usage
  wire [0:0] gtwiz_reset_tx_done_vio_sync;

  (* DONT_TOUCH = "TRUE" *)
  gt_example_bit_synchronizer bit_synchronizer_vio_gtwiz_reset_tx_done_0_inst (
    .clk_in (hb_gtwiz_reset_clk_freerun_buf_int),
    .i_in   (gtwiz_reset_tx_done_int[0]),
    .o_out  (gtwiz_reset_tx_done_vio_sync[0])
  );

  // Synchronize gtwiz_reset_rx_done into the free-running clock domain for VIO usage
  wire [0:0] gtwiz_reset_rx_done_vio_sync;

  (* DONT_TOUCH = "TRUE" *)
  gt_example_bit_synchronizer bit_synchronizer_vio_gtwiz_reset_rx_done_0_inst (
    .clk_in (hb_gtwiz_reset_clk_freerun_buf_int),
    .i_in   (gtwiz_reset_rx_done_int[0]),
    .o_out  (gtwiz_reset_rx_done_vio_sync[0])
  );

  // Synchronize rxbufstatus into the free-running clock domain for VIO usage
  wire [5:0] rxbufstatus_vio_sync;

  (* DONT_TOUCH = "TRUE" *)
  gt_example_bit_synchronizer bit_synchronizer_vio_rxbufstatus_0_inst (
    .clk_in (hb_gtwiz_reset_clk_freerun_buf_int),
    .i_in   (rxbufstatus_int[0]),
    .o_out  (rxbufstatus_vio_sync[0])
  );
  (* DONT_TOUCH = "TRUE" *)
  gt_example_bit_synchronizer bit_synchronizer_vio_rxbufstatus_1_inst (
    .clk_in (hb_gtwiz_reset_clk_freerun_buf_int),
    .i_in   (rxbufstatus_int[1]),
    .o_out  (rxbufstatus_vio_sync[1])
  );
  (* DONT_TOUCH = "TRUE" *)
  gt_example_bit_synchronizer bit_synchronizer_vio_rxbufstatus_2_inst (
    .clk_in (hb_gtwiz_reset_clk_freerun_buf_int),
    .i_in   (rxbufstatus_int[2]),
    .o_out  (rxbufstatus_vio_sync[2])
  );

  (* DONT_TOUCH = "TRUE" *)
  gt_example_bit_synchronizer bit_synchronizer_vio_rxbufstatus_3_inst (
    .clk_in (hb_gtwiz_reset_clk_freerun_buf_int),
    .i_in   (rxbufstatus_int[3]),
    .o_out  (rxbufstatus_vio_sync[3])
  );
  (* DONT_TOUCH = "TRUE" *)
  gt_example_bit_synchronizer bit_synchronizer_vio_rxbufstatus_4_inst (
    .clk_in (hb_gtwiz_reset_clk_freerun_buf_int),
    .i_in   (rxbufstatus_int[4]),
    .o_out  (rxbufstatus_vio_sync[4])
  );
  (* DONT_TOUCH = "TRUE" *)
  gt_example_bit_synchronizer bit_synchronizer_vio_rxbufstatus_5_inst (
    .clk_in (hb_gtwiz_reset_clk_freerun_buf_int),
    .i_in   (rxbufstatus_int[5]),
    .o_out  (rxbufstatus_vio_sync[5])
  );


  // Instantiate the VIO IP core for hardware bring-up and debug purposes, connecting relevant debug and analysis
  // signals which have been enabled during Wizard IP customization. This initial set of connected signals is
  // provided as a convenience and example, but more or fewer ports can be used as needed; simply re-customize and
  // re-generate the VIO instance, then connect any exposed signals that are needed. Signals which are synchronous to
  // clocks other than the free-running clock will require synchronization. For usage, refer to Vivado Design Suite
  // User Guide: Programming and Debugging (UG908)
  gt_vio_0 gt_vio_0_inst (
    .clk (hb_gtwiz_reset_clk_freerun_buf_int)
    ,.probe_in0 (link_status_out)
    ,.probe_in1 (link_down_latched_out)
    ,.probe_in2 (init_done_int)
    ,.probe_in3 (init_retry_ctr_int)
    ,.probe_in4 (gtpowergood_vio_sync)
    ,.probe_in5 (txpmaresetdone_vio_sync)
    ,.probe_in6 (rxpmaresetdone_vio_sync)
    ,.probe_in7 (gtwiz_reset_tx_done_vio_sync)
    ,.probe_in8 (gtwiz_reset_rx_done_vio_sync)
    ,.probe_in9 (rxbufstatus_vio_sync)
    ,.probe_out0 (hb_gtwiz_reset_all_vio_int)
    ,.probe_out1 (hb0_gtwiz_reset_tx_pll_and_datapath_int)
    ,.probe_out2 (hb0_gtwiz_reset_tx_datapath_int)
    ,.probe_out3 (hb_gtwiz_reset_rx_pll_and_datapath_vio_int)
    ,.probe_out4 (hb_gtwiz_reset_rx_datapath_vio_int)
    ,.probe_out5 (link_down_latched_reset_vio_int)
  );


  // ===================================================================================================================
  // EXAMPLE WRAPPER INSTANCE
  // ===================================================================================================================

  // Instantiate the example design wrapper, mapping its enabled ports to per-channel internal signals and example
  // resources as appropriate
  gt_example_wrapper example_wrapper_inst (
    .gthrxn_in                               (gthrxn_int)
   ,.gthrxp_in                               (gthrxp_int)
   ,.gthtxn_out                              (gthtxn_int)
   ,.gthtxp_out                              (gthtxp_int)
   ,.gtwiz_userclk_tx_reset_in               (gtwiz_userclk_tx_reset_int)
   ,.gtwiz_userclk_tx_srcclk_out             (gtwiz_userclk_tx_srcclk_int)
   ,.gtwiz_userclk_tx_usrclk_out             (gtwiz_userclk_tx_usrclk_int)
   ,.gtwiz_userclk_tx_usrclk2_out            (gtwiz_userclk_tx_usrclk2_int)
   ,.gtwiz_userclk_tx_active_out             (gtwiz_userclk_tx_active_int)
   ,.gtwiz_userclk_rx_reset_in               (gtwiz_userclk_rx_reset_int)
   ,.gtwiz_userclk_rx_srcclk_out             (gtwiz_userclk_rx_srcclk_int)
   ,.gtwiz_userclk_rx_usrclk_out             (gtwiz_userclk_rx_usrclk_int)
   ,.gtwiz_userclk_rx_usrclk2_out            (gtwiz_userclk_rx_usrclk2_int)
   ,.gtwiz_userclk_rx_active_out             (gtwiz_userclk_rx_active_int)
   ,.gtwiz_reset_clk_freerun_in              ({1{hb_gtwiz_reset_clk_freerun_buf_int}})
   ,.gtwiz_reset_all_in                      ({1{hb_gtwiz_reset_all_int}})
   ,.gtwiz_reset_tx_pll_and_datapath_in      (gtwiz_reset_tx_pll_and_datapath_int)
   ,.gtwiz_reset_tx_datapath_in              (gtwiz_reset_tx_datapath_int)
   ,.gtwiz_reset_rx_pll_and_datapath_in      ({1{hb_gtwiz_reset_rx_pll_and_datapath_int}})
   ,.gtwiz_reset_rx_datapath_in              ({1{hb_gtwiz_reset_rx_datapath_int}})
   ,.gtwiz_reset_rx_cdr_stable_out           (gtwiz_reset_rx_cdr_stable_int)
   ,.gtwiz_reset_tx_done_out                 (gtwiz_reset_tx_done_int)
   ,.gtwiz_reset_rx_done_out                 (gtwiz_reset_rx_done_int)
   ,.gtwiz_userdata_tx_in                    (gtwiz_userdata_tx_int)
   ,.gtwiz_userdata_rx_out                   (gtwiz_userdata_rx_int)
   ,.gtrefclk00_in                           (gtrefclk00_int)
   ,.qpll0outclk_out                         (qpll0outclk_int)
   ,.qpll0outrefclk_out                      (qpll0outrefclk_int)
   ,.rx8b10ben_in                            (rx8b10ben_int)
   ,.rxbufreset_in                           (rxbufreset_int)
   ,.rxchbonden_in                           (rxchbonden_int)
   ,.rxchbondi_in                            (rxchbondi_int)
   ,.rxchbondlevel_in                        (rxchbondlevel_int)
   ,.rxchbondmaster_in                       (rxchbondmaster_int)
   ,.rxchbondslave_in                        (rxchbondslave_int)
   ,.rxcommadeten_in                         (rxcommadeten_int)
   ,.rxlpmen_in                              (rxlpmen_int)
   ,.rxmcommaalignen_in                      (rxmcommaalignen_int)
   ,.rxpcommaalignen_in                      (rxpcommaalignen_int)
   ,.tx8b10ben_in                            (tx8b10ben_int)
   ,.txctrl0_in                              (txctrl0_int)
   ,.txctrl1_in                              (txctrl1_int)
   ,.txctrl2_in                              (txctrl2_int)
   ,.gtpowergood_out                         (gtpowergood_int)
   ,.rxbufstatus_out                         (rxbufstatus_int)
   ,.rxbyteisaligned_out                     (rxbyteisaligned_int)
   ,.rxbyterealign_out                       (rxbyterealign_int)
   ,.rxchanbondseq_out                       (rxchanbondseq_int)
   ,.rxchanisaligned_out                     (rxchanisaligned_int)
   ,.rxchanrealign_out                       (rxchanrealign_int)
   ,.rxchbondo_out                           (rxchbondo_int)
   ,.rxclkcorcnt_out                         (rxclkcorcnt_int)
   ,.rxcommadet_out                          (rxcommadet_int)
   ,.rxctrl0_out                             (rxctrl0_int)
   ,.rxctrl1_out                             (rxctrl1_int)
   ,.rxctrl2_out                             (rxctrl2_int)
   ,.rxctrl3_out                             (rxctrl3_int)
   ,.rxpmaresetdone_out                      (rxpmaresetdone_int)
   ,.txpmaresetdone_out                      (txpmaresetdone_int)
);


endmodule

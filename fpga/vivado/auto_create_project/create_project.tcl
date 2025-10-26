# Minimalized for: PS UART0 (MIO) + AXI-GPIO LED

set tclpath [pwd]
cd $tclpath
set src_dir $tclpath/src

# create project path
cd ..
set projpath [pwd]

source $projpath/auto_create_project/project_info.tcl

if {[string equal $devicePart "xczu5ev-sfvc784-2-i" ]} {
  puts "xczu5ev-sfvc784-2-i"
  set projName "axu5ev_p_trd"
} else {
  puts "Wrong Part!"
  return 0
}

create_project -force $projName $projpath -part $devicePart

# Create filesets
if {[string equal [get_filesets -quiet sources_1] ""]} { create_fileset -srcset sources_1 }
file mkdir $projpath/$projName.srcs/sources_1/ip
file mkdir $projpath/$projName.srcs/sources_1/new

if {[string equal [get_filesets -quiet constrs_1] ""]} { create_fileset -constrset constrs_1 }
file mkdir $projpath/$projName.srcs/constrs_1/new

if {[string equal [get_filesets -quiet sim_1] ""]} { create_fileset -simset sim_1 }
file mkdir $projpath/$projName.srcs/sim_1/new

# --- User IP repos ---
set_property ip_repo_paths {} [current_project]
set repos [list \
  [file normalize "C:/Vivado/ip_projs/sdr_chain_axi64"] \
  [file normalize "C:/Vivado/ip_projs/prbs_axi_stream_axis8"] ]
set_property ip_repo_paths $repos [current_project]
update_ip_catalog

puts "SDR defs:  [get_ipdefs -all -filter {VLNV =~ *:sdr_chain*:*}]"
puts "PRBS defs: [get_ipdefs -all -filter {VLNV =~ *:prbs_axi_stream*:*}]"

# === BD ===
set bdname "design_1"
create_bd_design $bdname
open_bd_design $projpath/$projName.srcs/sources_1/bd/$bdname/$bdname.bd

# PS
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ultra_ps_e_0
source $projpath/auto_create_project/ps_config.tcl
set_ps_config zynq_ultra_ps_e_0

# Force PL FCLK0 = 100 MHz using a valid source (IOPLL)
set_property -dict [list \
  CONFIG.PSU__FPGA_PL0_ENABLE {1} \
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__SRCSEL {IOPLL} \
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100.000000} \
] [get_bd_cells zynq_ultra_ps_e_0]
# (metadata) in case Vivado still reports odd value
set_property CONFIG.FREQ_HZ 100000000 [get_bd_pins zynq_ultra_ps_e_0/pl_clk0]

# PS tweaks
set_property -dict [list CONFIG.PSU__USE__IRQ0 {1}] [get_bd_cells zynq_ultra_ps_e_0]
set_property -dict [list CONFIG.PSU__USE__IRQ1 {1}] [get_bd_cells zynq_ultra_ps_e_0]
set_property -dict [list CONFIG.PSU__USE__M_AXI_GP0 {1}] [get_bd_cells zynq_ultra_ps_e_0]
set_property -dict [list CONFIG.PSU__UART1__PERIPHERAL__ENABLE {1} CONFIG.PSU__UART1__PERIPHERAL__IO {EMIO}] [get_bd_cells zynq_ultra_ps_e_0]
set_property -dict [list CONFIG.PSU__PSS_REF_CLK__FREQMHZ {33.333333}] [get_bd_cells zynq_ultra_ps_e_0]

# PL (LED/BTN fabric etc.)
source $tclpath/pl_config.tcl

# ===== Add SDR chain + PRBS + width conv to BD =====
set sdr_vlnv  [lindex [get_ipdefs -all -filter {VLNV =~ "*:sdr_chain*:*"}] 0]
set prbs_vlnv [lindex [get_ipdefs -all -filter {VLNV =~ "*:prbs_axi_stream*:*"}] 0]
if { $sdr_vlnv eq "" || $prbs_vlnv eq "" } {
  error "Missing IP. Check Settings→IP→Add Repository and that both IPs are packaged."
}

create_bd_cell -type ip -vlnv $sdr_vlnv  sdr_chain_0
# Make sdr_chain S_AXI 16-bit address to avoid [15:0] OOR select
set_property -dict [list CONFIG.AXIL_ADDR_WIDTH {16}] [get_bd_cells sdr_chain_0]

create_bd_cell -type ip -vlnv $prbs_vlnv prbs_axi_0

# SmartConnect (2023.2)
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc_0
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] [get_bd_cells axi_smc_0]

# Width converter 8->64
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 axis_dw_8to64_0
set_property -dict [list CONFIG.S_TDATA_NUM_BYTES {1} CONFIG.M_TDATA_NUM_BYTES {8} CONFIG.HAS_TLAST {1} CONFIG.HAS_TKEEP {1}] [get_bd_cells axis_dw_8to64_0]

# Constant tready=1 sink (temp)
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconst_one
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] [get_bd_cells xlconst_one]

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# ADD: AXI4-Stream Broadcaster (PRBS split)
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_broadcaster:1.1 axis_bcast_0
# 1 input byte → 2 outputs (both 1 byte), TLAST propagated
set_property -dict [list \
  CONFIG.S_TDATA_NUM_BYTES {1} \
  CONFIG.M_TDATA_NUM_BYTES {1} \
  CONFIG.NUM_MI_SLOTS {2} \
  CONFIG.TDATA_REMAP {tdata[7:0]} \
  CONFIG.HAS_TLAST {1} \
] [get_bd_cells axis_bcast_0]

# Cheap always-ready sink for M01 (prevents backpressure on main path)
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_register_slice:1.1 axis_tap_0
set_property -dict [list CONFIG.TDATA_NUM_BYTES {1} CONFIG.HAS_TLAST {1}] [get_bd_cells axis_tap_0]
# <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

# --- CLOCK/RESET hookup (robust) ---

# CLOCKS: drive our IP clocks from PS pl_clk0
set clk_src [get_bd_pins -quiet zynq_ultra_ps_e_0/pl_clk0]
if {$clk_src eq ""} { error "pl_clk0 not found on PS." }

set clk_sinks {}
foreach p {sdr_chain_0/clk prbs_axi_0/clk axis_dw_8to64_0/aclk axi_smc_0/aclk axis_bcast_0/aclk axis_tap_0/aclk} {
  set pin [get_bd_pins -quiet $p]
  if {$pin ne ""} { lappend clk_sinks $pin }
}
if {[llength $clk_sinks] >= 1} {
  connect_bd_net $clk_src {*}$clk_sinks
}

# Also drive HPM ACLKs if present (FPD/LPD)
foreach p {maxihpm0_fpd_aclk maxihpm0_lpd_aclk} {
  set h [get_bd_pins -quiet zynq_ultra_ps_e_0/$p]
  if {$h ne ""} { catch { connect_bd_net $clk_src $h } }
}

# RESET: use rst_ps8_0_200M/peripheral_aresetn (from pl_config.tcl); fallback if absent
set rst_pin [get_bd_pins -quiet rst_ps8_0_200M/peripheral_aresetn]
if {$rst_pin eq ""} {
  if {[llength [get_bd_cells -quiet rst_ps_fallback]] == 0} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps_fallback
    connect_bd_net $clk_src [get_bd_pins rst_ps_fallback/slowest_sync_clk]
    connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] [get_bd_pins rst_ps_fallback/ext_reset_in]
  }
  set rst_pin [get_bd_pins rst_ps_fallback/peripheral_aresetn]
}

set rst_sinks {}
foreach p {sdr_chain_0/rst_n prbs_axi_0/rst_n axis_dw_8to64_0/aresetn axi_smc_0/aresetn axis_bcast_0/aresetn axis_tap_0/aresetn} {
  set pin [get_bd_pins -quiet $p]
  if {$pin ne ""} { lappend rst_sinks $pin }
}
if {[llength $rst_sinks] >= 1} {
  connect_bd_net $rst_pin {*}$rst_sinks
}

# --- Align FREQ_HZ metadata of pins & interfaces to pl_clk0 (now 100 MHz) ---
set pl_hz [get_property CONFIG.FREQ_HZ [get_bd_pins zynq_ultra_ps_e_0/pl_clk0]]
if {$pl_hz eq ""} { set pl_hz 100000000 }

# Clock pins
foreach p {sdr_chain_0/clk prbs_axi_0/clk axis_dw_8to64_0/aclk axi_smc_0/aclk axis_bcast_0/aclk axis_tap_0/aclk} {
  if {[llength [get_bd_pins -quiet $p]]} {
    set_property -quiet CONFIG.FREQ_HZ $pl_hz [get_bd_pins $p]
  }
}
# AXI-Lite/AXIS interfaces
foreach i {
  sdr_chain_0/S_AXI
  axi_smc_0/S00_AXI axi_smc_0/M00_AXI axi_smc_0/M01_AXI
  prbs_axi_0/M_AXIS
  axis_bcast_0/S_AXIS axis_bcast_0/M00_AXIS axis_bcast_0/M01_AXIS
  axis_tap_0/S_AXIS  axis_tap_0/M_AXIS
  axis_dw_8to64_0/S_AXIS axis_dw_8to64_0/M_AXIS
  sdr_chain_0/S_AXIS_ALT
} {
  if {[llength [get_bd_intf_pins -quiet $i]]} {
    set_property -quiet CONFIG.FREQ_HZ $pl_hz [get_bd_intf_pins $i]
  }
}
# PRBS AXI-Lite may be named differently
set prbs_axil [get_bd_intf_pins -quiet prbs_axi_0/S_AXI]
if {$prbs_axil eq ""} { set prbs_axil [get_bd_intf_pins -quiet prbs_axi_0/S_AXIL] }
if {$prbs_axil eq ""} { set prbs_axil [get_bd_intf_pins -quiet prbs_axi_0/s_axil] }
if {$prbs_axil ne ""} { set_property -quiet CONFIG.FREQ_HZ $pl_hz $prbs_axil }

# AXI-Lite: PS → SmartConnect → {sdr_chain, prbs}
# Pick FPD if present else LPD
set ps_m_axi [get_bd_intf_pins -quiet zynq_ultra_ps_e_0/M_AXI_HPM0_FPD]
if {$ps_m_axi eq ""} { set ps_m_axi [get_bd_intf_pins -quiet zynq_ultra_ps_e_0/M_AXI_HPM0_LPD] }
if {$ps_m_axi eq ""} { error "No PS HPM master (FPD/LPD) interface found." }

connect_bd_intf_net $ps_m_axi [get_bd_intf_pins axi_smc_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc_0/M00_AXI] [get_bd_intf_pins sdr_chain_0/S_AXI]

# Robust lookup for PRBS AXI-Lite interface name
set prbs_axil [get_bd_intf_pins -quiet prbs_axi_0/S_AXI]
if {$prbs_axil eq ""} { set prbs_axil [get_bd_intf_pins -quiet prbs_axi_0/S_AXIL] }
if {$prbs_axil eq ""} { set prbs_axil [get_bd_intf_pins -quiet prbs_axi_0/s_axil] }
if {$prbs_axil eq ""} { error "PRBS AXI-Lite interface not found (S_AXI/S_AXIL/s_axil). Check IP packager name." }

connect_bd_intf_net [get_bd_intf_pins axi_smc_0/M01_AXI] $prbs_axil

# ---------------- AXIS data path with Broadcaster ----------------
# PRBS(8) -> Broadcaster -> { M00 -> 8->64,  M01 -> tap (always-ready) }
connect_bd_intf_net [get_bd_intf_pins prbs_axi_0/M_AXIS]        [get_bd_intf_pins axis_bcast_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins axis_bcast_0/M00_AXIS]    [get_bd_intf_pins axis_dw_8to64_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins axis_bcast_0/M01_AXIS]    [get_bd_intf_pins axis_tap_0/S_AXIS]

# Tie the tap's output ready high so broadcaster never stalls on M01
connect_bd_net [get_bd_pins xlconst_one/dout] [get_bd_pins axis_tap_0/m_axis_tready]

# 8->64 out -> sdr_chain ALT(64)
connect_bd_intf_net [get_bd_intf_pins axis_dw_8to64_0/M_AXIS]   [get_bd_intf_pins sdr_chain_0/S_AXIS_ALT]

# TEMP sink so TX handshakes happen
connect_bd_net [get_bd_pins xlconst_one/dout] [get_bd_pins sdr_chain_0/m_axis_tx_tready]

############################### ILA core(s)
# (unchanged) — your native ILA wiring below, left as-is

# create native ILA
create_bd_cell -type ip -vlnv xilinx.com:ip:ila:6.2 ila_axis_0

set_property -dict [list \
  CONFIG.C_MONITOR_TYPE {Native} \
  CONFIG.C_DATA_DEPTH {4096} \
  CONFIG.C_NUM_OF_PROBES {14} \
  CONFIG.C_PROBE0_WIDTH {8} \
  CONFIG.C_PROBE4_WIDTH {64} \
  CONFIG.C_PROBE5_WIDTH {8} \
  CONFIG.C_PROBE9_WIDTH {64} \
  CONFIG.C_PROBE10_WIDTH {8} \
] [get_bd_cells ila_axis_0]

# clock the ILA
connect_bd_net [get_bd_pins /zynq_ultra_ps_e_0/pl_clk0] [get_bd_pins /ila_axis_0/clk]

# (You purposely skipped probing S_AXIS — keep as you prefer)

# width-converter -> sdr_chain (M_AXIS, 64-bit)
connect_bd_net [get_bd_pins /ila_axis_0/probe4] [get_bd_pins /axis_dw_8to64_0/m_axis_tdata]
connect_bd_net [get_bd_pins /ila_axis_0/probe5] [get_bd_pins /axis_dw_8to64_0/m_axis_tkeep]
connect_bd_net [get_bd_pins /ila_axis_0/probe6] [get_bd_pins /axis_dw_8to64_0/m_axis_tvalid]
connect_bd_net [get_bd_pins /ila_axis_0/probe7] [get_bd_pins /axis_dw_8to64_0/m_axis_tready]
connect_bd_net [get_bd_pins /ila_axis_0/probe8] [get_bd_pins /axis_dw_8to64_0/m_axis_tlast]

# sdr_chain TX (M_AXIS_TX, 64-bit)
connect_bd_net [get_bd_pins /ila_axis_0/probe9]  [get_bd_pins /sdr_chain_0/m_axis_tx_tdata]
connect_bd_net [get_bd_pins /ila_axis_0/probe10] [get_bd_pins /sdr_chain_0/m_axis_tx_tkeep]
connect_bd_net [get_bd_pins /ila_axis_0/probe11] [get_bd_pins /sdr_chain_0/m_axis_tx_tvalid]
connect_bd_net [get_bd_pins /ila_axis_0/probe12] [get_bd_pins /sdr_chain_0/m_axis_tx_tready]
connect_bd_net [get_bd_pins /ila_axis_0/probe13] [get_bd_pins /sdr_chain_0/m_axis_tx_tlast]

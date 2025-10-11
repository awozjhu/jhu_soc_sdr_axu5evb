# Minimalized for: PS UART0 (MIO) + AXI-GPIO LED
# Non-essential IO and extras are commented with "## MIN:"

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

# Create 'sources_1' fileset (if not found)
if {[string equal [get_filesets -quiet sources_1] ""]} {
  create_fileset -srcset sources_1
}

file mkdir $projpath/$projName.srcs/sources_1/ip
file mkdir $projpath/$projName.srcs/sources_1/new

# Create 'constrs_1' fileset (if not found)
if {[string equal [get_filesets -quiet constrs_1] ""]} {
  create_fileset -constrset constrs_1
}
file mkdir $projpath/$projName.srcs/constrs_1/new

# Create 'sim_1' fileset (if not found)
if {[string equal [get_filesets -quiet constrs_1] ""]} {
  create_fileset -simset sim_1
}
file mkdir $projpath/$projName.srcs/sim_1/new

# set ip repo
set_property  ip_repo_paths  $projpath/ip_repo [current_project]
update_ip_catalog

set bdname "design_1"
create_bd_design $bdname

open_bd_design $projpath/$projName.srcs/sources_1/bd/$bdname/$bdname.bd

create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ultra_ps_e_0

source $projpath/auto_create_project/ps_config.tcl
set_ps_config zynq_ultra_ps_e_0

# --- PS configuration (keep GP0 for AXI-Lite control path) ---
set_property -dict [list CONFIG.PSU__USE__IRQ0 {1}] [get_bd_cells zynq_ultra_ps_e_0]
set_property -dict [list CONFIG.PSU__USE__IRQ1 {1}] [get_bd_cells zynq_ultra_ps_e_0]
set_property -dict [list CONFIG.PSU__USE__M_AXI_GP0 {1}] [get_bd_cells zynq_ultra_ps_e_0]

## MIN: Not needed for UART+LED control plane
# set_property -dict [list CONFIG.PSU__USE__S_AXI_GP2 {1}] [get_bd_cells zynq_ultra_ps_e_0]
# set_property -dict [list CONFIG.PSU__USE__S_AXI_GP3 {1}] [get_bd_cells zynq_ultra_ps_e_0]

## MIN: No EMIO GPIO for this minimal target
# set_property -dict [list CONFIG.PSU__GPIO_EMIO__PERIPHERAL__ENABLE {1}] [get_bd_cells zynq_ultra_ps_e_0]

## MIN: I2C0 over EMIO not required
# set_property -dict [list CONFIG.PSU__I2C0__PERIPHERAL__ENABLE {1} CONFIG.PSU__I2C0__PERIPHERAL__IO {EMIO}] [get_bd_cells zynq_ultra_ps_e_0]

# Per your note, leave UART1 EMIO line as-is (UART0 on MIO will be your console)
set_property -dict [list CONFIG.PSU__UART1__PERIPHERAL__ENABLE {1} CONFIG.PSU__UART1__PERIPHERAL__IO {EMIO}] [get_bd_cells zynq_ultra_ps_e_0]

# Keep PS ref clock freq override
set_property -dict [list CONFIG.PSU__PSS_REF_CLK__FREQMHZ {33.333333}] [get_bd_cells zynq_ultra_ps_e_0]

## MIN: EDID/EEPROM sources not needed for LED/ UART bring-up
# add_files -fileset sources_1  -copy_to $projpath/$projName.srcs/sources_1/new -force -quiet [glob -nocomplain $src_dir/hdl/edid/*.vhd]
# add_files -fileset sources_1  -copy_to $projpath/$projName.srcs/sources_1/new -force -quiet [glob -nocomplain $src_dir/hdl/edid/*.txt]
# update_compile_order -fileset sources_1
# create_bd_cell -type module -reference EEPROM_8b EEPROM_8b_0

source $tclpath/pl_config.tcl

regenerate_bd_layout

validate_bd_design
save_bd_design		 

make_wrapper -files [get_files $projpath/$projName.srcs/sources_1/bd/$bdname/$bdname.bd] -top
# add_files -norecurse [glob -nocomplain $projpath/$projName.srcs/sources_1/bd/$bdname/hdl/*.v]

# Add the BD wrapper HDL (handle .gen vs .srcs)
set wrap_files [glob -nocomplain $projpath/$projName.gen/sources_1/bd/$bdname/hdl/*.v]
if {[llength $wrap_files] == 0} {
  set wrap_files [glob -nocomplain $projpath/$projName.srcs/sources_1/bd/$bdname/hdl/*.v]
}
if {[llength $wrap_files]} {
  add_files -norecurse $wrap_files
} else {
  puts "WARNING: No wrapper HDL files found to add."
}


puts $bdname
append bdWrapperName $bdname "_wrapper"
puts $bdWrapperName
set_property top $bdWrapperName [current_fileset]

# Constraints:
# NOTE: This wildcard may pull in unused IO constraints (HDMI/SFP/etc).
# Leave enabled for now so LED pins get mapped, but if you hit "no nets matched"
# warnings/criticals, narrow to only base/system + LED XDCs.
add_files -fileset constrs_1  -copy_to $projpath/$projName.srcs/constrs_1/new -force -quiet [glob -nocomplain $src_dir/constraints/*.xdc]

generate_target all [get_files  $projpath/$projName.srcs/sources_1/bd/$bdname/$bdname.bd]

## MIN: XDMA GT XDC toggle not applicable in minimal build; can error if file absent
# set_property is_enabled false [get_files  $projpath/$projName.srcs/sources_1/bd/$bdname/ip/design_1_xdma_0_0/ip_0/ip_0/synth/design_1_xdma_0_0_pcie4_ip_gt.xdc]

launch_runs impl_1 -to_step write_bitstream -jobs $runs_jobs
wait_on_run impl_1 

write_hw_platform -fixed -force -include_bit -file $projpath/$bdWrapperName.xsa

close_project

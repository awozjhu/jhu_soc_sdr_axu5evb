# USAGE (repo root):
#   vivado -mode batch -source fpga/scripts/bringup_led_uart.tcl | tee vivado_bringup.log

# ===== User inputs =====
set PART      "xczu5ev-sfvc784-2-i"
set PS_UART   0                      ;# 0 or 1 depending on your USB-UART
set PROJ_NAME "bringup_led_uart"

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set PROJ_DIR   [file normalize "$SCRIPT_DIR/../proj/$PROJ_NAME"]
set XDC_FILE   [file normalize "$SCRIPT_DIR/../src/constraints/gpio.xdc"]
# ========================

file mkdir $PROJ_DIR
create_project $PROJ_NAME $PROJ_DIR -part $PART -force

# ---- Block design ----
create_bd_design "design_1"
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e zynq_ultra_ps_e_0]

# Enable the PS UART you’re using (console)
if { $PS_UART == 0 } {
  catch { set_property -dict [list CONFIG.PSU__UART0__PERIPHERAL__ENABLE {1}] $ps }
} else {
  catch { set_property -dict [list CONFIG.PSU__UART1__PERIPHERAL__ENABLE {1}] $ps }
}

# Provide a sane PL clock; harmless if already default
catch { set_property -dict [list CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100}] $ps }
catch { set_property -dict [list CONFIG.PSU__PL_CLK0_BUF {TRUE}] $ps }

# One AXI GPIO named like Alinx: 'pl_led'
#  - GPIO  (ch1): LED (output, width 1)
#  - GPIO2 (ch2): BTN (input,  width 1)
set pl_led [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio pl_led]
set_property -dict [list \
  CONFIG.C_GPIO_WIDTH {1} \
  CONFIG.C_ALL_OUTPUTS {1} \
  CONFIG.C_IS_DUAL {1} \
  CONFIG.C_GPIO2_WIDTH {1} \
  CONFIG.C_ALL_INPUTS_2 {1} \
] $pl_led

# Find a valid PS master AXI interface (names vary across Vivado/IP revs)
set masters {}
lappend masters {*}[get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD]
lappend masters {*}[get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM1_FPD]
lappend masters {*}[get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_LPD]
if {[llength $masters] == 0} {
  puts "ERROR: No PS master AXI interface (M_AXI_HPM*) found on zynq_ultra_ps_e_0."
  foreach p [lsort [get_bd_intf_pins -of_objects [get_bd_cells zynq_ultra_ps_e_0]]] { puts "  IFACE: $p" }
  error "Cannot proceed without a PS master AXI."
}
set ps_master [lindex $masters 0]
puts "Using PS master interface: $ps_master"

# Let Vivado wire AXI + clock + reset to S_AXI on pl_led
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
  -config [format {Master "%s" Clk "/zynq_ultra_ps_e_0/pl_clk0 (100 MHz)"} $ps_master] \
  [get_bd_intf_pins pl_led/S_AXI]

# External ports — match your gpio.xdc names
make_bd_pins_external [get_bd_pins pl_led/gpio_io_o]  -name leds_tri_o
make_bd_pins_external [get_bd_pins pl_led/gpio2_io_i] -name btns_tri_i

# Assign AXI addresses
assign_bd_address

# Validate/save
validate_bd_design
save_bd_design

# Wrapper + constraints
# Generate HDL wrapper and add it as the project top
set bd_file      "$PROJ_DIR/$PROJ_NAME.srcs/sources_1/bd/design_1/design_1.bd"
set wrapper_path [make_wrapper -files [get_files $bd_file] -top]

# Add wrapper to sources_1 and set top
add_files -norecurse $wrapper_path
update_compile_order -fileset sources_1
set_property top design_1_wrapper [current_fileset]

# Add constraints
add_files -fileset constrs_1 $XDC_FILE


# ---- Build ----
launch_runs synth_1 -jobs 1
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1

# ---- Export XSA (with bitstream) ----
file mkdir "$PROJ_DIR/export"
write_hw_platform -fixed -include_bit -force -file "$PROJ_DIR/export/${PROJ_NAME}.xsa"

puts "======================================================="
puts "DONE!"
puts "XSA: $PROJ_DIR/export/${PROJ_NAME}.xsa"
puts "BIT: $PROJ_DIR/$PROJ_NAME.runs/impl_1/${PROJ_NAME}.bit"
puts "======================================================="

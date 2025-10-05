# USAGE: from project root
# vivado -mode batch -source fpga/scripts/bringup_led_uart.tcl | tee vivado_bringup.log
# ===== User inputs =====
set PART      "xczu5ev-sfvc784-2-i"
set PS_UART   0
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

# Enable the PS UART you’re using
if { $PS_UART == 0 } {
  catch { set_property -dict [list CONFIG.PSU__UART0__PERIPHERAL__ENABLE {1}] $ps }
} else {
  catch { set_property -dict [list CONFIG.PSU__UART1__PERIPHERAL__ENABLE {1}] $ps }
}

# One AXI GPIO named like the Alinx script: 'pl_led'
#  - GPIO (ch1) : LED (output, width 1)
#  - GPIO2(ch2) : Button (input,  width 1)
set pl_led [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio pl_led]
set_property -dict [list \
  CONFIG.C_GPIO_WIDTH {1} \
  CONFIG.C_ALL_OUTPUTS {1} \
  CONFIG.C_IS_DUAL {1} \
  CONFIG.C_GPIO2_WIDTH {1} \
  CONFIG.C_ALL_INPUTS_2 {1} \
] $pl_led





# Make the PS provide a PL clock/reset and wire AXI by hand (robust)
catch { set_property -dict [list CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100}] $ps }
catch { set_property -dict [list CONFIG.PSU__PL_CLK0_BUF {TRUE}] $ps }
catch { set_property -dict [list CONFIG.PSU__USE__PL__CLK0 {1}] $ps }

# AXI4-Lite to HPM0_FPD
connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] [get_bd_intf_pins pl_led/S_AXI]
# Clock/reset
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0]    [get_bd_pins pl_led/s_axi_aclk]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] [get_bd_pins pl_led/s_axi_aresetn]




# External ports — MUST match your gpio.xdc
make_bd_pins_external [get_bd_pins pl_led/GPIO/io_o]  -name leds_tri_o
make_bd_pins_external [get_bd_pins pl_led/GPIO2/io_i] -name btns_tri_i

validate_bd_design
save_bd_design

# Wrapper + constraints
make_wrapper -files [get_files "$PROJ_DIR/$PROJ_NAME.srcs/sources_1/bd/design_1/design_1.bd"] -top
update_compile_order -fileset sources_1
add_files -fileset constrs_1 $XDC_FILE

# ---- Build ----
launch_runs synth_1 -jobs 8
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# ---- Export XSA (with bitstream) ----
file mkdir "$PROJ_DIR/export"
write_hw_platform -fixed -include_bit -force -file "$PROJ_DIR/export/${PROJ_NAME}.xsa"

puts "======================================================="
puts "DONE!"
puts "XSA: $PROJ_DIR/export/${PROJ_NAME}.xsa"
puts "BIT: $PROJ_DIR/$PROJ_NAME.runs/impl_1/${PROJ_NAME}.bit"
puts "======================================================="

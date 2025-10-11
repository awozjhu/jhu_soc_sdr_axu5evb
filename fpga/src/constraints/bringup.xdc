## Global
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

## LED0 (AXI GPIO -> LED)
set_property PACKAGE_PIN AE15 [get_ports {leds_tri_o[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {leds_tri_o[0]}]

## Optional: Button0 (only if 'btns' exists in BD)
set_property PACKAGE_PIN AE14 [get_ports {btns_tri_i[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btns_tri_i[0]}]

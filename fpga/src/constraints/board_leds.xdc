# TODO: set your board LED pin
set_property PACKAGE_PIN <PIN_NAME> [get_ports {led_o}]
set_property IOSTANDARD LVCMOS33    [get_ports {led_o}]
set_property DRIVE 8                [get_ports {led_o}]
set_property SLEW SLOW              [get_ports {led_o}]

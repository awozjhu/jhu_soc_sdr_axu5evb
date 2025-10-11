  # =============================
  # Minimal PL config for UART0 (PS on MIO) + LED (AXI GPIO) + Button
  # Non-essential lines commented with "## MIN:"
  # Added minimal clock/reset nets are marked "## MIN: ADDED"
  # =============================

  # Create interface ports
  ## MIN: RS485 not used
  # set RS485_0_DE [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 RS485_0_DE ]

  ## MIN: RS485 not used
  # set RS485_1_DE [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 RS485_1_DE ]

  # KEEP: Buttons interface
  set btns [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 btns ]

  ## MIN: External DDR4 (PL MIG) interface not used
  # set c0_ddr4 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 c0_ddr4 ]

  ## MIN: I2C for camera not used
  # set cam_i2c [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0 cam_i2c ]

  ## MIN: Fan GPIO not used
  # set fan [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 fan ]

  ## MIN: HDMI I2C not used
  # set hdmi_in_i2c [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0 hdmi_in_i2c ]
  ## MIN: HDMI I2C not used
  # set hdmi_out_i2c [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0 hdmi_out_i2c ]

  ## MIN: HDMI resetn not used
  # set hdmi_rstn [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 hdmi_rstn ]

  # KEEP: LEDs interface for external pin mapping
  set leds [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 leds ]

  ## MIN: MDIO not used
  # set mdio [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:mdio_rtl:1.0 mdio ]

  ## MIN: MIPI not used
  # set mipi_phy_if [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:mipi_phy_rtl:1.0 mipi_phy_if ]

  ## MIN: PCIe not used
  # set pcie_mgt [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:pcie_7x_mgt_rtl:1.0 pcie_mgt ]
  ## MIN: PCIe refclk not used
  # set pcie_ref [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 pcie_ref ]

  ## MIN: Ethernet RGMII not used
  # set rgmii [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:rgmii_rtl:1.0 rgmii ]

  ## MIN: External sys_clk not used (we’ll use PS FCLK0)
  # set sys_clk [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 sys_clk ]
  # set_property -dict [ list CONFIG.FREQ_HZ {200000000} ] $sys_clk

  ## MIN: PS UART1 via EMIO interface port to PL not used in minimal
  # set uart [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:uart_rtl:1.0 uart ]


  # Create ports (discrete pins) — all unused for minimal
  ## MIN:
  # set RS485_0_rxd [ create_bd_port -dir I RS485_0_rxd ]
  ## MIN:
  # set RS485_0_txd [ create_bd_port -dir O RS485_0_txd ]
  ## MIN:
  # set RS485_1_rxd [ create_bd_port -dir I RS485_1_rxd ]
  ## MIN:
  # set RS485_1_txd [ create_bd_port -dir O RS485_1_txd ]
  ## MIN:
  # set cam_gpio [ create_bd_port -dir O -from 0 -to 0 cam_gpio ]
  ## MIN:
  # set edid_scl [ create_bd_port -dir IO edid_scl ]
  ## MIN:
  # set edid_sda [ create_bd_port -dir IO edid_sda ]
  ## MIN:
  # set hdmi_in_clk [ create_bd_port -dir I -type clk -freq_hz 74250000 hdmi_in_clk ]
  ## MIN:
  # set hdmi_in_data [ create_bd_port -dir I -from 23 -to 0 hdmi_in_data ]
  ## MIN:
  # set hdmi_in_de [ create_bd_port -dir I hdmi_in_de ]
  ## MIN:
  # set hdmi_in_hs [ create_bd_port -dir I hdmi_in_hs ]
  ## MIN:
  # set hdmi_in_vs [ create_bd_port -dir I hdmi_in_vs ]
  ## MIN:
  # set hdmi_out_clk [ create_bd_port -dir O -type clk hdmi_out_clk ]
  ## MIN:
  # set hdmi_out_data [ create_bd_port -dir O -from 23 -to 0 hdmi_out_data ]
  ## MIN:
  # set hdmi_out_de [ create_bd_port -dir O hdmi_out_de ]
  ## MIN:
  # set hdmi_out_hs [ create_bd_port -dir O hdmi_out_hs ]
  ## MIN:
  # set hdmi_out_vs [ create_bd_port -dir O hdmi_out_vs ]
  ## MIN:
  # set hpd [ create_bd_port -dir O -from 0 -to 0 hpd ]
  ## MIN:
  # set pcie_rst_n [ create_bd_port -dir I -type rst pcie_rst_n ]
  ## MIN:
  # set phy_reset_n [ create_bd_port -dir O -from 0 -to 0 -type rst phy_reset_n ]
  ## MIN:
  # set_property -dict [ list CONFIG.POLARITY {ACTIVE_LOW} ] $phy_reset_n


  # Create instance: EEPROM_8b_0 (unused)
  ## MIN:
  # set_property -dict [ list CONFIG.kInitFileName {1080_edid.txt} CONFIG.kSampleClkFreqInMHz {200} ] [get_bd_cells EEPROM_8b_0]

  ## MIN:
  # set axi_dynclk_0 [ create_bd_cell -type ip -vlnv digilentinc.com:ip:axi_dynclk:1.0 axi_dynclk_0 ]

  ## MIN:
  # set axi_ethernet_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_ethernet:7.2 axi_ethernet_0 ]
  # set_property -dict [ list CONFIG.PHY_TYPE {RGMII} ] $axi_ethernet_0

  ## MIN:
  # set axi_ethernet_0_dma [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_ethernet_0_dma ]
  # set_property -dict [ list CONFIG.c_addr_width {64} CONFIG.c_include_mm2s_dre {1} CONFIG.c_include_s2mm_dre {1} CONFIG.c_sg_length_width {16} CONFIG.c_sg_use_stsapp_length {1} ] $axi_ethernet_0_dma

  ## MIN:
  # set axi_ethernet_0_refclk [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 axi_ethernet_0_refclk ]
  # set_property -dict [ list CONFIG.CLKIN1_JITTER_PS {50.0} CONFIG.CLKOUT1_JITTER {83.559} CONFIG.CLKOUT1_PHASE_ERROR {73.186} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200} CONFIG.CLKOUT2_JITTER {91.406} CONFIG.CLKOUT2_PHASE_ERROR {73.186} CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125} CONFIG.CLKOUT2_USED {true} CONFIG.CLKOUT3_JITTER {77.345} CONFIG.CLKOUT3_PHASE_ERROR {73.186} CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {300.000} CONFIG.CLKOUT3_USED {true} CONFIG.MMCM_CLKFBOUT_MULT_F {7.500} CONFIG.MMCM_CLKIN1_PERIOD {5.000} CONFIG.MMCM_CLKIN2_PERIOD {10.0} CONFIG.MMCM_CLKOUT0_DIVIDE_F {7.500} CONFIG.MMCM_CLKOUT1_DIVIDE {12} CONFIG.MMCM_CLKOUT2_DIVIDE {5} CONFIG.NUM_OUT_CLKS {3} CONFIG.PRIM_IN_FREQ {200.000} CONFIG.PRIM_SOURCE {No_buffer} CONFIG.USE_RESET {false} ] $axi_ethernet_0_refclk

  ## MIN:
  # set axi_iic_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_iic:2.0 axi_iic_0 ]
  ## MIN:
  # set axi_iic_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_iic:2.0 axi_iic_1 ]

  ## MIN:
  # set axi_interconnect_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0 ]
  # set_property -dict [ list CONFIG.NUM_MI {1} CONFIG.NUM_SI {3} ] $axi_interconnect_0

  ## MIN:
  # set axi_interconnect_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_1 ]
  # set_property -dict [ list CONFIG.NUM_MI {1} CONFIG.NUM_SI {3} ] $axi_interconnect_1

  ## MIN:
  # set axi_interconnect_2 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_2 ]
  # set_property -dict [ list CONFIG.NUM_MI {1} CONFIG.NUM_SI {2} ] $axi_interconnect_2

  ## MIN:
  # set axi_uart16550_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uart16550:2.0 axi_uart16550_0 ]
  # set_property -dict [ list CONFIG.C_S_AXI_ACLK_FREQ_HZ {200000000} ] $axi_uart16550_0

  ## MIN:
  # set axi_uart16550_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uart16550:2.0 axi_uart16550_1 ]
  # set_property -dict [ list CONFIG.C_S_AXI_ACLK_FREQ_HZ {200000000} ] $axi_uart16550_1

  ## MIN:
  # set axi_vdma_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma:6.3 axi_vdma_0 ]
  # set_property -dict [ list CONFIG.c_addr_width {64} CONFIG.c_include_mm2s {0} CONFIG.c_include_s2mm_dre {1} CONFIG.c_m_axi_s2mm_data_width {128} CONFIG.c_s2mm_genlock_mode {0} CONFIG.c_s2mm_linebuffer_depth {2048} CONFIG.c_s2mm_max_burst_length {128} ] $axi_vdma_0

  ## MIN:
  # set axi_vdma_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma:6.3 axi_vdma_1 ]
  # set_property -dict [ list CONFIG.c_addr_width {64} CONFIG.c_include_mm2s_dre {1} CONFIG.c_include_s2mm {0} CONFIG.c_m_axi_mm2s_data_width {128} CONFIG.c_m_axis_mm2s_tdata_width {24} CONFIG.c_mm2s_genlock_mode {1} CONFIG.c_mm2s_linebuffer_depth {2048} CONFIG.c_mm2s_max_burst_length {128} ] $axi_vdma_1

  ## MIN:
  # set axis_subset_converter_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_subset_converter:1.1 axis_subset_converter_0 ]
  # set_property -dict [ list CONFIG.M_HAS_TLAST {1} CONFIG.M_TDATA_NUM_BYTES {6} CONFIG.M_TUSER_WIDTH {1} CONFIG.S_HAS_TLAST {1} CONFIG.S_TDATA_NUM_BYTES {4} CONFIG.S_TUSER_WIDTH {1} CONFIG.TDATA_REMAP {16'b0000000000000000,tdata[31:0]} CONFIG.TLAST_REMAP {tlast[0]} CONFIG.TUSER_REMAP {tuser[0:0]} ] $axis_subset_converter_0

  ## MIN:
  # set csc_rst_gpio [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 csc_rst_gpio ]
  ## MIN:
  # set ddr4_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4:2.2 ddr4_0 ]
  ## MIN:
  # set fan_gpio [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 fan_gpio ]
  ## MIN:
  # set frmbuf_wr_rst_gpio [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 frmbuf_wr_rst_gpio ]
  ## MIN:
  # set hdmi_rst_gpio [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 hdmi_rst_gpio ]
  ## MIN:
  # set mipi_csi2_rx_subsyst_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:mipi_csi2_rx_subsystem:5.0 mipi_csi2_rx_subsyst_0 ]

  # KEEP: AXI-GPIO for Button (inputs)
  set pl_key [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 pl_key ]
  set_property -dict [ list \
   CONFIG.C_ALL_INPUTS {1} \
   CONFIG.C_ALL_OUTPUTS {0} \
   CONFIG.C_GPIO_WIDTH {1} \
   CONFIG.C_INTERRUPT_PRESENT {1} \
 ] $pl_key

  # KEEP: AXI-GPIO for LED (output)
  set pl_led [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 pl_led ]
  set_property -dict [ list \
   CONFIG.C_ALL_OUTPUTS {1} \
   CONFIG.C_GPIO_WIDTH {1} \
 ] $pl_led

  ## MIN: second proc_sys_reset not used
  # set proc_sys_reset_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0 ]

  # KEEP: AXI interconnect from PS (we’ll use S00 + M06/M07 only)
  set ps8_0_axi_periph [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ps8_0_axi_periph ]
  set_property -dict [ list CONFIG.NUM_MI {19} ] $ps8_0_axi_periph

  ## MIN:
  # set rs485de [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 rs485de ]
  ## MIN:
  # set rs485de1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 rs485de1 ]

  # KEEP: Reset block to generate aresetn
  set rst_ps8_0_200M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps8_0_200M ]

  ## MIN:
  # set util_ds_buf_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.1 util_ds_buf_0 ]
  ## MIN:
  # set util_ds_buf_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.1 util_ds_buf_1 ]
  ## MIN:
  # set_property -dict [ list CONFIG.C_BUF_TYPE {IBUFDSGTE} ] $util_ds_buf_1

  ## MIN:
  # set util_vector_logic_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 util_vector_logic_1 ]
  # set_property -dict [ list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {1} CONFIG.LOGO_FILE {data/sym_notgate.png} ] $util_vector_logic_1

  ## MIN:
  # set v_axi4s_vid_out_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:v_axi4s_vid_out:4.0 v_axi4s_vid_out_0 ]
  ## MIN:
  # set v_frmbuf_wr_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:v_frmbuf_wr:2.1 v_frmbuf_wr_0 ]
  ## MIN:
  # set v_proc_ss_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:v_proc_ss:2.2 v_proc_ss_0 ]
  ## MIN:
  # set v_tc_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:v_tc:6.2 v_tc_0 ]
  ## MIN:
  # set v_vid_in_axi4s_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:v_vid_in_axi4s:4.0 v_vid_in_axi4s_0 ]
  ## MIN:
  # set xdma_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xdma:4.1 xdma_0 ]

  ## MIN:
  # set xlconcat_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0 ]
  # set_property -dict [ list CONFIG.NUM_PORTS {7} ] $xlconcat_0

  ## MIN:
  # set xlconcat_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_1 ]
  # set_property -dict [ list CONFIG.NUM_PORTS {6} ] $xlconcat_1

  ## MIN:
  # set xlconstant_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_0 ]
  # set_property -dict [ list CONFIG.CONST_VAL {0} ] $xlconstant_0

  ## MIN:
  # set xlconstant_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_1 ]
  # set_property -dict [ list CONFIG.CONST_VAL {1} ] $xlconstant_1

  ## MIN:
  # set xlconstant_2 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_2 ]
  ## MIN:
  # set xlconstant_3 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_3 ]
  ## MIN:
  # set xlconstant_4 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_4 ]


  # Create interface connections
  ## MIN:
  # connect_bd_intf_net -intf_net CLK_IN_D_0_1 [get_bd_intf_ports sys_clk] [get_bd_intf_pins util_ds_buf_0/CLK_IN_D]
  ## MIN:
  # connect_bd_intf_net -intf_net CLK_IN_D_0_2 [get_bd_intf_ports pcie_ref] [get_bd_intf_pins util_ds_buf_1/CLK_IN_D]
  ## MIN:
  # connect_bd_intf_net -intf_net S00_AXI_1 [get_bd_intf_pins axi_ethernet_0_dma/M_AXI_SG] [get_bd_intf_pins axi_interconnect_0/S00_AXI]
  ## MIN:
  # connect_bd_intf_net -intf_net S00_AXI_2 [get_bd_intf_pins axi_interconnect_2/S00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD]
  ## MIN:
  # connect_bd_intf_net -intf_net S01_AXI_1 [get_bd_intf_pins axi_ethernet_0_dma/M_AXI_MM2S] [get_bd_intf_pins axi_interconnect_0/S01_AXI]
  ## MIN:
  # connect_bd_intf_net -intf_net S02_AXI_1 [get_bd_intf_pins axi_ethernet_0_dma/M_AXI_S2MM] [get_bd_intf_pins axi_interconnect_0/S02_AXI]
  ## MIN:
  # connect_bd_intf_net -intf_net axi_ethernet_0_dma_M_AXIS_CNTRL [get_bd_intf_pins axi_ethernet_0/s_axis_txc] [get_bd_intf_pins axi_ethernet_0_dma/M_AXIS_CNTRL]
  ## MIN:
  # connect_bd_intf_net -intf_net axi_ethernet_0_dma_M_AXIS_MM2S [get_bd_intf_pins axi_ethernet_0/s_axis_txd] [get_bd_intf_pins axi_ethernet_0_dma/M_AXIS_MM2S]
  ## MIN:
  # connect_bd_intf_net -intf_net axi_ethernet_0_m_axis_rxd [get_bd_intf_pins axi_ethernet_0/m_axis_rxd] [get_bd_intf_pins axi_ethernet_0_dma/S_AXIS_S2MM]
  ## MIN:
  # connect_bd_intf_net -intf_net axi_ethernet_0_m_axis_rxs [get_bd_intf_pins axi_ethernet_0/m_axis_rxs] [get_bd_intf_pins axi_ethernet_0_dma/S_AXIS_STS]
  ## MIN:
  # connect_bd_intf_net -intf_net axi_ethernet_0_mdio [get_bd_intf_ports mdio] [get_bd_intf_pins axi_ethernet_0/mdio]
  ## MIN:
  # connect_bd_intf_net -intf_net axi_ethernet_0_rgmii [get_bd_intf_ports rgmii] [get_bd_intf_pins axi_ethernet_0/rgmii]
  ## MIN:
  # connect_bd_intf_net -intf_net axi_iic_0_IIC [get_bd_intf_ports hdmi_in_i2c] [get_bd_intf_pins axi_iic_0/IIC]
  ## MIN:
  # connect_bd_intf_net -intf_net axi_iic_1_IIC [get_bd_intf_ports hdmi_out_i2c] [get_bd_intf_pins axi_iic_1/IIC]
  ## MIN:
  # connect_bd_intf_net -intf_net axi_interconnect_0_M00_AXI [get_bd_intf_pins axi_interconnect_0/M00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP0_FPD]
  ## MIN:
  # connect_bd_intf_net -intf_net axi_interconnect_1_M00_AXI [get_bd_intf_pins axi_interconnect_1/M00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP1_FPD]
  ## MIN:
  # connect_bd_intf_net -intf_net axi_interconnect_2_M00_AXI [get_bd_intf_pins axi_interconnect_2/M00_AXI] [get_bd_intf_pins ddr4_0/C0_DDR4_S_AXI]
  ## MIN:
  # connect_bd_intf_net -intf_net axi_vdma_0_M_AXI_S2MM [get_bd_intf_pins axi_interconnect_1/S01_AXI] [get_bd_intf_pins axi_vdma_0/M_AXI_S2MM]
  ## MIN:
  # connect_bd_intf_net -intf_net axi_vdma_1_M_AXIS_MM2S [get_bd_intf_pins axi_vdma_1/M_AXIS_MM2S] [get_bd_intf_pins v_axi4s_vid_out_0/video_in]
  ## MIN:
  # connect_bd_intf_net -intf_net axi_vdma_1_M_AXI_MM2S [get_bd_intf_pins axi_interconnect_1/S02_AXI] [get_bd_intf_pins axi_vdma_1/M_AXI_MM2S]
  ## MIN:
  # connect_bd_intf_net -intf_net axis_subset_converter_0_M_AXIS [get_bd_intf_pins axis_subset_converter_0/M_AXIS] [get_bd_intf_pins v_proc_ss_0/s_axis]
  ## MIN:
  # connect_bd_intf_net -intf_net ddr4_0_C0_DDR4 [get_bd_intf_ports c0_ddr4] [get_bd_intf_pins ddr4_0/C0_DDR4]
  ## MIN:
  # connect_bd_intf_net -intf_net fan_gpio_GPIO [get_bd_intf_ports fan] [get_bd_intf_pins fan_gpio/GPIO]
  ## MIN:
  # connect_bd_intf_net -intf_net hdmi_rst_gpio_GPIO [get_bd_intf_ports hdmi_rstn] [get_bd_intf_pins hdmi_rst_gpio/GPIO]
  ## MIN:
  # connect_bd_intf_net -intf_net mipi_csi2_rx_subsyst_0_video_out [get_bd_intf_pins axis_subset_converter_0/S_AXIS] [get_bd_intf_pins mipi_csi2_rx_subsyst_0/video_out]
  ## MIN:
  # connect_bd_intf_net -intf_net mipi_phy_if_0_1 [get_bd_intf_ports mipi_phy_if] [get_bd_intf_pins mipi_csi2_rx_subsyst_0/mipi_phy_if]

  # KEEP: Buttons to GPIO
  connect_bd_intf_net -intf_net pl_key_GPIO [get_bd_intf_ports btns] [get_bd_intf_pins pl_key/GPIO]

  # KEEP: LEDs to GPIO
  connect_bd_intf_net -intf_net pl_led_GPIO [get_bd_intf_ports leds] [get_bd_intf_pins pl_led/GPIO]

  ## MIN:
  # connect_bd_intf_net -intf_net ps8_0_axi_periph_M00_AXI [get_bd_intf_pins axi_ethernet_0/s_axi] [get_bd_intf_pins ps8_0_axi_periph/M00_AXI]
  ## MIN:
  # connect_bd_intf_net -intf_net ps8_0_axi_periph_M01_AXI [get_bd_intf_pins axi_ethernet_0_dma/S_AXI_LITE] [get_bd_intf_pins ps8_0_axi_periph/M01_AXI]

  ## MIN: PL UARTs not used
  # connect_bd_intf_net -intf_net ps8_0_axi_periph_M02_AXI [get_bd_intf_pins axi_uart16550_0/S_AXI] [get_bd_intf_pins ps8_0_axi_periph/M02_AXI]
  # connect_bd_intf_net -intf_net ps8_0_axi_periph_M03_AXI [get_bd_intf_pins axi_uart16550_1/S_AXI] [get_bd_intf_pins ps8_0_axi_periph/M03_AXI]

  ## MIN:
  # connect_bd_intf_net -intf_net ps8_0_axi_periph_M04_AXI [get_bd_intf_pins fan_gpio/S_AXI] [get_bd_intf_pins ps8_0_axi_periph/M04_AXI]
  ## MIN:
  # connect_bd_intf_net -intf_net ps8_0_axi_periph_M05_AXI [get_bd_intf_pins axi_dynclk_0/s00_axi] [get_bd_intf_pins ps8_0_axi_periph/M05_AXI]

  # KEEP: PS→AXI (M06) for button
  connect_bd_intf_net -intf_net ps8_0_axi_periph_M06_AXI [get_bd_intf_pins pl_key/S_AXI] [get_bd_intf_pins ps8_0_axi_periph/M06_AXI]

  # KEEP: PS→AXI (M07) for LED
  connect_bd_intf_net -intf_net ps8_0_axi_periph_M07_AXI [get_bd_intf_pins pl_led/S_AXI] [get_bd_intf_pins ps8_0_axi_periph/M07_AXI]

  ## MIN: everything else on ps8_0_axi_periph MI disabled
  # connect_bd_intf_net -intf_net ps8_0_axi_periph_M08_AXI [get_bd_intf_pins ps8_0_axi_periph/M08_AXI] [get_bd_intf_pins rs485de/S_AXI]
  # connect_bd_intf_net -intf_net ps8_0_axi_periph_M09_AXI [get_bd_intf_pins ps8_0_axi_periph/M09_AXI] [get_bd_intf_pins rs485de1/S_AXI]
  # connect_bd_intf_net -intf_net ps8_0_axi_periph_M10_AXI [get_bd_intf_pins mipi_csi2_rx_subsyst_0/csirxss_s_axi] [get_bd_intf_pins ps8_0_axi_periph/M10_AXI]
  # connect_bd_intf_net -intf_net ps8_0_axi_periph_M11_AXI [get_bd_intf_pins ps8_0_axi_periph/M11_AXI] [get_bd_intf_pins v_frmbuf_wr_0/s_axi_CTRL]
  # connect_bd_intf_net -intf_net ps8_0_axi_periph_M12_AXI [get_bd_intf_pins ps8_0_axi_periph/M12_AXI] [get_bd_intf_pins v_proc_ss_0/s_axi_ctrl]
  # connect_bd_intf_net -intf_net ps8_0_axi_periph_M13_AXI [get_bd_intf_pins axi_vdma_0/S_AXI_LITE] [get_bd_intf_pins ps8_0_axi_periph/M13_AXI]
  # connect_bd_intf_net -intf_net ps8_0_axi_periph_M14_AXI [get_bd_intf_pins axi_vdma_1/S_AXI_LITE] [get_bd_intf_pins ps8_0_axi_periph/M14_AXI]
  # connect_bd_intf_net -intf_net ps8_0_axi_periph_M15_AXI [get_bd_intf_pins ps8_0_axi_periph/M15_AXI] [get_bd_intf_pins v_tc_0/ctrl]
  # connect_bd_intf_net -intf_net ps8_0_axi_periph_M16_AXI [get_bd_intf_pins hdmi_rst_gpio/S_AXI] [get_bd_intf_pins ps8_0_axi_periph/M16_AXI]
  # connect_bd_intf_net -intf_net ps8_0_axi_periph_M17_AXI [get_bd_intf_pins axi_iic_0/S_AXI] [get_bd_intf_pins ps8_0_axi_periph/M17_AXI]
  # connect_bd_intf_net -intf_net ps8_0_axi_periph_M18_AXI [get_bd_intf_pins axi_iic_1/S_AXI] [get_bd_intf_pins ps8_0_axi_periph/M18_AXI]

  ## MIN:
  # connect_bd_intf_net -intf_net rs485de1_GPIO [get_bd_intf_ports RS485_1_DE] [get_bd_intf_pins rs485de1/GPIO]
  ## MIN:
  # connect_bd_intf_net -intf_net rs485de_GPIO [get_bd_intf_ports RS485_0_DE] [get_bd_intf_pins rs485de/GPIO]
  ## MIN:
  # connect_bd_intf_net -intf_net v_frmbuf_wr_0_m_axi_mm_video [get_bd_intf_pins axi_interconnect_1/S00_AXI] [get_bd_intf_pins v_frmbuf_wr_0/m_axi_mm_video]
  ## MIN:
  # connect_bd_intf_net -intf_net v_proc_ss_0_m_axis [get_bd_intf_pins v_frmbuf_wr_0/s_axis_video] [get_bd_intf_pins v_proc_ss_0/m_axis]
  ## MIN:
  # connect_bd_intf_net -intf_net v_tc_0_vtiming_out [get_bd_intf_pins v_axi4s_vid_out_0/vtiming_in] [get_bd_intf_pins v_tc_0/vtiming_out]
  ## MIN:
  # connect_bd_intf_net -intf_net v_vid_in_axi4s_0_video_out [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM] [get_bd_intf_pins v_vid_in_axi4s_0/video_out]
  ## MIN:
  # connect_bd_intf_net -intf_net xdma_0_M_AXI [get_bd_intf_pins axi_interconnect_2/S01_AXI] [get_bd_intf_pins xdma_0/M_AXI]
  ## MIN:
  # connect_bd_intf_net -intf_net xdma_0_pcie_mgt [get_bd_intf_ports pcie_mgt] [get_bd_intf_pins xdma_0/pcie_mgt]

  # KEEP: PS master to AXI interconnect S00
  connect_bd_intf_net -intf_net zynq_ultra_ps_e_0_M_AXI_HPM0_LPD [get_bd_intf_pins ps8_0_axi_periph/S00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_LPD]

  ## MIN: PS I2C/UART EMIO to PL not used
  # connect_bd_intf_net -intf_net zynq_ultra_ps_e_0_IIC_0 [get_bd_intf_ports cam_i2c] [get_bd_intf_pins zynq_ultra_ps_e_0/IIC_0]
  # connect_bd_intf_net -intf_net zynq_ultra_ps_e_0_UART_1 [get_bd_intf_ports uart] [get_bd_intf_pins zynq_ultra_ps_e_0/UART_1]


  # Create port connections (clocks/resets/IRQs)
  ## MIN:
  # connect_bd_net -net M00_ACLK_1 [get_bd_pins axi_interconnect_2/M00_ACLK] [get_bd_pins ddr4_0/c0_ddr4_ui_clk] [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
  ## MIN:
  # connect_bd_net -net Net [get_bd_pins csc_rst_gpio/Din] [get_bd_pins frmbuf_wr_rst_gpio/Din] [get_bd_pins zynq_ultra_ps_e_0/emio_gpio_o]
  ## MIN:
  # connect_bd_net -net Net1 [get_bd_ports edid_sda] [get_bd_pins EEPROM_8b_0/aSDA]
  ## MIN:
  # connect_bd_net -net Net2 [get_bd_ports edid_scl] [get_bd_pins EEPROM_8b_0/aSCL]

  ## MIN: Big clock tree driven by clk_wiz — not used
  # connect_bd_net -net axi_ethernet_0_refclk_clk_out2 [get_bd_pins axi_ethernet_0/gtx_clk] [get_bd_pins axi_ethernet_0_refclk/clk_out2]
  # connect_bd_net -net axi_ethernet_0_refclk_clk_out3 [get_bd_pins EEPROM_8b_0/SampleClk] [get_bd_pins axi_dynclk_0/s00_axi_aclk] [get_bd_pins axi_ethernet_0/axis_clk] [get_bd_pins axi_ethernet_0/s_axi_lite_clk] [get_bd_pins axi_ethernet_0_dma/m_axi_mm2s_aclk] [get_bd_pins axi_ethernet_0_dma/m_axi_s2mm_aclk] [get_bd_pins axi_ethernet_0_dma/m_axi_sg_aclk] [get_bd_pins axi_ethernet_0_dma/s_axi_lite_aclk] [get_bd_pins axi_ethernet_0_refclk/clk_out1] [get_bd_pins axi_iic_0/s_axi_aclk] [get_bd_pins axi_iic_1/s_axi_aclk] [get_bd_pins axi_interconnect_0/ACLK] [get_bd_pins axi_interconnect_0/M00_ACLK] [get_bd_pins axi_interconnect_0/S00_ACLK] [get_bd_pins axi_interconnect_0/S01_ACLK] [get_bd_pins axi_interconnect_0/S02_ACLK] [get_bd_pins axi_interconnect_1/ACLK] [get_bd_pins axi_interconnect_1/M00_ACLK] [get_bd_pins axi_interconnect_1/S00_ACLK] [get_bd_pins axi_interconnect_1/S01_ACLK] [get_bd_pins axi_interconnect_1/S02_ACLK] [get_bd_pins axi_interconnect_2/ACLK] [get_bd_pins axi_interconnect_2/S00_ACLK] [get_bd_pins axi_uart16550_0/s_axi_aclk] [get_bd_pins axi_uart16550_1/s_axi_aclk] [get_bd_pins axi_vdma_0/m_axi_s2mm_aclk] [get_bd_pins axi_vdma_0/s_axi_lite_aclk] [get_bd_pins axi_vdma_0/s_axis_s2mm_aclk] [get_bd_pins axi_vdma_1/m_axi_mm2s_aclk] [get_bd_pins axi_vdma_1/m_axis_mm2s_aclk] [get_bd_pins axi_vdma_1/s_axi_lite_aclk] [get_bd_pins axis_subset_converter_0/aclk] [get_bd_pins fan_gpio/s_axi_aclk] [get_bd_pins hdmi_rst_gpio/s_axi_aclk] [get_bd_pins mipi_csi2_rx_subsyst_0/dphy_clk_200M] [get_bd_pins mipi_csi2_rx_subsyst_0/lite_aclk] [get_bd_pins mipi_csi2_rx_subsyst_0/video_aclk] [get_bd_pins pl_key/s_axi_aclk] [get_bd_pins pl_led/s_axi_aclk] [get_bd_pins ps8_0_axi_periph/ACLK] [get_bd_pins ps8_0_axi_periph/M00_ACLK] [get_bd_pins ps8_0_axi_periph/M01_ACLK] [get_bd_pins ps8_0_axi_periph/M02_ACLK] [get_bd_pins ps8_0_axi_periph/M03_ACLK] [get_bd_pins ps8_0_axi_periph/M04_ACLK] [get_bd_pins ps8_0_axi_periph/M05_ACLK] [get_bd_pins ps8_0_axi_periph/M06_ACLK] [get_bd_pins ps8_0_axi_periph/M07_ACLK] [get_bd_pins ps8_0_axi_periph/M08_ACLK] [get_bd_pins ps8_0_axi_periph/M09_ACLK] [get_bd_pins ps8_0_axi_periph/M10_ACLK] [get_bd_pins ps8_0_axi_periph/M11_ACLK] [get_bd_pins ps8_0_axi_periph/M12_ACLK] [get_bd_pins ps8_0_axi_periph/M13_ACLK] [get_bd_pins ps8_0_axi_periph/M14_ACLK] [get_bd_pins ps8_0_axi_periph/M15_ACLK] [get_bd_pins ps8_0_axi_periph/M16_ACLK] [get_bd_pins ps8_0_axi_periph/M17_ACLK] [get_bd_pins ps8_0_axi_periph/M18_ACLK] [get_bd_pins ps8_0_axi_periph/S00_ACLK] [get_bd_pins rs485de/s_axi_aclk] [get_bd_pins rs485de1/s_axi_aclk] [get_bd_pins rst_ps8_0_200M/slowest_sync_clk] [get_bd_pins v_axi4s_vid_out_0/aclk] [get_bd_pins v_frmbuf_wr_0/ap_clk] [get_bd_pins v_proc_ss_0/aclk] [get_bd_pins v_tc_0/s_axi_aclk] [get_bd_pins v_vid_in_axi4s_0/aclk] [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk] [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_lpd_aclk] [get_bd_pins zynq_ultra_ps_e_0/saxihp0_fpd_aclk] [get_bd_pins zynq_ultra_ps_e_0/saxihp1_fpd_aclk]

  ## MIN:
  # connect_bd_net -net axi_ethernet_0_refclk_clk_out4 [get_bd_pins axi_ethernet_0/ref_clk] [get_bd_pins axi_ethernet_0_refclk/clk_out3]
  ## MIN:
  # connect_bd_net -net axi_iic_0_iic2intc_irpt [get_bd_pins axi_iic_0/iic2intc_irpt] [get_bd_pins xlconcat_1/In4]
  ## MIN:
  # connect_bd_net -net axi_iic_1_iic2intc_irpt [get_bd_pins axi_iic_1/iic2intc_irpt] [get_bd_pins xlconcat_1/In5]
  ## MIN:
  # connect_bd_net -net axi_uart16550_0_ip2intc_irpt [get_bd_pins axi_uart16550_0/ip2intc_irpt] [get_bd_pins xlconcat_0/In4]
  ## MIN:
  # connect_bd_net -net axi_uart16550_0_sout [get_bd_ports RS485_0_txd] [get_bd_pins axi_uart16550_0/sout]
  ## MIN:
  # connect_bd_net -net axi_uart16550_1_ip2intc_irpt [get_bd_pins axi_uart16550_1/ip2intc_irpt] [get_bd_pins xlconcat_0/In5]
  ## MIN:
  # connect_bd_net -net axi_uart16550_1_sout [get_bd_ports RS485_1_txd] [get_bd_pins axi_uart16550_1/sout]
  ## MIN:
  # connect_bd_net -net axi_vdma_0_s2mm_introut [get_bd_pins axi_vdma_0/s2mm_introut] [get_bd_pins xlconcat_1/In2]
  ## MIN:
  # connect_bd_net -net axi_vdma_1_mm2s_introut [get_bd_pins axi_vdma_1/mm2s_introut] [get_bd_pins xlconcat_1/In3]
  ## MIN:
  # connect_bd_net -net csc_rst_gpio_Dout [get_bd_pins csc_rst_gpio/Dout] [get_bd_pins ps8_0_axi_periph/M12_ARESETN] [get_bd_pins v_proc_ss_0/aresetn]
  ## MIN:
  # connect_bd_net -net ddr4_0_c0_ddr4_ui_clk_sync_rst [get_bd_pins ddr4_0/c0_ddr4_ui_clk_sync_rst] [get_bd_pins proc_sys_reset_0/ext_reset_in]
  ## MIN:
  # connect_bd_net -net frmbuf_wr_rst_gpio_Dout [get_bd_pins axis_subset_converter_0/aresetn] [get_bd_pins frmbuf_wr_rst_gpio/Dout] [get_bd_pins ps8_0_axi_periph/M11_ARESETN] [get_bd_pins v_frmbuf_wr_0/ap_rst_n]
  ## MIN:
  # connect_bd_net -net mipi_csi2_rx_subsyst_0_csirxss_csi_irq [get_bd_pins mipi_csi2_rx_subsyst_0/csirxss_csi_irq] [get_bd_pins xlconcat_1/In0]
  ## MIN:
  # connect_bd_net -net pl_key_ip2intc_irpt [get_bd_pins pl_key/ip2intc_irpt] [get_bd_pins xlconcat_0/In6]
  ## MIN:
  # connect_bd_net -net proc_sys_reset_0_peripheral_aresetn [get_bd_pins axi_interconnect_2/M00_ARESETN] [get_bd_pins ddr4_0/c0_ddr4_aresetn] [get_bd_pins proc_sys_reset_0/peripheral_aresetn]
  ## MIN:
  # connect_bd_net -net rst_ps8_0_99M_interconnect_aresetn [get_bd_pins axi_interconnect_0/ARESETN] [get_bd_pins axi_interconnect_1/ARESETN] [get_bd_pins ps8_0_axi_periph/ARESETN] [get_bd_pins rst_ps8_0_200M/interconnect_aresetn]
  ## MIN:
  # connect_bd_net -net rst_ps8_0_99M_peripheral_aresetn [get_bd_pins axi_dynclk_0/s00_axi_aresetn] [get_bd_pins axi_ethernet_0/s_axi_lite_resetn] [get_bd_pins axi_ethernet_0_dma/axi_resetn] [get_bd_pins axi_iic_0/s_axi_aresetn] [get_bd_pins axi_iic_1/s_axi_aresetn] [get_bd_pins axi_interconnect_0/M00_ARESETN] [get_bd_pins axi_interconnect_0/S00_ARESETN] [get_bd_pins axi_interconnect_0/S01_ARESETN] [get_bd_pins axi_interconnect_0/S02_ARESETN] [get_bd_pins axi_interconnect_1/M00_ARESETN] [get_bd_pins axi_interconnect_1/S00_ARESETN] [get_bd_pins axi_interconnect_1/S01_ARESETN] [get_bd_pins axi_interconnect_1/S02_ARESETN] [get_bd_pins axi_interconnect_2/ARESETN] [get_bd_pins axi_interconnect_2/S00_ARESETN] [get_bd_pins axi_uart16550_0/s_axi_aresetn] [get_bd_pins axi_uart16550_1/s_axi_aresetn] [get_bd_pins axi_vdma_0/axi_resetn] [get_bd_pins axi_vdma_1/axi_resetn] [get_bd_pins fan_gpio/s_axi_aresetn] [get_bd_pins hdmi_rst_gpio/s_axi_aresetn] [get_bd_pins mipi_csi2_rx_subsyst_0/lite_aresetn] [get_bd_pins mipi_csi2_rx_subsyst_0/video_aresetn] [get_bd_pins pl_key/s_axi_aresetn] [get_bd_pins pl_led/s_axi_aresetn] [get_bd_pins ps8_0_axi_periph/M00_ARESETN] [get_bd_pins ps8_0_axi_periph/M01_ARESETN] [get_bd_pins ps8_0_axi_periph/M02_ARESETN] [get_bd_pins ps8_0_axi_periph/M03_ARESETN] [get_bd_pins ps8_0_axi_periph/M04_ARESETN] [get_bd_pins ps8_0_axi_periph/M05_ARESETN] [get_bd_pins ps8_0_axi_periph/M06_ARESETN] [get_bd_pins ps8_0_axi_periph/M07_ARESETN] [get_bd_pins ps8_0_axi_periph/M08_ARESETN] [get_bd_pins ps8_0_axi_periph/M09_ARESETN] [get_bd_pins ps8_0_axi_periph/M10_ARESETN] [get_bd_pins ps8_0_axi_periph/M13_ARESETN] [get_bd_pins ps8_0_axi_periph/M14_ARESETN] [get_bd_pins ps8_0_axi_periph/M15_ARESETN] [get_bd_pins ps8_0_axi_periph/M16_ARESETN] [get_bd_pins ps8_0_axi_periph/M17_ARESETN] [get_bd_pins ps8_0_axi_periph/M18_ARESETN] [get_bd_pins ps8_0_axi_periph/S00_ARESETN] [get_bd_pins rs485de/s_axi_aresetn] [get_bd_pins rs485de1/s_axi_aresetn] [get_bd_pins rst_ps8_0_200M/peripheral_aresetn] [get_bd_pins v_tc_0/s_axi_aresetn]
  ## MIN:
  # connect_bd_net -net sin_0_1 [get_bd_ports RS485_1_rxd] [get_bd_pins axi_uart16550_1/sin]
  ## MIN:
  # connect_bd_net -net sin_1_1 [get_bd_ports RS485_0_rxd] [get_bd_pins axi_uart16550_0/sin]
  ## MIN:
  # connect_bd_net -net sys_rst_n_0_1 [get_bd_ports pcie_rst_n] [get_bd_pins xdma_0/sys_rst_n]
  ## MIN:
  # connect_bd_net -net util_ds_buf_0_IBUF_OUT [get_bd_pins axi_ethernet_0_refclk/clk_in1] [get_bd_pins ddr4_0/c0_sys_clk_i] [get_bd_pins util_ds_buf_0/IBUF_OUT]
  ## MIN:
  # connect_bd_net -net util_ds_buf_1_IBUF_DS_ODIV2 [get_bd_pins util_ds_buf_1/IBUF_DS_ODIV2] [get_bd_pins xdma_0/sys_clk]
  ## MIN:
  # connect_bd_net -net util_ds_buf_1_IBUF_OUT [get_bd_pins util_ds_buf_1/IBUF_OUT] [get_bd_pins xdma_0/sys_clk_gt]
  ## MIN:
  # connect_bd_net -net util_vector_logic_1_Res [get_bd_pins ddr4_0/sys_rst] [get_bd_pins util_vector_logic_1/Res]
  ## MIN:
  # connect_bd_net -net v_axi4s_vid_out_0_vid_active_video [get_bd_ports hdmi_out_de] [get_bd_pins v_axi4s_vid_out_0/vid_active_video]
  ## MIN:
  # connect_bd_net -net v_axi4s_vid_out_0_vid_data [get_bd_ports hdmi_out_data] [get_bd_pins v_axi4s_vid_out_0/vid_data]
  ## MIN:
  # connect_bd_net -net v_axi4s_vid_out_0_vid_hsync [get_bd_ports hdmi_out_hs] [get_bd_pins v_axi4s_vid_out_0/vid_hsync]
  ## MIN:
  # connect_bd_net -net v_axi4s_vid_out_0_vid_vsync [get_bd_ports hdmi_out_vs] [get_bd_pins v_axi4s_vid_out_0/vid_vsync]
  ## MIN:
  # connect_bd_net -net v_frmbuf_wr_0_interrupt [get_bd_pins v_frmbuf_wr_0/interrupt] [get_bd_pins xlconcat_1/In1]
  ## MIN:
  # connect_bd_net -net vid_active_video_0_1 [get_bd_ports hdmi_in_de] [get_bd_pins v_vid_in_axi4s_0/vid_active_video]
  ## MIN:
  # connect_bd_net -net vid_data_0_1 [get_bd_ports hdmi_in_data] [get_bd_pins v_vid_in_axi4s_0/vid_data]
  ## MIN:
  # connect_bd_net -net vid_hsync_0_1 [get_bd_ports hdmi_in_hs] [get_bd_pins v_vid_in_axi4s_0/vid_hsync]
  ## MIN:
  # connect_bd_net -net vid_io_in_clk_0_1 [get_bd_ports hdmi_in_clk] [get_bd_pins v_vid_in_axi4s_0/vid_io_in_clk]
  ## MIN:
  # connect_bd_net -net vid_vsync_0_1 [get_bd_ports hdmi_in_vs] [get_bd_pins v_vid_in_axi4s_0/vid_vsync]
  ## MIN:
  # connect_bd_net -net xdma_0_axi_aclk [get_bd_pins axi_interconnect_2/S01_ACLK] [get_bd_pins xdma_0/axi_aclk]
  ## MIN:
  # connect_bd_net -net xdma_0_axi_aresetn [get_bd_pins axi_interconnect_2/S01_ARESETN] [get_bd_pins xdma_0/axi_aresetn]
  ## MIN:
  # connect_bd_net -net xlconcat_0_dout [get_bd_pins xlconcat_0/dout] [get_bd_pins zynq_ultra_ps_e_0/pl_ps_irq0]
  ## MIN:
  # connect_bd_net -net xlconcat_1_dout [get_bd_pins xlconcat_1/dout] [get_bd_pins zynq_ultra_ps_e_0/pl_ps_irq1]
  ## MIN:
  # connect_bd_net -net xlconstant_0_dout [get_bd_pins axi_uart16550_0/dcdn] [get_bd_pins axi_uart16550_0/dsrn] [get_bd_pins axi_uart16550_0/freeze] [get_bd_pins axi_uart16550_1/dcdn] [get_bd_pins axi_uart16550_1/dsrn] [get_bd_pins axi_uart16550_1/freeze] [get_bd_pins xlconstant_0/dout]
  ## MIN:
  # connect_bd_net -net xlconstant_1_dout [get_bd_pins axi_uart16550_0/ctsn] [get_bd_pins axi_uart16550_0/rin] [get_bd_pins axi_uart16550_1/ctsn] [get_bd_pins axi_uart16550_1/rin] [get_bd_pins xlconstant_1/dout]
  ## MIN:
  # connect_bd_net -net xlconstant_2_dout [get_bd_ports cam_gpio] [get_bd_pins xlconstant_2/dout]
  ## MIN:
  # connect_bd_net -net xlconstant_3_dout [get_bd_pins v_vid_in_axi4s_0/aclken] [get_bd_pins v_vid_in_axi4s_0/aresetn] [get_bd_pins v_vid_in_axi4s_0/axis_enable] [get_bd_pins v_vid_in_axi4s_0/vid_io_in_ce] [get_bd_pins xlconstant_3/dout]
  ## MIN:
  # connect_bd_net -net xlconstant_4_dout [get_bd_ports hpd] [get_bd_pins xlconstant_4/dout]

  ## MIN: Original PS→PL clock tie to another IP; not needed
  # connect_bd_net -net zynq_ultra_ps_e_0_pl_clk0 [get_bd_pins axi_dynclk_0/REF_CLK_I] [get_bd_pins zynq_ultra_ps_e_0/pl_clk0]

  ## MIN: Original reset fan-out using NOT gate and others
  # connect_bd_net -net zynq_ultra_ps_e_0_pl_resetn0 [get_bd_pins rst_ps8_0_200M/ext_reset_in] [get_bd_pins util_vector_logic_1/Op1] [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0]

  # ## MIN: ADDED — Minimal PS clock to AXI-lite and GPIOs
  connect_bd_net -net ps_clk0 \
    [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
    [get_bd_pins ps8_0_axi_periph/ACLK] \
    [get_bd_pins ps8_0_axi_periph/S00_ACLK] \
    [get_bd_pins ps8_0_axi_periph/M06_ACLK] \
    [get_bd_pins ps8_0_axi_periph/M07_ACLK] \
    [get_bd_pins pl_key/s_axi_aclk] \
    [get_bd_pins pl_led/s_axi_aclk] \
    [get_bd_pins rst_ps8_0_200M/slowest_sync_clk]

  # ## MIN: ADDED — Minimal reset fan-out (active-high resets generated)
  connect_bd_net -net ps_pl_resetn0_to_extreset \
    [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] \
    [get_bd_pins rst_ps8_0_200M/ext_reset_in]

  connect_bd_net -net periph_aresetn_min \
    [get_bd_pins rst_ps8_0_200M/peripheral_aresetn] \
    [get_bd_pins ps8_0_axi_periph/ARESETN] \
    [get_bd_pins ps8_0_axi_periph/S00_ARESETN] \
    [get_bd_pins ps8_0_axi_periph/M06_ARESETN] \
    [get_bd_pins ps8_0_axi_periph/M07_ARESETN] \
    [get_bd_pins pl_key/s_axi_aresetn] \
    [get_bd_pins pl_led/s_axi_aresetn]


  # --- Zynq PS v3.5: drive HPM ACLKs (required) ---
  catch { connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_lpd_aclk] [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] }
  catch { connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk] [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] }

  # --- Tie off unused ps8_0_axi_periph MI ACLKs so validate_bd passes ---
  foreach m {M00 M01 M02 M03 M04 M05 M08 M09 M10 M11 M12 M13 M14 M15 M16 M17 M18} {
    catch { connect_bd_net [get_bd_pins ps8_0_axi_periph/${m}_ACLK] [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] }
  }

  # (Optional but tidy: also tie unused MI resets to the same reset net)
  foreach m {M00 M01 M02 M03 M04 M05 M08 M09 M10 M11 M12 M13 M14 M15 M16 M17 M18} {
    catch { connect_bd_net [get_bd_pins ps8_0_axi_periph/${m}_ARESETN] [get_bd_pins rst_ps8_0_200M/peripheral_aresetn] }
  }

  assign_bd_address	

  ## MIN: Addressing for XDMA/DDR/etc not used
  # set_property offset 0x0000000000000000 [get_bd_addr_segs {xdma_0/M_AXI/SEG_ddr4_0_C0_DDR4_ADDRESS_BLOCK}]
  # (all other assign_bd_address lines were already commented in your original)

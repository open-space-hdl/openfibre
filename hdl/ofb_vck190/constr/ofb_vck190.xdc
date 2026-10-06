#---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
#---------------------------------------------------------------------------------------------------
# Constraints of the OpenFibre reference design for the AMD VCK190 evaluation board (XCVC1902-VSVA2197).
# Pins from the device package (GTY quad 200 = QSFP1, UG1366) and the VCK190 board files (LEDs).
#
# Documentation: hdl/ofb_vck190/docs/architecture.md
#---------------------------------------------------------------------------------------------------

# Clocks of the programmable logic: the constraints of the CIPS IP create clk_pl_0 (100 MHz: MIB, transceiver reset
# controller, power-on reset) and clk_pl_1 (150 MHz: user side of the core); the lane clock is TXOUTCLK of channel 0.

# Transceiver reference clock: MGTREFCLK1 of quad 200 (8A34001 output Q1, programmed to 156.25 MHz)
set_property PACKAGE_PIN AD11 [get_ports GtRefClk_P]
set_property PACKAGE_PIN AD10 [get_ports GtRefClk_N]
create_clock -period 6.400 -name gt_refclk [get_ports GtRefClk_P]

# QSFP1: GTY quad 200 (GTY_QUAD_X1Y0), channels 0 to 3 = lanes 0 to 3
set_property LOC GTY_QUAD_X1Y0 [get_cells -hierarchical -filter {REF_NAME == GTYE5_QUAD}]
set_property PACKAGE_PIN AF2 [get_ports {Qsfp_RxP[0]}]
set_property PACKAGE_PIN AF1 [get_ports {Qsfp_RxN[0]}]
set_property PACKAGE_PIN AF7 [get_ports {Qsfp_TxP[0]}]
set_property PACKAGE_PIN AF6 [get_ports {Qsfp_TxN[0]}]
set_property PACKAGE_PIN AE4 [get_ports {Qsfp_RxP[1]}]
set_property PACKAGE_PIN AE3 [get_ports {Qsfp_RxN[1]}]
set_property PACKAGE_PIN AE9 [get_ports {Qsfp_TxP[1]}]
set_property PACKAGE_PIN AE8 [get_ports {Qsfp_TxN[1]}]
set_property PACKAGE_PIN AD2 [get_ports {Qsfp_RxP[2]}]
set_property PACKAGE_PIN AD1 [get_ports {Qsfp_RxN[2]}]
set_property PACKAGE_PIN AD7 [get_ports {Qsfp_TxP[2]}]
set_property PACKAGE_PIN AD6 [get_ports {Qsfp_TxN[2]}]
set_property PACKAGE_PIN AC4 [get_ports {Qsfp_RxP[3]}]
set_property PACKAGE_PIN AC3 [get_ports {Qsfp_RxN[3]}]
set_property PACKAGE_PIN AC9 [get_ports {Qsfp_TxP[3]}]
set_property PACKAGE_PIN AC8 [get_ports {Qsfp_TxN[3]}]

# LEDs (GPIO_LED_0 to 3)
set_property PACKAGE_PIN H34 [get_ports {Led[0]}]
set_property PACKAGE_PIN J33 [get_ports {Led[1]}]
set_property PACKAGE_PIN K36 [get_ports {Led[2]}]
set_property PACKAGE_PIN L35 [get_ports {Led[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {Led[*]}]
set_false_path -to [get_ports {Led[*]}]

# Clock domain crossings between the clocks of the CIPS and the lane clock (Open Logic crossings): datapath delay of
# at most the period of the faster clock of each pair
set lane_clk [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *i_pa/i_bufg/O}]]
set mgmt_clk [get_clocks clk_pl_0]
set user_clk [get_clocks clk_pl_1]
set_max_delay -datapath_only -from $mgmt_clk -to $lane_clk 6.400
set_max_delay -datapath_only -from $lane_clk -to $mgmt_clk 6.400
set_max_delay -datapath_only -from $user_clk -to $lane_clk 6.400
set_max_delay -datapath_only -from $lane_clk -to $user_clk 6.400
set_max_delay -datapath_only -from $mgmt_clk -to $user_clk 6.666
set_max_delay -datapath_only -from $user_clk -to $mgmt_clk 6.666

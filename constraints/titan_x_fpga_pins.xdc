## SPDX-License-Identifier: Apache-2.0
## SMVDU TITAN-X SoC — FPGA Pin Placement & IO Standards Constraints
## Target: Xilinx Kintex-7 / UltraScale+ Development Platform (KC705 / VCU118 Reference)

## -------------------------------------------------------------
## System Clock (200 MHz Differential Oscillator)
## -------------------------------------------------------------
set_property PACKAGE_PIN AD12 [get_ports sys_clk_p]
set_property IOSTANDARD DIFF_SSTL15 [get_ports sys_clk_p]
set_property PACKAGE_PIN AD11 [get_ports sys_clk_n]
set_property IOSTANDARD DIFF_SSTL15 [get_ports sys_clk_n]

## -------------------------------------------------------------
## System Reset Push-button (Active Low)
## -------------------------------------------------------------
set_property PACKAGE_PIN AB12 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS15 [get_ports sys_rst_n]

## -------------------------------------------------------------
## Primary UART 16550 Console (USB-UART Bridge)
## -------------------------------------------------------------
set_property PACKAGE_PIN M19 [get_ports fpga_uart_tx]
set_property IOSTANDARD LVCMOS25 [get_ports fpga_uart_tx]
set_property PACKAGE_PIN K24 [get_ports fpga_uart_rx]
set_property IOSTANDARD LVCMOS25 [get_ports fpga_uart_rx]

## -------------------------------------------------------------
## Diagnostic & Telemetry LEDs (Active High)
## -------------------------------------------------------------
set_property PACKAGE_PIN AB8  [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS15 [get_ports {led[0]}]
set_property PACKAGE_PIN AA8  [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS15 [get_ports {led[1]}]
set_property PACKAGE_PIN AC9  [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS15 [get_ports {led[2]}]
set_property PACKAGE_PIN AB9  [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS15 [get_ports {led[3]}]
set_property PACKAGE_PIN AE26 [get_ports {led[4]}]
set_property IOSTANDARD LVCMOS25 [get_ports {led[4]}]
set_property PACKAGE_PIN G19  [get_ports {led[5]}]
set_property IOSTANDARD LVCMOS25 [get_ports {led[5]}]
set_property PACKAGE_PIN E18  [get_ports {led[6]}]
set_property IOSTANDARD LVCMOS25 [get_ports {led[6]}]
set_property PACKAGE_PIN F16  [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS25 [get_ports {led[7]}]

## -------------------------------------------------------------
## User Configuration DIP Switches
## -------------------------------------------------------------
set_property PACKAGE_PIN Y29  [get_ports {sw[0]}]
set_property IOSTANDARD LVCMOS25 [get_ports {sw[0]}]
set_property PACKAGE_PIN W29  [get_ports {sw[1]}]
set_property IOSTANDARD LVCMOS25 [get_ports {sw[1]}]
set_property PACKAGE_PIN AA28 [get_ports {sw[2]}]
set_property IOSTANDARD LVCMOS25 [get_ports {sw[2]}]
set_property PACKAGE_PIN Y28  [get_ports {sw[3]}]
set_property IOSTANDARD LVCMOS25 [get_ports {sw[3]}]
set_property PACKAGE_PIN AE8  [get_ports {sw[4]}]
set_property IOSTANDARD LVCMOS15 [get_ports {sw[4]}]
set_property PACKAGE_PIN AF8  [get_ports {sw[5]}]
set_property IOSTANDARD LVCMOS15 [get_ports {sw[5]}]
set_property PACKAGE_PIN AE10 [get_ports {sw[6]}]
set_property IOSTANDARD LVCMOS15 [get_ports {sw[6]}]
set_property PACKAGE_PIN AF10 [get_ports {sw[7]}]
set_property IOSTANDARD LVCMOS15 [get_ports {sw[7]}]

## -------------------------------------------------------------
## HDMI Video Display Interface (Phase 2 Ubuntu GUI)
## -------------------------------------------------------------
set_property PACKAGE_PIN K20 [get_ports hdmi_tx_clk_p]
set_property IOSTANDARD TMDS_33 [get_ports hdmi_tx_clk_p]
set_property PACKAGE_PIN K21 [get_ports hdmi_tx_clk_n]
set_property IOSTANDARD TMDS_33 [get_ports hdmi_tx_clk_n]
set_property PACKAGE_PIN B23 [get_ports {hdmi_tx_d_p[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_tx_d_p[0]}]
set_property PACKAGE_PIN A23 [get_ports {hdmi_tx_d_n[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_tx_d_n[0]}]
set_property PACKAGE_PIN E23 [get_ports {hdmi_tx_d_p[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_tx_d_p[1]}]
set_property PACKAGE_PIN D23 [get_ports {hdmi_tx_d_n[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_tx_d_n[1]}]
set_property PACKAGE_PIN F25 [get_ports {hdmi_tx_d_p[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_tx_d_p[2]}]
set_property PACKAGE_PIN E25 [get_ports {hdmi_tx_d_n[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_tx_d_n[2]}]

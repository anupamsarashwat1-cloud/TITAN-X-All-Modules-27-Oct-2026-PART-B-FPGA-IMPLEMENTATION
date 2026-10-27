## SPDX-License-Identifier: Apache-2.0
## SMVDU TITAN-X SoC — FPGA Timing Constraints

## -------------------------------------------------------------
## Primary Clock Definition (200 MHz Differential Oscillator)
## -------------------------------------------------------------
create_clock -period 5.000 -name sys_clk_pin -waveform {0.000 2.500} [get_ports sys_clk_p]

## Clock Uncertainty & Jitter
set_clock_uncertainty 0.200 [get_clocks -all]

## -------------------------------------------------------------
## Asynchronous Domain Crossings & False Paths
## -------------------------------------------------------------
# System reset push-button is fully asynchronous
set_false_path -from [get_ports sys_rst_n]

# Diagnostic status LEDs and manual DIP switches
set_false_path -to [get_ports {led[*]}]
set_false_path -from [get_ports {sw[*]}]

# Low-speed UART serial RX/TX pins (baud rate 115200 is asynchronous to 50MHz core clock)
set_false_path -from [get_ports fpga_uart_rx]
set_false_path -to [get_ports fpga_uart_tx]

## Output Drive & Slew Configuration
set_property SLEW SLOW [get_ports {led[*]}]
set_property DRIVE 8 [get_ports {led[*]}]
set_property SLEW FAST [get_ports fpga_uart_tx]
set_property DRIVE 8 [get_ports fpga_uart_tx]

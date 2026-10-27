# SPDX-License-Identifier: Apache-2.0
# Vivado Batch Synthesis Script for TITAN-X FPGA Implementation
# Target Device: Kintex-7 (xc7k325tffg900-2) or UltraScale+ (xcku040-ffva1156-2-e)

set PART "xc7k325tffg900-2"
set TOP_MODULE "fpga_titan_x_top"
set OUTPUT_DIR "build/synth"

file mkdir $OUTPUT_DIR

puts "=========================================================="
puts " TITAN-X FPGA Synthesis: Target Part $PART, Top: $TOP_MODULE"
puts "=========================================================="

# Read synthesizable Verilog filelist
set fp [open "fresh_soc_filelist.f" r]
set file_data [read $fp]
close $fp

set data [split $file_data "\n"]
foreach line $data {
    set line [string trim $line]
    if {$line ne "" && ![string match "#*" $line] && ![string match "//*" $line] && ![string match "*tb_*" $line]} {
        puts "Reading RTL: $line"
        read_verilog $line
    }
}

# Read FPGA top wrapper and Clock/MIG wrappers
read_verilog fpga/clk_wiz_wrapper.v
read_verilog fpga/mig_ddr4_wrapper.v
read_verilog memory/fpga_ram_models.v
read_verilog top/fpga_top/fpga_titan_x_top.v

# Read XDC Constraints
read_xdc constraints/titan_x_fpga_pins.xdc
read_xdc constraints/titan_x_fpga_timing.xdc

# Run Synthesis with Flatten Hierarchy and Fanout Optimization
synth_design -top $TOP_MODULE -part $PART -flatten_hierarchy rebuilt -directive AreaOptimized_high

# Write Post-Synthesis Reports and Netlist
report_utilization -file $OUTPUT_DIR/utilization_synth.rpt
report_timing_summary -file $OUTPUT_DIR/timing_synth.rpt
write_checkpoint -force $OUTPUT_DIR/post_synth.dcp

puts "Synthesis completed successfully. Checkpoint saved to $OUTPUT_DIR/post_synth.dcp"

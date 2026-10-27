# SPDX-License-Identifier: Apache-2.0
# Vivado Batch Implementation Script for TITAN-X FPGA
set OUTPUT_DIR "build/impl"
file mkdir $OUTPUT_DIR

puts "=========================================================="
puts " TITAN-X FPGA Place & Route Implementation Flow"
puts "=========================================================="

# Open post-synthesis checkpoint
open_checkpoint build/synth/post_synth.dcp

# 1. Optimize Design
opt_design -directive Explore

# 2. Place Design
place_design -directive Explore
report_clock_utilization -file $OUTPUT_DIR/clock_utilization.rpt

# 3. Physical Optimization
phys_opt_design -directive AggressiveExplore

# 4. Route Design
route_design -directive Explore
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 10 -file $OUTPUT_DIR/timing_summary.rpt
report_drc -file $OUTPUT_DIR/drc_routed.rpt
report_power -file $OUTPUT_DIR/power_routed.rpt

# Save routed design checkpoint
write_checkpoint -force $OUTPUT_DIR/post_route.dcp
puts "Implementation completed successfully. Checkpoint saved to $OUTPUT_DIR/post_route.dcp"

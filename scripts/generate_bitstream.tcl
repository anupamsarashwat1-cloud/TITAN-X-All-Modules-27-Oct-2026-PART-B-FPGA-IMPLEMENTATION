# SPDX-License-Identifier: Apache-2.0
# Vivado Bitstream Generation Script for TITAN-X FPGA
set OUTPUT_DIR "build/bitstream"
file mkdir $OUTPUT_DIR

open_checkpoint build/impl/post_route.dcp

# Set Bitstream Options (SPIx4, 66MHz configuration rate)
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 66 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# Write Bitstream
write_bitstream -force $OUTPUT_DIR/titan_x_soc.bit
puts "=========================================================="
puts " Bitstream Generated: $OUTPUT_DIR/titan_x_soc.bit"
puts "=========================================================="

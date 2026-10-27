#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# FPGA Boot Simulation Runner using Icarus Verilog

set -e

SIM_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SIM_DIR}/.." && pwd)

echo "=========================================================="
echo " Running TITAN-X FPGA Minimal Linux Boot Simulation..."
echo " Repo Root: ${REPO_ROOT}"
echo "=========================================================="

cd "${REPO_ROOT}"

# Filter filelist for synthesizable modules
grep -v '^#' fresh_soc_filelist.f | grep -v '^//' | grep -v 'tb_fresh_titan_x_top' > sim/sim_files.f

iverilog -g2012 \
    -I includes \
    -I common/BUFX4 \
    -f sim/sim_files.f \
    fpga/clk_wiz_wrapper.v \
    fpga/mig_ddr4_wrapper.v \
    memory/fpga_ram_models.v \
    top/fpga_top/fpga_titan_x_top.v \
    sim/tb_fpga_minimal_boot.v \
    -o sim/tb_fpga_minimal_boot.vvp

echo "Compilation successful. Executing simulation..."
vvp sim/tb_fpga_minimal_boot.vvp +hex=top/axi_rom/firmware.hex

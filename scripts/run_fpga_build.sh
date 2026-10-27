#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Master FPGA Synthesis & Implementation Script

set -e

echo "=========================================================="
echo " SMVDU TITAN-X SoC: FPGA Build Automation Pipeline"
echo "=========================================================="

if command -v vivado >/dev/null 2>&1; then
    echo "[1/3] Running Vivado Batch Synthesis..."
    vivado -mode batch -source scripts/synth_fpga.tcl
    echo "[2/3] Running Vivado Batch Implementation (Place & Route)..."
    vivado -mode batch -source scripts/impl_fpga.tcl
    echo "[3/3] Generating FPGA Bitstream..."
    vivado -mode batch -source scripts/generate_bitstream.tcl
    echo "SUCCESS: Bitstream generated at build/bitstream/titan_x_soc.bit"
else
    echo "[INFO] Vivado not found in PATH. Running Open-Source Yosys Xilinx Synthesis..."
    yosys -s scripts/synth_xilinx_yosys.tcl
    echo "SUCCESS: Yosys FPGA Synthesis completed."
fi

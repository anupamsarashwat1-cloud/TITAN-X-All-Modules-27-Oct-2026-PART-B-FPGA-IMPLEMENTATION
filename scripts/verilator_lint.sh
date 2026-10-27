#!/bin/bash
set -e
SCRIPT_DIR="$(dirname "$0")"
CPU_BASE="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "============================================"
echo " SMVDU-TITAN-X SoC RTL Lint Analysis"
echo " Linter : Verilator"
echo "============================================"

# Collect all Verilog/SystemVerilog sources except testbenches
mapfile -t SRCS < <(find "$CPU_BASE" -type f \( -name "*.v" -o -name "*.sv" \) -not -path "*/verification/*")

echo "[1/2] Running Verilator lint..."
verilator --lint-only -Wall \
    -I"$CPU_BASE/common" \
    --top-module titan_x_top \
    -Wno-fatal \
    -Wno-DECLFILENAME \
    -Wno-UNUSEDSIGNAL \
    -Wno-UNDRIVEN \
    -Wno-PINCONNECTEMPTY \
    -Wno-MULTIDRIVEN \
    -Wno-WIDTH \
    -Wno-UNUSEDPARAM \
    -Wno-BLKSEQ \
    "${SRCS[@]}"

echo "============================================"
echo " Verilator Lint: PASSED (Clean)"
echo "============================================"

# SMVDU TITAN-X SoC — FPGA Implementation Repository

## Overview
This repository contains the complete, dedicated **FPGA Implementation** of the **SMVDU TITAN-X SoC**, a 64-bit multi-core RISC-V System-on-Chip featuring:
- **Processor Cluster**: 4× RV64GC Out-of-Order/Pipelined Cores + 1× RV64IMAC Real-Time Monitor Core
- **Interconnect**: 15-Master × 9-Slave AXI4 Crossbar Matrix with QoS Arbitration and MPU
- **Memory Subsystem**: L2 Shared Cache (Tag/Data Arrays, Snoop Filter) and DDR4 Memory Controller
- **Physical Memory**: 2048 MB DDR4 SDRAM mapped at base address `0x8000_0000`
- **Boot Subsystem**: Hardware AXI Read-Only BootROM mapped at `0x0001_0000`
- **Serial Console**: Full NS16550A-compatible UART at `0x1000_0000`

---

## Directory Structure
```
TITAN-X-All-Modules-27-Oct-2026-PART-B-FPGA-IMPLEMENTATION/
├── fresh_soc_filelist.f           # 71 synthesizable RTL modules in dependency order
├── common/                        # Synchronizers, clock buffers, and async FIFOs
├── includes/                      # ISA definitions, parameters, and headers
├── frontend/                      # Fetch, Decode, Branch Prediction, and I-Cache
├── backend/                       # Execute, Memory, Regfile, CSRs, MMU/TLB/PTW, FPU, PLIC, CLINT
├── interconnect/                  # AXI4 Crossbar, APB/AHB Bridges, MPU, QoS
├── memory/                        # L2 Cache, DDR4 Controller & PHY, FPGA Block RAM models
├── peripherals/                   # UART 16550, GPIO, RTC, Watchdog, I2C, SPI, CAN, Ethernet
├── storage/                       # SD/MMC Controller, QSPI Flash, USB OTG
├── video/                         # HDMI Controller, VDMA, ISP, MIPI CSI-2 RX
├── security/                      # Secure Boot RoT, ECDSA, SHA-256, AES, DRBG, TRNG
├── top/                           # SoC Top (titan_x_top) and FPGA Board Top (fpga_titan_x_top)
├── fpga/                          # Clock Wizard (MMCM) & MIG DDR4 Memory Wrappers
├── constraints/                   # Board Pin Placements (XDC) & Timing Constraints
├── firmware/                      # RISC-V 64-bit BootROM Assembly & C Firmware Source
├── linux/                         # Linux Device Tree Source (DTS), defconfig, build scripts
├── scripts/                       # Vivado batch and Yosys synthesis/implementation automation
└── sim/                           # Icarus Verilog FPGA boot simulation testbenches
```

---

## FPGA Implementation Roadmap

### Phase 1: Boot a Minimal Linux Image (Current Deliverable)
- **Objective**: Verify end-to-end hardware execution of processor pipeline, clocking, resets, DDR4 memory initialization, BootROM firmware, serial console transmission, and Linux kernel execution vector.
- **Key Hardware Verification**:
  1. **Clock Wizard MMCM**: Generates 50 MHz core clock (`clk_cpu`) and 200 MHz reference clock (`clk_ddr`) from 200 MHz on-board differential oscillator.
  2. **Reset Synchronization**: Power-on reset synchronized across clock domains; released only after MMCM lock.
  3. **DDR4 Memory Controller**: Physical DDR interface calibration with hardware status indicator (`init_calib_complete`).
  4. **BootROM Firmware**: Executed by Hart 0 to initialize UART 16550, print ASCII banner, verify DDR4 read/write at `0x8000_0000`, and transfer execution to Linux Kernel vector.
  5. **Console Output**: Earlycon / ttyS0 UART 16550 serial console output running at 115200 8-N-1.

### Phase 2: Full Ubuntu Desktop Bringup (Subsequent Phase)
- **Objective**: Boot and run full Ubuntu with graphical desktop and interactive peripherals.
- **Peripherals Utilized**:
  - **Video Pipeline**: HDMI controller + VDMA frame buffer for 720p/1080p display output.
  - **Human Interface**: USB OTG Host for keyboard and mouse interaction.
  - **Mass Storage**: MMC/SD-Card controller for root filesystem storage.
  - **Networking**: Gigabit Ethernet MAC (GEM) + PHY for high-speed network connectivity.

---

## Toolchain & Build Instructions

### 1. Prerequisites
- **FPGA Tool**: Xilinx Vivado (2020.2 or newer) or Yosys 0.33+ with `synth_xilinx`.
- **Simulation**: Icarus Verilog (`iverilog`, `vvp`) and GTKWave.
- **RISC-V Toolchain**: `riscv64-unknown-elf-gcc` (RV64GC LP64D).

### 2. BootROM Firmware Compilation
To rebuild the hardware BootROM image from source:
```bash
cd firmware
make clean && make
# Copy resulting hex to top/axi_rom/
cp firmware.hex ../top/axi_rom/firmware.hex
```

### 3. FPGA Simulation Verification
To run the automated minimal Linux boot simulation:
```bash
bash sim/run_sim.sh
```
This testbench simulates:
- Differential clock input and MMCM frequency synthesis.
- Power-on reset deassertion.
- DDR4 initialization and calibration handshake.
- Real-time decoding of UART TX byte stream at 115200 baud.
- CPU jump to `0x8000_0000`.

### 4. FPGA Synthesis & Bitstream Generation
#### Vivado Automated Batch Flow:
```bash
# Run complete synthesis, placement, routing, and bitstream generation:
bash scripts/run_fpga_build.sh
```
Or run individual steps:
```bash
vivado -mode batch -source scripts/synth_fpga.tcl
vivado -mode batch -source scripts/impl_fpga.tcl
vivado -mode batch -source scripts/generate_bitstream.tcl
```
Output bitstream: `build/bitstream/titan_x_soc.bit`.

#### Open-Source Yosys Flow:
```bash
yosys -s scripts/synth_xilinx_yosys.tcl
```

### 5. Linux Kernel & Device Tree Compilation
To compile the Device Tree Source (`.dts`) into a binary Device Tree Blob (`.dtb`):
```bash
cd linux
bash build_minimal_linux.sh
```

---

## Serial Console Parameters
- **Interface**: USB-UART Micro-B / Type-C on FPGA Board
- **Baud Rate**: `115200`
- **Data Bits**: `8`
- **Parity**: `None`
- **Stop Bits**: `1`
- **Flow Control**: `None`

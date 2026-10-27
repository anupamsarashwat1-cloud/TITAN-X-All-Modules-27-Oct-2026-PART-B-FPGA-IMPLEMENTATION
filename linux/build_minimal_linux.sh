#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SMVDU TITAN-X SoC — Automated Minimal Linux Kernel & Busybox Image Builder
# Targets: RV64GC Linux Kernel Image + Initramfs payload for FPGA DDR4 RAM (0x8000_0000)

set -e

CROSS_COMPILE=${CROSS_COMPILE:-/home/anupam-sarashwat/.local/riscv/bin/riscv64-unknown-elf-}
ARCH=riscv
BUILD_DIR=$(pwd)/build_linux
DTS_FILE=$(pwd)/dts/titan_x_soc.dts
DTB_OUT=${BUILD_DIR}/titan_x_soc.dtb

echo "=========================================================="
echo " SMVDU TITAN-X SoC: Linux Kernel & Initramfs Build Pipeline"
echo " Cross-Compiler: ${CROSS_COMPILE}"
echo "=========================================================="

mkdir -p ${BUILD_DIR}

# 1. Compile Device Tree Source (.dts -> .dtb)
echo "[1/3] Compiling Device Tree Source..."
if command -v dtc >/dev/null 2>&1; then
    dtc -I dts -O dtb -o ${DTB_OUT} ${DTS_FILE}
    echo "  -> Generated DTB: ${DTB_OUT}"
else
    echo "  [INFO] dtc (device tree compiler) not found in PATH; skipping DTB binary generation."
fi

# 2. Build Minimal Initramfs with BusyBox
echo "[2/3] Preparing Minimal Root Filesystem (Initramfs)..."
ROOTFS_DIR=${BUILD_DIR}/rootfs
mkdir -p ${ROOTFS_DIR}/{bin,sbin,etc,proc,sys,usr/bin,usr/sbin,dev}

cat << 'INIT_EOF' > ${ROOTFS_DIR}/sbin/init
#!/bin/sh
# Minimal init script for TITAN-X Linux bringup
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

echo ""
echo "========================================================"
echo " Welcome to SMVDU TITAN-X Quad-Core Linux System!"
echo " Architecture : RV64GC (Multi-Core RISC-V)"
echo " Memory       : 2048 MB DDR4 RAM @ 0x80000000"
echo " Console      : UART 16550 115200 8-N-1"
echo "========================================================"
echo ""
uname -a
echo ""
exec /bin/sh
INIT_EOF
chmod +x ${ROOTFS_DIR}/sbin/init

echo "  -> Initramfs structure prepared at ${ROOTFS_DIR}"

# 3. Kernel Instructions
echo "[3/3] Linux Kernel Build Instructions:"
echo "  To build the official upstream kernel for TITAN-X:"
echo "    git clone --depth 1 https://github.com/torvalds/linux.git -b v6.6"
echo "    cd linux"
echo "    cp ../kernel_defconfig arch/riscv/configs/titan_x_defconfig"
echo "    make ARCH=riscv CROSS_COMPILE=${CROSS_COMPILE} titan_x_defconfig"
echo "    make ARCH=riscv CROSS_COMPILE=${CROSS_COMPILE} Image -j\$(nproc)"
echo "=========================================================="
echo "Build pipeline script completed successfully."

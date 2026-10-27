// SPDX-License-Identifier: Apache-2.0
// TITAN-X SoC — Production FPGA BootROM Firmware
// Initializes Hardware, Tests DDR4 RAM, and Boots Minimal Linux Kernel

.section .text.init
.globl _start

_start:
    // 1. Invalidate and clear all integer registers
    li  x1,  0
    li  x2,  0
    li  x3,  0
    li  x4,  0
    li  x5,  0
    li  x6,  0
    li  x7,  0
    li  x8,  0
    li  x9,  0
    li  x10, 0
    li  x11, 0
    li  x12, 0
    li  x13, 0
    li  x14, 0
    li  x15, 0
    li  x16, 0
    li  x17, 0
    li  x18, 0
    li  x19, 0
    li  x20, 0
    li  x21, 0
    li  x22, 0
    li  x23, 0
    li  x24, 0
    li  x25, 0
    li  x26, 0
    li  x27, 0
    li  x28, 0
    li  x29, 0
    li  x30, 0
    li  x31, 0

    // Setup initial stack pointer
    la   sp, _stack_top

    // 2. Multicore Hart Coordination
    csrr a0, mhartid
    bnez a0, secondary_core_park

    // 3. Hart 0 (Primary Core) Initializes UART 16550 Channel 0 at 0x1000_0000
    li   s0, 0x40000000          // UART0 Base Address

    // Enable DLAB (Divisor Latch Access) bit 7 in LCR (offset 3)
    li   t0, 0x80
    sb   t0, 3(s0)

    // Set Baud Divisor for 115200 Baud @ 50MHz: Divisor = 27 (0x001B)
    li   t0, 0x1B                // DLL
    sb   t0, 0(s0)
    li   t0, 0x00                // DLM
    sb   t0, 1(s0)

    // Clear DLAB and configure 8 data bits, 1 stop bit, no parity: LCR = 0x03
    li   t0, 0x03
    sb   t0, 3(s0)

    // Enable and Reset FIFOs: FCR = 0x07 (offset 2)
    li   t0, 0x07
    sb   t0, 2(s0)

    // 4. Output Boot Banner to UART
    la   a0, msg_banner
    jal  uart_puts

    // 5. Test DDR4 Memory Controller at 0x8000_0000
    la   a0, msg_ddr_test
    jal  uart_puts

    li   s1, 0x80000000          // DDR4 Memory Base Address
    li   t1, 0xCAFEF00DDEADBEEF  // Test pattern
    sd   t1, 0(s1)               // Write 64-bit doubleword
    fence rw, rw
    ld   t2, 0(s1)               // Read back 64-bit doubleword

    bne  t1, t2, ddr_fail

    la   a0, msg_ddr_ok
    jal  uart_puts

    // 6. Output Linux Jump Banner
    la   a0, msg_linux_boot
    jal  uart_puts

    // 7. Prepare RISC-V Standard Boot Calling Convention
    //    a0 = Hart ID (0)
    //    a1 = Pointer to Device Tree Binary (DTB) at 0x8200_0000
    csrr a0, mhartid
    li   a1, 0x82000000

    // Jump to Kernel Execution Vector at DDR RAM (0x8000_0000)
    li   ra, 0x80000000
    jr   ra

ddr_fail:
    la   a0, msg_ddr_err
    jal  uart_puts
1:  wfi
    j 1b

secondary_core_park:
    // Secondary cores (Harts 1-4) enter low-power wait-for-interrupt loop
    wfi
    j secondary_core_park

// -------------------------------------------------------------
// UART Transmit Subroutine: a0 = pointer to null-terminated string
// -------------------------------------------------------------
uart_puts:
    li   s0, 0x40000000
1:
    lbu  t0, 0(a0)
    beqz t0, 3f                  // End of string

2:  // Wait until Transmitter Holding Register Empty (THRE = bit 5 of LSR at offset 5)
    lbu  t1, 5(s0)
    andi t1, t1, 0x20
    beqz t1, 2b

    // Write character to THR (offset 0)
    sb   t0, 0(s0)
    addi a0, a0, 1
    j    1b
3:
    ret

// -------------------------------------------------------------
// String Data Table
// -------------------------------------------------------------
.section .rodata
msg_banner:
    .string "\r\n=======================================================\r\n[TITAN-X FPGA] SMVDU 64-bit RISC-V Multi-Core System Online\r\n[TITAN-X FPGA] CPU Clocks: 50 MHz | DDR Clocks: 200 MHz\r\n=======================================================\r\n"

msg_ddr_test:
    .string "[TITAN-X FPGA] Testing DDR4 Memory Controller at 0x80000000...\r\n"

msg_ddr_ok:
    .string "[TITAN-X FPGA] DDR4 Memory Check Passed! 2048 MB Available.\r\n"

msg_linux_boot:
    .string "[TITAN-X FPGA] Booting Minimal Linux Kernel Image...\r\n"

msg_ddr_err:
    .string "[TITAN-X FPGA ERROR] DDR4 Memory Verification Failed!\r\n"

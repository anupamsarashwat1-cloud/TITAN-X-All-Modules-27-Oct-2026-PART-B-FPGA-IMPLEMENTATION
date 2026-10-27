/* SPDX-License-Identifier: Apache-2.0 */
/* TITAN-X BootROM Linker Script */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    rom (rx)  : ORIGIN = 0x10000000, LENGTH = 64K
    ram (rwx) : ORIGIN = 0x80000000, LENGTH = 2048M
}

SECTIONS
{
    .text : {
        *(.text.init)
        *(.text .text.*)
        *(.rodata .rodata.*)
    } > rom

    .data : {
        *(.data .data.*)
        *(.sdata .sdata.*)
    } > rom

    .bss (NOLOAD) : {
        __bss_start = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    } > rom

    . = ALIGN(16);
    _stack_top = ORIGIN(rom) + LENGTH(rom) - 128;
}

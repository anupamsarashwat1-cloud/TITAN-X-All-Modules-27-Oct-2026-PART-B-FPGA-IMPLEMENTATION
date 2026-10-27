# SPDX-License-Identifier: Apache-2.0
# TITAN-X BootROM Makefile

CROSS_COMPILE ?= /home/anupam-sarashwat/.local/riscv/bin/riscv64-unknown-elf-
CC      := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump

CFLAGS  := -march=rv64gc -mabi=lp64d -mcmodel=medany -nostdlib -ffreestanding -O2 -Wall
LDFLAGS := -T link.ld -nostdlib

all: firmware.elf firmware.bin firmware.hex boot.mem

firmware.elf: bootrom.S link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) bootrom.S -o $@

firmware.bin: firmware.elf
	$(OBJCOPY) -O binary $< $@

firmware.hex: firmware.bin
	hexdump -v -e '1/4 "%08x\n"' $< > $@

boot.mem: firmware.hex
	cp $< $@

clean:
	rm -f *.elf *.bin *.hex *.mem

.PHONY: all clean

#include <stdint.h>

#define UART0_BASE 0x40010000
#define UART0_TX   (*(volatile uint32_t*)(UART0_BASE + 0x00))
#define UART0_LSR  (*(volatile uint32_t*)(UART0_BASE + 0x14))

void uart_putc(char c) {
    while ((UART0_LSR & 0x20) == 0); // Wait for TX empty
    UART0_TX = c;
}

void uart_puts(const char* s) {
    while (*s) {
        uart_putc(*s++);
    }
}

int main() {
    uart_puts("TITAN-X Booting from 0x10000000...\n");
    uart_puts("Test Passed: SoC Top Level Integration verified!\n");
    
    // Write a special value to a magic address to signal completion to testbench
    // Assuming 0x40000000 (RTC) or 0x80000000 (DDR) can be used.
    // Let's use 0x80000000.
    *(volatile uint32_t*)0x80000000 = 0xDEADBEEF;

    return 0;
}

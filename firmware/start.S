    .section .init, "ax"
    .global _start
_start:
    # Set up stack pointer (e.g. use DDR or somewhere valid).
    # DDR is at 0x8000_0000. Let's put stack at 0x8001_0000.
    # Note: L2 is at 0x0000_0000 but it's cache. Let's just use 0x80010000.
    li sp, 0x80010000
    
    # Call main
    call main

    # Infinite loop if main returns
1:
    j 1b

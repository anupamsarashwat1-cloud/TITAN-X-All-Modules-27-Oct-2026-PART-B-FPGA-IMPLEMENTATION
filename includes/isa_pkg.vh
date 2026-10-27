// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Centralized ISA Package
// Covers: RV64I, M, A, F, D, C extensions + Sv39 CSR addresses
// Iteration 3 — complete spec-compliant definitions
`ifndef ISA_PKG_VH
`define ISA_PKG_VH

// ============================================================
// Base Opcodes (RV32I / RV64I)
// ============================================================
`define OP_LUI      7'b0110111
`define OP_AUIPC    7'b0010111
`define OP_JAL      7'b1101111
`define OP_JALR     7'b1100111
`define OP_BRANCH   7'b1100011
`define OP_LOAD     7'b0000011
`define OP_STORE    7'b0100011
`define OP_IMM      7'b0010011  // OP-IMM (RV32I 32-bit immediate)
`define OP_REG      7'b0110011  // OP (RV32I register-register)
`define OP_IMM64    7'b0011011  // OP-IMM-32 (RV64I word ops)
`define OP_REG64    7'b0111011  // OP-32 (RV64I word register-register)
`define OP_SYSTEM   7'b1110011
`define OP_FENCE    7'b0001111
`define OP_AMO      7'b0101111  // A-extension atomic operations
`define OP_LOAD_FP  7'b0000111  // F/D-extension FP load
`define OP_STORE_FP 7'b0100111  // F/D-extension FP store
`define OP_FP       7'b1010011  // F/D-extension FP arithmetic
`define OP_FMADD    7'b1000011  // FMADD
`define OP_FMSUB    7'b1000111  // FMSUB
`define OP_FNMSUB   7'b1001011  // FNMSUB
`define OP_FNMADD   7'b1001111  // FNMADD

// ============================================================
// M-Extension funct3 codes (within OP_REG / OP_REG64)
// funct7 = 7'b0000001 for all M-ext ops
// ============================================================
`define F3_MUL      3'b000
`define F3_MULH     3'b001
`define F3_MULHSU   3'b010
`define F3_MULHU    3'b011
`define F3_DIV      3'b100
`define F3_DIVU     3'b101
`define F3_REM      3'b110
`define F3_REMU     3'b111
`define F7_MEXT     7'b0000001

// ============================================================
// A-Extension AMO funct5 codes (within OP_AMO, bits [31:27])
// ============================================================
`define AMO_LR      5'b00010
`define AMO_SC      5'b00011
`define AMO_SWAP    5'b00001
`define AMO_ADD     5'b00000
`define AMO_XOR     5'b00100
`define AMO_AND     5'b01100
`define AMO_OR      5'b01000
`define AMO_MIN     5'b10000
`define AMO_MAX     5'b10100
`define AMO_MINU    5'b11000
`define AMO_MAXU    5'b11100
// funct3 for AMO width: 010=W(32-bit), 011=D(64-bit)
`define AMO_W       3'b010
`define AMO_D       3'b011

// ============================================================
// F/D-Extension FP Operation funct5 codes (bits [31:27])
// ============================================================
`define FOP_FADD    5'b00000
`define FOP_FSUB    5'b00001
`define FOP_FMUL    5'b00010
`define FOP_FDIV    5'b00011
`define FOP_FSQRT   5'b01011
`define FOP_FSGNJ   5'b00100
`define FOP_FMINMAX 5'b00101
`define FOP_FCVT_WF 5'b11000  // float → int
`define FOP_FCVT_FW 5'b11010  // int → float
`define FOP_FCVT_FF 5'b01000  // float ↔ float (SP/DP conversion)
`define FOP_FMVXW   5'b11100  // FMV.X.W / FMV.X.D
`define FOP_FMVWX   5'b11110  // FMV.W.X / FMV.D.X
`define FOP_FCMP    5'b10100  // FEQ/FLT/FLE

// fmt field: 00=S (single), 01=D (double)
`define FMT_S       2'b00
`define FMT_D       2'b01

// ============================================================
// FP Rounding Modes (frm CSR / instruction rm field)
// ============================================================
`define RM_RNE      3'b000  // Round to Nearest, ties to Even
`define RM_RTZ      3'b001  // Round towards Zero
`define RM_RDN      3'b010  // Round Down (toward -∞)
`define RM_RUP      3'b011  // Round Up (toward +∞)
`define RM_RMM      3'b100  // Round to Nearest, ties to Max Magnitude
`define RM_DYN      3'b111  // Dynamic (use frm CSR)

// ============================================================
// FP Exception Flags (fflags CSR bits)
// ============================================================
`define FFLAG_NX    5'b00001  // Inexact
`define FFLAG_UF    5'b00010  // Underflow
`define FFLAG_OF    5'b00100  // Overflow
`define FFLAG_DZ    5'b01000  // Divide by Zero
`define FFLAG_NV    5'b10000  // Invalid Operation

// ============================================================
// CSR Addresses — Machine Mode
// ============================================================
// Status / Control
`define CSR_MSTATUS     12'h300
`define CSR_MISA        12'h301
`define CSR_MEDELEG     12'h302
`define CSR_MIDELEG     12'h303
`define CSR_MIE         12'h304
`define CSR_MTVEC       12'h305
`define CSR_MCOUNTEREN  12'h306
`define CSR_MSCRATCH    12'h340
`define CSR_MEPC        12'h341
`define CSR_MCAUSE      12'h342
`define CSR_MTVAL       12'h343
`define CSR_MIP         12'h344
// PMP Configuration
`define CSR_PMPCFG0     12'h3A0
`define CSR_PMPCFG1     12'h3A1
`define CSR_PMPCFG2     12'h3A2
`define CSR_PMPCFG3     12'h3A3
`define CSR_PMPADDR0    12'h3B0
`define CSR_PMPADDR1    12'h3B1
`define CSR_PMPADDR2    12'h3B2
`define CSR_PMPADDR3    12'h3B3
`define CSR_PMPADDR4    12'h3B4
`define CSR_PMPADDR5    12'h3B5
`define CSR_PMPADDR6    12'h3B6
`define CSR_PMPADDR7    12'h3B7
// Hardware Performance Counters
`define CSR_MCYCLE      12'hB00
`define CSR_MINSTRET    12'hB02
`define CSR_MHARTID     12'hF14

// ============================================================
// CSR Addresses — Supervisor Mode (Sv39)
// ============================================================
`define CSR_SSTATUS     12'h100
`define CSR_SIE         12'h104
`define CSR_STVEC       12'h105
`define CSR_SCOUNTEREN  12'h106
`define CSR_SSCRATCH    12'h140
`define CSR_SEPC        12'h141
`define CSR_SCAUSE      12'h142
`define CSR_STVAL       12'h143
`define CSR_SIP         12'h144
`define CSR_SATP        12'h180  // Sv39: mode[63:60]=8, ASID[59:44], PPN[43:0]

// ============================================================
// CSR Addresses — Floating Point
// ============================================================
`define CSR_FFLAGS      12'h001  // FP Exception Flags
`define CSR_FRM         12'h002  // FP Rounding Mode
`define CSR_FCSR        12'h003  // FP Control+Status (fflags + frm combined)

// ============================================================
// SATP Register Fields (Sv39)
// ============================================================
`define SATP_MODE_BARE  4'd0
`define SATP_MODE_SV39  4'd8

// ============================================================
// Cause Codes — Exceptions (mcause/scause, interrupt=0)
// ============================================================
`define EXC_INSTR_MISALIGN   64'd0
`define EXC_INSTR_ACCESS     64'd1
`define EXC_ILLEGAL_INSTR    64'd2
`define EXC_BREAKPOINT       64'd3
`define EXC_LOAD_MISALIGN    64'd4
`define EXC_LOAD_ACCESS      64'd5
`define EXC_STORE_MISALIGN   64'd6
`define EXC_STORE_ACCESS     64'd7
`define EXC_ECALL_U          64'd8
`define EXC_ECALL_S          64'd9
`define EXC_ECALL_M          64'd11
`define EXC_INSTR_PAGE       64'd12
`define EXC_LOAD_PAGE        64'd13
`define EXC_STORE_PAGE       64'd15

// ============================================================
// Cause Codes — Interrupts (mcause/scause, interrupt=1)
// ============================================================
`define INT_U_SW    64'd0
`define INT_S_SW    64'd1
`define INT_M_SW    64'd3
`define INT_U_TIM   64'd4
`define INT_S_TIM   64'd5
`define INT_M_TIM   64'd7
`define INT_U_EXT   64'd8
`define INT_S_EXT   64'd9
`define INT_M_EXT   64'd11

// ============================================================
// ALU Operation Selectors (extended for M/F/A extensions)
// ============================================================
// Integer ALU
`define ALU_ADD     5'd0
`define ALU_SUB     5'd1
`define ALU_SLT     5'd2
`define ALU_SLTU    5'd3
`define ALU_XOR     5'd4
`define ALU_OR      5'd5
`define ALU_AND     5'd6
`define ALU_SLL     5'd7
`define ALU_SRL     5'd8
`define ALU_SRA     5'd9
`define ALU_LUI     5'd10
`define ALU_AUIPC   5'd11
// M-Extension
`define ALU_MUL     5'd12
`define ALU_MULH    5'd13
`define ALU_MULHSU  5'd14
`define ALU_MULHU   5'd15
`define ALU_DIV     5'd16
`define ALU_DIVU    5'd17
`define ALU_REM     5'd18
`define ALU_REMU    5'd19
// Copy / Pass-through
`define ALU_COPY_B  5'd20

// ============================================================
// C-Extension (Compressed) Quadrant Identifiers
// ============================================================
`define C_Q0        2'b00  // Quadrant 0
`define C_Q1        2'b01  // Quadrant 1
`define C_Q2        2'b10  // Quadrant 2
// (instructions with bits[1:0]==11 are regular 32-bit)

// ============================================================
// Privilege Levels
// ============================================================
`define PRIV_U      2'b00  // User
`define PRIV_S      2'b01  // Supervisor
`define PRIV_M      2'b11  // Machine

// ============================================================
// PMP Configuration Register (pmpcfg) bit fields
// ============================================================
`define PMP_R       8'b00000001  // Read permission
`define PMP_W       8'b00000010  // Write permission
`define PMP_X       8'b00000100  // Execute permission
`define PMP_A_OFF   2'b00        // Disabled
`define PMP_A_TOR   2'b01        // Top Of Range
`define PMP_A_NA4   2'b10        // Naturally Aligned 4B
`define PMP_A_NAPOT 2'b11        // Naturally Aligned Power of Two
`define PMP_L       8'b10000000  // Lock bit

// ============================================================
// MISA ISA Extension Bits
// ============================================================
`define MISA_A      26'h0000001  // Atomic extension
`define MISA_C      26'h0000004  // Compressed extension
`define MISA_D      26'h0000008  // Double-precision FP
`define MISA_F      26'h0000020  // Single-precision FP
`define MISA_G      26'h0000040  // General (IMAFD)
`define MISA_I      26'h0000100  // Base integer ISA
`define MISA_M      26'h0001000  // Integer multiply/divide
`define MISA_S      26'h0040000  // Supervisor mode
`define MISA_U      26'h0100000  // User mode

`endif // ISA_PKG_VH

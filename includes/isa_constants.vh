// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Shared RISC-V ISA Constants Header

// Opcode constants (RV64I base instruction format)
localparam OP_LUI      = 7'b0110111;
localparam OP_AUIPC    = 7'b0010111;
localparam OP_JAL      = 7'b1101111;
localparam OP_JALR     = 7'b1100111;
localparam OP_BRANCH   = 7'b1100011;
localparam OP_LOAD     = 7'b0000011;
localparam OP_STORE    = 7'b0100011;
localparam OP_IMM      = 7'b0010011;
localparam OP_REG      = 7'b0110011;
localparam OP_IMM64    = 7'b0011011;
localparam OP_REG64    = 7'b0111011;
localparam OP_SYSTEM   = 7'b1110011;
localparam OP_FENCE    = 7'b0001111;

// ALU operation selectors
localparam ALU_ADD     = 4'd0;
localparam ALU_SUB     = 4'd1;
localparam ALU_SLT     = 4'd2;
localparam ALU_SLTU    = 4'd3;
localparam ALU_XOR     = 4'd4;
localparam ALU_OR      = 4'd5;
localparam ALU_AND     = 4'd6;
localparam ALU_SLL     = 4'd7;
localparam ALU_SRL     = 4'd8;
localparam ALU_SRA     = 4'd9;
localparam ALU_LUI     = 4'd10;
localparam ALU_AUIPC   = 4'd11;

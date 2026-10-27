// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RV64I Decode + Register File Stage
`timescale 1ns/1ps
// Shared ISA constants — single source of truth shared with execute/top.
// (isa_constants.vh was a drifted 4-bit localparam duplicate; retired.)
// Included at file scope, matching every other consumer of this header.
`include "isa_pkg.vh"

module rv_decode (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,
    // From fetch
    input  wire [63:0] pc_in,
    input  wire [31:0] instr_in,
    input  wire        valid_in,
    // Writeback feedback
    input  wire [4:0]  wb_rd,
    input  wire [63:0] wb_data,
    input  wire        wb_we,
    // To execute
    output reg  [63:0] pc_out,
    output reg  [63:0] rs1_data,
    output reg  [63:0] rs2_data,
    output reg  [63:0] imm,
    output reg  [4:0]  rd,
    output reg  [4:0]  rs1_addr,
    output reg  [4:0]  rs2_addr,
    output reg  [2:0]  funct3,
    output reg  [6:0]  funct7,
    output reg  [6:0]  opcode,
    output reg  [4:0]  alu_op,
    output reg         mem_read,
    output reg         mem_write,
    output reg         reg_write,
    output reg         branch,
    output reg         jal,
    output reg         jalr,
    // SYSTEM (Zicsr + privileged simples, Phase 5 Step 5.4)
    output reg         is_csr,
    output reg  [1:0]  csr_op,      // f3[1:0]: 01 W, 10 S, 11 C
    output reg         is_ecall,
    output reg         is_ebreak,
    output reg         is_mret,
    output reg         valid_out
);
    wire [6:0] op   = instr_in[6:0];
    wire [4:0] r_rs1 = instr_in[19:15];
    wire [4:0] r_rs2 = instr_in[24:20];
    wire [4:0] r_rd  = instr_in[11:7];
    wire [2:0] f3   = instr_in[14:12];
    wire [6:0] f7   = instr_in[31:25];

    // Immediate decode (combinational)
    reg [63:0] imm_comb;
    reg [4:0]  alu_op_comb;
    reg        mem_r_comb, mem_w_comb, reg_w_comb, br_comb, jal_comb, jalr_comb;
    reg        csr_comb, ec_comb, eb_comb, mret_comb;
    reg [1:0]  csrop_comb;

    always @(*) begin
        imm_comb    = 64'h0;
        alu_op_comb = `ALU_ADD;
        mem_r_comb  = 1'b0;
        mem_w_comb  = 1'b0;
        reg_w_comb  = 1'b0;
        br_comb     = 1'b0;
        jal_comb    = 1'b0;
        jalr_comb   = 1'b0;
        csr_comb    = 1'b0;
        ec_comb     = 1'b0;
        eb_comb     = 1'b0;
        mret_comb   = 1'b0;
        csrop_comb  = 2'b00;

        case (op)
            `OP_LUI: begin
                imm_comb    = {{32{instr_in[31]}}, instr_in[31:12], 12'h0};
                alu_op_comb = `ALU_LUI;
                reg_w_comb  = 1'b1;
            end
            `OP_AUIPC: begin
                imm_comb    = {{32{instr_in[31]}}, instr_in[31:12], 12'h0};
                alu_op_comb = `ALU_AUIPC;
                reg_w_comb  = 1'b1;
            end
            `OP_JAL: begin
                // Width check: 51 sign bits + 1 + 8 + 1 + 10 + 1 = 64.
                // (Was 43 sign bits — a 63-bit concat silently
                // zero-extended, corrupting every jal target.)
                imm_comb    = {{51{instr_in[31]}}, instr_in[19:12],
                               instr_in[20], instr_in[30:21], 1'b0};
                alu_op_comb = `ALU_ADD;
                reg_w_comb  = 1'b1;
                jal_comb    = 1'b1;
            end
            `OP_JALR: begin
                imm_comb    = {{52{instr_in[31]}}, instr_in[31:20]};
                alu_op_comb = `ALU_ADD;
                reg_w_comb  = 1'b1;
                jalr_comb   = 1'b1;
            end
            `OP_BRANCH: begin
                imm_comb    = {{51{instr_in[31]}}, instr_in[31], instr_in[7],
                               instr_in[30:25], instr_in[11:8], 1'b0};
                br_comb     = 1'b1;
                case (f3)
                    3'b000: alu_op_comb = `ALU_SUB;  // BEQ
                    3'b001: alu_op_comb = `ALU_SUB;  // BNE
                    3'b100: alu_op_comb = `ALU_SLT;  // BLT
                    3'b101: alu_op_comb = `ALU_SLT;  // BGE
                    3'b110: alu_op_comb = `ALU_SLTU; // BLTU
                    3'b111: alu_op_comb = `ALU_SLTU; // BGEU
                    default: alu_op_comb = `ALU_SUB;
                endcase
            end
            `OP_LOAD: begin
                imm_comb   = {{52{instr_in[31]}}, instr_in[31:20]};
                mem_r_comb = 1'b1;
                reg_w_comb = 1'b1;
            end
            `OP_STORE: begin
                imm_comb   = {{52{instr_in[31]}}, instr_in[31:25], instr_in[11:7]};
                mem_w_comb = 1'b1;
            end
            `OP_IMM, `OP_IMM64: begin
                imm_comb   = {{52{instr_in[31]}}, instr_in[31:20]};
                reg_w_comb = 1'b1;
                case (f3)
                    3'b000: alu_op_comb = `ALU_ADD;
                    3'b010: alu_op_comb = `ALU_SLT;
                    3'b011: alu_op_comb = `ALU_SLTU;
                    3'b100: alu_op_comb = `ALU_XOR;
                    3'b110: alu_op_comb = `ALU_OR;
                    3'b111: alu_op_comb = `ALU_AND;
                    3'b001: alu_op_comb = `ALU_SLL;
                    3'b101: alu_op_comb = (f7[5]) ? `ALU_SRA : `ALU_SRL;
                    default: alu_op_comb = `ALU_ADD;
                endcase
            end
            `OP_REG, `OP_REG64: begin
                reg_w_comb = 1'b1;
                if (f7 == 7'b0000001) begin
                    // M-extension. Dispatched on the FULL funct7: the old
                    // {f7[5],f3} table ignored f7[0], so every MUL/DIV
                    // decoded as its base-op twin (MUL executed as ADD,
                    // DIV as XOR).
                    case (f3)
                        3'b000: alu_op_comb = `ALU_MUL;
                        3'b001: alu_op_comb = `ALU_MULH;
                        3'b010: alu_op_comb = `ALU_MULHSU;
                        3'b011: alu_op_comb = `ALU_MULHU;
                        3'b100: alu_op_comb = `ALU_DIV;
                        3'b101: alu_op_comb = `ALU_DIVU;
                        3'b110: alu_op_comb = `ALU_REM;
                        3'b111: alu_op_comb = `ALU_REMU;
                        default: alu_op_comb = `ALU_ADD;
                    endcase
                end else
                case ({f7[5], f3})
                    4'b0000: alu_op_comb = `ALU_ADD;
                    4'b1000: alu_op_comb = `ALU_SUB;
                    4'b0010: alu_op_comb = `ALU_SLT;
                    4'b0011: alu_op_comb = `ALU_SLTU;
                    4'b0100: alu_op_comb = `ALU_XOR;
                    4'b0110: alu_op_comb = `ALU_OR;
                    4'b0111: alu_op_comb = `ALU_AND;
                    4'b0001: alu_op_comb = `ALU_SLL;
                    4'b0101: alu_op_comb = `ALU_SRL;
                    4'b1101: alu_op_comb = `ALU_SRA;
                    default: alu_op_comb = `ALU_ADD;
                endcase
            end
            `OP_SYSTEM: begin
                // Zicsr + privileged simples. The CSR address rides the
                // imm field (no extra datapath). funct3[2] marks the
                // immediate forms: rs1 field is a zimm VALUE, not an
                // index — Block 3 substitutes {59'b0, r_rs1}.
                if (f3 == 3'b000) begin
                    case (instr_in[31:20])
                        12'h000: ec_comb   = 1'b1;    // ECALL
                        12'h001: eb_comb   = 1'b1;    // EBREAK
                        12'h302: mret_comb = 1'b1;    // MRET
                        default: ;                    // unrecognized SYSTEM
                                                      // -> execute raises
                                                      // illegal-instruction
                    endcase
                end else begin
                    csr_comb   = 1'b1;
                    csrop_comb = f3[1:0];
                    imm_comb   = {52'h0, instr_in[31:20]};
                    reg_w_comb = 1'b1;            // rd <- old value (x0 discards)
                end
            end
            default: begin end
        endcase
    end

    wire zimm_form = (op == `OP_SYSTEM) && f3[2];

    // Register file: dedicated module (unit-tested under backend/rv_regfile),
    // written from the writeback stage through the wb_* feedback port.
    wire [63:0] rf_rs1_data, rf_rs2_data;
    rv_regfile u_rf (
        .clk      (clk),
        .rst_n    (rst_n),
        .rd_addr1 (r_rs1),   .rd_data1 (rf_rs1_data),
        .rd_addr2 (r_rs2),   .rd_data2 (rf_rs2_data),
        .wr_en    (wb_we),
        .wr_addr  (wb_rd),
        .wr_data  (wb_data)
    );

    wire flush_buf1, flush_buf2, flush_buf3, flush_buf4, flush_buf5;
    BUFX4 u_buf1 (.A(flush), .Y(flush_buf1)); // for pc_out
    BUFX4 u_buf2 (.A(flush), .Y(flush_buf2)); // for imm
    BUFX4 u_buf3 (.A(flush), .Y(flush_buf3)); // for rs1_data
    BUFX4 u_buf4 (.A(flush), .Y(flush_buf4)); // for rs2_data
    BUFX4 u_buf5 (.A(flush), .Y(flush_buf5)); // for control bits

    // Pipeline register - Block 1: pc_out
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out    <= 64'h0;
        end else if (flush_buf1) begin
            pc_out    <= 64'h0;
        end else if (!stall) begin
            pc_out    <= pc_in;
        end
    end

    // Pipeline register - Block 2: imm
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            imm       <= 64'h0;
        end else if (flush_buf2) begin
            imm       <= 64'h0;
        end else if (!stall) begin
            imm       <= imm_comb;
        end
    end

    // Pipeline register - Block 3: rs1_data
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rs1_data  <= 64'h0;
        end else if (flush_buf3) begin
            rs1_data  <= 64'h0;
        end else if (!stall) begin
            rs1_data  <= (wb_we && wb_rd == r_rs1 && r_rs1 != 5'h0) ?
                         wb_data :
                         zimm_form ? {59'b0, r_rs1} :   // CSRR*I: field is a value
                         rf_rs1_data;
        end
    end

    // Pipeline register - Block 4: rs2_data
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rs2_data  <= 64'h0;
        end else if (flush_buf4) begin
            rs2_data  <= 64'h0;
        end else if (!stall) begin
            rs2_data  <= (wb_we && wb_rd == r_rs2 && r_rs2 != 5'h0) ?
                         wb_data : rf_rs2_data;
        end
    end

    // Pipeline register - Block 5: control signals
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd        <= 5'h0;
            rs1_addr  <= 5'h0;
            rs2_addr  <= 5'h0;
            funct3    <= 3'h0;
            funct7    <= 7'h0;
            opcode    <= 7'h0;
            alu_op    <= 5'h0;
            mem_read  <= 1'b0;
            mem_write <= 1'b0;
            reg_write <= 1'b0;
            branch    <= 1'b0;
            jal       <= 1'b0;
            jalr      <= 1'b0;
            is_csr    <= 1'b0;
            csr_op    <= 2'b00;
            is_ecall  <= 1'b0;
            is_ebreak <= 1'b0;
            is_mret   <= 1'b0;
            valid_out <= 1'b0;
        end else if (flush_buf5) begin
            rd        <= 5'h0;
            rs1_addr  <= 5'h0;
            rs2_addr  <= 5'h0;
            funct3    <= 3'h0;
            funct7    <= 7'h0;
            opcode    <= 7'h0;
            alu_op    <= 5'h0;
            mem_read  <= 1'b0;
            mem_write <= 1'b0;
            reg_write <= 1'b0;
            branch    <= 1'b0;
            jal       <= 1'b0;
            jalr      <= 1'b0;
            is_csr    <= 1'b0;
            csr_op    <= 2'b00;
            is_ecall  <= 1'b0;
            is_ebreak <= 1'b0;
            is_mret   <= 1'b0;
            valid_out <= 1'b0;
        end else if (!stall) begin
            rd        <= r_rd;
            rs1_addr  <= r_rs1;
            rs2_addr  <= r_rs2;
            funct3    <= f3;
            funct7    <= f7;
            opcode    <= op;
            alu_op    <= alu_op_comb;
            mem_read  <= mem_r_comb;
            mem_write <= mem_w_comb;
            reg_write <= reg_w_comb;
            branch    <= br_comb;
            jal       <= jal_comb;
            jalr      <= jalr_comb;
            is_csr    <= csr_comb;
            csr_op    <= csrop_comb;
            is_ecall  <= ec_comb;
            is_ebreak <= eb_comb;
            is_mret   <= mret_comb;
            valid_out <= valid_in;
        end
    end
endmodule

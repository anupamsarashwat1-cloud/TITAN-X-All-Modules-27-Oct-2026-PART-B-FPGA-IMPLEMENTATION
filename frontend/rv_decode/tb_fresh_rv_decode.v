// SPDX-License-Identifier: Apache-2.0
// Fresh, self-checking testbench for rv_decode module
// SMVDU-TITAN-X Microprocessor Verification Suite
`timescale 1ns/1ps
`include "isa_pkg.vh"

module tb_fresh_rv_decode;
    reg         clk;
    reg         rst_n;
    reg         stall;
    reg         flush;
    reg  [63:0] pc_in;
    reg  [31:0] instr_in;
    reg         valid_in;
    reg  [4:0]  wb_rd;
    reg  [63:0] wb_data;
    reg         wb_we;

    wire [63:0] pc_out;
    wire [63:0] rs1_data;
    wire [63:0] rs2_data;
    wire [63:0] imm;
    wire [4:0]  rd;
    wire [4:0]  rs1_addr;
    wire [4:0]  rs2_addr;
    wire [2:0]  funct3;
    wire [6:0]  funct7;
    wire [6:0]  opcode;
    wire [4:0]  alu_op;
    wire        mem_read;
    wire        mem_write;
    wire        reg_write;
    wire        branch;
    wire        jal;
    wire        jalr;
    wire        is_csr;
    wire [1:0]  csr_op;
    wire        is_ecall;
    wire        is_ebreak;
    wire        is_mret;
    wire        valid_out;

    integer tests_passed = 0;
    integer tests_failed = 0;

    // Clock generation: 100 MHz (10ns period)
    always #5 clk = ~clk;

    // Instantiate DUT
    rv_decode dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .stall      (stall),
        .flush      (flush),
        .pc_in      (pc_in),
        .instr_in   (instr_in),
        .valid_in   (valid_in),
        .wb_rd      (wb_rd),
        .wb_data    (wb_data),
        .wb_we      (wb_we),
        .pc_out     (pc_out),
        .rs1_data   (rs1_data),
        .rs2_data   (rs2_data),
        .imm        (imm),
        .rd         (rd),
        .rs1_addr   (rs1_addr),
        .rs2_addr   (rs2_addr),
        .funct3     (funct3),
        .funct7     (funct7),
        .opcode     (opcode),
        .alu_op     (alu_op),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .reg_write  (reg_write),
        .branch     (branch),
        .jal        (jal),
        .jalr       (jalr),
        .is_csr     (is_csr),
        .csr_op     (csr_op),
        .is_ecall   (is_ecall),
        .is_ebreak  (is_ebreak),
        .is_mret    (is_mret),
        .valid_out  (valid_out)
    );

    task check(input [255:0] test_name, input condition);
        begin
            if (condition) begin
                $display("[PASS] %0s", test_name);
                tests_passed = tests_passed + 1;
            end else begin
                $display("[FAIL] %0s", test_name);
                tests_failed = tests_failed + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("verification_waves/rv_decode.vcd");
        $dumpvars(0, tb_fresh_rv_decode);

        clk      = 0;
        rst_n    = 0;
        stall    = 0;
        flush    = 0;
        pc_in    = 64'h0;
        instr_in = 32'h0;
        valid_in = 0;
        wb_rd    = 0;
        wb_data  = 0;
        wb_we    = 0;

        // Reset DUT
        #20;
        @(posedge clk); #1;
        rst_n = 1;

        // ----------------------------------------------------
        // Test 1: Reset State Verification
        // ----------------------------------------------------
        @(posedge clk); #1;
        check("Test 1: Reset state valid_out == 0", valid_out == 1'b0);
        check("Test 1: Reset state reg_write == 0", reg_write == 1'b0);
        check("Test 1: Reset state mem_read == 0", mem_read == 1'b0);

        // ----------------------------------------------------
        // Test 2: R-type Arithmetic Decoding (ADD x1, x2, x3)
        // [funct7=0000000][rs2=00011][rs1=00010][funct3=000][rd=00001][opcode=0110011]
        // instr = 32'b0000000_00011_00010_000_00001_0110011 = 32'h003100B3
        // ----------------------------------------------------
        @(posedge clk); #1;
        pc_in    = 64'h0000_0000_8000_0000;
        instr_in = 32'h0031_00B3;
        valid_in = 1'b1;

        @(posedge clk); #1;
        check("Test 2.1: R-type ADD opcode", opcode == `OP_REG);
        check("Test 2.2: R-type ADD rd == 1", rd == 5'd1);
        check("Test 2.3: R-type ADD rs1 == 2", rs1_addr == 5'd2);
        check("Test 2.4: R-type ADD rs2 == 3", rs2_addr == 5'd3);
        check("Test 2.5: R-type ADD alu_op == ALU_ADD", alu_op == `ALU_ADD);
        check("Test 2.6: R-type ADD reg_write == 1", reg_write == 1'b1);
        check("Test 2.7: R-type ADD valid_out == 1", valid_out == 1'b1);

        // ----------------------------------------------------
        // Test 3: I-type Arithmetic with Negative Sign Extension
        // ADDI x4, x1, -16 (imm = 12'hFF0)
        // [imm=111111110000][rs1=00001][funct3=000][rd=00100][opcode=0010011]
        // instr = 32'hFF008213
        // ----------------------------------------------------
        @(posedge clk); #1;
        pc_in    = 64'h0000_0000_8000_0004;
        instr_in = 32'hFF00_8213;
        valid_in = 1'b1;

        @(posedge clk); #1;
        check("Test 3.1: I-type ADDI opcode", opcode == `OP_IMM);
        check("Test 3.2: I-type ADDI rd == 4", rd == 5'd4);
        check("Test 3.3: I-type ADDI rs1 == 1", rs1_addr == 5'd1);
        check("Test 3.4: I-type ADDI imm == -16", imm == 64'hFFFF_FFFF_FFFF_FFF0);
        check("Test 3.5: I-type ADDI alu_op == ALU_ADD", alu_op == `ALU_ADD);

        // ----------------------------------------------------
        // Test 4: U-type Upper Immediate Decoding (LUI & AUIPC)
        // LUI x5, 0x12345: imm[31:12] = 0x12345, rd=5, op=0110111 -> 32'h123452B7
        // AUIPC x6, 0xABCDE: imm[31:12] = 0xABCDE, rd=6, op=0010111 -> 32'hABCDE317
        // ----------------------------------------------------
        @(posedge clk); #1;
        instr_in = 32'h1234_52B7; // LUI
        @(posedge clk); #1;
        check("Test 4.1: LUI opcode", opcode == `OP_LUI);
        check("Test 4.2: LUI rd == 5", rd == 5'd5);
        check("Test 4.3: LUI imm shift", imm == 64'h0000_0000_1234_5000);
        check("Test 4.4: LUI alu_op == ALU_LUI", alu_op == `ALU_LUI);

        @(posedge clk); #1;
        instr_in = 32'hABCD_E317; // AUIPC (bit 31=1 -> sign extended)
        @(posedge clk); #1;
        check("Test 4.5: AUIPC opcode", opcode == `OP_AUIPC);
        check("Test 4.6: AUIPC rd == 6", rd == 5'd6);
        check("Test 4.7: AUIPC imm sign-extended", imm == 64'hFFFF_FFFF_ABCD_E000);
        check("Test 4.8: AUIPC alu_op == ALU_AUIPC", alu_op == `ALU_AUIPC);

        // ----------------------------------------------------
        // Test 5: J-type and B-type Control Transfer Decoding
        // JAL x1, offset=8 -> instr = 32'h008000EF
        // BEQ x1, x2, offset=16 -> instr = 32'h00208863
        // ----------------------------------------------------
        @(posedge clk); #1;
        instr_in = 32'h0080_00EF; // JAL x1, 8
        @(posedge clk); #1;
        check("Test 5.1: JAL opcode", opcode == `OP_JAL);
        check("Test 5.2: JAL flag", jal == 1'b1);
        check("Test 5.3: JAL rd == 1", rd == 5'd1);
        check("Test 5.4: JAL imm == +8", imm == 64'd8);

        @(posedge clk); #1;
        instr_in = 32'h0020_8863; // BEQ x1, x2, 16
        @(posedge clk); #1;
        check("Test 5.5: BEQ opcode", opcode == `OP_BRANCH);
        check("Test 5.6: BEQ branch flag", branch == 1'b1);
        check("Test 5.7: BEQ alu_op == ALU_SUB", alu_op == `ALU_SUB);
        check("Test 5.8: BEQ imm == +16", imm == 64'd16);

        // ----------------------------------------------------
        // Test 6: Memory Load & Store Decoding
        // LD x10, 8(x11) -> op=0000011, f3=011, rd=10, rs1=11, imm=8 -> 32'h0085B503
        // SD x12, 16(x13) -> op=0100011, f3=011, rs2=12, rs1=13, imm=16 -> 32'h00C6B823
        // ----------------------------------------------------
        @(posedge clk); #1;
        instr_in = 32'h0085_B503; // LD
        @(posedge clk); #1;
        check("Test 6.1: LD mem_read == 1", mem_read == 1'b1);
        check("Test 6.2: LD reg_write == 1", reg_write == 1'b1);
        check("Test 6.3: LD funct3 == 3'b011", funct3 == 3'b011);

        @(posedge clk); #1;
        instr_in = 32'h00C6_B823; // SD
        @(posedge clk); #1;
        check("Test 6.4: SD mem_write == 1", mem_write == 1'b1);
        check("Test 6.5: SD reg_write == 0", reg_write == 1'b0);
        check("Test 6.6: SD imm == 16", imm == 64'd16);

        // ----------------------------------------------------
        // Test 7: M-extension Decoding (MUL & DIVU)
        // MUL x14, x15, x16: op=OP_REG, f7=0000001, f3=000 -> 32'h03078733
        // DIVU x17, x18, x19: op=OP_REG, f7=0000001, f3=101 -> 32'h033958B3
        // ----------------------------------------------------
        @(posedge clk); #1;
        instr_in = 32'h0307_8733; // MUL
        @(posedge clk); #1;
        check("Test 7.1: MUL alu_op == ALU_MUL", alu_op == `ALU_MUL);

        @(posedge clk); #1;
        instr_in = 32'h0339_58B3; // DIVU
        @(posedge clk); #1;
        check("Test 7.2: DIVU alu_op == ALU_DIVU", alu_op == `ALU_DIVU);

        // ----------------------------------------------------
        // Test 8: System & CSR Operations
        // CSRRW x1, 0x300 (mstatus), x2: op=OP_SYSTEM, f3=001 -> 32'h300110F3
        // CSRRSI x3, 0x304 (mie), 5: f3=110 -> 32'h3042E1F3
        // ECALL: 32'h0000_0073, EBREAK: 32'h0010_0073, MRET: 32'h3020_0073
        // ----------------------------------------------------
        @(posedge clk); #1;
        instr_in = 32'h3001_10F3; // CSRRW
        @(posedge clk); #1;
        check("Test 8.1: CSRRW is_csr == 1", is_csr == 1'b1);
        check("Test 8.2: CSRRW csr_op == 2'b01", csr_op == 2'b01);
        check("Test 8.3: CSRRW csr addr == 0x300", imm == 64'h300);

        @(posedge clk); #1;
        instr_in = 32'h3042_E1F3; // CSRRSI with zimm = 5
        @(posedge clk); #1;
        check("Test 8.4: CSRRSI is_csr == 1", is_csr == 1'b1);
        check("Test 8.5: CSRRSI csr_op == 2'b10", csr_op == 2'b10);
        check("Test 8.6: CSRRSI zimm forwarded to rs1_data", rs1_data == 64'd5);

        @(posedge clk); #1;
        instr_in = 32'h0000_0073; // ECALL
        @(posedge clk); #1;
        check("Test 8.7: ECALL is_ecall == 1", is_ecall == 1'b1);

        @(posedge clk); #1;
        instr_in = 32'h0010_0073; // EBREAK
        @(posedge clk); #1;
        check("Test 8.8: EBREAK is_ebreak == 1", is_ebreak == 1'b1);

        @(posedge clk); #1;
        instr_in = 32'h3020_0073; // MRET
        @(posedge clk); #1;
        check("Test 8.9: MRET is_mret == 1", is_mret == 1'b1);

        // ----------------------------------------------------
        // Test 9: Register File Writeback and Zero-Cycle Bypass
        // Write 0xDEADBEEFCAFE0001 to x7 via writeback interface.
        // In the same cycle, decode an instruction that reads x7 as rs1.
        // ----------------------------------------------------
        @(posedge clk); #1;
        wb_rd    = 5'd7;
        wb_data  = 64'hDEAD_BEEF_CAFE_0001;
        wb_we    = 1'b1;
        instr_in = 32'h0003_8413; // ADDI x8, x7, 0 (rs1 = x7)

        @(posedge clk); #1;
        check("Test 9.1: Write-first bypass forward wb_data to rs1_data",
              rs1_data == 64'hDEAD_BEEF_CAFE_0001);

        // Now read x7 normally next cycle without active wb_we
        wb_we = 1'b0;
        instr_in = 32'h0003_8493; // ADDI x9, x7, 0
        @(posedge clk); #1;
        check("Test 9.2: Stored regfile read x7 value",
              rs1_data == 64'hDEAD_BEEF_CAFE_0001);

        // Verify x0 write suppression
        wb_rd   = 5'd0;
        wb_data = 64'hFFFF_FFFF_FFFF_FFFF;
        wb_we   = 1'b1;
        instr_in = 32'h0000_0513; // ADDI x10, x0, 0
        @(posedge clk); #1;
        check("Test 9.3: x0 hardwired to zero", rs1_data == 64'h0);
        wb_we   = 1'b0;

        // ----------------------------------------------------
        // Test 10: Pipeline Stall and Flush Interlocks
        // ----------------------------------------------------
        instr_in = 32'h0010_0093; // ADDI x1, x0, 1
        @(posedge clk); #1;
        check("Test 10.1: Instruction registered before stall", rd == 5'd1 && valid_out == 1'b1);

        // Assert stall
        stall = 1'b1;
        instr_in = 32'h0020_0113; // ADDI x2, x0, 2
        @(posedge clk); #1;
        check("Test 10.2: Stall holds previous rd", rd == 5'd1);
        check("Test 10.3: Stall holds previous valid_out", valid_out == 1'b1);

        // Release stall
        stall = 1'b0;
        @(posedge clk); #1;
        check("Test 10.4: Next instruction enters after stall release", rd == 5'd2);

        // Assert flush
        flush = 1'b1;
        @(posedge clk); #1;
        check("Test 10.5: Flush clears valid_out", valid_out == 1'b0);
        check("Test 10.6: Flush clears rd", rd == 5'd0);
        check("Test 10.7: Flush clears reg_write", reg_write == 1'b0);
        flush = 1'b0;

        // ----------------------------------------------------
        // Final Scorecard
        // ----------------------------------------------------
        #20;
        $display("\n=======================================================");
        $display(" rv_decode Verification Scorecard");
        $display(" Total Passed: %0d", tests_passed);
        $display(" Total Failed: %0d", tests_failed);
        $display("=======================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED] rv_decode 100% verified.");
        end else begin
            $fatal(1, "[TESTBENCH FAILED] Found %0d failures.", tests_failed);
        end
        $finish;
    end
endmodule

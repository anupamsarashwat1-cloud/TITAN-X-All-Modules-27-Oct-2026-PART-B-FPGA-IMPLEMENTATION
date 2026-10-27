// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RV Decode Stage Directed Self-Checking Testbench
// Note: rv_decode is fully pipelined - outputs are registered on posedge clk.
// Outputs appear at the posedge AFTER valid_in is presented (1-cycle latency).
// We must capture outputs BEFORE clearing the inputs.
`timescale 1ns/1ps
`include "isa_pkg.vh"

module tb_rv_decode();
    reg        clk, rst_n, stall, flush;
    reg [63:0] pc_in;
    reg [31:0] instr_in;
    reg        valid_in;
    reg [4:0]  wb_rd;
    reg [63:0] wb_data;
    reg        wb_we;

    wire [63:0] pc_out;
    wire [63:0] rs1_data, rs2_data;
    wire [63:0] imm;
    wire [4:0]  rd, rs1_addr, rs2_addr;
    wire [2:0]  funct3;
    wire [6:0]  funct7, opcode;
    wire [4:0]  alu_op;
    wire        mem_read, mem_write, reg_write;
    wire        branch, jal, jalr, valid_out;

    integer error_count;

    rv_decode uut (
        .clk(clk), .rst_n(rst_n), .stall(stall), .flush(flush),
        .pc_in(pc_in), .instr_in(instr_in), .valid_in(valid_in),
        .wb_rd(wb_rd), .wb_data(wb_data), .wb_we(wb_we),
        .pc_out(pc_out), .rs1_data(rs1_data), .rs2_data(rs2_data), .imm(imm),
        .rd(rd), .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .funct3(funct3), .funct7(funct7), .opcode(opcode), .alu_op(alu_op),
        .mem_read(mem_read), .mem_write(mem_write), .reg_write(reg_write),
        .branch(branch), .jal(jal), .jalr(jalr), .valid_out(valid_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [63:0] got; input [63:0] exp; input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=0x%X exp=0x%X", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    // Helper: send instruction and sample output on next posedge
    // Strategy: present instr on negedge (mid-cycle), sample on the NEXT posedge
    task decode_instr;
        input [63:0] pc;
        input [31:0] instr;
        begin
            // Present inputs mid-cycle (after negedge of clock)
            @(negedge clk);
            pc_in = pc; instr_in = instr; valid_in = 1;
            // Outputs will be registered on the UPCOMING posedge
            @(posedge clk); #1;  // sample outputs here (registered on this edge)
            // Clear inputs after sampling
            valid_in = 0; instr_in = 32'h0;
        end
    endtask

    initial begin
        $dumpfile("tb_rv_decode.vcd");
        $dumpvars(0, tb_rv_decode);
        error_count = 0;
        stall=0; flush=0; pc_in=0; instr_in=32'h0; valid_in=0;
        wb_rd=0; wb_data=0; wb_we=0;
        rst_n=0; repeat(6) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

        // TEST 1: Reset state
        $display("\n--- TEST 1: Reset state ---");
        @(posedge clk); #1;
        check(valid_out, 1'b0, "valid_out=0 after reset");

        // TEST 2: ADDI x1, x0, 42
        // I-type: [31:20]=imm, [19:15]=rs1, [14:12]=funct3, [11:7]=rd, [6:0]=opcode
        $display("\n--- TEST 2: ADDI x1, x0, 42 ---");
        decode_instr(64'h1000, {12'd42, 5'd0, 3'b000, 5'd1, 7'h13});
        check(opcode,    7'h13,   "opcode=0x13 (OP_IMM) for ADDI");
        check(rd,        5'd1,    "rd=1 for ADDI x1,x0,42");
        check(rs1_addr,  5'd0,    "rs1=0 for ADDI x1,x0,42");
        check(imm,       64'd42,  "imm=42 for ADDI");
        check(alu_op,    `ALU_ADD, "alu_op=ALU_ADD for ADDI");
        check(reg_write, 1'b1,    "reg_write=1 for ADDI");
        check(mem_read,  1'b0,    "mem_read=0 for ADDI");
        check(valid_out, 1'b1,    "valid_out=1 for ADDI");

        // TEST 3: LW x2, 8(x1)
        $display("\n--- TEST 3: LW x2, 8(x1) ---");
        decode_instr(64'h1004, {12'd8, 5'd1, 3'b010, 5'd2, 7'h03});
        check(opcode,    7'h03,  "opcode=0x03 (OP_LOAD) for LW");
        check(rd,        5'd2,   "rd=2 for LW");
        check(rs1_addr,  5'd1,   "rs1=1 for LW");
        check(imm,       64'd8,  "imm=8 for LW");
        check(mem_read,  1'b1,   "mem_read=1 for LW");
        check(mem_write, 1'b0,   "mem_write=0 for LW");
        check(reg_write, 1'b1,   "reg_write=1 for LW");

        // TEST 4: SW x2, 16(x1)
        // S-type: [31:25]=imm[11:5], [24:20]=rs2, [19:15]=rs1, [14:12]=funct3, [11:7]=imm[4:0], [6:0]=opcode
        // imm=16: imm[11:5]=7'b0000000, imm[4:0]=5'b10000
        $display("\n--- TEST 4: SW x2, 16(x1) ---");
        decode_instr(64'h1008, {7'b0000000, 5'd2, 5'd1, 3'b010, 5'b10000, 7'h23});
        check(opcode,    7'h23,  "opcode=0x23 (OP_STORE) for SW");
        check(rs1_addr,  5'd1,   "rs1=1 for SW");
        check(rs2_addr,  5'd2,   "rs2=2 for SW");
        check(mem_write, 1'b1,   "mem_write=1 for SW");
        check(mem_read,  1'b0,   "mem_read=0 for SW");
        check(reg_write, 1'b0,   "reg_write=0 for SW");

        // TEST 5: BEQ x0, x0, +8
        // B-type encoding: imm[12]=0 imm[10:5]=6'b0 rs2=0 rs1=0 f3=000 imm[4:1]=4'b0100 imm[11]=0 op=0x63
        $display("\n--- TEST 5: BEQ x0, x0, +8 ---");
        decode_instr(64'h100C, {7'b0000000, 5'd0, 5'd0, 3'b000, 5'b01000, 7'h63});
        check(opcode,   7'h63,  "opcode=0x63 (OP_BRANCH) for BEQ");
        check(branch,   1'b1,   "branch=1 for BEQ");
        check(reg_write,1'b0,   "reg_write=0 for BEQ");
        check(mem_read, 1'b0,   "mem_read=0 for BEQ");

        // TEST 6: Flush
        $display("\n--- TEST 6: Flush ---");
        @(negedge clk);
        instr_in={12'd5, 5'd2, 3'b000, 5'd3, 7'h13}; valid_in=1; flush=1;
        @(posedge clk); #1;
        valid_in=0; instr_in=32'h0; flush=0;
        check(valid_out, 1'b0, "valid_out=0 during flush");

        // TEST 7: WB forwarding — write x5=0xABCDEF, then read x5 as rs1
        $display("\n--- TEST 7: WB forwarding (x5) ---");
        @(negedge clk); wb_rd=5'd5; wb_data=64'hABCD_EF01_2345_6789; wb_we=1;
        @(posedge clk); #1; wb_we=0;  // x5 written to regfile
        // Now decode ADDI x6, x5, 0 — rs1=x5 should read back 0xABCD...
        decode_instr(64'h2000, {12'd0, 5'd5, 3'b000, 5'd6, 7'h13});
        check(rs1_data, 64'hABCD_EF01_2345_6789, "rs1_data=0xABCDEF0123456789 (WB x5)");

        $display("\n==============================");
        if (error_count == 0)
            $display("RV_DECODE VERDICT: ✅ PASS — All tests passed");
        else
            $display("RV_DECODE VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #500_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

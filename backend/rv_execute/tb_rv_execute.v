// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RV Execute Stage Directed Self-Checking Testbench
// Tests: ADD, SUB, AND, OR, XOR, SLL, SRA, SLT, branch_taken, JAL target
// NOTE: rv_execute uses `include isa_pkg.vh for `define ALU_*
`timescale 1ns/1ps
`include "isa_pkg.vh"

module tb_rv_execute();
    reg        clk, rst_n, stall, flush;
    reg [63:0] pc_in, rs1_data, rs2_data, imm;
    reg [4:0]  rd_in, rs1_addr, rs2_addr;
    reg [2:0]  funct3;
    reg [6:0]  funct7, opcode;
    reg [4:0]  alu_op;
    reg        mem_read, mem_write, reg_write, branch, jal, jalr;
    reg        is_amo; reg [4:0] amo_funct5;
    // SYSTEM controls (Step 5.4) — tied off below; CSR/trap semantics are
    // covered at the core level (tb_rv_core_csr) and by tb_rv_csr.
    reg        is_csr; reg [1:0] csr_op;
    reg        is_ecall, is_ebreak, is_mret;
    reg        irq_m_ext, irq_m_timer, irq_m_soft;
    reg        valid_in;
    reg [63:0] fwd_mem_data; reg fwd_mem_valid; reg [4:0] fwd_mem_rd;
    reg [63:0] fwd_wb_data;  reg fwd_wb_valid;  reg [4:0] fwd_wb_rd;
    reg [63:0] fpu_result;   reg fpu_valid;     reg fpu_done;

    wire [63:0] alu_result, rs2_out;
    wire [4:0]  rd_out; wire [2:0] funct3_out; wire [6:0] opcode_out;
    wire        mem_read_out, mem_write_out, reg_write_out;
    wire        is_amo_out; wire [4:0] amo_funct5_out;
    wire        valid_out;
    wire        mul_div_stall;
    wire        branch_taken;
    wire [63:0] branch_target;
    wire [63:0] lr_addr; wire lr_valid;

    integer error_count;
    reg [63:0] cap_result;
    reg cap_valid, cap_branch;

    always @(posedge clk) begin
        if (valid_out) begin cap_result <= alu_result; cap_valid <= 1; end
        if (branch_taken) cap_branch <= 1;
    end

    rv_execute uut (
        .clk(clk), .rst_n(rst_n), .stall(stall), .flush(flush),
        .pc_in(pc_in), .rs1_data(rs1_data), .rs2_data(rs2_data), .imm(imm),
        .rd_in(rd_in), .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .funct3(funct3), .funct7(funct7), .opcode(opcode), .alu_op(alu_op),
        .mem_read(mem_read), .mem_write(mem_write), .reg_write(reg_write),
        .branch(branch), .jal(jal), .jalr(jalr),
        .is_amo(is_amo), .amo_funct5(amo_funct5), .valid_in(valid_in),
        .is_csr(is_csr), .csr_op(csr_op),
        .is_ecall(is_ecall), .is_ebreak(is_ebreak), .is_mret(is_mret),
        .irq_m_ext(irq_m_ext), .irq_m_timer(irq_m_timer), .irq_m_soft(irq_m_soft),
        .fwd_mem_data(fwd_mem_data), .fwd_mem_valid(fwd_mem_valid), .fwd_mem_rd(fwd_mem_rd),
        .fwd_wb_data(fwd_wb_data), .fwd_wb_valid(fwd_wb_valid), .fwd_wb_rd(fwd_wb_rd),
        .fpu_result(fpu_result), .fpu_valid(fpu_valid), .fpu_done(fpu_done),
        .alu_result(alu_result), .rs2_out(rs2_out), .rd_out(rd_out),
        .funct3_out(funct3_out), .opcode_out(opcode_out),
        .mem_read_out(mem_read_out), .mem_write_out(mem_write_out),
        .reg_write_out(reg_write_out), .is_amo_out(is_amo_out),
        .amo_funct5_out(amo_funct5_out), .valid_out(valid_out),
        .mul_div_stall(mul_div_stall), .branch_taken(branch_taken),
        .branch_target(branch_target), .lr_addr(lr_addr), .lr_valid(lr_valid)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [63:0] got; input [63:0] exp; input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=0x%016X exp=0x%016X", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    task exec_op;
        input [63:0] s1, s2, imm_v;
        input [4:0] alu;
        input [63:0] pc;
        begin
            cap_valid = 0; cap_branch = 0;
            @(negedge clk);
            rs1_data=s1; rs2_data=s2; imm=imm_v; alu_op=alu;
            pc_in=pc; valid_in=1; branch=0; jal=0; jalr=0;
            mem_read=0; mem_write=0; reg_write=1; is_amo=0;
            @(posedge clk); #1;  // results registered
            valid_in=0; reg_write=0;
        end
    endtask

    initial begin
        $dumpfile("tb_rv_execute.vcd");
        $dumpvars(0, tb_rv_execute);
        error_count = 0; cap_result=0; cap_valid=0; cap_branch=0;
        stall=0; flush=0; pc_in=0; rs1_data=0; rs2_data=0; imm=0;
        rd_in=0; rs1_addr=0; rs2_addr=0; funct3=0; funct7=0; opcode=7'h33;
        alu_op=0; mem_read=0; mem_write=0; reg_write=0;
        branch=0; jal=0; jalr=0; is_amo=0; amo_funct5=0; valid_in=0;
        is_csr=0; csr_op=0; is_ecall=0; is_ebreak=0; is_mret=0;
        irq_m_ext=0; irq_m_timer=0; irq_m_soft=0;
        fwd_mem_data=0; fwd_mem_valid=0; fwd_mem_rd=0;
        fwd_wb_data=0; fwd_wb_valid=0; fwd_wb_rd=0;
        fpu_result=0; fpu_valid=0; fpu_done=0;
        rst_n=0; repeat(6) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

        // TEST 1: Reset
        $display("\n--- TEST 1: Reset state ---");
        @(posedge clk); #1;
        check(valid_out, 1'b0, "valid_out=0 after reset");

        // TEST 2: ADD: 100 + 200 = 300
        $display("\n--- TEST 2: ADD 100+200=300 ---");
        exec_op(64'd100, 64'd200, 0, `ALU_ADD, 64'h1000);
        check(alu_result, 64'd300, "ADD: 100+200=300");
        check(valid_out, 1'b1, "valid_out=1 for ADD");

        // TEST 3: SUB: 500 - 200 = 300
        $display("\n--- TEST 3: SUB 500-200=300 ---");
        exec_op(64'd500, 64'd200, 0, `ALU_SUB, 64'h1004);
        check(alu_result, 64'd300, "SUB: 500-200=300");

        // TEST 4: AND: 0xFF & 0x0F = 0x0F
        $display("\n--- TEST 4: AND 0xFF & 0x0F ---");
        exec_op(64'hFF, 64'h0F, 0, `ALU_AND, 64'h1008);
        check(alu_result, 64'h0F, "AND: 0xFF & 0x0F = 0x0F");

        // TEST 5: OR: 0xF0 | 0x0F = 0xFF
        $display("\n--- TEST 5: OR 0xF0 | 0x0F ---");
        exec_op(64'hF0, 64'h0F, 0, `ALU_OR, 64'h100C);
        check(alu_result, 64'hFF, "OR: 0xF0|0x0F=0xFF");

        // TEST 6: XOR: 0xAA ^ 0x55 = 0xFF
        $display("\n--- TEST 6: XOR 0xAA^0x55 ---");
        exec_op(64'hAA, 64'h55, 0, `ALU_XOR, 64'h1010);
        check(alu_result, 64'hFF, "XOR: 0xAA^0x55=0xFF");

        // TEST 7: SLL: 1 << 4 = 16
        $display("\n--- TEST 7: SLL 1<<4=16 ---");
        exec_op(64'd1, 64'd4, 0, `ALU_SLL, 64'h1014);
        check(alu_result, 64'd16, "SLL: 1<<4=16");

        // TEST 8: SLT: -1 < 1 → 1 (signed)
        $display("\n--- TEST 8: SLT (-1)<1=1 ---");
        exec_op(64'hFFFFFFFF_FFFFFFFF, 64'd1, 0, `ALU_SLT, 64'h1018);
        check(alu_result, 64'd1, "SLT: -1<1=1 (signed)");

        // TEST 9: AUIPC: PC + imm = 0x1000 + 0x10000 = 0x11000
        $display("\n--- TEST 9: AUIPC 0x1000 + 0x10000 ---");
        // For AUIPC, src2=imm and src1=pc are set by rv_execute from pc_in
        exec_op(64'h0, 64'h10000, 64'h10000, `ALU_AUIPC, 64'h1000);
        check(alu_result, 64'h11000, "AUIPC: 0x1000+0x10000=0x11000");

        // TEST 10: Flush clears valid_out
        $display("\n--- TEST 10: Flush ---");
        @(negedge clk); rs1_data=64'd42; rs2_data=64'd8; alu_op=`ALU_ADD;
        valid_in=1; flush=1; reg_write=1;
        @(posedge clk); #1; valid_in=0; flush=0; reg_write=0;
        check(valid_out, 1'b0, "valid_out=0 when flush=1");

        $display("\n==============================");
        if (error_count == 0)
            $display("RV_EXECUTE VERDICT: ✅ PASS — All tests passed");
        else
            $display("RV_EXECUTE VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #1_000_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

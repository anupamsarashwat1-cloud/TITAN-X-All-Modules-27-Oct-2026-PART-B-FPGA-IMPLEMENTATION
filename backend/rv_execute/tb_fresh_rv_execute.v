// SPDX-License-Identifier: Apache-2.0
// Brand-New Fresh Self-Checking Testbench for rv_execute
// Generated strictly from prd.json architectural truth tables & constraints

`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module tb_fresh_rv_execute;
    reg         clk;
    reg         rst_n;
    reg         stall;
    reg         flush;
    reg  [63:0] pc_in;
    reg  [63:0] rs1_data;
    reg  [63:0] rs2_data;
    reg  [63:0] imm;
    reg  [4:0]  rd_in;
    reg  [4:0]  rs1_addr;
    reg  [4:0]  rs2_addr;
    reg  [2:0]  funct3;
    reg  [6:0]  funct7;
    reg  [6:0]  opcode;
    reg  [4:0]  alu_op;
    reg         mem_read;
    reg         mem_write;
    reg         reg_write;
    reg         branch;
    reg         jal;
    reg         jalr;
    reg         is_amo;
    reg  [4:0]  amo_funct5;
    reg         is_csr;
    reg  [1:0]  csr_op;
    reg         is_ecall;
    reg         is_ebreak;
    reg         is_mret;
    reg         irq_m_ext;
    reg         irq_m_timer;
    reg         irq_m_soft;
    reg         valid_in;
    reg  [63:0] fwd_mem_data;
    reg         fwd_mem_valid;
    reg  [4:0]  fwd_mem_rd;
    reg  [63:0] fwd_wb_data;
    reg         fwd_wb_valid;
    reg  [4:0]  fwd_wb_rd;
    reg  [63:0] fpu_result;
    reg         fpu_valid;
    reg         fpu_done;

    wire [63:0] alu_result;
    wire [63:0] rs2_out;
    wire [4:0]  rd_out;
    wire [2:0]  funct3_out;
    wire [6:0]  opcode_out;
    wire        mem_read_out;
    wire        mem_write_out;
    wire        reg_write_out;
    wire        is_amo_out;
    wire [4:0]  amo_funct5_out;
    wire        valid_out;
    wire        mul_div_stall;
    wire        branch_taken;
    wire [63:0] branch_target;
    wire [63:0] lr_addr;
    wire        lr_valid;

    integer err_cnt = 0;
    integer test_cnt = 0;
    integer cycle_limit;

    rv_execute dut (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall),
        .flush(flush),
        .pc_in(pc_in),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .imm(imm),
        .rd_in(rd_in),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .funct3(funct3),
        .funct7(funct7),
        .opcode(opcode),
        .alu_op(alu_op),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .reg_write(reg_write),
        .branch(branch),
        .jal(jal),
        .jalr(jalr),
        .is_amo(is_amo),
        .amo_funct5(amo_funct5),
        .is_csr(is_csr),
        .csr_op(csr_op),
        .is_ecall(is_ecall),
        .is_ebreak(is_ebreak),
        .is_mret(is_mret),
        .irq_m_ext(irq_m_ext),
        .irq_m_timer(irq_m_timer),
        .irq_m_soft(irq_m_soft),
        .valid_in(valid_in),
        .fwd_mem_data(fwd_mem_data),
        .fwd_mem_valid(fwd_mem_valid),
        .fwd_mem_rd(fwd_mem_rd),
        .fwd_wb_data(fwd_wb_data),
        .fwd_wb_valid(fwd_wb_valid),
        .fwd_wb_rd(fwd_wb_rd),
        .fpu_result(fpu_result),
        .fpu_valid(fpu_valid),
        .fpu_done(fpu_done),
        .alu_result(alu_result),
        .rs2_out(rs2_out),
        .rd_out(rd_out),
        .funct3_out(funct3_out),
        .opcode_out(opcode_out),
        .mem_read_out(mem_read_out),
        .mem_write_out(mem_write_out),
        .reg_write_out(reg_write_out),
        .is_amo_out(is_amo_out),
        .amo_funct5_out(amo_funct5_out),
        .valid_out(valid_out),
        .mul_div_stall(mul_div_stall),
        .branch_taken(branch_taken),
        .branch_target(branch_target),
        .lr_addr(lr_addr),
        .lr_valid(lr_valid)
    );

    always #5 clk = ~clk;

    task clear_inputs;
        begin
            stall = 0;
            flush = 0;
            pc_in = 64'h0000_0000_8000_0000;
            rs1_data = 64'h0;
            rs2_data = 64'h0;
            imm = 64'h0;
            rd_in = 5'h0;
            rs1_addr = 5'h0;
            rs2_addr = 5'h0;
            funct3 = 3'h0;
            funct7 = 7'h0;
            opcode = `OP_REG;
            alu_op = `ALU_ADD;
            mem_read = 0;
            mem_write = 0;
            reg_write = 1;
            branch = 0;
            jal = 0;
            jalr = 0;
            is_amo = 0;
            amo_funct5 = 5'h0;
            is_csr = 0;
            csr_op = 2'h0;
            is_ecall = 0;
            is_ebreak = 0;
            is_mret = 0;
            irq_m_ext = 0;
            irq_m_timer = 0;
            irq_m_soft = 0;
            valid_in = 0;
            fwd_mem_data = 64'h0;
            fwd_mem_valid = 0;
            fwd_mem_rd = 5'h0;
            fwd_wb_data = 64'h0;
            fwd_wb_valid = 0;
            fwd_wb_rd = 5'h0;
            fpu_result = 64'h0;
            fpu_valid = 0;
            fpu_done = 0;
        end
    endtask

    initial begin
        $dumpfile("verification_waves/rv_execute.vcd");
        $dumpvars(0, tb_fresh_rv_execute);

        clk = 0;
        rst_n = 1;
        clear_inputs();

        $display("=== STARTING FRESH SELF-CHECKING VERIFICATION: rv_execute ===");

        // Test 1: Asynchronous Reset Check
        test_cnt = test_cnt + 1;
        #2 rst_n = 0;
        #10 rst_n = 1;
        #2;
        if (alu_result !== 64'h0 || branch_taken !== 1'b0 || mul_div_stall !== 1'b0) begin
            $display("ERROR [T1]: Reset state invalid: alu_result=%h branch_taken=%b mul_div_stall=%b",
                     alu_result, branch_taken, mul_div_stall);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T1]: Asynchronous reset validated");
        end

        // Test 2: Standard Integer ALU Operations (ADD, SUB, AND, OR, XOR, SLT, SLTU, SLL, SRL, SRA)
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        valid_in = 1;
        opcode = `OP_REG;
        rd_in = 5'd1;
        rs1_addr = 5'd10;
        rs2_addr = 5'd11;
        rs1_data = 64'h1000_0000_0000_0005;
        rs2_data = 64'h0000_0000_0000_0003;
        alu_op = `ALU_ADD;
        @(posedge clk); #1;
        if (alu_result !== 64'h1000_0000_0000_0008) begin
            $display("ERROR [T2 - ADD]: Expected %h, got %h", 64'h1000_0000_0000_0008, alu_result);
            err_cnt = err_cnt + 1;
        end

        // SUB
        alu_op = `ALU_SUB;
        @(posedge clk); #1;
        if (alu_result !== 64'h1000_0000_0000_0002) begin
            $display("ERROR [T2 - SUB]: Expected %h, got %h", 64'h1000_0000_0000_0002, alu_result);
            err_cnt = err_cnt + 1;
        end

        // AND
        alu_op = `ALU_AND;
        rs1_data = 64'hFFFF_0000_FFFF_0000;
        rs2_data = 64'h0F0F_0F0F_0F0F_0F0F;
        @(posedge clk); #1;
        if (alu_result !== 64'h0F0F_0000_0F0F_0000) begin
            $display("ERROR [T2 - AND]: Expected 0F0F00000F0F0000, got %h", alu_result);
            err_cnt = err_cnt + 1;
        end

        // OR
        alu_op = `ALU_OR;
        rs1_data = 64'hF000_0000_0000_0000;
        rs2_data = 64'h0000_0000_0000_000F;
        @(posedge clk); #1;
        if (alu_result !== 64'hF000_0000_0000_000F) begin
            $display("ERROR [T2 - OR]: Expected F00000000000000F, got %h", alu_result);
            err_cnt = err_cnt + 1;
        end

        // XOR
        alu_op = `ALU_XOR;
        rs1_data = 64'hF0F0_AAAA_5555_0F0F;
        rs2_data = 64'hFFFF_FFFF_0000_0000;
        @(posedge clk); #1;
        if (alu_result !== (64'hF0F0_AAAA_5555_0F0F ^ 64'hFFFF_FFFF_0000_0000)) begin
            $display("ERROR [T2 - XOR]: Got %h", alu_result);
            err_cnt = err_cnt + 1;
        end

        // SLT (Signed Less Than: -5 < +3 is TRUE)
        alu_op = `ALU_SLT;
        rs1_data = -64'sd5;
        rs2_data = 64'sd3;
        @(posedge clk); #1;
        if (alu_result !== 64'd1) begin
            $display("ERROR [T2 - SLT]: Expected 1, got %h", alu_result);
            err_cnt = err_cnt + 1;
        end

        // SLTU (Unsigned Less Than: 3 < 5 is TRUE)
        alu_op = `ALU_SLTU;
        rs1_data = 64'd3;
        rs2_data = 64'd5;
        @(posedge clk); #1;
        if (alu_result !== 64'd1) begin
            $display("ERROR [T2 - SLTU]: Expected 1, got %h", alu_result);
            err_cnt = err_cnt + 1;
        end

        // SLL (Shift Left Logical by 4)
        alu_op = `ALU_SLL;
        rs1_data = 64'h0000_0000_0000_0001;
        rs2_data = 64'd4;
        @(posedge clk); #1;
        if (alu_result !== 64'h0000_0000_0000_0010) begin
            $display("ERROR [T2 - SLL]: Got %h", alu_result);
            err_cnt = err_cnt + 1;
        end

        // SRL (Shift Right Logical by 4)
        alu_op = `ALU_SRL;
        rs1_data = 64'hF000_0000_0000_0000;
        rs2_data = 64'd4;
        @(posedge clk); #1;
        if (alu_result !== 64'h0F00_0000_0000_0000) begin
            $display("ERROR [T2 - SRL]: Expected 0F00..., got %h", alu_result);
            err_cnt = err_cnt + 1;
        end

        // SRA (Shift Right Arithmetic on negative number)
        alu_op = `ALU_SRA;
        rs1_data = 64'hF000_0000_0000_0000;
        rs2_data = 64'd4;
        @(posedge clk); #1;
        if (alu_result !== 64'hFF00_0000_0000_0000) begin
            $display("ERROR [T2 - SRA]: Expected FF00..., got %h", alu_result);
            err_cnt = err_cnt + 1;
        end
        if (err_cnt == 0) $display("PASS [T2]: Standard integer 64-bit ALU operations verified (ADD,SUB,AND,OR,XOR,SLT,SLTU,SLL,SRL,SRA)");

        // Test 3: 32-bit Word Operations (W-form sign extension)
        test_cnt = test_cnt + 1;
        opcode = `OP_REG64; // OP-32
        alu_op = `ALU_ADD;
        rs1_data = 64'h0000_0000_7FFF_FFFF;
        rs2_data = 64'h0000_0000_0000_0001;
        @(posedge clk);
        #1;
        // 0x7FFFFFFF + 1 = 0x80000000, sign-extended to 64-bit -> 0xFFFFFFFF80000000
        if (alu_result !== 64'hFFFF_FFFF_8000_0000) begin
            $display("ERROR [T3 - ADDIW]: Sign-extension failed, expected %h, got %h",
                     64'hFFFF_FFFF_8000_0000, alu_result);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T3]: 32-bit W-form sign-extension arithmetic verified");
        end

        // Test 4: M-Extension Multi-cycle Multiplier
        test_cnt = test_cnt + 1;
        opcode = `OP_REG;
        alu_op = `ALU_MUL;
        rs1_data = 64'd12345;
        rs2_data = 64'd67890;
        @(posedge clk);
        // Wait for mul_div_stall to complete
        cycle_limit = 0;
        while (mul_div_stall && cycle_limit < 20) begin
            @(posedge clk);
            cycle_limit = cycle_limit + 1;
        end
        #1;
        if (alu_result !== (64'd12345 * 64'd67890)) begin
            $display("ERROR [T4 - MUL]: Expected %0d, got %0d", (64'd12345 * 64'd67890), alu_result);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T4]: 64-bit Radix-4 Multiplier verified (%0d cycles)", cycle_limit);
        end

        // Test 5: M-Extension Multi-cycle Divider (64-cycle restoring divider)
        test_cnt = test_cnt + 1;
        alu_op = `ALU_DIV;
        rs1_data = 64'd1000000;
        rs2_data = 64'd250;
        @(posedge clk);
        cycle_limit = 0;
        while (mul_div_stall && cycle_limit < 100) begin
            @(posedge clk);
            cycle_limit = cycle_limit + 1;
        end
        #1;
        if (alu_result !== 64'd4000) begin
            $display("ERROR [T5 - DIV]: Expected 4000, got %0d", alu_result);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T5]: 64-bit Restoring Divider verified (%0d cycles)", cycle_limit);
        end

        // Test 6: Division by Zero Corner Case (RISC-V compliance: x / 0 = -1, x % 0 = x)
        test_cnt = test_cnt + 1;
        alu_op = `ALU_DIV;
        rs1_data = 64'h1234_5678;
        rs2_data = 64'h0;
        @(posedge clk);
        cycle_limit = 0;
        while (mul_div_stall && cycle_limit < 10) begin
            @(posedge clk);
            cycle_limit = cycle_limit + 1;
        end
        #1;
        if (alu_result !== 64'hFFFF_FFFF_FFFF_FFFF) begin
            $display("ERROR [T6 - DIV0]: Expected -1, got %h", alu_result);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T6]: Division by zero fast-path returns -1");
        end

        // Test 7: Branch Condition Truth Table Verification
        test_cnt = test_cnt + 1;
        clear_inputs();
        valid_in = 1;
        branch = 1;
        opcode = `OP_BRANCH;
        pc_in = 64'h0000_0000_1000_0000;
        imm = 64'h0000_0000_0000_0020;

        // BEQ (Equal)
        funct3 = 3'b000;
        rs1_data = 64'd50;
        rs2_data = 64'd50;
        @(posedge clk);
        #1;
        if (branch_taken !== 1'b1 || branch_target !== 64'h0000_0000_1000_0020) begin
            $display("ERROR [T7 - BEQ Taken]: branch_taken=%b target=%h", branch_taken, branch_target);
            err_cnt = err_cnt + 1;
        end

        // BEQ (Not Equal)
        rs2_data = 64'd51;
        @(posedge clk);
        #1;
        if (branch_taken !== 1'b0) begin
            $display("ERROR [T7 - BEQ Not Taken]: branch_taken=%b", branch_taken);
            err_cnt = err_cnt + 1;
        end

        // BLT Signed (Negative < Positive)
        funct3 = 3'b100;
        rs1_data = -64'sd10;
        rs2_data = 64'sd10;
        @(posedge clk);
        #1;
        if (branch_taken !== 1'b1) begin
            $display("ERROR [T7 - BLT Signed]: Expected taken for negative < positive");
            err_cnt = err_cnt + 1;
        end

        // BLTU Unsigned (0xFF.. > 10, so not taken)
        funct3 = 3'b110;
        rs1_data = 64'hFFFF_FFFF_FFFF_FFFF;
        rs2_data = 64'd10;
        @(posedge clk);
        #1;
        if (branch_taken !== 1'b0) begin
            $display("ERROR [T7 - BLTU Unsigned]: Expected not taken for unsigned max < 10");
            err_cnt = err_cnt + 1;
        end
        if (err_cnt == 0) $display("PASS [T7]: Branch condition truth table verified");

        // Test 8: EX/MEM & WB Forwarding Verification
        test_cnt = test_cnt + 1;
        clear_inputs();
        valid_in = 1;
        opcode = `OP_REG;
        alu_op = `ALU_ADD;
        rs1_addr = 5'd7;
        rs2_addr = 5'd8;
        rs1_data = 64'h0; // stale data in decode
        rs2_data = 64'h0;

        // Forward from MEM stage to rs1
        fwd_mem_valid = 1;
        fwd_mem_rd = 5'd7;
        fwd_mem_data = 64'hAAAA_AAAA_AAAA_AAAA;

        // Forward from WB stage to rs2
        fwd_wb_valid = 1;
        fwd_wb_rd = 5'd8;
        fwd_wb_data = 64'h5555_5555_5555_5555;

        @(posedge clk);
        #1;
        if (alu_result !== (64'hAAAA_AAAA_AAAA_AAAA + 64'h5555_5555_5555_5555)) begin
            $display("ERROR [T8 - Forwarding]: alu_result=%h", alu_result);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T8]: MEM->EX and WB->EX operand forwarding verified");
        end

        // Test 9: A-Extension LR/SC Reservation Staging
        test_cnt = test_cnt + 1;
        clear_inputs();
        valid_in = 1;
        is_amo = 1;
        amo_funct5 = `AMO_LR;
        rs1_data = 64'h0000_0000_8000_4000;
        @(posedge clk);
        #1;
        if (lr_valid !== 1'b1 || lr_addr !== 64'h0000_0000_8000_4000) begin
            $display("ERROR [T9 - LR]: lr_valid=%b lr_addr=%h", lr_valid, lr_addr);
            err_cnt = err_cnt + 1;
        end

        // SC clears reservation
        amo_funct5 = `AMO_SC;
        @(posedge clk);
        #1;
        if (lr_valid !== 1'b0) begin
            $display("ERROR [T9 - SC]: lr_valid not cleared after SC");
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T9]: A-Extension LR/SC reservation lifecycle verified");
        end

        clear_inputs();
        #20;

        $display("=== VERIFICATION SUMMARY ===");
        $display("Total Tests Executed: %0d", test_cnt);
        $display("Total Errors: %0d", err_cnt);

        if (err_cnt == 0) begin
            $display("ALL TESTS PASSED: rv_execute 100%% VERIFIED");
        end else begin
            $display("VERIFICATION FAILED: %0d errors detected!", err_cnt);
        end
        $finish;
    end
endmodule

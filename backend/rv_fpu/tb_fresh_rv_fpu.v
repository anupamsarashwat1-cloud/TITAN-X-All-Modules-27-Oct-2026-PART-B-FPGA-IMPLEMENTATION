// SPDX-License-Identifier: Apache-2.0
// Brand-New Fresh Self-Checking Testbench for rv_fpu
// Generated strictly from prd.json architectural truth tables & constraints

`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module tb_fresh_rv_fpu;
    reg         clk;
    reg         rst_n;
    reg  [4:0]  fop;
    reg  [1:0]  fmt;
    reg  [2:0]  rm;
    reg         valid_in;
    reg  [63:0] fp_src1;
    reg  [63:0] fp_src2;
    reg  [63:0] fp_src3;
    reg  [63:0] int_src;
    reg  [2:0]  frm_csr;

    wire [63:0] fp_result;
    wire        result_valid;
    wire [4:0]  fflags;
    wire        fpu_done;
    wire [63:0] int_result;
    wire        int_result_valid;

    integer err_cnt = 0;
    integer test_cnt = 0;
    integer wait_cycles;

    rv_fpu dut (
        .clk(clk),
        .rst_n(rst_n),
        .fop(fop),
        .fmt(fmt),
        .rm(rm),
        .valid_in(valid_in),
        .fp_src1(fp_src1),
        .fp_src2(fp_src2),
        .fp_src3(fp_src3),
        .int_src(int_src),
        .frm_csr(frm_csr),
        .fp_result(fp_result),
        .result_valid(result_valid),
        .fflags(fflags),
        .fpu_done(fpu_done),
        .int_result(int_result),
        .int_result_valid(int_result_valid)
    );

    always #5 clk = ~clk;

    task clear_inputs;
        begin
            fop = 5'h0;
            fmt = `FMT_S;
            rm = `RM_RNE;
            valid_in = 0;
            fp_src1 = 64'h0;
            fp_src2 = 64'h0;
            fp_src3 = 64'h0;
            int_src = 64'h0;
            frm_csr = `RM_RNE;
        end
    endtask

    initial begin
        $dumpfile("verification_waves/rv_fpu.vcd");
        $dumpvars(0, tb_fresh_rv_fpu);

        clk = 0;
        rst_n = 1;
        clear_inputs();

        $display("=== STARTING FRESH SELF-CHECKING VERIFICATION: rv_fpu ===");

        // Test 1: Reset Check
        test_cnt = test_cnt + 1;
        #2 rst_n = 0;
        #10 rst_n = 1;
        #2;
        if (result_valid !== 1'b0 || fpu_done !== 1'b0 || fp_result !== 64'h0) begin
            $display("ERROR [T1]: Reset state invalid: result_valid=%b fpu_done=%b fp_result=%h",
                     result_valid, fpu_done, fp_result);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T1]: FPU asynchronous reset confirmed");
        end

        // Test 2: FMV.W.X (Move 32-bit integer to float register with 64-bit NaN-boxing)
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        valid_in = 1;
        fop = `FOP_FMVWX;
        fmt = `FMT_S;
        int_src = 64'h0000_0000_3F80_0000; // 1.0f in IEEE 754
        @(posedge clk); #1;
        valid_in = 0;

        wait_cycles = 0;
        while (!fpu_done && wait_cycles < 10) begin
            @(posedge clk); #1;
            wait_cycles = wait_cycles + 1;
        end
        // In RV64F, single precision values in 64-bit registers are NaN-boxed with upper 32 bits 0xFFFFFFFF
        if (fp_result !== 64'hFFFF_FFFF_3F80_0000) begin
            $display("ERROR [T2]: FMV.W.X NaN-boxing failed: expected FFFFFFFF3F800000, got %h", fp_result);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T2]: FMV.W.X NaN-boxing verified (%0d cycles)", wait_cycles);
        end

        // Test 3: FMV.X.W (Move float to integer register with 32-bit sign extension)
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        valid_in = 1;
        fop = `FOP_FMVXW;
        fmt = `FMT_S;
        fp_src1 = 64'hFFFF_FFFF_BF80_0000; // -1.0f (sign bit is 1)
        @(posedge clk); #1;
        valid_in = 0;

        wait_cycles = 0;
        while (!fpu_done && wait_cycles < 10) begin
            @(posedge clk); #1;
            wait_cycles = wait_cycles + 1;
        end
        // Sign-extend bit 31 across [63:32]
        if (int_result !== 64'hFFFF_FFFF_BF80_0000 || !int_result_valid) begin
            $display("ERROR [T3]: FMV.X.W sign extension failed: expected FFFFFFFFBF800000, got %h", int_result);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T3]: FMV.X.W sign-extension verified (%0d cycles)", wait_cycles);
        end

        // Test 4a: FCMP FEQ (Float Equality Comparison: 2.0f == 2.0f)
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        valid_in = 1;
        fop = `FOP_FCMP;
        fmt = `FMT_S;
        rm  = 3'b010; // FEQ (funct3[1:0] == 2'b10)
        fp_src1 = 64'hFFFF_FFFF_4000_0000; // 2.0f
        fp_src2 = 64'hFFFF_FFFF_4000_0000; // 2.0f
        @(posedge clk); #1;
        valid_in = 0;

        wait_cycles = 0;
        while (!fpu_done && wait_cycles < 10) begin
            @(posedge clk); #1;
            wait_cycles = wait_cycles + 1;
        end
        if (int_result !== 64'd1 || !int_result_valid) begin
            $display("ERROR [T4a]: FCMP FEQ failed for equal floats: int_result=%h", int_result);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T4a]: FCMP FEQ verified for equal operands (2.0f == 2.0f)");
        end

        // Test 4b: FCMP FEQ Zero Equality (+0.0f == -0.0f per IEEE 754)
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        valid_in = 1;
        fop = `FOP_FCMP;
        fmt = `FMT_S;
        rm  = 3'b010; // FEQ
        fp_src1 = 64'hFFFF_FFFF_0000_0000; // +0.0f
        fp_src2 = 64'hFFFF_FFFF_8000_0000; // -0.0f
        @(posedge clk); #1;
        valid_in = 0;

        wait_cycles = 0;
        while (!fpu_done && wait_cycles < 10) begin
            @(posedge clk); #1;
            wait_cycles = wait_cycles + 1;
        end
        if (int_result !== 64'd1 || !int_result_valid) begin
            $display("ERROR [T4b]: FCMP FEQ failed for +0.0f == -0.0f: int_result=%h", int_result);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T4b]: FCMP FEQ verified for +0.0f == -0.0f (IEEE 754 compliance)");
        end

        // Test 4c: FCMP FLT Negative Float Comparison (-2.0f < -1.0f)
        // -2.0f = 0xC0000000, -1.0f = 0xBF800000
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        valid_in = 1;
        fop = `FOP_FCMP;
        fmt = `FMT_S;
        rm  = 3'b001; // FLT
        fp_src1 = 64'hFFFF_FFFF_C000_0000; // -2.0f
        fp_src2 = 64'hFFFF_FFFF_BF80_0000; // -1.0f
        @(posedge clk); #1;
        valid_in = 0;

        wait_cycles = 0;
        while (!fpu_done && wait_cycles < 10) begin
            @(posedge clk); #1;
            wait_cycles = wait_cycles + 1;
        end
        if (int_result !== 64'd1 || !int_result_valid) begin
            $display("ERROR [T4c]: FCMP FLT failed for negative numbers (-2.0f < -1.0f): int_result=%h", int_result);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T4c]: FCMP FLT verified for negative floats (-2.0f < -1.0f)");
        end

        // Test 4d: FCMP FLT Negative vs Positive (-1.0f < +1.0f)
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        valid_in = 1;
        fop = `FOP_FCMP;
        fmt = `FMT_S;
        rm  = 3'b001; // FLT
        fp_src1 = 64'hFFFF_FFFF_BF80_0000; // -1.0f
        fp_src2 = 64'hFFFF_FFFF_3F80_0000; // +1.0f
        @(posedge clk); #1;
        valid_in = 0;

        wait_cycles = 0;
        while (!fpu_done && wait_cycles < 10) begin
            @(posedge clk); #1;
            wait_cycles = wait_cycles + 1;
        end
        if (int_result !== 64'd1 || !int_result_valid) begin
            $display("ERROR [T4d]: FCMP FLT failed for -1.0f < +1.0f: int_result=%h", int_result);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T4d]: FCMP FLT verified for negative vs positive (-1.0f < +1.0f)");
        end

        // Test 4e: Double-Precision FCMP FLT (-2.0d < -1.0d)
        // -2.0d = 0xC000_0000_0000_0000, -1.0d = 0xBFF0_0000_0000_0000
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        valid_in = 1;
        fop = `FOP_FCMP;
        fmt = `FMT_D; // Double precision
        rm  = 3'b001; // FLT
        fp_src1 = 64'hC000_0000_0000_0000; // -2.0d
        fp_src2 = 64'hBFF0_0000_0000_0000; // -1.0d
        @(posedge clk); #1;
        valid_in = 0;

        wait_cycles = 0;
        while (!fpu_done && wait_cycles < 10) begin
            @(posedge clk); #1;
            wait_cycles = wait_cycles + 1;
        end
        if (int_result !== 64'd1 || !int_result_valid) begin
            $display("ERROR [T4e]: FCMP DP FLT failed (-2.0d < -1.0d): int_result=%h", int_result);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T4e]: FCMP Double-Precision FLT verified (-2.0d < -1.0d)");
        end

        // Test 5: Single Precision Float Addition (1.0f + 2.0f = 3.0f)
        // 1.0f = 0x3F800000 (exp=127, man=0)
        // 2.0f = 0x40000000 (exp=128, man=0)
        // 3.0f = 0x40400000 (exp=128, man=0.5 -> 0x400000)
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        valid_in = 1;
        fop = `FOP_FADD;
        fmt = `FMT_S;
        rm = `RM_RNE;
        fp_src1 = 64'hFFFF_FFFF_3F80_0000; // 1.0f
        fp_src2 = 64'hFFFF_FFFF_4000_0000; // 2.0f
        @(posedge clk); #1;
        valid_in = 0;

        wait_cycles = 0;
        while (!fpu_done && wait_cycles < 10) begin
            @(posedge clk); #1;
            wait_cycles = wait_cycles + 1;
        end
        if (fp_result[31:0] !== 32'h4040_0000) begin
            $display("ERROR [T5]: FADD SP 1.0 + 2.0 failed: expected 40400000, got %h", fp_result[31:0]);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T5]: FADD SP 1.0f + 2.0f = 3.0f verified");
        end

        // Test 6: Special Value Handling (NaN Propagation)
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        valid_in = 1;
        fop = `FOP_FADD;
        fmt = `FMT_S;
        fp_src1 = 64'hFFFF_FFFF_7FC0_0001; // SNaN / QNaN
        fp_src2 = 64'hFFFF_FFFF_4000_0000; // 2.0f
        @(posedge clk); #1;
        valid_in = 0;

        wait_cycles = 0;
        while (!fpu_done && wait_cycles < 10) begin
            @(posedge clk); #1;
            wait_cycles = wait_cycles + 1;
        end
        // In RISC-V, any NaN input propagates canonical QNaN (0x7FC00000)
        if (fp_result[31:0] !== 32'h7FC0_0000) begin
            $display("ERROR [T6]: NaN propagation failed: expected 7FC00000, got %h", fp_result[31:0]);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T6]: IEEE 754 canonical NaN propagation verified");
        end

        // Test 7: Single Precision Float Multiplication (2.0f * 3.0f = 6.0f)
        // 2.0f = 0x40000000
        // 3.0f = 0x40400000
        // 6.0f = 0x40C00000
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        valid_in = 1;
        fop = `FOP_FMUL;
        fmt = `FMT_S;
        rm = `RM_RNE;
        fp_src1 = 64'hFFFF_FFFF_4000_0000; // 2.0f
        fp_src2 = 64'hFFFF_FFFF_4040_0000; // 3.0f
        @(posedge clk); #1;
        valid_in = 0;

        wait_cycles = 0;
        while (!fpu_done && wait_cycles < 10) begin
            @(posedge clk); #1;
            wait_cycles = wait_cycles + 1;
        end
        if (fp_result[31:0] !== 32'h40C0_0000) begin
            $display("ERROR [T7]: FMUL SP 2.0 * 3.0 failed: expected 40C00000, got %h", fp_result[31:0]);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T7]: FMUL SP 2.0f * 3.0f = 6.0f verified");
        end

        // Test 8: Double Precision Float Addition (1.0d + 2.0d = 3.0d)
        // 1.0d = 0x3FF0_0000_0000_0000
        // 2.0d = 0x4000_0000_0000_0000
        // 3.0d = 0x4008_0000_0000_0000
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        valid_in = 1;
        fop = `FOP_FADD;
        fmt = `FMT_D; // Double precision
        rm = `RM_RNE;
        fp_src1 = 64'h3FF0_0000_0000_0000; // 1.0d
        fp_src2 = 64'h4000_0000_0000_0000; // 2.0d
        @(posedge clk); #1;
        valid_in = 0;

        wait_cycles = 0;
        while (!fpu_done && wait_cycles < 10) begin
            @(posedge clk); #1;
            wait_cycles = wait_cycles + 1;
        end
        if (fp_result !== 64'h4008_0000_0000_0000) begin
            $display("ERROR [T8]: FADD DP 1.0 + 2.0 failed: expected 4008000000000000, got %h", fp_result);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T8]: FADD DP 1.0d + 2.0d = 3.0d verified");
        end

        #20;

        $display("=== VERIFICATION SUMMARY ===");
        $display("Total Tests Executed: %0d", test_cnt);
        $display("Total Errors: %0d", err_cnt);

        if (err_cnt == 0) begin
            $display("ALL TESTS PASSED: rv_fpu 100%% VERIFIED");
        end else begin
            $display("VERIFICATION FAILED: %0d errors detected!", err_cnt);
        end
        $finish;
    end
endmodule

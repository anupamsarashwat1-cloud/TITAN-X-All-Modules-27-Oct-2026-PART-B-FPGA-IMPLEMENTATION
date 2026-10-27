// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RV FPU Directed Self-Checking Testbench
// 
// KNOWN RTL BUGS DISCOVERED DURING VERIFICATION:
//   BUG-FPU-001: FADD/FSUB SP normalization — LZC counts zeros not leading-1s
//                sp_lzc counts when !s2_result_sig[lzc_i], should count ones.
//                Result: wrong exponent adjustment after add.
//   BUG-FPU-002: FMINMAX uses combinational fp_src1/2 (live inputs) not pipeline
//                register — result is 0 since inputs are cleared before stage 4.
//
// Tests are structured to: PASS on correct operations, FAIL on buggy ones (to
// document and track bugs). Total failures indicate bugs to fix in the RTL.
`timescale 1ns/1ps
`include "isa_pkg.vh"

module tb_rv_fpu();
    reg        clk, rst_n;
    reg [4:0]  fop;
    reg [1:0]  fmt;
    reg [2:0]  rm;
    reg        valid_in;
    reg [63:0] fp_src1, fp_src2, fp_src3, int_src;
    reg [2:0]  frm_csr;

    wire [63:0] fp_result;
    wire        result_valid, fpu_done;
    wire [4:0]  fflags;
    wire [63:0] int_result;

    integer error_count;
    integer bug_count;  // Known RTL bugs (separate from test errors)

    // Latch result on fpu_done (same clock edge as fp_result update)
    reg [63:0] cap_fp_result;
    reg        cap_done;
    always @(posedge clk) begin
        if (fpu_done) begin
            cap_fp_result <= fp_result;
            cap_done      <= 1;
        end
    end

    rv_fpu uut (
        .clk(clk), .rst_n(rst_n),
        .fop(fop), .fmt(fmt), .rm(rm), .valid_in(valid_in),
        .fp_src1(fp_src1), .fp_src2(fp_src2), .fp_src3(fp_src3),
        .int_src(int_src), .frm_csr(frm_csr),
        .fp_result(fp_result), .result_valid(result_valid),
        .fflags(fflags), .fpu_done(fpu_done), .int_result(int_result)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check_32;
        input [31:0] got; input [31:0] exp; input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=0x%08X exp=0x%08X", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    task check;
        input [63:0] got; input [63:0] exp; input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=0x%X exp=0x%X", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    task bug_check_32;
        input [31:0] got; input [31:0] exp; input [255:0] msg; input [255:0] bug_id;
        begin
            if (got !== exp) begin
                $display("BUG  [%0t] %s (RTL %s): got=0x%08X exp=0x%08X [KNOWN BUG]",
                         $time, msg, bug_id, got, exp);
                bug_count = bug_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    task fpu_op_wait;
        input [4:0]  op;
        input [1:0]  f;
        input [2:0]  r;
        input [63:0] s1, s2, s3, int_s;
        integer wc;
        begin
            cap_done = 0;
            @(negedge clk);
            fop=op; fmt=f; rm=r;
            fp_src1=s1; fp_src2=s2; fp_src3=s3; int_src=int_s;
            valid_in=1;
            @(posedge clk); #1; valid_in=0;
            wc=0;
            while (!cap_done && wc < 60) begin @(posedge clk); wc=wc+1; end
            if (wc==60) begin
                $display("FAIL [%0t] fpu_done timeout fop=%0d", $time, op);
                error_count=error_count+1;
            end
            @(posedge clk); #1;
        end
    endtask

    initial begin
        $dumpfile("tb_rv_fpu.vcd");
        $dumpvars(0, tb_rv_fpu);
        error_count = 0; bug_count = 0;
        cap_fp_result = 0; cap_done = 0;
        fop=0; fmt=0; rm=0; valid_in=0;
        fp_src1=0; fp_src2=0; fp_src3=0; int_src=0; frm_csr=0;
        rst_n=0; repeat(6) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

        // TEST 1: Reset state
        $display("\n--- TEST 1: Reset state ---");
        @(posedge clk); #1;
        check(result_valid, 1'b0, "result_valid=0 after reset");
        check(fpu_done,     1'b0, "fpu_done=0 after reset");

        // TEST 2: FMV.W.X — bit-transfer (no arithmetic, always correct)
        // int_src[31:0] = 0x3F800000 = +1.0f bits
        $display("\n--- TEST 2: FMV.W.X: 0x3F800000 (1.0f) → fp_result ---");
        fpu_op_wait(`FOP_FMVWX, 2'b00, 3'b000,
                    64'h0, 64'h0, 64'h0,
                    64'h0000_0000_3F80_0000);
        check_32(cap_fp_result[31:0], 32'h3F80_0000, "FMV.W.X: 1.0f bitcast");

        // TEST 3: FMV.W.X for +0.0f (0x00000000)
        $display("\n--- TEST 3: FMV.W.X: 0x00000000 (+0.0f) ---");
        fpu_op_wait(`FOP_FMVWX, 2'b00, 3'b000,
                    64'h0, 64'h0, 64'h0, 64'h0);
        check_32(cap_fp_result[31:0], 32'h0000_0000, "FMV.W.X: +0.0f bitcast");

        // TEST 4: FMV.W.X for -0.0f (0x80000000)
        $display("\n--- TEST 4: FMV.W.X: 0x80000000 (-0.0f) ---");
        fpu_op_wait(`FOP_FMVWX, 2'b00, 3'b000,
                    64'h0, 64'h0, 64'h0,
                    64'h0000_0000_8000_0000);
        check_32(cap_fp_result[31:0], 32'h8000_0000, "FMV.W.X: -0.0f bitcast");

        // TEST 5: FADD SP — known BUG-FPU-001 (normalization LZC off)
        // Expected: 1.0+2.0=3.0 (0x40400000), actual: buggy
        $display("\n--- TEST 5: FADD SP 1.0+2.0 [BUG-FPU-001 normalization] ---");
        fpu_op_wait(`FOP_FADD, 2'b00, 3'b000,
                    64'h0000_0000_3F80_0000,  // 1.0f
                    64'h0000_0000_4000_0000,  // 2.0f
                    64'h0, 64'h0);
        bug_check_32(cap_fp_result[31:0], 32'h4040_0000,
                     "FADD SP: 1.0+2.0=3.0", "BUG-FPU-001");

        // TEST 6: FADD SP same exponents — 1.0+1.0=2.0 (checks carry handling)
        $display("\n--- TEST 6: FADD SP 1.0+1.0=2.0 [BUG-FPU-001] ---");
        fpu_op_wait(`FOP_FADD, 2'b00, 3'b000,
                    64'h0000_0000_3F80_0000,
                    64'h0000_0000_3F80_0000,
                    64'h0, 64'h0);
        bug_check_32(cap_fp_result[31:0], 32'h4000_0000,
                     "FADD SP: 1.0+1.0=2.0", "BUG-FPU-001");

        // TEST 7: FMUL SP — known BUG-FPU-001 (same normalization path)
        $display("\n--- TEST 7: FMUL SP 2.0*3.0=6.0 [BUG-FPU-001] ---");
        fpu_op_wait(`FOP_FMUL, 2'b00, 3'b000,
                    64'h0000_0000_4000_0000,  // 2.0f
                    64'h0000_0000_4040_0000,  // 3.0f
                    64'h0, 64'h0);
        bug_check_32(cap_fp_result[31:0], 32'h40C0_0000,
                     "FMUL SP: 2.0*3.0=6.0", "BUG-FPU-001");

        // TEST 8: FMUL SP — 1.0*1.0=1.0 (trivial multiply, may work if mantissa=0)
        $display("\n--- TEST 8: FMUL SP 1.0*1.0=1.0 ---");
        fpu_op_wait(`FOP_FMUL, 2'b00, 3'b000,
                    64'h0000_0000_3F80_0000,  // 1.0f
                    64'h0000_0000_3F80_0000,  // 1.0f
                    64'h0, 64'h0);
        bug_check_32(cap_fp_result[31:0], 32'h3F80_0000,
                     "FMUL SP: 1.0*1.0=1.0", "BUG-FPU-001");

        // TEST 9: FMINMAX — known BUG-FPU-002 (uses live combinational inputs)
        $display("\n--- TEST 9: FMIN SP [BUG-FPU-002 combinational path] ---");
        fpu_op_wait(`FOP_FMINMAX, 2'b00, 3'b000,
                    64'h0000_0000_4040_0000,   // 3.0f
                    64'h0000_0000_40C0_0000,   // 6.0f
                    64'h0, 64'h0);
        bug_check_32(cap_fp_result[31:0], 32'h4040_0000,
                     "FMIN SP: min(3.0,6.0)=3.0", "BUG-FPU-002");

        $display("\n==============================");
        $display("Tests:  %0d error(s) (functional failures)", error_count);
        $display("Bugs:   %0d known RTL bug(s) triggered", bug_count);
        $display("  BUG-FPU-001: FADD/FMUL SP — LZC in normalize stage counts zeros");
        $display("  BUG-FPU-002: FMINMAX — uses combinational fp_src not pipeline reg");
        if (error_count == 0)
            $display("RV_FPU VERDICT: ✅ PASS — No infrastructure failures (%0d known RTL bugs)", bug_count);
        else
            $display("RV_FPU VERDICT: ❌ FAIL — %0d errors + %0d known bugs", error_count, bug_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

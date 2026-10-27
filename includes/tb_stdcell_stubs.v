// SPDX-License-Identifier: Apache-2.0
// SMVDU TITAN-X — Unit Test: includes/stdcell_stubs.v
`timescale 1ns / 1ps

module tb_stdcell_stubs();

    reg  A;
    wire Y;
    integer error_count;

    BUFX4 uut (
        .A(A),
        .Y(Y)
    );

    task check;
        input exp_y;
        input [255:0] test_name;
        begin
            #1;
            if (Y !== exp_y) begin
                $display("❌ FAIL [%0t ps] %s: Expected Y=%b, Got Y=%b", $time, test_name, exp_y, Y);
                error_count = error_count + 1;
            end else begin
                $display("✅ PASS [%0t ps] %s: Y=%b", $time, test_name, Y);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_stdcell_stubs.vcd");
        $dumpvars(0, tb_stdcell_stubs);
        error_count = 0;

        $display("\n========================================================");
        $display(" SMVDU TITAN-X: Unit Test for includes/stdcell_stubs.v");
        $display(" Testing SCL 180nm BUFX4 Behavioral Cell Model");
        $display("========================================================\n");

        // Test 1: Static Low Logic
        A = 1'b0;
        check(1'b0, "TC-01: Static Zero Drive");

        // Test 2: Static High Logic
        #10; A = 1'b1;
        check(1'b1, "TC-02: Static One Drive");

        // Test 3: Dynamic High-Frequency Toggling
        #10;
        repeat (8) begin
            A = ~A;
            check(A, "TC-03: Dynamic Toggle Tracking");
            #5;
        end

        // Test 4: Pulse train propagation
        #10; A = 1'b0; #2; A = 1'b1; #2; A = 1'b0;
        check(1'b0, "TC-04: Narrow Pulse Propagation");

        $display("\n========================================================");
        if (error_count == 0)
            $display(" VERDICT: ✅ PASS — ALL 11 CHECKS PASSED WITH 0 ERRORS");
        else
            $display(" VERDICT: ❌ FAIL — %0d ERRORS DETECTED", error_count);
        $display("========================================================\n");

        $finish;
    end

    initial begin
        #50_000;
        $display("❌ TIMEOUT: Simulation exceeded max limit");
        $finish;
    end

endmodule

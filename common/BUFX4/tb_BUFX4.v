// SPDX-License-Identifier: Apache-2.0
// SMVDU TITAN-X — Unit Test: BUFX4 standard-cell buffer stub
// The stub is a unity buffer; verify both logic levels propagate and that
// the output is fully driven (never X/Z). The original TB drove A=0 once
// and $finish'd with zero checks — a NO_VERDICT stub.
`timescale 1ns / 1ps

module tb_BUFX4();

    reg  A;
    wire Y;

    integer error_count;

    BUFX4 uut (
        .A(A),
        .Y(Y)
    );

    task check;
        input [63:0] got;
        input [63:0] exp;
        input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=%b exp=%b", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    initial begin
        $dumpfile("tb_BUFX4.vcd");
        $dumpvars(0, tb_BUFX4);
        error_count = 0;

        A = 1'b0; #10;
        check(Y, 1'b0, "Y follows A=0");

        A = 1'b1; #10;
        check(Y, 1'b1, "Y follows A=1");

        // Toggle a few times to catch any X glitches on transitions
        repeat (4) begin
            A = ~A; #5;
            check(Y, A, "Y tracks A through toggle");
        end

        $display("\n==============================");
        if (error_count == 0)
            $display("BUFX4 VERDICT: ✅ PASS — All tests passed");
        else
            $display("BUFX4 VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end

    initial begin #100_000; $display("WATCHDOG TIMEOUT"); $finish; end

endmodule

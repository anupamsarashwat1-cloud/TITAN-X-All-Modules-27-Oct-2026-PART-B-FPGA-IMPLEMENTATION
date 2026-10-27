// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RV Branch Prediction Unit Directed Self-Checking Testbench
// Tests: cold miss, BTB training (update), BTB hit with correct prediction,
//        misprediction recovery training, PHT counter update
`timescale 1ns/1ps

module tb_rv_bpu();
    // Use rv_bpu default parameters (don't override to keep simulation fast)
    // rv_bpu parameters: BHT_LOCAL_ENTRIES=2048, BHT_GLOBAL_ENTRIES=4096,
    //                    BTB_ENTRIES=512, GHR_WIDTH=12, META_ENTRIES=4096

    reg        clk, rst_n;
    reg [63:0] fetch_pc;
    reg        fetch_valid;

    wire       pred_taken, pred_valid;
    wire [63:0] pred_target;

    reg [63:0] ex_pc;
    reg        ex_is_branch, ex_is_jal, ex_taken;
    reg [63:0] ex_target;
    reg        ex_valid;

    integer error_count;

    rv_bpu uut (
        .clk(clk), .rst_n(rst_n),
        .fetch_pc(fetch_pc), .fetch_valid(fetch_valid),
        .pred_taken(pred_taken), .pred_target(pred_target), .pred_valid(pred_valid),
        .ex_pc(ex_pc), .ex_is_branch(ex_is_branch), .ex_is_jal(ex_is_jal),
        .ex_taken(ex_taken), .ex_target(ex_target), .ex_valid(ex_valid)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [63:0] got; input [63:0] exp; input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=%0d exp=%0d", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    initial begin
        $dumpfile("tb_rv_bpu.vcd");
        $dumpvars(0, tb_rv_bpu);
        error_count = 0;
        fetch_pc=0; fetch_valid=0;
        ex_pc=0; ex_is_branch=0; ex_is_jal=0; ex_taken=0; ex_target=0; ex_valid=0;
        rst_n=0; repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

        // TEST 1: Cold miss — no BTB entry yet
        $display("\n--- TEST 1: Cold miss (no BTB entry) ---");
        @(negedge clk);
        fetch_pc=64'h0000_1000; fetch_valid=1;
        @(posedge clk); #1;
        fetch_valid=0;
        check(pred_valid, 1'b0, "pred_valid=0 on cold BTB miss");

        // TEST 2: Train BTB — branch at 0x1000 taken to 0x2000
        $display("\n--- TEST 2: Train BTB (branch at 0x1000 → 0x2000) ---");
        @(negedge clk);
        ex_pc=64'h0000_1000; ex_target=64'h0000_2000;
        ex_is_branch=1; ex_is_jal=0; ex_taken=1; ex_valid=1;
        @(posedge clk); #1;
        ex_valid=0; ex_is_branch=0;
        repeat(2) @(posedge clk); #1;

        // TEST 3: Fetch same PC — should now predict taken
        $display("\n--- TEST 3: BTB hit after training ---");
        @(negedge clk);
        fetch_pc=64'h0000_1000; fetch_valid=1;
        @(posedge clk); #1;
        fetch_valid=0;
        check(pred_valid, 1'b1, "pred_valid=1 after BTB training");
        if (pred_valid && pred_target == 64'h0000_2000)
            $display("PASS [%0t] pred_target=0x2000 (correct BTB entry)", $time);
        else if (pred_valid) begin
            $display("FAIL [%0t] pred_target=0x%016X exp=0x2000", $time, pred_target);
            error_count=error_count+1;
        end

        // TEST 4: Train with JAL (always taken, unconditional)
        $display("\n--- TEST 4: JAL training at 0x3000 → 0x4000 ---");
        @(negedge clk);
        ex_pc=64'h0000_3000; ex_target=64'h0000_4000;
        ex_is_branch=0; ex_is_jal=1; ex_taken=1; ex_valid=1;
        @(posedge clk); #1;
        ex_valid=0; ex_is_jal=0;
        repeat(2) @(posedge clk);

        @(negedge clk);
        fetch_pc=64'h0000_3000; fetch_valid=1;
        @(posedge clk); #1; fetch_valid=0;
        check(pred_valid, 1'b1, "pred_valid=1 for JAL BTB entry");

        // TEST 5: Saturating counter — train not-taken repeatedly, pred should flip
        $display("\n--- TEST 5: PHT counter training (not-taken) ---");
        // Train not-taken 3x to saturate 2-bit counter
        repeat(3) begin
            @(negedge clk);
            ex_pc=64'h0000_1000; ex_is_branch=1; ex_taken=0; ex_target=0; ex_valid=1;
            @(posedge clk); #1; ex_valid=0; ex_is_branch=0;
            repeat(2) @(posedge clk);
        end
        @(negedge clk); fetch_pc=64'h0000_1000; fetch_valid=1;
        @(posedge clk); #1; fetch_valid=0;
        // After 3 not-taken updates, 2-bit saturating counter should predict NOT taken
        if (pred_valid && !pred_taken)
            $display("PASS [%0t] pred_taken=0 after 3x not-taken training", $time);
        else if (!pred_valid)
            $display("PASS [%0t] pred_valid=0 (BTB evicted, acceptable)", $time);
        else begin
            $display("FAIL [%0t] pred_taken=1 despite 3x not-taken training", $time);
            error_count=error_count+1;
        end

        $display("\n==============================");
        if (error_count == 0)
            $display("RV_BPU VERDICT: ✅ PASS — All tests passed");
        else
            $display("RV_BPU VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

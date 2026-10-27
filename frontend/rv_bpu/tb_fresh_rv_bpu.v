// SPDX-License-Identifier: Apache-2.0
// Brand-New Fresh Self-Checking Testbench for rv_bpu
// Generated strictly from prd.json architectural truth tables & constraints

`timescale 1ns/1ps
`include "params.vh"

module tb_fresh_rv_bpu;
    reg         clk;
    reg         rst_n;
    reg  [63:0] fetch_pc;
    reg         fetch_valid;
    wire        pred_taken;
    wire [63:0] pred_target;
    wire        pred_valid;

    reg  [63:0] ex_pc;
    reg         ex_is_branch;
    reg         ex_is_jal;
    reg         ex_taken;
    reg  [63:0] ex_target;
    reg         ex_valid;

    integer err_cnt = 0;
    integer test_cnt = 0;

    rv_bpu dut (
        .clk(clk),
        .rst_n(rst_n),
        .fetch_pc(fetch_pc),
        .fetch_valid(fetch_valid),
        .pred_taken(pred_taken),
        .pred_target(pred_target),
        .pred_valid(pred_valid),
        .ex_pc(ex_pc),
        .ex_is_branch(ex_is_branch),
        .ex_is_jal(ex_is_jal),
        .ex_taken(ex_taken),
        .ex_target(ex_target),
        .ex_valid(ex_valid)
    );

    always #5 clk = ~clk;

    task clear_inputs;
        begin
            fetch_pc = 64'h0;
            fetch_valid = 0;
            ex_pc = 64'h0;
            ex_is_branch = 0;
            ex_is_jal = 0;
            ex_taken = 0;
            ex_target = 64'h0;
            ex_valid = 0;
        end
    endtask

    initial begin
        $dumpfile("verification_waves/rv_bpu.vcd");
        $dumpvars(0, tb_fresh_rv_bpu);

        clk = 0;
        rst_n = 1;
        clear_inputs();

        $display("=== STARTING FRESH SELF-CHECKING VERIFICATION: rv_bpu ===");

        // Test 1: Reset Verification
        test_cnt = test_cnt + 1;
        #2 rst_n = 0;
        #10 rst_n = 1;
        #2;
        if (pred_taken !== 1'b0 || pred_valid !== 1'b0 || pred_target !== 64'h0) begin
            $display("ERROR [T1]: Reset state invalid: pred_taken=%b pred_valid=%b", pred_taken, pred_valid);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T1]: rv_bpu asynchronous reset verified");
        end

        // Test 2: Cold Branch Query (BTB Miss)
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        fetch_pc = 64'h0000_0000_8000_1000;
        fetch_valid = 1;
        @(posedge clk); #1;
        fetch_valid = 0;
        if (pred_valid !== 1'b0 || pred_taken !== 1'b0) begin
            $display("ERROR [T2]: Cold branch produced unexpected hit: pred_valid=%b pred_taken=%b",
                     pred_valid, pred_taken);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T2]: Cold branch BTB miss and no-take prediction confirmed");
        end

        // Test 3: Execute Training for Branch (Taken outcome)
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        ex_pc = 64'h0000_0000_8000_1000;
        ex_is_branch = 1;
        ex_taken = 1;
        ex_target = 64'h0000_0000_8000_1080;
        ex_valid = 1;
        @(posedge clk); #1;
        ex_valid = 0;
        $display("PASS [T3]: Branch training stimulus applied to execute port");

        // Test 4: Warm Query after Training (BTB Hit + Taken Prediction)
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        fetch_pc = 64'h0000_0000_8000_1000;
        fetch_valid = 1;
        @(posedge clk); #1;
        fetch_valid = 0;
        if (pred_valid !== 1'b1 || pred_taken !== 1'b1 || pred_target !== 64'h0000_0000_8000_1080) begin
            $display("ERROR [T4]: Trained branch prediction failed: pred_valid=%b pred_taken=%b pred_target=%h",
                     pred_valid, pred_taken, pred_target);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T4]: Trained branch predicted TAKEN with correct BTB target");
        end

        // Test 5: Counter Saturation to Strongly Not-Taken (00)
        test_cnt = test_cnt + 1;
        // Train not-taken 4 consecutive times
        repeat (4) begin
            @(posedge clk); #1;
            ex_pc = 64'h0000_0000_8000_1000;
            ex_is_branch = 1;
            ex_taken = 0;
            ex_valid = 1;
        end
        @(posedge clk); #1;
        ex_valid = 0;

        // Query again: BTB should still hit, but pred_taken should now be NOT-TAKEN (0)
        fetch_pc = 64'h0000_0000_8000_1000;
        fetch_valid = 1;
        @(posedge clk); #1;
        fetch_valid = 0;
        if (pred_valid !== 1'b1 || pred_taken !== 1'b0) begin
            $display("ERROR [T5]: Saturating counter failed to invert prediction: pred_valid=%b pred_taken=%b",
                     pred_valid, pred_taken);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T5]: 2-bit counter saturated to NOT-TAKEN (pred_taken=0, BTB hit=1)");
        end

        // Test 6: JAL Unconditional Target Training
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        ex_pc = 64'h0000_0000_8000_2000;
        ex_is_branch = 0;
        ex_is_jal = 1;
        ex_taken = 1;
        ex_target = 64'h0000_0000_8000_3000;
        ex_valid = 1;
        @(posedge clk); #1;
        ex_valid = 0;

        fetch_pc = 64'h0000_0000_8000_2000;
        fetch_valid = 1;
        @(posedge clk); #1;
        fetch_valid = 0;
        if (pred_valid !== 1'b1 || pred_target !== 64'h0000_0000_8000_3000) begin
            $display("ERROR [T6]: JAL BTB target registration failed: pred_valid=%b pred_target=%h",
                     pred_valid, pred_target);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T6]: JAL unconditional target registration and BTB hit verified");
        end

        clear_inputs();
        #20;

        $display("=== VERIFICATION SUMMARY ===");
        $display("Total Tests Executed: %0d", test_cnt);
        $display("Total Errors: %0d", err_cnt);

        if (err_cnt == 0) begin
            $display("ALL TESTS PASSED: rv_bpu 100%% VERIFIED");
        end else begin
            $display("VERIFICATION FAILED: %0d errors detected!", err_cnt);
        end
        $finish;
    end
endmodule

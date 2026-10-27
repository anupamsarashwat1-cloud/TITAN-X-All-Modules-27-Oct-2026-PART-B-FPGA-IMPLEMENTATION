// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Reset Synchronizer Directed Self-Checking Testbench
// Tests: async reset deassertion synchronized to clock, sync output behavior
`timescale 1ns/1ps

module tb_reset_sync();

    reg  clk;
    reg  async_rst_n;
    wire sync_rst_n;

    integer error_count;

    reset_sync #(.STAGES(2)) uut (
        .clk(clk),
        .async_rst_n(async_rst_n),
        .sync_rst_n(sync_rst_n)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input got;
        input exp;
        input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=%b expected=%b", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    initial begin
        $dumpfile("tb_reset_sync.vcd");
        $dumpvars(0, tb_reset_sync);
        error_count = 0;
        async_rst_n = 0;
        #12; // Apply reset asynchronously (between clock edges)

        // TEST 1: Reset asserted → sync output must be 0
        $display("\n--- TEST 1: Reset asserted immediately ---");
        #3; // Wait for output (could be async)
        check(sync_rst_n, 1'b0, "sync_rst_n=0 while async_rst_n=0");

        // TEST 2: Deassert reset, wait for synchronization (2 stages = 2 clocks)
        $display("\n--- TEST 2: Reset deassertion synchronizes ---");
        @(posedge clk); #1;
        async_rst_n = 1;  // Deassert reset
        // After 2 clock cycles, sync_rst_n should follow
        repeat(3) @(posedge clk); #1;
        check(sync_rst_n, 1'b1, "sync_rst_n=1 after 3 clock edges post-deassert");

        // TEST 3: Reassert reset asynchronously
        $display("\n--- TEST 3: Async reassert ---");
        #3; // Between clocks
        async_rst_n = 0;
        #2;
        check(sync_rst_n, 1'b0, "sync_rst_n=0 immediately on async_rst_n=0");

        // TEST 4: Deassert again
        $display("\n--- TEST 4: Second deassert ---");
        @(posedge clk); #1;
        async_rst_n = 1;
        repeat(3) @(posedge clk); #1;
        check(sync_rst_n, 1'b1, "sync_rst_n=1 after second deassert");

        $display("\n==============================");
        if (error_count == 0)
            $display("RESET_SYNC VERDICT: ✅ PASS — All tests passed");
        else
            $display("RESET_SYNC VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #100_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

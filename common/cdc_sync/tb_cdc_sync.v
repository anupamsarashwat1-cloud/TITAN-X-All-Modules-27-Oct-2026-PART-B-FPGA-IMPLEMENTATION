// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — CDC Synchronizer Directed Self-Checking Testbench
// Tests 2-stage synchronizer behavior: data propagates after 2 clock edges
`timescale 1ns/1ps

module tb_cdc_sync();
    parameter WIDTH = 8;

    reg                  dst_clk;
    reg                  rst_n;
    reg  [WIDTH-1:0]     data_in;
    wire [WIDTH-1:0]     data_out;

    integer error_count;

    cdc_sync #(.WIDTH(WIDTH), .STAGES(2)) uut (
        .dst_clk(dst_clk), .rst_n(rst_n),
        .data_in(data_in), .data_out(data_out)
    );

    // Second instance with a deeper chain: catches reset bugs on stages
    // beyond index 1 (the original RTL hardcoded the reset for STAGES=2).
    reg                  rst_n3;
    reg  [WIDTH-1:0]     data_in3;
    wire [WIDTH-1:0]     data_out3;
    cdc_sync #(.WIDTH(WIDTH), .STAGES(3)) uut3 (
        .dst_clk(dst_clk), .rst_n(rst_n3),
        .data_in(data_in3), .data_out(data_out3)
    );

    initial dst_clk = 0;
    always #5 dst_clk = ~dst_clk;

    task check;
        input [63:0] got;
        input [63:0] exp;
        input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=0x%02X expected=0x%02X", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    initial begin
        $dumpfile("tb_cdc_sync.vcd");
        $dumpvars(0, tb_cdc_sync);
        error_count = 0;
        data_in = 8'h00;
        rst_n = 0; repeat(4) @(posedge dst_clk); rst_n = 1;

        // TEST 1: Reset state → output=0
        $display("\n--- TEST 1: Reset output = 0 ---");
        @(posedge dst_clk); #1;
        check(data_out, 8'h0, "data_out=0 after reset");

        // TEST 2: Apply data, wait 2 stages to propagate
        $display("\n--- TEST 2: Data propagates after 2 clocks ---");
        data_in = 8'hA5;
        repeat(3) @(posedge dst_clk);  // 2 stages + 1 margin
        check(data_out, 8'hA5, "data_out=0xA5 after 3 cycles");

        // TEST 3: Change data
        $display("\n--- TEST 3: Data change propagates ---");
        data_in = 8'h3C;
        repeat(3) @(posedge dst_clk);
        check(data_out, 8'h3C, "data_out=0x3C after change");

        // TEST 4: All-ones
        $display("\n--- TEST 4: All-ones data ---");
        data_in = 8'hFF;
        repeat(3) @(posedge dst_clk);
        check(data_out, 8'hFF, "data_out=0xFF");

        // TEST 5: Zero again
        $display("\n--- TEST 5: Return to zero ---");
        data_in = 8'h00;
        repeat(3) @(posedge dst_clk);
        check(data_out, 8'h00, "data_out=0x00");

        // TEST 6: STAGES=3 instance — reset state and propagation depth.
        // Before the RTL fix, sync_ff[2] came out of reset X and this
        // comparison failed on the first random value.
        $display("\n--- TEST 6: STAGES=3 chain ---");
        rst_n3 = 0; data_in3 = 8'h00;
        repeat(4) @(posedge dst_clk); rst_n3 = 1;
        @(posedge dst_clk); #1;
        check(data_out3, 8'h00, "STAGES=3 data_out=0 after its reset");
        data_in3 = 8'hC3;
        repeat(4) @(posedge dst_clk); #1;   // 3 stages + margin
        check(data_out3, 8'hC3, "STAGES=3 propagates after 4 cycles");

        // TEST 7: Randomized multi-bit coherency — values must arrive
        // intact (no partial updates) on both instances.
        $display("\n--- TEST 7: Randomized coherency sweep ---");
        begin : sweep
            integer k, n_err;
            reg [WIDTH-1:0] exp2, exp3, d2, d3;
            n_err = 0;
            for (k = 0; k < 32; k = k + 1) begin
                d2 = $random; d3 = $random;
                data_in = d2; data_in3 = d3;
                repeat(4) @(posedge dst_clk); #1;
                if (data_out !== d2 || data_out3 !== d3) begin
                    $display("FAIL [%0t] sweep[%0d]: st2 got=0x%02X exp=0x%02X | st3 got=0x%02X exp=0x%02X",
                             $time, k, data_out, d2, data_out3, d3);
                    n_err = n_err + 1;
                end
            end
            if (n_err == 0) $display("PASS [%0t] 32 randomized values coherent through both chains", $time);
            error_count = error_count + n_err;
        end

        $display("\n==============================");
        if (error_count == 0)
            $display("CDC_SYNC VERDICT: ✅ PASS — All tests passed");
        else
            $display("CDC_SYNC VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #100_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

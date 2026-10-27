// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — PLIC Directed Self-Checking Testbench
// Tests: interrupt priority, enable, threshold, irq_targets generation
// PLIC register map:
//   0x000000 + src*4  : priority_reg[src] (3-bit)
//   0x002000 + tgt*128 + word*4 : enable[tgt][src]
//   0x200000 + tgt*4  : threshold[tgt]
`timescale 1ns/1ps

module tb_plic();
    parameter NUM_SOURCES = 186;
    parameter NUM_TARGETS = 10;

    reg        clk, rst_n;
    reg [NUM_SOURCES-1:0] interrupt_sources;
    reg        psel, penable, pwrite;
    reg [23:0] paddr;
    reg [31:0] pwdata;
    wire[31:0] prdata;
    wire       pready;
    wire[NUM_TARGETS-1:0] irq_targets;

    integer error_count;

    plic #(.NUM_SOURCES(NUM_SOURCES), .NUM_TARGETS(NUM_TARGETS)) uut (
        .clk(clk), .rst_n(rst_n),
        .interrupt_sources(interrupt_sources),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata), .prdata(prdata), .pready(pready),
        .irq_targets(irq_targets)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task apb_write;
        input [23:0] addr;
        input [31:0] data;
        begin
            @(posedge clk); #1;
            paddr=addr; pwdata=data; psel=1; penable=0; pwrite=1;
            @(posedge clk); #1; penable=1;
            @(posedge clk); #1;
            while (!pready) @(posedge clk);
            #1; psel=0; penable=0; pwrite=0;
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

    initial begin
        $dumpfile("tb_plic.vcd");
        $dumpvars(0, tb_plic);
        error_count = 0;
        interrupt_sources = 0;
        psel=0; penable=0; pwrite=0; paddr=0; pwdata=0;
        rst_n=0; repeat(6) @(posedge clk); rst_n=1; repeat(5) @(posedge clk);

        // TEST 1: Reset — no interrupts
        $display("\n--- TEST 1: Reset state ---");
        check(pready, 1'b1, "pready=1 after reset");
        check(irq_targets, {NUM_TARGETS{1'b0}}, "irq_targets=0 at reset (no sources)");

        // TEST 2: Set priority for source 1 (priority=5)
        // priority_reg addr: 0x000000 + src*4 = 0x004
        $display("\n--- TEST 2: Set source 1 priority=5 ---");
        apb_write(24'h000004, 32'h5);   // priority_reg[1] = 5

        // TEST 3: Enable source 1 for target 0
        // enable addr: 0x002000 + tgt*128 + word*4
        // Source 1 is in word 0 (bits [31:0]), bit 1
        $display("\n--- TEST 3: Enable source 1 for target 0 ---");
        apb_write(24'h002000, 32'h0000_0002);   // enable[0][1] = 1 (bit 1)

        // TEST 4: Set threshold[0] = 0 (all priorities above threshold)
        // threshold addr: 0x200000 + tgt*4
        $display("\n--- TEST 4: Set threshold[0]=0 ---");
        apb_write(24'h200000, 32'h0);   // threshold[0] = 0

        // TEST 5: Assert interrupt source 1 → irq_targets[0] should go high
        $display("\n--- TEST 5: Assert interrupt source 1 ---");
        @(posedge clk); #1;
        interrupt_sources[1] = 1;
        repeat(3) @(posedge clk); #1;  // allow pending to latch and priority encoder to run
        check(irq_targets[0], 1'b1, "irq_targets[0]=1 when src1 pending+enabled");

        // TEST 6: De-assert interrupt source → irq remains (level-based, pending stays)
        $display("\n--- TEST 6: Pending stays after source de-asserts ---");
        interrupt_sources[1] = 0;
        repeat(2) @(posedge clk); #1;
        // pending is latched, so irq should still be asserted
        check(irq_targets[0], 1'b1, "irq_targets[0]=1 (pending latched)");

        // TEST 7: Disable source 1 for target 0 → irq_targets[0] clears
        $display("\n--- TEST 7: Disable source, irq clears ---");
        apb_write(24'h002000, 32'h0000_0000);  // enable[0] = 0
        repeat(3) @(posedge clk); #1;
        check(irq_targets[0], 1'b0, "irq_targets[0]=0 after disable");

        // TEST 8: Source 1 active but threshold higher than priority → no irq
        $display("\n--- TEST 8: Threshold blocks interrupt ---");
        apb_write(24'h002000, 32'h0000_0002);  // re-enable src1
        apb_write(24'h200000, 32'h7);          // threshold[0] = 7 (higher than prio=5)
        interrupt_sources[1] = 1;
        repeat(3) @(posedge clk); #1;
        check(irq_targets[0], 1'b0, "irq_targets[0]=0 when threshold>priority");
        interrupt_sources[1] = 0;

        $display("\n==============================");
        if (error_count == 0)
            $display("PLIC VERDICT: ✅ PASS — All tests passed");
        else
            $display("PLIC VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

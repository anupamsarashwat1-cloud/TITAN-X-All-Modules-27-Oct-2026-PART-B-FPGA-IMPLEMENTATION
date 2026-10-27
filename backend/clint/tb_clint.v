// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — CLINT Directed Self-Checking Testbench
// Tests: mtime increment, msip R/W, mtimecmp R/W, mtip generation
`timescale 1ns/1ps

module tb_clint();
    parameter NUM_HARTS = 5;

    reg        clk, rst_n;
    reg        psel, penable, pwrite;
    reg [15:0] paddr;
    reg [31:0] pwdata;
    wire[31:0] prdata;
    wire       pready;
    wire [NUM_HARTS-1:0] msip;
    wire [NUM_HARTS-1:0] mtip;

    integer error_count;

    clint #(.NUM_HARTS(NUM_HARTS)) uut (
        .clk(clk), .rst_n(rst_n),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata), .prdata(prdata), .pready(pready),
        .msip(msip), .mtip(mtip)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task apb_write;
        input [15:0] addr;
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

    task apb_read;
        input  [15:0] addr;
        output [31:0] data;
        begin
            @(posedge clk); #1;
            paddr=addr; psel=1; penable=0; pwrite=0;
            @(posedge clk); #1; penable=1;
            @(posedge clk); #1;
            while (!pready) @(posedge clk);
            data=prdata;
            #1; psel=0; penable=0;
        end
    endtask

    task check;
        input [63:0] got; input [63:0] exp; input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=0x%08X exp=0x%08X", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    reg [31:0] rdata;
    integer wc;

    initial begin
        $dumpfile("tb_clint.vcd");
        $dumpvars(0, tb_clint);
        error_count = 0;
        psel=0; penable=0; pwrite=0; paddr=0; pwdata=0;
        rst_n=0; repeat(6) @(posedge clk); rst_n=1; repeat(3) @(posedge clk);

        // TEST 1: Reset state
        $display("\n--- TEST 1: Reset state ---");
        check(pready, 1'b1, "pready=1 (zero-wait)");
        check(msip,  {NUM_HARTS{1'b0}}, "msip=0 after reset");

        // TEST 2: mtime increments every cycle
        $display("\n--- TEST 2: mtime increments ---");
        apb_read(16'hBFF8, rdata);  // mtime_lo
        $display("  mtime_lo after reset+3 cycles = 0x%08X (non-zero expected)", rdata);
        if (rdata > 32'h0)
            $display("PASS [%0t] mtime_lo > 0 (incrementing)", $time);
        else begin
            $display("FAIL [%0t] mtime_lo = 0 (not incrementing)", $time);
            error_count = error_count + 1;
        end

        // TEST 3: msip write/readback for hart 0
        $display("\n--- TEST 3: msip[0] set ---");
        apb_write(16'h0000, 32'h1);   // msip[0] = 1
        @(posedge clk); #1;
        check(msip[0], 1'b1, "msip[0]=1 after write");

        // TEST 4: msip clear
        $display("\n--- TEST 4: msip[0] clear ---");
        apb_write(16'h0000, 32'h0);   // msip[0] = 0
        @(posedge clk); #1;
        check(msip[0], 1'b0, "msip[0]=0 after clear");

        // TEST 5: mtimecmp write and mtip generation
        // Set mtimecmp[0] to a very small value (1) so mtime >= mtimecmp quickly
        $display("\n--- TEST 5: mtip generation ---");
        apb_write(16'h4000, 32'h0000_0001); // mtimecmp[0] lo = 1
        apb_write(16'h4004, 32'h0000_0000); // mtimecmp[0] hi = 0
        // Wait a few cycles for mtime to exceed mtimecmp
        repeat(5) @(posedge clk); #1;
        check(mtip[0], 1'b1, "mtip[0]=1 when mtime >= mtimecmp[0]=1");

        // TEST 6: Set mtimecmp to max → mtip should clear
        $display("\n--- TEST 6: mtip cleared by large mtimecmp ---");
        apb_write(16'h4000, 32'hFFFF_FFFF); // mtimecmp[0] lo = max
        apb_write(16'h4004, 32'hFFFF_FFFF); // mtimecmp[0] hi = max
        repeat(3) @(posedge clk); #1;
        check(mtip[0], 1'b0, "mtip[0]=0 when mtimecmp=max");

        // TEST 7: mtime readback
        $display("\n--- TEST 7: mtime readback ---");
        apb_read(16'hBFF8, rdata);
        $display("  mtime_lo = 0x%08X (incremented)", rdata);
        if (rdata > 32'h10)
            $display("PASS [%0t] mtime_lo > 16 after running", $time);
        else begin
            $display("FAIL [%0t] mtime_lo too small = 0x%08X", $time, rdata);
            error_count = error_count + 1;
        end

        $display("\n==============================");
        if (error_count == 0)
            $display("CLINT VERDICT: ✅ PASS — All tests passed");
        else
            $display("CLINT VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

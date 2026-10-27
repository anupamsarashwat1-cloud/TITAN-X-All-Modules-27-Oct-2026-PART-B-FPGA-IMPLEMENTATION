// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Watchdog Timer Directed Self-Checking Testbench
// Register map (paddr[3:2]):
//   0 = unlock register (write UNLOCK_KEY=0x1ACCE551 to unlock)
//   1 = load_val (W: set reload; R: read current load value) — needs unlock
//   2 = kick register (write 0xE5 to service/kick) / R: current count
//   3 = control: [1]=int_en, [0]=wdt_en — needs unlock
// Behavior: count decrements when wdt_en=1; on first expiry → int_stat=1;
//           on second expiry without service → wdt_reset_n=0
`timescale 1ns/1ps

module tb_watchdog_timer();

    reg        clk;
    reg        rst_n;
    reg        psel;
    reg        penable;
    reg        pwrite;
    reg [3:0]  paddr;
    reg [31:0] pwdata;
    wire[31:0] prdata;
    wire       pready;
    wire       wdt_reset_n;
    wire       irq;

    integer error_count;

    watchdog_timer uut (
        .clk(clk), .rst_n(rst_n),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata), .prdata(prdata), .pready(pready),
        .wdt_reset_n(wdt_reset_n), .irq(irq)
    );

    initial clk = 0;
    always #3.6 clk = ~clk;

    task apb_write;
        input [3:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk); #1;
            paddr = addr; pwdata = data; psel = 1; penable = 0; pwrite = 1;
            @(posedge clk); #1;
            penable = 1;
            @(posedge clk); #1;
            while (!pready) @(posedge clk);
            #1; psel = 0; penable = 0; pwrite = 0;
        end
    endtask

    task apb_read;
        input  [3:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk); #1;
            paddr = addr; psel = 1; penable = 0; pwrite = 0;
            @(posedge clk); #1;
            penable = 1;
            @(posedge clk); #1;
            while (!pready) @(posedge clk);
            data = prdata;
            #1; psel = 0; penable = 0;
        end
    endtask

    task check;
        input [63:0] got;
        input [63:0] exp;
        input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=0x%08X expected=0x%08X", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    reg [31:0] rdata;
    integer wait_cnt;

    initial begin
        $dumpfile("tb_watchdog_timer.vcd");
        $dumpvars(0, tb_watchdog_timer);
        error_count = 0;
        psel = 0; penable = 0; pwrite = 0; paddr = 0; pwdata = 0;

        // Reset
        rst_n = 0; repeat(8) @(posedge clk); rst_n = 1; repeat(3) @(posedge clk);

        // TEST 1: Reset state
        $display("\n--- TEST 1: Reset state ---");
        check(pready, 1'b1, "pready=1 after reset");
        check(wdt_reset_n, 1'b1, "wdt_reset_n=1 after reset");
        check(irq, 1'b0, "irq=0 after reset");

        // TEST 2: Load value reads back as 0xFFFFFFFF (reset default)
        $display("\n--- TEST 2: Default load_val ---");
        apb_read(4'h4, rdata);   // paddr[3:2]=1 → 4'h4
        check(rdata, 32'hFFFF_FFFF, "load_val=0xFFFFFFFF after reset");

        // TEST 3: Control register reads back wdt_en=0
        $display("\n--- TEST 3: Default control state ---");
        apb_read(4'hC, rdata);   // paddr[3:2]=3 → 4'hC
        check(rdata[0], 1'b0, "wdt_en=0 after reset");

        // TEST 4: Unlock + load_val write/readback
        $display("\n--- TEST 4: Unlock + load_val write ---");
        apb_write(4'h0, 32'h1ACC_E551);  // Unlock key
        apb_write(4'h4, 32'h0000_0010);  // load_val = 16
        apb_read (4'h4, rdata);
        check(rdata, 32'h0000_0010, "load_val=16 after write");

        // TEST 5: Enable WDT and observe timeout → irq fires
        // Note: count starts at 0xFFFFFFFF; kick first to load from load_val=16
        $display("\n--- TEST 5: WDT enable + timeout interrupt ---");
        apb_write(4'h0, 32'h1ACC_E551);  // Unlock
        apb_write(4'hC, 32'h0000_0003);  // wdt_en=1, int_en=1
        // Kick to reload count from load_val (0xE5 kick)
        apb_write(4'h8, 32'h0000_00E5);  // kick → count reloads to 16
        // Now count decrements from 16, should fire int_stat within ~20 cycles
        wait_cnt = 0;
        while (irq !== 1'b1 && wait_cnt < 500) begin
            @(posedge clk); wait_cnt = wait_cnt + 1;
        end
        if (irq === 1'b1)
            $display("PASS [%0t] irq=1 after WDT timeout (took %0d cycles)", $time, wait_cnt);
        else begin
            $display("FAIL [%0t] irq never fired in 500 cycles", $time);
            error_count = error_count + 1;
        end

        // TEST 6: int_stat bit in control reg
        $display("\n--- TEST 6: int_stat set in status reg ---");
        apb_read(4'hC, rdata);  // control/status
        check(rdata[1], 1'b1, "int_stat=1 after timeout");

        // TEST 7: Kick/service clears int_stat
        $display("\n--- TEST 7: Kick (service) clears int_stat ---");
        apb_write(4'h8, 32'h0000_00E5);  // kick = 0xE5
        apb_read (4'hC, rdata);
        check(rdata[1], 1'b0, "int_stat=0 after kick");
        check(irq, 1'b0, "irq=0 after kick");

        // TEST 8: wdt_reset_n still high after one kick (needs second timeout + no kick)
        $display("\n--- TEST 8: wdt_reset_n stays high after single timeout ---");
        check(wdt_reset_n, 1'b1, "wdt_reset_n=1 (no second timeout yet)");

        // TEST 9: Disable WDT → no more counting
        $display("\n--- TEST 9: Disable WDT ---");
        apb_write(4'h0, 32'h1ACC_E551);  // Unlock
        apb_write(4'hC, 32'h0000_0000);  // wdt_en=0
        apb_read (4'hC, rdata);
        check(rdata[0], 1'b0, "wdt_en=0 after disable");

        $display("\n==============================");
        if (error_count == 0)
            $display("WDT VERDICT: ✅ PASS — All tests passed");
        else
            $display("WDT VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end

    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end

endmodule

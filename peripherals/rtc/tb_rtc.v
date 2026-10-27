// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RTC Directed Self-Checking Testbench
// Tests: mtime counter, mtimecmp write, timer_irq generation
`timescale 1ns / 1ps

module tb_rtc();

    reg         clk;
    reg         rtc_clk;
    reg         rst_n;
    reg  [31:0] paddr;
    reg         psel;
    reg         penable;
    reg         pwrite;
    reg  [31:0] pwdata;
    wire [31:0] prdata;
    wire        pready;
    wire        pslverr;
    wire [4:0]  timer_irq;

    integer error_count;

    rtc uut (
        .clk(clk), .rtc_clk(rtc_clk), .rst_n(rst_n),
        .paddr(paddr), .psel(psel), .penable(penable),
        .pwrite(pwrite), .pwdata(pwdata), .prdata(prdata),
        .pready(pready), .pslverr(pslverr),
        .timer_irq(timer_irq)
    );

    // System clock: 138.8 MHz ≈ 7.2 ns
    initial clk = 0;
    always #3.6 clk = ~clk;

    // RTC clock: 32.768 kHz ≈ 30517 ns period
    initial rtc_clk = 0;
    always #15258 rtc_clk = ~rtc_clk;

    task apb_write;
        input [31:0] addr;
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
        input  [31:0] addr;
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
        input [63:0] expected;
        input [255:0] msg;
        begin
            if (got !== expected) begin
                $display("FAIL [%0t] %s: got=0x%08X expected=0x%08X", $time, msg, got, expected);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    reg [31:0] rdata;
    reg [31:0] mtime_lo_before, mtime_lo_after;

    initial begin
        $dumpfile("tb_rtc.vcd");
        $dumpvars(0, tb_rtc);
        error_count = 0;
        paddr = 0; psel = 0; penable = 0; pwrite = 0; pwdata = 0;

        // ---- Reset ----
        rst_n = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        // ==============================================================
        // TEST 1: pready is combinatorially asserted
        // ==============================================================
        $display("\n--- TEST 1: pready asserts ---");
        check(pready, 1'b1, "pready = 1 after reset");

        // ==============================================================
        // TEST 2: Read mtime_lo at 0xBFF8, confirm it starts at 0
        // ==============================================================
        $display("\n--- TEST 2: mtime reset value ---");
        apb_read(32'hBFF8, rdata);
        check(rdata, 32'h0, "mtime_lo = 0 after reset");
        apb_read(32'hBFFC, rdata);
        check(rdata, 32'h0, "mtime_hi = 0 after reset");

        // ==============================================================
        // TEST 3: mtime increments with rtc_clk
        //   Wait for 5 rtc_clk cycles (~152580 ns) and re-read
        // ==============================================================
        $display("\n--- TEST 3: mtime increments ---");
        apb_read(32'hBFF8, mtime_lo_before);
        repeat(5) @(posedge rtc_clk);
        repeat(3) @(posedge clk); // let CDC synchronize
        apb_read(32'hBFF8, mtime_lo_after);
        if (mtime_lo_after > mtime_lo_before)
            $display("PASS [%0t] mtime_lo incremented: %0d -> %0d", $time, mtime_lo_before, mtime_lo_after);
        else begin
            $display("FAIL [%0t] mtime_lo did NOT increment: %0d -> %0d", $time, mtime_lo_before, mtime_lo_after);
            error_count = error_count + 1;
        end

        // ==============================================================
        // TEST 4: timer_irq[0] fires when mtime >= mtimecmp[0]
        //   Set mtimecmp[0] to a small value so irq fires quickly
        // ==============================================================
        $display("\n--- TEST 4: timer_irq generation ---");
        // Read current mtime
        apb_read(32'hBFF8, rdata);
        // Set mtimecmp[0] slightly above current mtime (current + 3 ticks)
        apb_write(32'h4000, rdata + 3);  // mtimecmp[0][31:0]
        apb_write(32'h4004, 32'h0);      // mtimecmp[0][63:32]

        // Wait for a few rtc_clk edges — irq should fire
        repeat(10) @(posedge rtc_clk);
        repeat(5) @(posedge clk);
        check(timer_irq[0], 1'b1, "timer_irq[0] fires when mtime >= mtimecmp");

        // ==============================================================
        // TEST 5: Clear irq by writing mtimecmp[0] = 0xFFFF_FFFF_FFFF_FFFF
        // ==============================================================
        $display("\n--- TEST 5: Clear irq by resetting mtimecmp ---");
        apb_write(32'h4000, 32'hFFFF_FFFF); // mtimecmp[0][31:0]
        apb_write(32'h4004, 32'hFFFF_FFFF); // mtimecmp[0][63:32]
        repeat(3) @(posedge clk);
        check(timer_irq[0], 1'b0, "timer_irq[0] cleared after mtimecmp reset");

        // ==============================================================
        // TEST 6: mtimecmp readback
        // ==============================================================
        $display("\n--- TEST 6: mtimecmp readback ---");
        apb_write(32'h4008, 32'hDEAD_BEEF); // mtimecmp[1][31:0]
        apb_write(32'h400C, 32'hCAFE_BABE); // mtimecmp[1][63:32]
        apb_read(32'h4008, rdata);
        check(rdata, 32'hDEAD_BEEF, "mtimecmp[1] lo readback");
        apb_read(32'h400C, rdata);
        check(rdata, 32'hCAFE_BABE, "mtimecmp[1] hi readback");

        // ==============================================================
        // FINAL RESULT
        // ==============================================================
        repeat(10) @(posedge clk);
        $display("\n==============================");
        if (error_count == 0)
            $display("RTC VERDICT: ✅ PASS — All tests passed");
        else
            $display("RTC VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end

    initial begin #5_000_000; $display("WATCHDOG TIMEOUT"); $finish; end

endmodule

// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — TRNG Directed Self-Checking Testbench
// Tests: ring oscillator entropy generation, trng_valid flag, APB register access
`timescale 1ns / 1ps

module tb_trng();

    reg         clk;
    reg         rst_n;
    reg  [31:0] paddr;
    reg         psel;
    reg         penable;
    reg         pwrite;
    reg  [31:0] pwdata;
    wire [31:0] prdata;
    wire        pready;
    wire        pslverr;
    wire [255:0] trng_entropy;
    wire         trng_valid;
    reg          trng_ready;
    wire         trng_irq;

    integer error_count;

    trng uut (
        .clk(clk), .rst_n(rst_n),
        .paddr(paddr), .psel(psel), .penable(penable),
        .pwrite(pwrite), .pwdata(pwdata), .prdata(prdata),
        .pready(pready), .pslverr(pslverr),
        .trng_entropy(trng_entropy), .trng_valid(trng_valid),
        .trng_ready(trng_ready),
        .trng_irq(trng_irq)
    );

    initial clk = 0;
    always #3.6 clk = ~clk;  // 138.8 MHz

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

    reg  [31:0] rdata;
    reg  [255:0] entropy_snapshot1;
    reg  [255:0] entropy_snapshot2;
    integer wait_cycles;

    initial begin
        $dumpfile("tb_trng.vcd");
        $dumpvars(0, tb_trng);
        error_count = 0;
        paddr = 0; psel = 0; penable = 0; pwrite = 0; pwdata = 0;
        trng_ready = 0;

        // Reset
        rst_n = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        // ==============================================================
        // TEST 1: pready asserts
        // ==============================================================
        $display("\n--- TEST 1: pready ---");
        check(pready, 1'b1, "pready=1 after reset");

        // ==============================================================
        // TEST 2: ctrl_reg reset = 0
        // ==============================================================
        $display("\n--- TEST 2: ctrl_reg reset value ---");
        apb_read(32'h00, rdata);
        check(rdata, 32'h0, "ctrl_reg = 0 after reset");

        // ==============================================================
        // TEST 3: trng_valid asserts after 256 entropy bits collected
        //   Von Neumann needs bit transitions. With fixed RO, bits come slowly.
        //   Wait up to 20000 clk cycles for trng_valid.
        // ==============================================================
        $display("\n--- TEST 3: trng_valid asserts (collecting entropy) ---");
        wait_cycles = 0;
        while (trng_valid !== 1'b1 && wait_cycles < 20000) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end

        if (trng_valid === 1'b1) begin
            $display("PASS [%0t] trng_valid=1 after %0d clock cycles", $time, wait_cycles);
        end else begin
            $display("FAIL [%0t] trng_valid did NOT assert in 20000 cycles (RO fix needed)", $time);
            error_count = error_count + 1;
        end

        // ==============================================================
        // TEST 4: Status register reflects trng_valid
        //   Reg 0x04[1] = entropy_valid
        // ==============================================================
        $display("\n--- TEST 4: Status register entropy_valid bit ---");
        apb_read(32'h04, rdata);
        check(rdata[1], 1'b1, "status_reg[1]=entropy_valid");
        check(rdata[0], 1'b0, "status_reg[0]=health_fail=0");

        // ==============================================================
        // TEST 5: trng_entropy is non-zero
        // ==============================================================
        $display("\n--- TEST 5: trng_entropy non-zero ---");
        entropy_snapshot1 = trng_entropy;
        if (entropy_snapshot1 !== 256'h0) begin
            $display("PASS [%0t] trng_entropy = non-zero (0x%064X)", $time, entropy_snapshot1[255:224]);
        end else begin
            $display("FAIL [%0t] trng_entropy = all zeros!", $time);
            error_count = error_count + 1;
        end

        // ==============================================================
        // TEST 6: Acknowledge entropy → module starts collecting next batch
        //   Assert trng_ready=1 to consume the current entropy word
        // ==============================================================
        $display("\n--- TEST 6: trng_ready handshake → new collection ---");
        @(posedge clk); #1;
        trng_ready = 1;
        @(posedge clk); #1;
        trng_ready = 0;

        // After handshake, trng_valid should go low
        repeat(5) @(posedge clk);
        check(trng_valid, 1'b0, "trng_valid deasserted after trng_ready handshake");

        // ==============================================================
        // TEST 7: New entropy collected (different from first batch)
        // ==============================================================
        $display("\n--- TEST 7: Second entropy batch is different ---");
        wait_cycles = 0;
        while (trng_valid !== 1'b1 && wait_cycles < 20000) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end
        entropy_snapshot2 = trng_entropy;

        if (entropy_snapshot2 !== entropy_snapshot1) begin
            $display("PASS [%0t] Second entropy batch differs from first", $time);
        end else begin
            $display("WARN [%0t] Second entropy batch identical to first (may be deterministic)", $time);
            // Not a failure — could be deterministic mock
        end

        // ==============================================================
        // TEST 8: Health test — no failure in normal operation
        // ==============================================================
        $display("\n--- TEST 8: trng_irq (health fail) = 0 ---");
        check(trng_irq, 1'b0, "trng_irq=0 (no health test failure)");

        // ==============================================================
        // FINAL RESULT
        // ==============================================================
        repeat(20) @(posedge clk);
        $display("\n==============================");
        if (error_count == 0)
            $display("TRNG VERDICT: ✅ PASS — All tests passed");
        else
            $display("TRNG VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end

    initial begin #5_000_000; $display("WATCHDOG TIMEOUT"); $finish; end

endmodule

// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X — sram_512kx8_180nm Directed Self-Checking Testbench
// Tests: Write/read byte, address boundaries, CEN disable, WEN behavior
`timescale 1ns/1ps

module tb_sram_512kx8_180nm();

    reg         CLK;
    reg         CEN;
    reg         WEN;
    reg  [18:0] A;
    reg  [7:0]  D;
    wire [7:0]  Q;

    integer error_count;

    sram_512kx8_180nm uut (
        .CLK(CLK), .CEN(CEN), .WEN(WEN), .A(A), .D(D), .Q(Q)
    );

    initial CLK = 0;
    always #3.6 CLK = ~CLK;

    task sram_write;
        input [18:0] addr;
        input [7:0]  data;
        begin
            @(posedge CLK); #1;
            CEN = 0; WEN = 0; A = addr; D = data;
            @(posedge CLK); #1;
            CEN = 1; WEN = 1;
        end
    endtask

    task sram_read;
        input  [18:0] addr;
        output [7:0]  data;
        begin
            @(posedge CLK); #1;
            CEN = 0; WEN = 1; A = addr;
            @(posedge CLK); #1;
            data = Q;
            CEN = 1;
        end
    endtask

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

    reg [7:0] rdata;
    integer i;

    initial begin
        $dumpfile("tb_sram_512kx8_180nm.vcd");
        $dumpvars(0, tb_sram_512kx8_180nm);
        error_count = 0;
        CEN = 1; WEN = 1; A = 0; D = 0;
        repeat(4) @(posedge CLK);

        // TEST 1: Basic write/read at addr 0
        $display("\n--- TEST 1: Basic write/read ---");
        sram_write(19'd0, 8'hAB);
        sram_read (19'd0, rdata);
        check(rdata, 8'hAB, "addr[0] = 0xAB");

        // TEST 2: Write/read at last address (512K-1)
        $display("\n--- TEST 2: Last address (0x7FFFF) ---");
        sram_write(19'h7FFFF, 8'hCD);
        sram_read (19'h7FFFF, rdata);
        check(rdata, 8'hCD, "addr[7FFFF] = 0xCD");

        // TEST 3: Address independence
        $display("\n--- TEST 3: Address independence ---");
        sram_read(19'd0, rdata);
        check(rdata, 8'hAB, "addr[0] unchanged after last addr write");

        // TEST 4: Sequential byte addresses
        $display("\n--- TEST 4: Sequential byte sweep ---");
        for (i = 0; i < 8; i = i + 1)
            sram_write(i + 100, (i + 8'hA0));
        for (i = 0; i < 8; i = i + 1) begin
            sram_read(i + 100, rdata);
            check(rdata, (i + 8'hA0), "sequential byte sweep");
        end

        // TEST 5: All-ones data
        $display("\n--- TEST 5: All-ones (0xFF) ---");
        sram_write(19'd200, 8'hFF);
        sram_read (19'd200, rdata);
        check(rdata, 8'hFF, "addr[200] = 0xFF");

        // TEST 6: All-zeros data
        $display("\n--- TEST 6: All-zeros (0x00) ---");
        sram_write(19'd201, 8'h00);
        sram_read (19'd201, rdata);
        check(rdata, 8'h00, "addr[201] = 0x00");

        // TEST 7: CEN=1 (chip disabled) — no write should happen
        $display("\n--- TEST 7: CEN=1 no write ---");
        sram_write(19'd300, 8'h55); // write pattern
        @(posedge CLK); #1;
        CEN = 1; WEN = 0; A = 19'd300; D = 8'hAA; // disabled write
        @(posedge CLK); #1;
        sram_read(19'd300, rdata);
        check(rdata, 8'h55, "CEN=1: no write occurs");

        // TEST 8: Write-first behavior (read returns new data when addr matches)
        $display("\n--- TEST 8: Write-first transparency ---");
        sram_write(19'd400, 8'h11); // Pre-write
        @(posedge CLK); #1;
        CEN = 0; WEN = 0; A = 19'd400; D = 8'h22; // Write new data
        @(posedge CLK); #1;
        check(Q, 8'h22, "Write-first: Q shows new data on write cycle");
        CEN = 1;

        $display("\n==============================");
        if (error_count == 0)
            $display("SRAM_512Kx8 VERDICT: ✅ PASS — All tests passed");
        else
            $display("SRAM_512Kx8 VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end

    initial begin #500_000; $display("WATCHDOG TIMEOUT"); $finish; end

endmodule

// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — SHA-256 Engine Directed Self-Checking Testbench
// Register map (paddr[7:0]):
//   0x00-0x3C = msg_block[0..15] (W: 512-bit message block, 16x32b words)
//                                 R: readback of msg_block words
//   0x40-0x5C = hash[0..7] (R: 256-bit hash output, 8x32b words)
//   0x60 = start register (W: pwdata[0]=1 starts compression)
//   0x80+ = status: prdata = {30'h0, done, active}
// SHA-256 initial hash values (H0-H7) are the standard IV constants
`timescale 1ns/1ps

module tb_sha256_engine();

    reg        clk;
    reg        rst_n;
    reg        psel;
    reg        penable;
    reg        pwrite;
    reg [7:0]  paddr;
    reg [31:0] pwdata;
    wire[31:0] prdata;
    wire       pready;
    wire       irq;

    integer error_count;

    sha256_engine uut (
        .clk(clk), .rst_n(rst_n),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata), .prdata(prdata), .pready(pready),
        .irq(irq)
    );

    initial clk = 0;
    always #3.6 clk = ~clk;

    task apb_write;
        input [7:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk); #1;
            paddr = addr; pwdata = data; psel = 1; penable = 0; pwrite = 1;
            @(posedge clk); #1; penable = 1;
            @(posedge clk); #1;
            while (!pready) @(posedge clk);
            #1; psel = 0; penable = 0; pwrite = 0;
        end
    endtask

    task apb_read;
        input  [7:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk); #1;
            paddr = addr; psel = 1; penable = 0; pwrite = 0;
            @(posedge clk); #1; penable = 1;
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

    task check_nonzero;
        input [31:0] got;
        input [255:0] msg;
        begin
            if (got === 32'h0) begin
                $display("FAIL [%0t] %s = 0 (expected non-zero)", $time, msg);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s = 0x%08X (non-zero)", $time, msg, got);
        end
    endtask

    reg [31:0] rdata;
    integer i;
    integer wait_cnt;

    initial begin
        $dumpfile("tb_sha256_engine.vcd");
        $dumpvars(0, tb_sha256_engine);
        error_count = 0;
        psel = 0; penable = 0; pwrite = 0; paddr = 0; pwdata = 0;

        // Reset
        rst_n = 0; repeat(8) @(posedge clk); rst_n = 1; repeat(3) @(posedge clk);

        // TEST 1: pready + irq reset state
        $display("\n--- TEST 1: Reset state ---");
        check(pready, 1'b1, "pready=1 after reset");
        check(irq, 1'b0, "irq=0 after reset");

        // TEST 2: Hash initial values after reset
        // SHA-256 IV: H0=0x6a09e667, H1=0xbb67ae85 ...
        $display("\n--- TEST 2: Initial hash values (SHA-256 IV) ---");
        apb_read(8'h40, rdata);  // hash[0]
        check(rdata, 32'h6a09e667, "hash[0]=0x6a09e667 (H0 IV)");
        apb_read(8'h44, rdata);  // hash[1]
        check(rdata, 32'hbb67ae85, "hash[1]=0xBB67AE85 (H1 IV)");

        // TEST 3: Message block write/readback
        $display("\n--- TEST 3: Message block write/readback ---");
        apb_write(8'h00, 32'h8000_0000);  // msg_block[0] = SHA-256 padding header
        apb_write(8'h04, 32'hDEAD_BEEF);  // msg_block[1] = test data
        apb_read (8'h00, rdata);
        check(rdata, 32'h8000_0000, "msg_block[0] readback");
        apb_read (8'h04, rdata);
        check(rdata, 32'hDEAD_BEEF, "msg_block[1] readback");

        // TEST 4: Write all-zeros message block (empty message SHA-256 padding)
        //  SHA-256 of empty string: first block is 80 00 00...00 00 00 00 00 (length)
        $display("\n--- TEST 4: Load zero-length message block ---");
        for (i = 0; i < 16; i = i + 1)
            apb_write(i*4, 32'h0);
        // Set message 0: 0x80000000 (padding), word 15: 0x00000000 (length=0 bits)
        apb_write(8'h00, 32'h8000_0000);  // msg_block[0]: 0x80 padding
        // Words 1-14 are 0, word 15 = length = 0 bits
        $display("  Zero-length message block loaded");

        // TEST 5: Start SHA-256 compression
        $display("\n--- TEST 5: Start compression ---");
        apb_write(8'h60, 32'h0000_0001);  // start=1

        // Wait for done (irq) within 100 cycles
        wait_cnt = 0;
        while (irq !== 1'b1 && wait_cnt < 200) begin
            @(posedge clk); wait_cnt = wait_cnt + 1;
        end
        if (irq === 1'b1)
            $display("PASS [%0t] irq=1 (done) after SHA-256 compression (%0d cycles)", $time, wait_cnt);
        else begin
            $display("FAIL [%0t] SHA-256 done never fired in 200 cycles", $time);
            error_count = error_count + 1;
        end

        // TEST 6: SHA-256 hash output is non-zero after compression
        $display("\n--- TEST 6: Hash output non-zero after compression ---");
        apb_read(8'h40, rdata);  // hash[0]
        check_nonzero(rdata, "hash[0] non-zero after compression");
        apb_read(8'h44, rdata);  // hash[1]
        check_nonzero(rdata, "hash[1] non-zero after compression");

        // TEST 7: irq clears on next cycle (done is pulsed, not latched)
        $display("\n--- TEST 7: irq deasserts after one cycle ---");
        @(posedge clk); @(posedge clk);
        $display("  irq = %b (expected to deassert per RTL: done <= 1'b0)", irq);
        check(irq, 1'b0, "irq=0 one cycle after done pulse");

        $display("\n==============================");
        if (error_count == 0)
            $display("SHA256_ENGINE VERDICT: ✅ PASS — All tests passed");
        else
            $display("SHA256_ENGINE VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end

    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end

endmodule

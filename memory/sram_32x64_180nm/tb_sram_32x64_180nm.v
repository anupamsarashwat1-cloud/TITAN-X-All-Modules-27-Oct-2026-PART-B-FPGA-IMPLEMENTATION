// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X — sram_32x64_180nm Directed Self-Checking Testbench
// Tests: Write (byte-masked), Read, Address sweep, Word-level r/w
`timescale 1ns/1ps

module tb_sram_32x64_180nm();

    reg        clk0;
    reg        csb0;
    reg        web0;
    reg [3:0]  wmask0;
    reg [5:0]  addr0;
    reg [31:0] din0;
    wire[31:0] dout0;

    integer error_count;

    sram_32x64_180nm uut (
        .clk0(clk0), .csb0(csb0), .web0(web0),
        .wmask0(wmask0), .addr0(addr0), .din0(din0), .dout0(dout0)
    );

    initial clk0 = 0;
    always #3.6 clk0 = ~clk0;

    task sram_write;
        input [5:0]  addr;
        input [31:0] data;
        input [3:0]  mask;
        begin
            @(posedge clk0); #1;
            csb0 = 0; web0 = 0; addr0 = addr; din0 = data; wmask0 = mask;
            @(posedge clk0); #1;
            csb0 = 1; web0 = 1;
        end
    endtask

    task sram_read;
        input  [5:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk0); #1;
            csb0 = 0; web0 = 1; addr0 = addr; wmask0 = 4'hF;
            @(posedge clk0); #1;
            data = dout0;
            csb0 = 1;
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
    integer i;

    initial begin
        $dumpfile("tb_sram_32x64_180nm.vcd");
        $dumpvars(0, tb_sram_32x64_180nm);
        error_count = 0;
        csb0 = 1; web0 = 1; wmask0 = 4'hF; addr0 = 0; din0 = 0;
        repeat(4) @(posedge clk0);

        // TEST 1: Write/read word to addr 0
        $display("\n--- TEST 1: Write/read word ---");
        sram_write(6'd0, 32'hDEAD_BEEF, 4'hF);
        sram_read (6'd0, rdata);
        check(rdata, 32'hDEAD_BEEF, "addr[0] = 0xDEADBEEF");

        // TEST 2: Write/read to addr 63 (last)
        $display("\n--- TEST 2: Last address ---");
        sram_write(6'd63, 32'hCAFE_BABE, 4'hF);
        sram_read (6'd63, rdata);
        check(rdata, 32'hCAFE_BABE, "addr[63] = 0xCAFEBABE");

        // TEST 3: Address independence - addr[0] unchanged after addr[63] write
        $display("\n--- TEST 3: Address independence ---");
        sram_read(6'd0, rdata);
        check(rdata, 32'hDEAD_BEEF, "addr[0] unaffected by addr[63] write");

        // TEST 4: Byte mask — write only bytes 0,1 (mask=4'b0011)
        $display("\n--- TEST 4: Byte mask write ---");
        sram_write(6'd5, 32'hFFFF_FFFF, 4'hF); // Pre-fill
        sram_write(6'd5, 32'h1234_5678, 4'h3); // Write only bytes [1:0]
        sram_read (6'd5, rdata);
        check(rdata[15:0],  16'h5678, "byte mask [1:0] written");
        check(rdata[31:16], 16'hFFFF, "byte mask [3:2] unchanged");

        // TEST 5: Byte mask — write only bytes 2,3 (mask=4'b1100)
        $display("\n--- TEST 5: Upper byte mask ---");
        sram_write(6'd6, 32'h0000_0000, 4'hF); // Pre-fill zero
        sram_write(6'd6, 32'hABCD_EF12, 4'hC); // Write only bytes [3:2]
        sram_read (6'd6, rdata);
        check(rdata[31:16], 16'hABCD, "byte mask [3:2] written to addr 6");
        check(rdata[15:0],  16'h0000, "byte mask [1:0] unchanged at addr 6");

        // TEST 6: Sequential address sweep
        $display("\n--- TEST 6: Sequential address sweep (addr 0-7) ---");
        for (i = 0; i < 8; i = i + 1)
            sram_write(i, i * 32'h00010001 + 32'h10000000, 4'hF);
        for (i = 0; i < 8; i = i + 1) begin
            sram_read(i, rdata);
            check(rdata, i * 32'h00010001 + 32'h10000000, "sequential address sweep");
        end

        // TEST 7: Chip select disabled — no write
        $display("\n--- TEST 7: CSB=1 no write ---");
        sram_write(6'd10, 32'hAAAA_AAAA, 4'hF); // Write data first
        @(posedge clk0); #1;
        csb0 = 1; web0 = 0; addr0 = 6'd10; din0 = 32'h5555_5555; wmask0 = 4'hF; // CS disabled
        @(posedge clk0); #1;
        sram_read(6'd10, rdata);
        check(rdata, 32'hAAAA_AAAA, "CSB=1: no write occurs");

        $display("\n==============================");
        if (error_count == 0)
            $display("SRAM_32x64 VERDICT: ✅ PASS — All tests passed");
        else
            $display("SRAM_32x64 VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end

    initial begin #500_000; $display("WATCHDOG TIMEOUT"); $finish; end

endmodule

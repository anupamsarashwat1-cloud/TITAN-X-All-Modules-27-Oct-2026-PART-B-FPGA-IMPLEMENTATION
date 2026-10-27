// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Register File Directed + Randomized Self-Checking TB
// Tests: reset state, x0 hardwiring, both read ports, write-first bypass,
// write-drop on x0, 3000-cycle randomized traffic vs a shadow model.
`timescale 1ns/1ps

module tb_rv_regfile();
    reg         clk, rst_n;
    reg  [4:0]  rd_addr1, rd_addr2;
    wire [63:0] rd_data1, rd_data2;
    reg         wr_en;
    reg  [4:0]  wr_addr;
    reg  [63:0] wr_data;

    integer error_count;

    rv_regfile uut (
        .clk(clk), .rst_n(rst_n),
        .rd_addr1(rd_addr1), .rd_data1(rd_data1),
        .rd_addr2(rd_addr2), .rd_data2(rd_data2),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Shadow model — mirrors the architectural rules:
    // x0 never stores; bypass returns incoming write data.
    reg [63:0] m_mem [0:31];
    function [63:0] m_read;
        input [4:0] a;
        begin
            if (a == 5'h0)                 m_read = 64'h0;
            else if (wr_en && wr_addr==a)  m_read = wr_data;
            else                           m_read = m_mem[a];
        end
    endfunction

    task check;
        input [63:0] got; input [63:0] exp; input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=0x%X exp=0x%X", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    integer i;
    initial begin
        $dumpfile("tb_rv_regfile.vcd");
        $dumpvars(0, tb_rv_regfile);
        error_count = 0;
        rd_addr1 = 0; rd_addr2 = 0; wr_en = 0; wr_addr = 0; wr_data = 0;
        for (i = 0; i < 32; i = i + 1) m_mem[i] = 64'h0;
        rst_n = 0; repeat(4) @(posedge clk); rst_n = 1; repeat(2) @(posedge clk);

        // TEST 1: reset clears all registers (deterministic sim start)
        $display("\n--- TEST 1: Reset state ---");
        check(rd_data1, 64'h0, "port1 x0 reads 0 after reset");
        rd_addr1 = 5'd17; rd_addr2 = 5'd31;
        #1;
        check(rd_data1, 64'h0, "port1 x17 reads 0 after reset");
        check(rd_data2, 64'h0, "port2 x31 reads 0 after reset");

        // TEST 2: basic write then read on both ports
        $display("\n--- TEST 2: Write/readback ---");
        @(posedge clk); #1; wr_en = 1; wr_addr = 5'd17; wr_data = 64'hDEAD_BEEF_1234_5678;
        @(posedge clk); #1; wr_en = 0;
        m_mem[17] = 64'hDEAD_BEEF_1234_5678;
        rd_addr1 = 5'd17; rd_addr2 = 5'd17; #1;
        check(rd_data1, 64'hDEAD_BEEF_1234_5678, "port1 reads back x17");
        check(rd_data2, 64'hDEAD_BEEF_1234_5678, "port2 reads back x17");

        // TEST 3: x0 write dropped, x0 always zero
        $display("\n--- TEST 3: x0 hardwired ---");
        @(posedge clk); #1; wr_en = 1; wr_addr = 5'h0; wr_data = 64'hFFFF_FFFF_FFFF_FFFF;
        @(posedge clk); #1; wr_en = 0;
        rd_addr1 = 5'h0; #1;
        check(rd_data1, 64'h0, "write to x0 ignored, reads 0");

        // TEST 4: write-first bypass — read of written register THIS edge
        $display("\n--- TEST 4: Write-first bypass ---");
        rd_addr1 = 5'd9; rd_addr2 = 5'd9;
        @(posedge clk); #1; wr_en = 1; wr_addr = 5'd9; wr_data = 64'hCAFE_BABE_0000_0001;
        #1; // combinational bypass visible mid-cycle, before the edge commits it
        check(rd_data1, 64'hCAFE_BABE_0000_0001, "port1 bypass during write");
        check(rd_data2, 64'hCAFE_BABE_0000_0001, "port2 bypass during write");
        check(m_read(5'd9), 64'hCAFE_BABE_0000_0001, "model agrees on bypass value");
        m_mem[9] = wr_data;
        @(posedge clk); #1; wr_en = 0;
        check(rd_data1, 64'hCAFE_BABE_0000_0001, "value committed after edge");

        // TEST 5: bypass does NOT leak to a different register
        $display("\n--- TEST 5: No cross-register bypass ---");
        rd_addr1 = 5'd10; #1;
        check(rd_data1, 64'h0, "x10 unaffected by x9 write");

        // TEST 6: randomized traffic vs shadow model — every cycle, both
        // ports' outputs must match the model exactly (bypass included).
        $display("\n--- TEST 6: Randomized vs shadow model ---");
        begin : randblk
            integer k, n_err;
            n_err = 0;
            for (k = 0; k < 3000; k = k + 1) begin
                @(negedge clk);              // settle mid-cycle, away from edges
                wr_en   = (($random & 3) != 0);          // ~75% write attempt
                wr_addr = $random & 5'h1F;               // includes x0 attempts
                wr_data = {$random, $random};
                rd_addr1 = $random & 5'h1F;
                rd_addr2 = $random & 5'h1F;
                #1;
                if (rd_data1 !== m_read(rd_addr1)) begin
                    $display("FAIL [%0t] rnd[%0d] port1 x%0d got=0x%X exp=0x%X",
                             $time, k, rd_addr1, rd_data1, m_read(rd_addr1));
                    n_err = n_err + 1;
                end
                if (rd_data2 !== m_read(rd_addr2)) begin
                    $display("FAIL [%0t] rnd[%0d] port2 x%0d got=0x%X exp=0x%X",
                             $time, k, rd_addr2, rd_data2, m_read(rd_addr2));
                    n_err = n_err + 1;
                end
                @(posedge clk);
                if (wr_en && wr_addr != 5'h0)
                    m_mem[wr_addr] <= wr_data;   // model commits at same edge as DUT
            end
            wr_en = 0;
            if (n_err == 0)
                $display("PASS [%0t] 3000 randomized cycles match shadow model", $time);
            error_count = error_count + n_err;
        end

        $display("\n==============================");
        if (error_count == 0)
            $display("RV_REGFILE VERDICT: ✅ PASS — All tests passed");
        else
            $display("RV_REGFILE VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #500_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

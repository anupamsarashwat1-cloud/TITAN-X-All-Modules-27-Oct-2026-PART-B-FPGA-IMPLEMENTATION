// SPDX-License-Identifier: Apache-2.0
// Brand-New Fresh Self-Checking Testbench for rv_regfile
// Generated from prd.json architectural specification

`timescale 1ns/1ps

module tb_fresh_rv_regfile;
    reg         clk;
    reg         rst_n;
    reg  [4:0]  rd_addr1;
    wire [63:0] rd_data1;
    reg  [4:0]  rd_addr2;
    wire [63:0] rd_data2;
    reg         wr_en;
    reg  [4:0]  wr_addr;
    reg  [63:0] wr_data;

    integer err_cnt = 0;
    integer test_cnt = 0;
    integer i;

    // Device Under Test
    rv_regfile dut (
        .clk(clk),
        .rst_n(rst_n),
        .rd_addr1(rd_addr1),
        .rd_data1(rd_data1),
        .rd_addr2(rd_addr2),
        .rd_data2(rd_data2),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data)
    );

    // Clock generation (10ns period -> 100MHz)
    always #5 clk = ~clk;

    initial begin
        $dumpfile("verification_waves/rv_regfile.vcd");
        $dumpvars(0, tb_fresh_rv_regfile);

        // Initialize signals
        clk = 0;
        rst_n = 1;
        rd_addr1 = 5'd0;
        rd_addr2 = 5'd0;
        wr_en = 0;
        wr_addr = 5'd0;
        wr_data = 64'd0;

        $display("=== STARTING FRESH SELF-CHECKING VERIFICATION: rv_regfile ===");

        // Test 1: Asynchronous Reset Verification
        test_cnt = test_cnt + 1;
        #2 rst_n = 0;
        #10 rst_n = 1;
        #1;
        for (i = 0; i < 32; i = i + 1) begin
            rd_addr1 = i[4:0];
            #1;
            if (rd_data1 !== 64'h0) begin
                $display("ERROR [T1]: Register x%0d not zero after reset! Got %h", i, rd_data1);
                err_cnt = err_cnt + 1;
            end
        end
        if (err_cnt == 0) $display("PASS [T1]: Reset cleared all 32 GPRs to 0");

        // Test 2: Read x0 hardwire check
        test_cnt = test_cnt + 1;
        rd_addr1 = 5'd0;
        rd_addr2 = 5'd0;
        #2;
        if (rd_data1 !== 64'h0 || rd_data2 !== 64'h0) begin
            $display("ERROR [T2]: x0 read non-zero: rd_data1=%h, rd_data2=%h", rd_data1, rd_data2);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T2]: x0 returns 0 on both read ports");
        end

        // Test 3: Write to x0 must be ignored
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        wr_en = 1;
        wr_addr = 5'd0;
        wr_data = 64'hDEAD_BEEF_CAFE_BABE;
        @(posedge clk); #1;
        wr_en = 0;
        #1;
        rd_addr1 = 5'd0;
        rd_addr2 = 5'd0;
        #2;
        if (rd_data1 !== 64'h0 || rd_data2 !== 64'h0) begin
            $display("ERROR [T3]: x0 was overwritten! rd_data1=%h", rd_data1);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T3]: Write to x0 was successfully ignored");
        end

        // Test 4: Write all registers x1 to x31 with distinct patterns and read back
        test_cnt = test_cnt + 1;
        for (i = 1; i < 32; i = i + 1) begin
            @(posedge clk); #1;
            wr_en = 1;
            wr_addr = i[4:0];
            wr_data = (64'hA5A5_0000_0000_0000) ^ (64'd1 << i) ^ (64'h55AA_55AA * i);
        end
        @(posedge clk); #1;
        wr_en = 0;
        #5;

        // Verify all 31 registers across both read ports
        for (i = 1; i < 32; i = i + 1) begin
            rd_addr1 = i[4:0];
            rd_addr2 = 32 - i;
            #2;
            if (rd_data1 !== ((64'hA5A5_0000_0000_0000) ^ (64'd1 << i) ^ (64'h55AA_55AA * i))) begin
                $display("ERROR [T4]: Port 1 read mismatch on x%0d: got %h, expected %h",
                         i, rd_data1, ((64'hA5A5_0000_0000_0000) ^ (64'd1 << i) ^ (64'h55AA_55AA * i)));
                err_cnt = err_cnt + 1;
            end
            if (rd_data2 !== ((64'hA5A5_0000_0000_0000) ^ (64'd1 << (32 - i)) ^ (64'h55AA_55AA * (32 - i)))) begin
                $display("ERROR [T4]: Port 2 read mismatch on x%0d: got %h, expected %h",
                         32 - i, rd_data2, ((64'hA5A5_0000_0000_0000) ^ (64'd1 << (32 - i)) ^ (64'h55AA_55AA * (32 - i))));
                err_cnt = err_cnt + 1;
            end
        end
        if (err_cnt == 0) $display("PASS [T4]: Verified all 31 registers with unique 64-bit patterns on dual read ports");

        // Test 5: Internal Write-First Bypass Verification
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        wr_en = 1;
        wr_addr = 5'd14;
        wr_data = 64'hFEED_FACE_CAFE_D00D;
        rd_addr1 = 5'd14;
        rd_addr2 = 5'd14;
        #1; // Combinational evaluation before posedge
        if (rd_data1 !== 64'hFEED_FACE_CAFE_D00D || rd_data2 !== 64'hFEED_FACE_CAFE_D00D) begin
            $display("ERROR [T5]: Write-first bypass failed! rd_data1=%h, rd_data2=%h", rd_data1, rd_data2);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T5]: Write-first bypass confirmed combinationally on both ports");
        end

        // Test 6: Bypass suppression on x0 write
        test_cnt = test_cnt + 1;
        wr_en = 1;
        wr_addr = 5'd0;
        wr_data = 64'hFFFF_FFFF_FFFF_FFFF;
        rd_addr1 = 5'd0;
        rd_addr2 = 5'd0;
        #1;
        if (rd_data1 !== 64'h0 || rd_data2 !== 64'h0) begin
            $display("ERROR [T6]: Bypass leaked into x0 read! rd_data1=%h", rd_data1);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T6]: Bypass correctly suppressed for x0");
        end

        @(posedge clk); #1;
        wr_en = 0;
        #20;

        $display("=== VERIFICATION SUMMARY ===");
        $display("Total Tests Executed: %0d", test_cnt);
        $display("Total Errors: %0d", err_cnt);

        if (err_cnt == 0) begin
            $display("ALL TESTS PASSED: rv_regfile 100%% VERIFIED");
        end else begin
            $display("VERIFICATION FAILED: %0d errors detected!", err_cnt);
        end
        $finish;
    end
endmodule

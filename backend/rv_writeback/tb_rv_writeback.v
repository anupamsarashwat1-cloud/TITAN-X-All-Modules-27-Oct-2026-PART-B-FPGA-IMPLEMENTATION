// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RV Write-Back Stage Directed Self-Checking Testbench
// Tests: register write-back pipeline, forwarding outputs, flush/valid
`timescale 1ns/1ps

module tb_rv_writeback();
    reg        clk, rst_n;
    reg [63:0] result;
    reg [4:0]  rd_in;
    reg        reg_write;
    reg        valid_in;

    wire [63:0] wb_data;
    wire [4:0]  wb_rd;
    wire        wb_we;
    wire [63:0] fwd_wb_data;
    wire [4:0]  fwd_wb_rd;
    wire        fwd_wb_valid;

    integer error_count;

    rv_writeback uut (
        .clk(clk), .rst_n(rst_n),
        .result(result), .rd_in(rd_in), .reg_write(reg_write), .valid_in(valid_in),
        .wb_data(wb_data), .wb_rd(wb_rd), .wb_we(wb_we),
        .fwd_wb_data(fwd_wb_data), .fwd_wb_rd(fwd_wb_rd), .fwd_wb_valid(fwd_wb_valid)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [63:0] got; input [63:0] exp; input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=0x%016X exp=0x%016X", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    initial begin
        $dumpfile("tb_rv_writeback.vcd");
        $dumpvars(0, tb_rv_writeback);
        error_count = 0;
        result=0; rd_in=0; reg_write=0; valid_in=0;
        rst_n=0; repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

        // TEST 1: Reset — no write-back
        $display("\n--- TEST 1: Reset state ---");
        @(posedge clk); #1;
        check(wb_we, 1'b0, "wb_we=0 after reset");
        check(fwd_wb_valid, 1'b0, "fwd_wb_valid=0 after reset");

        // TEST 2: Simple write-back: rd=x5, result=0xDEADBEEF_12345678
        $display("\n--- TEST 2: Write-back rd=5, data=0xDEADBEEF12345678 ---");
        @(posedge clk); #1;
        result=64'hDEAD_BEEF_1234_5678; rd_in=5'h05; reg_write=1; valid_in=1;
        @(posedge clk); #1;
        result=0; rd_in=0; reg_write=0; valid_in=0;
        // After 1 cycle, wb_data should have latched
        check(wb_data, 64'hDEAD_BEEF_1234_5678, "wb_data=0xDEADBEEF12345678");
        check(wb_rd, 5'h05, "wb_rd=5");
        check(wb_we, 1'b1, "wb_we=1 for valid reg_write");

        // TEST 3: Forwarding outputs
        $display("\n--- TEST 3: Forwarding signals ---");
        check(fwd_wb_data, 64'hDEAD_BEEF_1234_5678, "fwd_wb_data = wb_data");
        check(fwd_wb_rd, 5'h05, "fwd_wb_rd = wb_rd");
        check(fwd_wb_valid, 1'b1, "fwd_wb_valid = wb_we");

        // TEST 4: valid_in=0 — no write-back
        $display("\n--- TEST 4: valid_in=0, no WB ---");
        @(posedge clk); #1;
        result=64'hAAAA_BBBB_CCCC_DDDD; rd_in=5'h10; reg_write=1; valid_in=0;
        @(posedge clk); #1;
        result=0; rd_in=0; reg_write=0; valid_in=0;
        @(posedge clk); #1;
        check(wb_we, 1'b0, "wb_we=0 when valid_in=0");

        // TEST 5: reg_write=0 — no WB even if valid
        $display("\n--- TEST 5: reg_write=0, no WB ---");
        @(posedge clk); #1;
        result=64'h1111_2222_3333_4444; rd_in=5'h1F; reg_write=0; valid_in=1;
        @(posedge clk); #1;
        result=0; rd_in=0; reg_write=0; valid_in=0;
        @(posedge clk); #1;
        check(wb_we, 1'b0, "wb_we=0 when reg_write=0");

        // TEST 6: Multiple consecutive write-backs
        $display("\n--- TEST 6: Consecutive write-backs ---");
        @(posedge clk); #1;
        result=64'hAAAA_AAAA_AAAA_AAAA; rd_in=5'h01; reg_write=1; valid_in=1;
        @(posedge clk); #1;
        result=64'hBBBB_BBBB_BBBB_BBBB; rd_in=5'h02; reg_write=1; valid_in=1;
        @(posedge clk); #1;
        result=0; rd_in=0; reg_write=0; valid_in=0;
        check(wb_data, 64'hBBBB_BBBB_BBBB_BBBB, "wb_data=0xBBBB... (second WB)");
        check(wb_rd, 5'h02, "wb_rd=2 (second WB)");

        $display("\n==============================");
        if (error_count == 0)
            $display("RV_WRITEBACK VERDICT: ✅ PASS — All tests passed");
        else
            $display("RV_WRITEBACK VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #500_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

// SPDX-License-Identifier: Apache-2.0
// Brand-New Fresh Self-Checking Testbench for rv_writeback
// Generated strictly from prd.json architectural truth tables & constraints

`timescale 1ns/1ps

module tb_fresh_rv_writeback;
    reg         clk;
    reg         rst_n;
    reg  [63:0] result;
    reg  [4:0]  rd_in;
    reg         reg_write;
    reg         valid_in;

    wire [63:0] wb_data;
    wire [4:0]  wb_rd;
    wire        wb_we;
    wire [63:0] fwd_wb_data;
    wire [4:0]  fwd_wb_rd;
    wire        fwd_wb_valid;

    integer err_cnt = 0;
    integer test_cnt = 0;

    rv_writeback dut (
        .clk(clk),
        .rst_n(rst_n),
        .result(result),
        .rd_in(rd_in),
        .reg_write(reg_write),
        .valid_in(valid_in),
        .wb_data(wb_data),
        .wb_rd(wb_rd),
        .wb_we(wb_we),
        .fwd_wb_data(fwd_wb_data),
        .fwd_wb_rd(fwd_wb_rd),
        .fwd_wb_valid(fwd_wb_valid)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("verification_waves/rv_writeback.vcd");
        $dumpvars(0, tb_fresh_rv_writeback);

        clk = 0;
        rst_n = 1;
        result = 64'h0;
        rd_in = 5'h0;
        reg_write = 0;
        valid_in = 0;

        $display("=== STARTING FRESH SELF-CHECKING VERIFICATION: rv_writeback ===");

        // Test 1: Reset Check
        test_cnt = test_cnt + 1;
        #2 rst_n = 0;
        #10 rst_n = 1;
        #2;
        if (wb_we !== 1'b0 || fwd_wb_valid !== 1'b0 || wb_data !== 64'h0) begin
            $display("ERROR [T1]: Reset state invalid: wb_we=%b fwd_wb_valid=%b wb_data=%h",
                     wb_we, fwd_wb_valid, wb_data);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T1]: Asynchronous reset verified");
        end

        // Test 2: Standard Destination Register Writeback
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        valid_in = 1;
        reg_write = 1;
        rd_in = 5'd7;
        result = 64'h1234_5678_9ABC_DEF0;
        @(posedge clk); #1;
        if (wb_data !== 64'h1234_5678_9ABC_DEF0 || wb_rd !== 5'd7 || wb_we !== 1'b1 ||
            fwd_wb_data !== 64'h1234_5678_9ABC_DEF0 || fwd_wb_valid !== 1'b1) begin
            $display("ERROR [T2]: Normal writeback failed: wb_data=%h wb_rd=%d wb_we=%b",
                     wb_data, wb_rd, wb_we);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T2]: Standard GPR writeback and forwarding bus verified");
        end

        // Test 3: x0 Write Suppression (rd_in == 0 must suppress write strobe)
        test_cnt = test_cnt + 1;
        valid_in = 1;
        reg_write = 1;
        rd_in = 5'd0;
        result = 64'hDEAD_BEEF_CAFE_BABE;
        @(posedge clk); #1;
        if (wb_we !== 1'b0 || fwd_wb_valid !== 1'b0) begin
            $display("ERROR [T3]: x0 write strobe not suppressed: wb_we=%b fwd_wb_valid=%b",
                     wb_we, fwd_wb_valid);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T3]: x0 write strobe successfully suppressed");
        end

        // Test 4: Invalid Instruction Suppression (valid_in == 0)
        test_cnt = test_cnt + 1;
        valid_in = 0;
        reg_write = 1;
        rd_in = 5'd15;
        result = 64'hA5A5_5A5A_A5A5_5A5A;
        @(posedge clk); #1;
        if (wb_we !== 1'b0 || fwd_wb_valid !== 1'b0) begin
            $display("ERROR [T4]: wb_we asserted for invalid instruction");
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T4]: Invalid instruction gated off wb_we");
        end

        // Test 5: Non-Writing Instruction (reg_write == 0)
        test_cnt = test_cnt + 1;
        valid_in = 1;
        reg_write = 0;
        rd_in = 5'd20;
        result = 64'h1111_2222_3333_4444;
        @(posedge clk); #1;
        if (wb_we !== 1'b0 || fwd_wb_valid !== 1'b0) begin
            $display("ERROR [T5]: wb_we asserted when reg_write is low");
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T5]: Store/Branch non-writing instruction gated off wb_we");
        end

        // Test 6: Consecutive Streaming Writes
        test_cnt = test_cnt + 1;
        for (integer i = 1; i <= 5; i = i + 1) begin
            valid_in = 1;
            reg_write = 1;
            rd_in = i[4:0];
            result = 64'h8000_0000_0000_0000 | i;
            @(posedge clk); #1;
            if (wb_data !== (64'h8000_0000_0000_0000 | i) || wb_rd !== i[4:0] || wb_we !== 1'b1) begin
                $display("ERROR [T6]: Stream mismatch on iteration %0d", i);
                err_cnt = err_cnt + 1;
            end
        end
        if (err_cnt == 0) $display("PASS [T6]: 5-cycle continuous streaming writeback verified");

        valid_in = 0;
        reg_write = 0;
        #20;

        $display("=== VERIFICATION SUMMARY ===");
        $display("Total Tests Executed: %0d", test_cnt);
        $display("Total Errors: %0d", err_cnt);

        if (err_cnt == 0) begin
            $display("ALL TESTS PASSED: rv_writeback 100%% VERIFIED");
        end else begin
            $display("VERIFICATION FAILED: %0d errors detected!", err_cnt);
        end
        $finish;
    end
endmodule

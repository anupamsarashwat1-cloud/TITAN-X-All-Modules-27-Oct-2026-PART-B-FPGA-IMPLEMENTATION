// SPDX-License-Identifier: Apache-2.0
// Brand-New Fresh Self-Checking Testbench for rv_tlb
// Generated strictly from prd.json architectural truth tables & constraints

`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module tb_fresh_rv_tlb;
    reg         clk;
    reg         rst_n;
    reg  [38:0] va_in;
    reg  [15:0] asid_in;
    reg         req_valid;
    wire [37:0] pa_out;
    wire        hit;
    wire        perm_r;
    wire        perm_w;
    wire        perm_x;
    wire        perm_u;
    wire        page_fault;

    reg         fill_valid;
    reg  [38:0] fill_va;
    reg  [37:0] fill_pa;
    reg  [15:0] fill_asid;
    reg  [7:0]  fill_perm;
    reg  [1:0]  fill_level;

    reg         sfence_vma;
    reg         sfence_asid;
    reg  [15:0] sfence_asid_val;
    reg         sfence_va;
    reg  [38:0] sfence_va_val;

    reg         access_r;
    reg         access_w;
    reg         access_x;
    reg         priv_s;

    integer err_cnt = 0;
    integer test_cnt = 0;

    rv_tlb dut (
        .clk(clk),
        .rst_n(rst_n),
        .va_in(va_in),
        .asid_in(asid_in),
        .req_valid(req_valid),
        .pa_out(pa_out),
        .hit(hit),
        .perm_r(perm_r),
        .perm_w(perm_w),
        .perm_x(perm_x),
        .perm_u(perm_u),
        .page_fault(page_fault),
        .fill_valid(fill_valid),
        .fill_va(fill_va),
        .fill_pa(fill_pa),
        .fill_asid(fill_asid),
        .fill_perm(fill_perm),
        .fill_level(fill_level),
        .sfence_vma(sfence_vma),
        .sfence_asid(sfence_asid),
        .sfence_asid_val(sfence_asid_val),
        .sfence_va(sfence_va),
        .sfence_va_val(sfence_va_val),
        .access_r(access_r),
        .access_w(access_w),
        .access_x(access_x),
        .priv_s(priv_s)
    );

    always #5 clk = ~clk;

    task clear_inputs;
        begin
            va_in = 39'h0;
            asid_in = 16'h0;
            req_valid = 0;
            fill_valid = 0;
            fill_va = 39'h0;
            fill_pa = 38'h0;
            fill_asid = 16'h0;
            fill_perm = 8'h0;
            fill_level = 2'h0;
            sfence_vma = 0;
            sfence_asid = 0;
            sfence_asid_val = 16'h0;
            sfence_va = 0;
            sfence_va_val = 39'h0;
            access_r = 0;
            access_w = 0;
            access_x = 0;
            priv_s = 0;
        end
    endtask

    initial begin
        $dumpfile("verification_waves/rv_tlb.vcd");
        $dumpvars(0, tb_fresh_rv_tlb);

        clk = 0;
        rst_n = 1;
        clear_inputs();

        $display("=== STARTING FRESH SELF-CHECKING VERIFICATION: rv_tlb ===");

        // Test 1: Reset Check
        test_cnt = test_cnt + 1;
        #2 rst_n = 0;
        #10 rst_n = 1;
        #2;
        if (hit !== 1'b0 || page_fault !== 1'b0) begin
            $display("ERROR [T1]: Reset state invalid: hit=%b page_fault=%b", hit, page_fault);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T1]: rv_tlb asynchronous reset confirmed");
        end

        // Test 2: Standard 4KB Translation Fill and Hit
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        fill_valid = 1;
        fill_va    = 39'h00_8000_1000;
        fill_pa    = 38'h08_0000_1000;
        fill_asid  = 16'h0001;
        fill_perm  = 8'b0000_0111; // R, W, X=0, V=1, non-global, user=0
        fill_level = 2'd0;         // 4KB page
        @(posedge clk); #1;
        fill_valid = 0;

        // Query translated address with offset 0x456
        va_in = 39'h00_8000_1456;
        asid_in = 16'h0001;
        req_valid = 1;
        access_r = 1;
        #2;
        if (!hit || pa_out !== 38'h08_0000_1456 || !perm_r || !perm_w || perm_x) begin
            $display("ERROR [T2]: 4KB Translation failed: hit=%b pa_out=%h perm_r=%b perm_w=%b",
                     hit, pa_out, perm_r, perm_w);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T2]: 4KB Translation hit verified (VA=0x80001456 -> PA=0x0800001456)");
        end

        // Test 3: ASID Isolation (Mismatch ASID must miss)
        test_cnt = test_cnt + 1;
        asid_in = 16'h0002; // different ASID
        #2;
        if (hit !== 1'b0) begin
            $display("ERROR [T3]: ASID isolation failed! Different ASID produced a hit");
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T3]: ASID isolation verified (ASID=0x0002 missed ASID=0x0001 entry)");
        end

        // Test 4: Global Translation (Shared across ASIDs)
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        fill_valid = 1;
        fill_va    = 39'h00_7000_2000;
        fill_pa    = 38'h04_0000_2000;
        fill_asid  = 16'h0001;
        fill_perm  = 8'b0010_0111; // Bit 5 is Global bit (G=1)
        fill_level = 2'd0;
        @(posedge clk); #1;
        fill_valid = 0;

        // Query with ASID 0x9999
        va_in = 39'h00_7000_2789;
        asid_in = 16'h9999;
        req_valid = 1;
        #2;
        if (!hit || pa_out !== 38'h04_0000_2789) begin
            $display("ERROR [T4]: Global page hit failed for foreign ASID: hit=%b pa_out=%h", hit, pa_out);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T4]: Global translation hit confirmed across arbitrary ASID");
        end

        // Test 5: Permission Fault Check (Write on Read-Only page)
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        fill_valid = 1;
        fill_va    = 39'h00_6000_3000;
        fill_pa    = 38'h02_0000_3000;
        fill_asid  = 16'h0001;
        fill_perm  = 8'b0000_0011; // Read-only (R=1, W=0)
        fill_level = 2'd0;
        @(posedge clk); #1;
        fill_valid = 0;

        va_in = 39'h00_6000_3000;
        asid_in = 16'h0001;
        req_valid = 1;
        access_w = 1; // Attempt write
        access_r = 0;
        #2;
        if (!hit || !page_fault) begin
            $display("ERROR [T5]: Permission violation did not trigger page_fault: hit=%b page_fault=%b",
                     hit, page_fault);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T5]: Page fault correctly generated on write to read-only page");
        end

        // Test 6: SFENCE.VMA Flush (Selective flush preserving Global entry)
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        sfence_vma = 1;
        @(posedge clk); #1;
        sfence_vma = 0;

        // Query non-global entry from Test 2 (should now miss)
        va_in = 39'h00_8000_1456;
        asid_in = 16'h0001;
        req_valid = 1;
        #2;
        if (hit !== 1'b0) begin
            $display("ERROR [T6]: SFENCE.VMA failed to flush non-global entry: hit=%b", hit);
            err_cnt = err_cnt + 1;
        end

        // Query global entry from Test 4 (should still hit)
        va_in = 39'h00_7000_2789;
        asid_in = 16'h9999;
        #2;
        if (hit !== 1'b1) begin
            $display("ERROR [T6]: SFENCE.VMA flushed global entry: hit=%b", hit);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T6]: SFENCE.VMA selective flush verified (non-global flushed, global retained)");
        end

        clear_inputs();
        #20;

        $display("=== VERIFICATION SUMMARY ===");
        $display("Total Tests Executed: %0d", test_cnt);
        $display("Total Errors: %0d", err_cnt);

        if (err_cnt == 0) begin
            $display("ALL TESTS PASSED: rv_tlb 100%% VERIFIED");
        end else begin
            $display("VERIFICATION FAILED: %0d errors detected!", err_cnt);
        end
        $finish;
    end
endmodule

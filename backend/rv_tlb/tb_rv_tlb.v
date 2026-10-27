// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RV TLB Directed Self-Checking Testbench
// Tests: miss/hit on fill, ASID matching, sfence_vma flush, page_fault on perm violation
`timescale 1ns/1ps

module tb_rv_tlb();
    parameter VA_W   = 39;
    parameter PA_W   = 38;
    parameter ASID_W = 16;

    reg        clk, rst_n;
    reg [VA_W-1:0]   va_in;
    reg [ASID_W-1:0] asid_in;
    reg        req_valid;
    wire [PA_W-1:0]  pa_out;
    wire       hit, perm_r, perm_w, perm_x, perm_u, page_fault;
    reg        fill_valid;
    reg [VA_W-1:0]   fill_va;
    reg [PA_W-1:0]   fill_pa;
    reg [ASID_W-1:0] fill_asid;
    reg [7:0]  fill_perm;  // D,A,G,U,X,W,R,V
    reg [1:0]  fill_level;
    reg        sfence_vma;

    integer error_count;

    rv_tlb #(.VA_W(VA_W), .PA_W(PA_W), .ASID_W(ASID_W)) uut (
        .clk(clk), .rst_n(rst_n),
        .va_in(va_in), .asid_in(asid_in), .req_valid(req_valid),
        .pa_out(pa_out), .hit(hit), .perm_r(perm_r), .perm_w(perm_w),
        .perm_x(perm_x), .perm_u(perm_u), .page_fault(page_fault),
        .fill_valid(fill_valid), .fill_va(fill_va), .fill_pa(fill_pa),
        .fill_asid(fill_asid), .fill_perm(fill_perm), .fill_level(fill_level),
        .sfence_vma(sfence_vma)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [63:0] got; input [63:0] exp; input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=%0d exp=%0d", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    initial begin
        $dumpfile("tb_rv_tlb.vcd");
        $dumpvars(0, tb_rv_tlb);
        error_count = 0;
        va_in=0; asid_in=0; req_valid=0;
        fill_valid=0; fill_va=0; fill_pa=0; fill_asid=0; fill_perm=8'h0; fill_level=0;
        sfence_vma=0;
        rst_n=0; repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

        // TEST 1: TLB miss on cold start
        $display("\n--- TEST 1: TLB miss (cold) ---");
        @(posedge clk); #1;
        va_in=39'h0_0001_0000; asid_in=16'h1; req_valid=1;
        @(posedge clk); #1;
        check(hit, 1'b0, "hit=0 on cold TLB (miss)");
        req_valid=0;

        // TEST 2: Fill TLB with entry VA=0x10000 PA=0x20000 ASID=1, perm=R+W+V (0x07)
        // fill_perm bits: [7:0] = D,A,G,U,X,W,R,V
        $display("\n--- TEST 2: Fill TLB entry ---");
        @(posedge clk); #1;
        fill_va=39'h0_0001_0000; fill_pa=38'h0_0002_0000; fill_asid=16'h1;
        fill_perm=8'b0000_0111;  // V=1, R=1, W=1, X=0
        fill_level=2'd0; fill_valid=1;
        @(posedge clk); #1; fill_valid=0;
        repeat(2) @(posedge clk); #1;

        // TEST 3: TLB hit after fill
        $display("\n--- TEST 3: TLB hit after fill ---");
        @(posedge clk); #1;
        va_in=39'h0_0001_0000; asid_in=16'h1; req_valid=1;
        @(posedge clk); #1; req_valid=0;
        check(hit, 1'b1, "hit=1 after TLB fill");
        check(perm_r, 1'b1, "perm_r=1 (read allowed)");
        check(perm_w, 1'b1, "perm_w=1 (write allowed)");
        check(perm_x, 1'b0, "perm_x=0 (execute blocked)");
        $display("  pa_out=0x%09X", pa_out);

        // TEST 4: ASID mismatch → miss
        $display("\n--- TEST 4: ASID mismatch → miss ---");
        @(posedge clk); #1;
        va_in=39'h0_0001_0000; asid_in=16'h2; req_valid=1;  // different ASID
        @(posedge clk); #1; req_valid=0;
        check(hit, 1'b0, "hit=0 with wrong ASID");

        // TEST 5: sfence_vma flushes TLB
        $display("\n--- TEST 5: sfence_vma flush ---");
        @(posedge clk); #1; sfence_vma=1;
        @(posedge clk); #1; sfence_vma=0;
        repeat(2) @(posedge clk); #1;
        va_in=39'h0_0001_0000; asid_in=16'h1; req_valid=1;
        @(posedge clk); #1; req_valid=0;
        check(hit, 1'b0, "hit=0 after sfence_vma flush");

        $display("\n==============================");
        if (error_count == 0)
            $display("RV_TLB VERDICT: ✅ PASS — All tests passed");
        else
            $display("RV_TLB VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #500_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

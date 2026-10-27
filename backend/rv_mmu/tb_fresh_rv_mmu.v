// SPDX-License-Identifier: Apache-2.0
// Fresh, self-checking testbench for rv_mmu module
// SMVDU-TITAN-X Microprocessor Verification Suite
`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module tb_fresh_rv_mmu;
    reg         clk;
    reg         rst_n;

    reg  [63:0] satp;
    reg  [1:0]  priv_mode;

    reg  [63:0] va_req;
    reg         req_valid;
    reg         req_r;
    reg         req_w;
    reg         req_x;

    wire [39:0] pa_out;
    wire        trans_valid;
    wire        trans_busy;

    wire        page_fault;
    wire [63:0] fault_va;

    wire        ptw_arvalid;
    reg         ptw_arready;
    wire [39:0] ptw_araddr;
    reg         ptw_rvalid;
    wire        ptw_rready;
    reg  [63:0] ptw_rdata;
    reg  [1:0]  ptw_rresp;

    reg         sfence_vma;
    reg         sfence_asid_en;
    reg         sfence_va_en;
    reg  [63:0] sfence_va_val;
    reg  [63:0] sfence_asid_val;

    integer tests_passed = 0;
    integer tests_failed = 0;

    // Clock: 100MHz (10ns period)
    always #5 clk = ~clk;

    // Instantiate DUT
    rv_mmu dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .satp           (satp),
        .priv_mode      (priv_mode),
        .va_req         (va_req),
        .req_valid      (req_valid),
        .req_r          (req_r),
        .req_w          (req_w),
        .req_x          (req_x),
        .pa_out         (pa_out),
        .trans_valid    (trans_valid),
        .trans_busy     (trans_busy),
        .page_fault     (page_fault),
        .fault_va       (fault_va),
        .ptw_arvalid    (ptw_arvalid),
        .ptw_arready    (ptw_arready),
        .ptw_araddr     (ptw_araddr),
        .ptw_rvalid     (ptw_rvalid),
        .ptw_rready     (ptw_rready),
        .ptw_rdata      (ptw_rdata),
        .ptw_rresp      (ptw_rresp),
        .sfence_vma     (sfence_vma),
        .sfence_asid_en (sfence_asid_en),
        .sfence_va_en   (sfence_va_en),
        .sfence_va_val  (sfence_va_val),
        .sfence_asid_val(sfence_asid_val)
    );

    task check(input [255:0] test_name, input condition);
        begin
            if (condition) begin
                $display("[PASS] %0s", test_name);
                tests_passed = tests_passed + 1;
            end else begin
                $display("[FAIL] %0s", test_name);
                tests_failed = tests_failed + 1;
            end
        end
    endtask

    // Helper task to service PTW memory read
    task reply_ptw_pte(input [63:0] pte_val);
        begin
            while (!ptw_arvalid) @(posedge clk);
            @(posedge clk); #1;
            ptw_arready = 1'b1;
            @(posedge clk); #1;
            ptw_arready = 1'b0;

            @(posedge clk); #1;
            ptw_rvalid = 1'b1;
            ptw_rdata  = pte_val;
            ptw_rresp  = 2'b00;
            @(posedge clk); #1;
            ptw_rvalid = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("verification_waves/rv_mmu.vcd");
        $dumpvars(0, tb_fresh_rv_mmu);

        clk             = 0;
        rst_n           = 0;
        satp            = 64'h0;
        priv_mode       = `PRIV_M;
        va_req          = 64'h0;
        req_valid       = 0;
        req_r           = 0;
        req_w           = 0;
        req_x           = 0;
        ptw_arready     = 0;
        ptw_rvalid      = 0;
        ptw_rdata       = 0;
        ptw_rresp       = 0;
        sfence_vma      = 0;
        sfence_asid_en  = 0;
        sfence_va_en    = 0;
        sfence_va_val   = 0;
        sfence_asid_val = 0;

        // Reset
        #20;
        @(posedge clk); #1;
        rst_n = 1;

        // ----------------------------------------------------
        // Test 1: Reset State
        // ----------------------------------------------------
        @(posedge clk); #1;
        check("Test 1.1: Reset trans_valid == 0", trans_valid == 1'b0);
        check("Test 1.2: Reset trans_busy == 0", trans_busy == 1'b0);
        check("Test 1.3: Reset page_fault == 0", page_fault == 1'b0);
        check("Test 1.4: Reset ptw_arvalid == 0", ptw_arvalid == 1'b0);

        // ----------------------------------------------------
        // Test 2: Bare Mode Direct Passthrough (M-Mode)
        // ----------------------------------------------------
        @(posedge clk); #1;
        priv_mode = `PRIV_M;
        satp      = 64'h0;
        va_req    = 64'h0000_0080_0000_1234;
        req_valid = 1'b1;
        req_r     = 1'b1;

        #1;
        check("Test 2.1: Bare mode trans_valid immediate", trans_valid == 1'b1);
        check("Test 2.2: Bare mode trans_busy is 0", trans_busy == 1'b0);
        check("Test 2.3: Bare mode pa_out equals va_req", pa_out == 40'h80_0000_1234);
        req_valid = 1'b0;

        // ----------------------------------------------------
        // Test 3: Sv39 Activation & Cold TLB Miss with PTW Walk
        // Mode = 8, ASID = 1, Root PPN = 0x80000
        // VA = 0x0000_0000_1000_0ABC
        // ----------------------------------------------------
        @(posedge clk); #1;
        priv_mode = `PRIV_S;
        satp      = {4'd8, 16'h0001, 44'h80000};
        va_req    = 64'h0000_0000_1000_0ABC; // vpn2=0, vpn1=0, vpn0=0x10, offset=0xABC
        req_valid = 1'b1;
        req_r     = 1'b1;

        @(posedge clk); #1;
        check("Test 3.1: Sv39 TLB miss asserts trans_busy", trans_busy == 1'b1);
        check("Test 3.2: PTW initiates memory walk", ptw_arvalid == 1'b1);

        // Service L2 read (non-leaf to L1 at PPN 0x80001)
        reply_ptw_pte({10'b0, 44'h0000_0080_001, 10'b0000000001});

        // Service L1 read (non-leaf to L0 at PPN 0x80002)
        reply_ptw_pte({10'b0, 44'h0000_0080_002, 10'b0000000001});

        // Service L0 read (valid 4KB leaf at physical PPN 0x90000 with R/W permissions: 0xCF)
        reply_ptw_pte({10'b0, 44'h0000_0090_000, 2'b00, 8'hCF});

        // PTW finishes and installs line into TLB
        check("Test 3.3: Translation valid asserted on PTW completion", trans_valid == 1'b1);
        req_valid = 1'b0;

        // ----------------------------------------------------
        // Test 4: Fast-Path TLB Hit (0-stall Translation)
        // Access address on the newly installed page: offset = 0xDEF
        // ----------------------------------------------------
        @(posedge clk); #1;
        va_req    = 64'h0000_0000_1000_0DEF;
        req_valid = 1'b1;
        req_r     = 1'b1;

        #1;
        check("Test 4.1: TLB hit gives trans_valid", trans_valid == 1'b1);
        check("Test 4.2: TLB hit trans_busy is 0", trans_busy == 1'b0);
        check("Test 4.3: Translated pa_out matches {PPN 0x90000, offset 0xDEF}",
              pa_out == 40'h00_9000_0DEF);
        req_valid = 1'b0;

        // ----------------------------------------------------
        // Test 5: Permission Violation on TLB Hit (Write to Read-Only Page)
        // Install read-only page at VA 0x2000_0000
        // ----------------------------------------------------
        @(posedge clk); #1;
        va_req    = 64'h0000_0000_2000_0000;
        req_valid = 1'b1;
        req_r     = 1'b1;

        @(posedge clk); #1;
        // Service walk: L2 non-leaf, L1 non-leaf, L0 leaf with Read-Only (R=1, W=0 -> 0xC3)
        reply_ptw_pte({10'b0, 44'h0000_0080_001, 10'b0000000001});
        reply_ptw_pte({10'b0, 44'h0000_0080_002, 10'b0000000001});
        reply_ptw_pte({10'b0, 44'h0000_0095_000, 2'b00, 8'hC3}); // R-only (W=0)
        req_valid = 1'b0;

        @(posedge clk); #1;
        // Now attempt store to this read-only page
        va_req    = 64'h0000_0000_2000_0008;
        req_valid = 1'b1;
        req_w     = 1'b1;
        req_r     = 1'b0;

        #1;
        check("Test 5.1: Store to Read-Only page triggers page_fault", page_fault == 1'b1);
        req_valid = 1'b0;
        req_w     = 1'b0;

        // ----------------------------------------------------
        // Test 6: SFENCE.VMA Invalidation
        // ----------------------------------------------------
        @(posedge clk); #1;
        sfence_vma = 1'b1;
        @(posedge clk); #1;
        sfence_vma = 1'b0;

        // After SFENCE, access to 0x1000_0ABC should MISS again and trigger PTW walk
        @(posedge clk); #1;
        va_req    = 64'h0000_0000_1000_0ABC;
        req_valid = 1'b1;
        req_r     = 1'b1;

        @(posedge clk); #1;
        check("Test 6.1: SFENCE cleared TLB, causing fresh PTW walk",
              trans_busy == 1'b1 && ptw_arvalid == 1'b1);

        req_valid = 1'b0;

        // ----------------------------------------------------
        // Final Scorecard
        // ----------------------------------------------------
        #20;
        $display("\n=======================================================");
        $display(" rv_mmu Verification Scorecard");
        $display(" Total Passed: %0d", tests_passed);
        $display(" Total Failed: %0d", tests_failed);
        $display("=======================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED] rv_mmu 100% verified.");
        end else begin
            $fatal(1, "[TESTBENCH FAILED] Found %0d failures.", tests_failed);
        end
        $finish;
    end
endmodule

// SPDX-License-Identifier: Apache-2.0
// Fresh, self-checking testbench for rv_ptw module
// SMVDU-TITAN-X Microprocessor Verification Suite
`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module tb_fresh_rv_ptw;
    reg         clk;
    reg         rst_n;

    reg  [38:0] va_req;
    reg  [15:0] asid_req;
    reg  [43:0] satp_ppn;
    reg         ptw_req;
    reg         access_r;
    reg         access_w;
    reg         access_x;
    reg         priv_s;
    wire        ptw_busy;

    wire        fill_valid;
    wire [38:0] fill_va;
    wire [37:0] fill_pa;
    wire [15:0] fill_asid;
    wire [7:0]  fill_perm;
    wire [1:0]  fill_level;

    wire        page_fault;
    wire [63:0] fault_addr;
    wire [1:0]  fault_type;

    wire        ptw_arvalid;
    reg         ptw_arready;
    wire [39:0] ptw_araddr;
    reg         ptw_rvalid;
    wire        ptw_rready;
    reg  [63:0] ptw_rdata;
    reg  [1:0]  ptw_rresp;

    integer tests_passed = 0;
    integer tests_failed = 0;

    // Clock: 100MHz (10ns period)
    always #5 clk = ~clk;

    // Instantiate DUT
    rv_ptw dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .va_req     (va_req),
        .asid_req   (asid_req),
        .satp_ppn   (satp_ppn),
        .ptw_req    (ptw_req),
        .access_r   (access_r),
        .access_w   (access_w),
        .access_x   (access_x),
        .priv_s     (priv_s),
        .ptw_busy   (ptw_busy),
        .fill_valid (fill_valid),
        .fill_va    (fill_va),
        .fill_pa    (fill_pa),
        .fill_asid  (fill_asid),
        .fill_perm  (fill_perm),
        .fill_level (fill_level),
        .page_fault (page_fault),
        .fault_addr (fault_addr),
        .fault_type (fault_type),
        .ptw_arvalid(ptw_arvalid),
        .ptw_arready(ptw_arready),
        .ptw_araddr (ptw_araddr),
        .ptw_rvalid (ptw_rvalid),
        .ptw_rready (ptw_rready),
        .ptw_rdata  (ptw_rdata),
        .ptw_rresp  (ptw_rresp)
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

    // Helper task to handshake PTW memory read
    task reply_pte(input [63:0] pte_val, input [1:0] resp_val);
        begin
            while (!ptw_arvalid) @(posedge clk);
            @(posedge clk); #1;
            ptw_arready = 1'b1;
            @(posedge clk); #1;
            ptw_arready = 1'b0;

            @(posedge clk); #1;
            ptw_rvalid = 1'b1;
            ptw_rdata  = pte_val;
            ptw_rresp  = resp_val;
            @(posedge clk); #1;
            ptw_rvalid = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("verification_waves/rv_ptw.vcd");
        $dumpvars(0, tb_fresh_rv_ptw);

        clk         = 0;
        rst_n       = 0;
        va_req      = 0;
        asid_req    = 0;
        satp_ppn    = 0;
        ptw_req     = 0;
        access_r    = 0;
        access_w    = 0;
        access_x    = 0;
        priv_s      = 0;
        ptw_arready = 0;
        ptw_rvalid  = 0;
        ptw_rdata   = 0;
        ptw_rresp   = 0;

        // Reset
        #20;
        @(posedge clk); #1;
        rst_n = 1;

        // ----------------------------------------------------
        // Test 1: Reset State
        // ----------------------------------------------------
        @(posedge clk); #1;
        check("Test 1.1: Reset ptw_busy == 0", ptw_busy == 1'b0);
        check("Test 1.2: Reset fill_valid == 0", fill_valid == 1'b0);
        check("Test 1.3: Reset page_fault == 0", page_fault == 1'b0);
        check("Test 1.4: Reset ptw_arvalid == 0", ptw_arvalid == 1'b0);

        // ----------------------------------------------------
        // Test 2: Standard 3-Level 4KB Page Table Walk (L2 -> L1 -> L0 -> Fill)
        // VA = 0x0000_0000_1234_5000 (vpn2=0, vpn1=0x91, vpn0=0x145, offset=0)
        // Root satp_ppn = 0x80000
        // ----------------------------------------------------
        @(posedge clk); #1;
        va_req   = 39'h00_1234_5000;
        asid_req = 16'h0001;
        satp_ppn = 44'h0000_0080_000;
        access_r = 1'b1;
        ptw_req  = 1'b1;

        @(posedge clk); #1;
        ptw_req = 1'b0;
        check("Test 2.1: PTW enters busy state", ptw_busy == 1'b1);
        check("Test 2.2: L2 read address matches root + vpn2*8",
              ptw_araddr == 40'h00_8000_0000);

        // L2 returns pointer to L1 table at PPN 0x80001 (non-leaf: V=1, R=0, X=0)
        reply_pte({10'b0, 44'h0000_0080_001, 10'b0000000001}, 2'b00);

        // L1 read address should be 0x8000_1000 + (vpn1=0x91 * 8 = 0x488) = 0x8000_1488
        while (!ptw_arvalid) @(posedge clk);
        check("Test 2.3: L1 read address matches L1 PPN + vpn1*8",
              ptw_araddr == 40'h00_8000_1488);

        // L1 returns pointer to L0 table at PPN 0x80002 (non-leaf: V=1, R=0, X=0)
        reply_pte({10'b0, 44'h0000_0080_002, 10'b0000000001}, 2'b00);

        // L0 read address should be 0x8000_2000 + (vpn0=0x145 * 8 = 0xA28) = 0x8000_2A28
        while (!ptw_arvalid) @(posedge clk);
        check("Test 2.4: L0 read address matches L0 PPN + vpn0*8",
              ptw_araddr == 40'h00_8000_2A28);

        // L0 returns valid 4KB leaf PTE with PPN 0x80050, R/W perms (V=1, R=1, W=1, U=1, A=1, D=1 -> 0xCF)
        reply_pte({10'b0, 44'h0000_0080_050, 2'b00, 8'hCF}, 2'b00);

        // Verify TLB fill output
        check("Test 2.5: fill_valid asserted on completion", fill_valid == 1'b1);
        check("Test 2.6: fill_level == 0 (4KB leaf)", fill_level == 2'd0);
        check("Test 2.7: fill_pa matches 38-bit physical page base", fill_pa == 38'h00_8005_0000);
        check("Test 2.8: fill_perm matches 0xCF", fill_perm == 8'hCF);
        check("Test 2.9: fill_asid matches 1", fill_asid == 16'h0001);
        check("Test 2.10: PTW returns to idle", ptw_busy == 1'b0);

        // ----------------------------------------------------
        // Test 3: 1GB Gigapage Early Leaf Termination at L2
        // VA = 0x0000_0040_0000_0000 (vpn2 = 1)
        // ----------------------------------------------------
        @(posedge clk); #1;
        va_req   = 39'h00_4000_0000;
        access_x = 1'b1;
        ptw_req  = 1'b1;
        @(posedge clk); #1;
        ptw_req  = 1'b0;

        // L2 returns leaf PTE (V=1, R=1, X=1 -> 0xEF, PPN = 0x80000)
        reply_pte({10'b0, 44'h0000_0080_000, 2'b00, 8'hEF}, 2'b00);

        check("Test 3.1: 1GB Gigapage fill_valid asserted immediately at L2", fill_valid == 1'b1);
        check("Test 3.2: 1GB Gigapage fill_level == 2", fill_level == 2'd2);
        check("Test 3.3: PTW busy clears", ptw_busy == 1'b0);
        access_x = 1'b0;

        // ----------------------------------------------------
        // Test 4: 2MB Megapage Early Leaf Termination at L1
        // VA = 0x0000_0000_0020_0000 (vpn2 = 0, vpn1 = 1)
        // ----------------------------------------------------
        @(posedge clk); #1;
        va_req   = 39'h00_0020_0000;
        access_r = 1'b1;
        ptw_req  = 1'b1;
        @(posedge clk); #1;
        ptw_req  = 1'b0;

        // L2 non-leaf
        reply_pte({10'b0, 44'h0000_0080_001, 10'b0000000001}, 2'b00);

        // L1 leaf (2MB megapage)
        reply_pte({10'b0, 44'h0000_0080_000, 2'b00, 8'hEF}, 2'b00);

        check("Test 4.1: 2MB Megapage fill_valid asserted at L1", fill_valid == 1'b1);
        check("Test 4.2: 2MB Megapage fill_level == 1", fill_level == 2'd1);
        check("Test 4.3: PTW busy clears", ptw_busy == 1'b0);
        access_r = 1'b0;

        // ----------------------------------------------------
        // Test 5: Page Fault on Invalid PTE (PTE.V == 0)
        // ----------------------------------------------------
        @(posedge clk); #1;
        va_req   = 39'h00_5555_5000;
        access_w = 1'b1;
        ptw_req  = 1'b1;
        @(posedge clk); #1;
        ptw_req  = 1'b0;

        // L2 returns invalid entry (V=0)
        reply_pte(64'h0, 2'b00);

        check("Test 5.1: Invalid PTE triggers page_fault", page_fault == 1'b1);
        check("Test 5.2: fault_type == 2 (Store Page Fault)", fault_type == 2'd2);
        check("Test 5.3: fault_addr matches request VA", fault_addr[38:0] == 39'h00_5555_5000);
        check("Test 5.4: PTW returns to idle after fault", ptw_busy == 1'b0);
        access_w = 1'b0;

        // ----------------------------------------------------
        // Test 6: Page Fault on Reserved W without R (!pte_r && pte_w)
        // ----------------------------------------------------
        @(posedge clk); #1;
        va_req   = 39'h00_6666_6000;
        access_r = 1'b1;
        ptw_req  = 1'b1;
        @(posedge clk); #1;
        ptw_req  = 1'b0;

        // L2 returns illegal PTE: V=1, W=1, R=0 (bit 2=1, bit 1=0, bit 0=1 -> 0x05)
        reply_pte({10'b0, 44'h0000_0080_000, 2'b00, 8'h05}, 2'b00);

        check("Test 6.1: Reserved W-only PTE triggers page_fault", page_fault == 1'b1);
        check("Test 6.2: fault_type == 1 (Load Page Fault)", fault_type == 2'd1);
        access_r = 1'b0;

        // ----------------------------------------------------
        // Final Scorecard
        // ----------------------------------------------------
        #20;
        $display("\n=======================================================");
        $display(" rv_ptw Verification Scorecard");
        $display(" Total Passed: %0d", tests_passed);
        $display(" Total Failed: %0d", tests_failed);
        $display("=======================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED] rv_ptw 100% verified.");
        end else begin
            $fatal(1, "[TESTBENCH FAILED] Found %0d failures.", tests_failed);
        end
        $finish;
    end
endmodule

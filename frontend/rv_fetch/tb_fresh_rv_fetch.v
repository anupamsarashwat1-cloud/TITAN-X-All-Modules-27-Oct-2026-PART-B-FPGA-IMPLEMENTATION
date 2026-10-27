// SPDX-License-Identifier: Apache-2.0
// Fresh, self-checking testbench for rv_fetch module
// SMVDU-TITAN-X Microprocessor Verification Suite
`timescale 1ns/1ps
`include "params.vh"

module tb_fresh_rv_fetch;
    reg         clk;
    reg         rst_n;
    reg         stall;
    reg         flush;
    reg         branch_taken;
    reg  [63:0] branch_target;

    wire [63:0] imem_addr;
    wire        imem_arvalid;
    reg         imem_arready;
    reg  [31:0] imem_rdata;
    reg         imem_rvalid;
    wire        imem_rready;
    reg  [1:0]  imem_rresp;

    wire [63:0] pc_out;
    wire [31:0] instr_out;
    wire        valid_out;

    integer tests_passed = 0;
    integer tests_failed = 0;

    // Clock: 100MHz (10ns period)
    always #5 clk = ~clk;

    // Instantiate DUT
    rv_fetch #(
        .RESET_PC(`RESET_PC)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .stall          (stall),
        .flush          (flush),
        .branch_taken   (branch_taken),
        .branch_target  (branch_target),
        .imem_addr      (imem_addr),
        .imem_arvalid   (imem_arvalid),
        .imem_arready   (imem_arready),
        .imem_rdata     (imem_rdata),
        .imem_rvalid    (imem_rvalid),
        .imem_rready    (imem_rready),
        .imem_rresp     (imem_rresp),
        .pc_out         (pc_out),
        .instr_out      (instr_out),
        .valid_out      (valid_out)
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

    initial begin
        $dumpfile("verification_waves/rv_fetch.vcd");
        $dumpvars(0, tb_fresh_rv_fetch);

        clk           = 0;
        rst_n         = 0;
        stall         = 0;
        flush         = 0;
        branch_taken  = 0;
        branch_target = 64'h0;
        imem_arready  = 0;
        imem_rdata    = 32'h0;
        imem_rvalid   = 0;
        imem_rresp    = 2'b00;

        // Reset
        #20;
        @(posedge clk); #1;
        rst_n = 1;

        // ----------------------------------------------------
        // Test 1: Reset Sequence
        // ----------------------------------------------------
        @(posedge clk); #1;
        check("Test 1.1: Reset pc_out == 0", pc_out == 64'h0);
        check("Test 1.2: Reset valid_out == 0", valid_out == 1'b0);
        check("Test 1.3: Reset instr_out is NOP", instr_out == 32'h0000_0013);

        // In F_REQ, next edge should assert imem_arvalid for RESET_PC
        @(posedge clk); #1;
        check("Test 1.4: First fetch address is RESET_PC", imem_addr == `RESET_PC);
        check("Test 1.5: imem_arvalid asserted", imem_arvalid == 1'b1);

        // ----------------------------------------------------
        // Test 2: Sequential Instruction Fetches (3 instructions)
        // ----------------------------------------------------
        // Handshake AR for instr 0
        imem_arready = 1'b1;
        @(posedge clk); #1;
        imem_arready = 1'b0;

        // Deliver R beat for instr 0
        imem_rdata  = 32'h0010_0093; // ADDI x1, x0, 1
        imem_rvalid = 1'b1;
        imem_rresp  = 2'b00;
        @(posedge clk); #1;
        imem_rvalid = 1'b0;

        check("Test 2.1: Instr 0 delivered valid_out == 1", valid_out == 1'b1);
        check("Test 2.2: Instr 0 pc_out == RESET_PC", pc_out == `RESET_PC);
        check("Test 2.3: Instr 0 instr_out matches", instr_out == 32'h0010_0093);

        // Instr 1 request issued at RESET_PC + 4
        @(posedge clk); #1;
        check("Test 2.4: Instr 1 address == RESET_PC + 4", imem_addr == (`RESET_PC + 64'd4));
        check("Test 2.5: Instr 1 arvalid asserted", imem_arvalid == 1'b1);

        // Accept AR & deliver R beat for instr 1
        imem_arready = 1'b1;
        @(posedge clk); #1;
        imem_arready = 1'b0;
        imem_rdata   = 32'h0020_0113; // ADDI x2, x0, 2
        imem_rvalid  = 1'b1;
        @(posedge clk); #1;
        imem_rvalid  = 1'b0;

        check("Test 2.6: Instr 1 pc_out == RESET_PC + 4", pc_out == (`RESET_PC + 64'd4));
        check("Test 2.7: Instr 1 instr_out matches", instr_out == 32'h0020_0113);

        // Accept AR & deliver R beat for instr 2
        @(posedge clk); #1;
        imem_arready = 1'b1;
        @(posedge clk); #1;
        imem_arready = 1'b0;
        imem_rdata   = 32'h0030_0193; // ADDI x3, x0, 3
        imem_rvalid  = 1'b1;
        @(posedge clk); #1;
        imem_rvalid  = 1'b0;

        check("Test 2.8: Instr 2 pc_out == RESET_PC + 8", pc_out == (`RESET_PC + 64'd8));
        check("Test 2.9: Instr 2 instr_out matches", instr_out == 32'h0030_0193);

        // ----------------------------------------------------
        // Test 3: Pipeline Stall Handling
        // ----------------------------------------------------
        // While instr 2 was delivered, assert stall = 1
        stall = 1'b1;
        @(posedge clk); #1;
        check("Test 3.1: imem_rready suppressed during stall", imem_rready == 1'b0);

        @(posedge clk); #1;
        // Release stall
        stall = 1'b0;
        @(posedge clk); #1;
        check("Test 3.2: Pipeline resumes after stall release", imem_arvalid == 1'b1);

        // ----------------------------------------------------
        // Test 4: Branch Taken Redirection in F_REQ
        // ----------------------------------------------------
        // Handshake current request
        imem_arready = 1'b1;
        @(posedge clk); #1;
        imem_arready = 1'b0;
        imem_rvalid  = 1'b1;
        imem_rdata   = 32'h0000_0013;
        @(posedge clk); #1;
        imem_rvalid  = 1'b0;

        // Now in F_REQ, branch taken to 0x8000_1000
        branch_taken  = 1'b1;
        branch_target = 64'h0000_0000_8000_1000;
        @(posedge clk); #1;
        branch_taken  = 1'b0;

        check("Test 4.1: Branch redirects fetch address", imem_addr == 64'h0000_0000_8000_1000);
        check("Test 4.2: Redirected arvalid asserted", imem_arvalid == 1'b1);

        // Handshake redirected fetch
        imem_arready = 1'b1;
        @(posedge clk); #1;
        imem_arready = 1'b0;
        imem_rdata   = 32'h1234_50B7; // LUI target instruction
        imem_rvalid  = 1'b1;
        @(posedge clk); #1;
        imem_rvalid  = 1'b0;

        check("Test 4.3: Target instruction delivered", instr_out == 32'h1234_50B7);
        check("Test 4.4: Target PC delivered", pc_out == 64'h0000_0000_8000_1000);

        // ----------------------------------------------------
        // Test 5: Branch Redirection with Orphan Draining in F_WAIT
        // ----------------------------------------------------
        // Allow sequential request to be issued for 0x8000_1004
        @(posedge clk); #1;
        check("Test 5.1: Sequential address 0x8000_1004 issued", imem_addr == 64'h0000_0000_8000_1004);
        imem_arready = 1'b1;
        @(posedge clk); #1;
        imem_arready = 1'b0;
        // Now AR is accepted, R beat is pending (fstate = F_WAIT, pending_r = 1)
        // Mid-flight branch arrives!
        branch_taken  = 1'b1;
        branch_target = 64'h0000_0000_9000_0000;
        @(posedge clk); #1;
        branch_taken  = 1'b0;

        check("Test 5.2: valid_out dropped on branch", valid_out == 1'b0);

        // Slave delivers the OLD orphan beat for 0x8000_1004
        imem_rdata  = 32'hDEAD_BEEF; // Stale instruction
        imem_rvalid = 1'b1;
        @(posedge clk); #1;
        imem_rvalid = 1'b0;

        check("Test 5.3: Stale instruction swallowed, valid_out still 0", valid_out == 1'b0);
        check("Test 5.4: pc_out did NOT pair with stale instruction", pc_out != 64'h0000_0000_9000_0000);

        // Next cycle should issue fetch for the NEW branch target 0x9000_0000
        @(posedge clk); #1;
        check("Test 5.5: Redirected fetch issued for 0x9000_0000",
              imem_addr == 64'h0000_0000_9000_0000 && imem_arvalid == 1'b1);

        // Deliver fresh instruction for 0x9000_0000
        imem_arready = 1'b1;
        @(posedge clk); #1;
        imem_arready = 1'b0;
        imem_rdata   = 32'hCAFE_BABE;
        imem_rvalid  = 1'b1;
        @(posedge clk); #1;
        imem_rvalid  = 1'b0;

        check("Test 5.6: Correct instruction delivered for target", instr_out == 32'hCAFE_BABE);
        check("Test 5.7: Target pc_out correct", pc_out == 64'h0000_0000_9000_0000);
        check("Test 5.8: valid_out asserted for fresh target", valid_out == 1'b1);

        // ----------------------------------------------------
        // Test 6: Bus Error Response Filtering
        // ----------------------------------------------------
        @(posedge clk); #1;
        imem_arready = 1'b1;
        @(posedge clk); #1;
        imem_arready = 1'b0;

        // Deliver with SLVERR (2'b10)
        imem_rresp  = 2'b10;
        imem_rdata  = 32'hFFFF_FFFF;
        imem_rvalid = 1'b1;
        @(posedge clk); #1;
        imem_rvalid = 1'b0;
        imem_rresp  = 2'b00;

        check("Test 6.1: SLVERR suppresses valid_out", valid_out == 1'b0);

        // ----------------------------------------------------
        // Final Scorecard
        // ----------------------------------------------------
        #20;
        $display("\n=======================================================");
        $display(" rv_fetch Verification Scorecard");
        $display(" Total Passed: %0d", tests_passed);
        $display(" Total Failed: %0d", tests_failed);
        $display("=======================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED] rv_fetch 100% verified.");
        end else begin
            $fatal(1, "[TESTBENCH FAILED] Found %0d failures.", tests_failed);
        end
        $finish;
    end
endmodule

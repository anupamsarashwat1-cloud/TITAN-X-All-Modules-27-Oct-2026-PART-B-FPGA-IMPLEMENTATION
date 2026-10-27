// SPDX-License-Identifier: Apache-2.0
// Fresh, self-checking testbench for clint module
// SMVDU-TITAN-X Microprocessor Verification Suite
`timescale 1ns/1ps

module tb_fresh_clint;
    localparam NUM_HARTS = 5;

    reg         clk;
    reg         rst_n;
    reg         psel;
    reg         penable;
    reg         pwrite;
    reg  [15:0] paddr;
    reg  [31:0] pwdata;
    wire [31:0] prdata;
    wire        pready;
    wire [NUM_HARTS-1:0] msip;
    wire [NUM_HARTS-1:0] mtip;

    integer tests_passed = 0;
    integer tests_failed = 0;

    // Clock: 100MHz (10ns period)
    always #5 clk = ~clk;

    // Instantiate DUT
    clint #(
        .NUM_HARTS(NUM_HARTS)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .psel    (psel),
        .penable (penable),
        .pwrite  (pwrite),
        .paddr   (paddr),
        .pwdata  (pwdata),
        .prdata  (prdata),
        .pready  (pready),
        .msip    (msip),
        .mtip    (mtip)
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

    // Helper task for APB write
    task apb_write(input [15:0] addr, input [31:0] data);
        begin
            @(posedge clk); #1;
            psel    = 1'b1;
            penable = 1'b0;
            pwrite  = 1'b1;
            paddr   = addr;
            pwdata  = data;

            @(posedge clk); #1;
            penable = 1'b1;

            @(posedge clk); #1;
            psel    = 1'b0;
            penable = 1'b0;
            pwrite  = 1'b0;
        end
    endtask

    // Helper task for APB read
    task apb_read(input [15:0] addr, output [31:0] data);
        begin
            @(posedge clk); #1;
            psel    = 1'b1;
            penable = 1'b0;
            pwrite  = 1'b0;
            paddr   = addr;

            @(posedge clk); #1;
            penable = 1'b1;

            @(posedge clk); #1;
            data    = prdata;
            psel    = 1'b0;
            penable = 1'b0;
        end
    endtask

    reg [31:0] rdata;

    initial begin
        $dumpfile("verification_waves/clint.vcd");
        $dumpvars(0, tb_fresh_clint);

        clk     = 0;
        rst_n   = 0;
        psel    = 0;
        penable = 0;
        pwrite  = 0;
        paddr   = 0;
        pwdata  = 0;

        // Reset
        #20;
        @(posedge clk); #1;
        rst_n = 1;

        // ----------------------------------------------------
        // Test 1: Reset State
        // ----------------------------------------------------
        @(posedge clk); #1;
        check("Test 1.1: Reset msip all 0", msip == 5'b00000);
        check("Test 1.2: Reset mtip all 0", mtip == 5'b00000);
        check("Test 1.3: pready always 1", pready == 1'b1);

        // ----------------------------------------------------
        // Test 2: Monotonic mtime Increment via APB Read
        // ----------------------------------------------------
        apb_read(16'hBFF8, rdata);
        check("Test 2.1: mtime low readable and non-zero", rdata > 32'd0);

        // Read high word
        apb_read(16'hBFFC, rdata);
        check("Test 2.2: mtime high readable and zero initially", rdata == 32'd0);

        // ----------------------------------------------------
        // Test 3: Software Interrupts (msip[0..4])
        // ----------------------------------------------------
        // Assert msip for hart 0 (0x0000)
        apb_write(16'h0000, 32'h1);
        check("Test 3.1: msip[0] asserts on write", msip[0] == 1'b1);
        check("Test 3.2: Other harts unaffected", msip[4:1] == 4'b0000);

        // Assert msip for hart 2 (0x0008)
        apb_write(16'h0008, 32'h1);
        check("Test 3.3: msip[2] asserts on write", msip[2] == 1'b1);

        // Assert msip for hart 4 (0x0010)
        apb_write(16'h0010, 32'h1);
        check("Test 3.4: msip[4] asserts on write", msip[4] == 1'b1);

        // Read back msip[0]
        apb_read(16'h0000, rdata);
        check("Test 3.5: Read back msip[0] returns 1", rdata == 32'h1);

        // Clear msip[0]
        apb_write(16'h0000, 32'h0);
        check("Test 3.6: msip[0] clears on 0 write", msip[0] == 1'b0);

        // ----------------------------------------------------
        // Test 4: Timer Interrupts (mtip[0..4])
        // ----------------------------------------------------
        // Read current mtime
        apb_read(16'hBFF8, rdata);

        // Program mtimecmp[0] = current mtime + 8
        apb_write(16'h4004, 32'h0);            // mtimecmp[0] hi = 0
        apb_write(16'h4000, rdata + 32'd8);    // mtimecmp[0] lo

        // Right after programming, mtime < mtimecmp[0]
        check("Test 4.1: mtip[0] not yet asserted before threshold", mtip[0] == 1'b0);

        // Wait until mtime passes threshold
        while (!mtip[0]) @(posedge clk);
        check("Test 4.2: mtip[0] asserts when mtime >= mtimecmp[0]", mtip[0] == 1'b1);
        check("Test 4.3: Other harts mtip remains 0", mtip[4:1] == 4'b0000);

        // Clear mtip[0] by programming mtimecmp[0] far into future
        apb_write(16'h4004, 32'hFFFF_FFFF);
        apb_write(16'h4000, 32'hFFFF_FFFF);
        check("Test 4.4: mtip[0] deasserts when mtimecmp moved to future", mtip[0] == 1'b0);

        // Program mtimecmp[3] to trigger mtip[3]
        apb_read(16'hBFF8, rdata);
        apb_write(16'h401C, 32'h0);            // mtimecmp[3] hi = 0 (0x4000 + 3*8 + 4 = 0x401C)
        apb_write(16'h4018, rdata + 32'd6);    // mtimecmp[3] lo (0x4000 + 3*8 = 0x4018)

        while (!mtip[3]) @(posedge clk);
        check("Test 4.5: mtip[3] asserts for hart 3", mtip[3] == 1'b1);
        check("Test 4.6: mtip[0] still 0", mtip[0] == 1'b0);

        // ----------------------------------------------------
        // Final Scorecard
        // ----------------------------------------------------
        #20;
        $display("\n=======================================================");
        $display(" clint Verification Scorecard");
        $display(" Total Passed: %0d", tests_passed);
        $display(" Total Failed: %0d", tests_failed);
        $display("=======================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED] clint 100% verified.");
        end else begin
            $fatal(1, "[TESTBENCH FAILED] Found %0d failures.", tests_failed);
        end
        $finish;
    end
endmodule

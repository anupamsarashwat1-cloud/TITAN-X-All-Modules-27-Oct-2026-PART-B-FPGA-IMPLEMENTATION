// SPDX-License-Identifier: Apache-2.0
// Fresh, self-checking testbench for plic module
// SMVDU-TITAN-X Microprocessor Verification Suite
`timescale 1ns/1ps

module tb_fresh_plic;
    localparam NUM_SOURCES = 186;
    localparam NUM_TARGETS = 10;

    reg                      clk;
    reg                      rst_n;
    reg  [NUM_SOURCES-1:0]   interrupt_sources;
    reg                      psel;
    reg                      penable;
    reg                      pwrite;
    reg  [23:0]              paddr;
    reg  [31:0]              pwdata;
    wire [31:0]              prdata;
    wire                     pready;
    wire [NUM_TARGETS-1:0]   irq_targets;

    integer tests_passed = 0;
    integer tests_failed = 0;

    // Clock: 100MHz (10ns period)
    always #5 clk = ~clk;

    // Instantiate DUT
    plic #(
        .NUM_SOURCES(NUM_SOURCES),
        .NUM_TARGETS(NUM_TARGETS)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .interrupt_sources  (interrupt_sources),
        .psel               (psel),
        .penable            (penable),
        .pwrite             (pwrite),
        .paddr              (paddr),
        .pwdata             (pwdata),
        .prdata             (prdata),
        .pready             (pready),
        .irq_targets        (irq_targets)
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
    task apb_write(input [23:0] addr, input [31:0] data);
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
    task apb_read(input [23:0] addr, output [31:0] data);
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
        $dumpfile("verification_waves/plic.vcd");
        $dumpvars(0, tb_fresh_plic);

        clk               = 0;
        rst_n             = 0;
        interrupt_sources = {NUM_SOURCES{1'b0}};
        psel              = 0;
        penable           = 0;
        pwrite            = 0;
        paddr             = 0;
        pwdata            = 0;

        // Reset
        #20;
        @(posedge clk); #1;
        rst_n = 1;

        // ----------------------------------------------------
        // Test 1: Reset State
        // ----------------------------------------------------
        @(posedge clk); #1;
        check("Test 1.1: Reset irq_targets all 0", irq_targets == {NUM_TARGETS{1'b0}});
        check("Test 1.2: pready is 1", pready == 1'b1);

        // ----------------------------------------------------
        // Test 2: Source Assertion, Priority & Enable Configuration
        // Source 10: prio 4, enabled for target 0, threshold 0
        // ----------------------------------------------------
        // Configure priority for source 10 at 0x000028 (10 * 4 = 0x28)
        apb_write(24'h000028, 32'd4);

        // Configure enable for target 0 word 0 at 0x002000 (bit 10 set: 1 << 10 = 0x400)
        apb_write(24'h002000, 32'h0000_0400);

        // Set threshold for target 0 at 0x200000 to 0
        apb_write(24'h200000, 32'd0);

        // Assert interrupt source 10 pulse
        @(posedge clk); #1;
        interrupt_sources[10] = 1'b1;
        @(posedge clk); #1;
        interrupt_sources[10] = 1'b0;

        #1;
        check("Test 2.1: Target 0 irq asserted for source 10", irq_targets[0] == 1'b1);
        check("Test 2.2: Other targets unaffected", irq_targets[NUM_TARGETS-1:1] == 9'b0);

        // ----------------------------------------------------
        // Test 3: Threshold Filtering
        // Raise target 0 threshold to 5 (source 10 prio 4 < 5)
        // ----------------------------------------------------
        apb_write(24'h200000, 32'd5);
        #1;
        check("Test 3.1: Raising threshold above priority masks IRQ", irq_targets[0] == 1'b0);

        // Lower threshold back to 2
        apb_write(24'h200000, 32'd2);
        #1;
        check("Test 3.2: Lowering threshold unmasks IRQ", irq_targets[0] == 1'b1);

        // ----------------------------------------------------
        // Test 4: Priority Arbitration (Source 20 with higher prio 6)
        // ----------------------------------------------------
        // Configure priority for source 20 at 0x000050 (20 * 4 = 80 = 0x50) to 6
        apb_write(24'h000050, 32'd6);

        // Enable source 20 for target 0 (bit 20 and bit 10 set: (1<<20)|(1<<10) = 0x100400)
        apb_write(24'h002000, 32'h0010_0400);

        // Assert interrupt source 20
        @(posedge clk); #1;
        interrupt_sources[20] = 1'b1;
        @(posedge clk); #1;
        interrupt_sources[20] = 1'b0;

        // Read claim register for target 0 at 0x200004
        apb_read(24'h200004, rdata);
        check("Test 4.1: Higher priority source 20 won arbitration", rdata[7:0] == 8'd20);

        // ----------------------------------------------------
        // Test 5: Atomic Claim & Complete Handshake
        // ----------------------------------------------------
        // Complete source 20 by writing 20 to 0x200004
        apb_write(24'h200004, 32'd20);

        #1;
        check("Test 5.1: IRQ target remains high for next source 10", irq_targets[0] == 1'b1);

        // Read claim register again: should now return source 10
        apb_read(24'h200004, rdata);
        check("Test 5.2: Claim returns next highest source 10", rdata[7:0] == 8'd10);

        // Complete source 10
        apb_write(24'h200004, 32'd10);

        #1;
        check("Test 5.3: Target 0 irq deasserts after all sources complete", irq_targets[0] == 1'b0);

        // ----------------------------------------------------
        // Final Scorecard
        // ----------------------------------------------------
        #20;
        $display("\n=======================================================");
        $display(" plic Verification Scorecard");
        $display(" Total Passed: %0d", tests_passed);
        $display(" Total Failed: %0d", tests_failed);
        $display("=======================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED] plic 100% verified.");
        end else begin
            $fatal(1, "[TESTBENCH FAILED] Found %0d failures.", tests_failed);
        end
        $finish;
    end
endmodule

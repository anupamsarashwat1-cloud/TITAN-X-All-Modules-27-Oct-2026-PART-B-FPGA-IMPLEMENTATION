// SPDX-License-Identifier: Apache-2.0
// Fresh, self-checking testbench for rv_icache module
// SMVDU-TITAN-X Microprocessor Verification Suite
`timescale 1ns/1ps
`include "params.vh"

module tb_fresh_rv_icache;
    localparam ADDR_W = 40;
    localparam DATA_W = 64;

    reg              clk;
    reg              rst_n;
    reg  [ADDR_W-1:0] cpu_addr;
    reg              cpu_req;
    wire [31:0]      cpu_rdata;
    wire             cpu_valid;
    wire             cpu_stall;
    reg              invalidate;

    wire             m_arvalid;
    reg              m_arready;
    wire [ADDR_W-1:0] m_araddr;
    wire [7:0]       m_arlen;
    wire [2:0]       m_arsize;
    wire [1:0]       m_arburst;
    reg              m_rvalid;
    wire             m_rready;
    reg  [DATA_W-1:0] m_rdata;
    reg              m_rlast;
    reg  [1:0]       m_rresp;
    wire             ecc_1bit;
    wire             ecc_2bit;

    integer tests_passed = 0;
    integer tests_failed = 0;

    // Clock generation: 100MHz (10ns period)
    always #5 clk = ~clk;

    // Instantiate DUT
    rv_icache #(
        .WAYS       (8),
        .SETS       (64),
        .LINE_BYTES (64),
        .ADDR_W     (ADDR_W),
        .DATA_W     (DATA_W)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .cpu_addr   (cpu_addr),
        .cpu_req    (cpu_req),
        .cpu_rdata  (cpu_rdata),
        .cpu_valid  (cpu_valid),
        .cpu_stall  (cpu_stall),
        .invalidate (invalidate),
        .m_arvalid  (m_arvalid),
        .m_arready  (m_arready),
        .m_araddr   (m_araddr),
        .m_arlen    (m_arlen),
        .m_arsize   (m_arsize),
        .m_arburst  (m_arburst),
        .m_rvalid   (m_rvalid),
        .m_rready   (m_rready),
        .m_rdata    (m_rdata),
        .m_rlast    (m_rlast),
        .m_rresp    (m_rresp),
        .ecc_1bit   (ecc_1bit),
        .ecc_2bit   (ecc_2bit)
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

    // Task to deliver an 8-beat AXI refill burst
    task deliver_refill(input [63:0] base_word);
        integer beat;
        begin
            // Wait for AR handshake
            while (!m_arvalid) @(posedge clk);
            @(posedge clk); #1;
            m_arready = 1'b1;
            @(posedge clk); #1;
            m_arready = 1'b0;

            // Deliver 8 beats
            for (beat = 0; beat < 8; beat = beat + 1) begin
                @(posedge clk); #1;
                m_rvalid = 1'b1;
                m_rdata  = base_word + (beat * 64'h0000_0001_0000_0001);
                m_rlast  = (beat == 7);
                m_rresp  = 2'b00;
            end
            @(posedge clk); #1;
            m_rvalid = 1'b0;
            m_rlast  = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("verification_waves/rv_icache.vcd");
        $dumpvars(0, tb_fresh_rv_icache);

        clk        = 0;
        rst_n      = 0;
        cpu_addr   = 0;
        cpu_req    = 0;
        invalidate = 0;
        m_arready  = 0;
        m_rvalid   = 0;
        m_rdata    = 0;
        m_rlast    = 0;
        m_rresp    = 0;

        // Reset
        #20;
        @(posedge clk); #1;
        rst_n = 1;

        // ----------------------------------------------------
        // Test 1: Reset State
        // ----------------------------------------------------
        @(posedge clk); #1;
        check("Test 1.1: Reset cpu_valid == 0", cpu_valid == 1'b0);
        check("Test 1.2: Reset cpu_stall == 0", cpu_stall == 1'b0);
        check("Test 1.3: Reset m_arvalid == 0", m_arvalid == 1'b0);

        // ----------------------------------------------------
        // Test 2: Cold Miss & 8-Beat Burst Refill
        // Request address 0x8000_0000 (Index 0, Tag 0x20000, Offset 0)
        // ----------------------------------------------------
        @(posedge clk); #1;
        cpu_addr = 40'h00_8000_0000;
        cpu_req  = 1'b1;

        @(posedge clk); #1;
        check("Test 2.1: Cold miss asserts cpu_stall", cpu_stall == 1'b1);
        check("Test 2.2: Miss asserts m_arvalid", m_arvalid == 1'b1);
        check("Test 2.3: m_arlen == 7 (8 beats)", m_arlen == 8'd7);
        check("Test 2.4: m_arsize == 3 (8 bytes)", m_arsize == 3'd3);
        check("Test 2.5: m_arburst == 2'b01 (INCR)", m_arburst == 2'b01);
        check("Test 2.6: m_araddr aligned to 64B", m_araddr == 40'h00_8000_0000);

        // Deliver refill with base word 0x1111_0001_2222_0002
        deliver_refill(64'h1111_0001_2222_0002);

        // Cache refill finishes, return to IDLE
        @(posedge clk); #1;

        // ----------------------------------------------------
        // Test 3: Cache Hit on Installed Line
        // ----------------------------------------------------
        // Request offset 0: should return lower 32 bits of beat 0 (0x2222_0002)
        cpu_addr = 40'h00_8000_0000;
        cpu_req  = 1'b1;
        @(posedge clk); #1;
        check("Test 3.1: Cache hit asserts cpu_valid", cpu_valid == 1'b1);
        check("Test 3.2: Cache hit does not stall", cpu_stall == 1'b0);
        check("Test 3.3: Correct word at offset 0", cpu_rdata == 32'h2222_0002);

        // Request offset 4: should return upper 32 bits of beat 0 (0x1111_0001)
        cpu_addr = 40'h00_8000_0004;
        @(posedge clk); #1;
        check("Test 3.4: Cache hit on word 1", cpu_valid == 1'b1 && cpu_rdata == 32'h1111_0001);

        // Request offset 8 (beat 1): should return lower 32 bits of beat 1
        cpu_addr = 40'h00_8000_0008;
        @(posedge clk); #1;
        check("Test 3.5: Cache hit on beat 1", cpu_valid == 1'b1 && cpu_rdata == 32'h2222_0003);

        cpu_req = 1'b0;
        @(posedge clk); #1;

        // ----------------------------------------------------
        // Test 4: Fill Another Set (Set 1 at 0x8000_0040)
        // ----------------------------------------------------
        cpu_addr = 40'h00_8000_0040; // Set 1
        cpu_req  = 1'b1;
        @(posedge clk); #1;
        check("Test 4.1: Miss on Set 1 asserts arvalid", m_arvalid == 1'b1);
        deliver_refill(64'h3333_0001_4444_0002);

        @(posedge clk); #1;
        // Verify hit on Set 1
        cpu_addr = 40'h00_8000_0040;
        @(posedge clk); #1;
        check("Test 4.2: Hit on Set 1", cpu_valid == 1'b1 && cpu_rdata == 32'h4444_0002);

        // Verify Set 0 still hits!
        cpu_addr = 40'h00_8000_0000;
        @(posedge clk); #1;
        check("Test 4.3: Set 0 still cached", cpu_valid == 1'b1 && cpu_rdata == 32'h2222_0002);

        cpu_req = 1'b0;

        // ----------------------------------------------------
        // Test 5: Cache Invalidation (invalidate = 1)
        // ----------------------------------------------------
        @(posedge clk); #1;
        invalidate = 1'b1;
        @(posedge clk); #1;
        invalidate = 1'b0;

        // Now address 0x8000_0000 must MISS because all valid bits were cleared
        @(posedge clk); #1;
        cpu_addr = 40'h00_8000_0000;
        cpu_req  = 1'b1;
        @(posedge clk); #1;
        check("Test 5.1: Invalidation caused previously cached line to miss",
              m_arvalid == 1'b1 && cpu_stall == 1'b1);

        // Cancel request and clean up
        deliver_refill(64'h5555_0001_6666_0002);
        @(posedge clk); #1;
        cpu_req = 1'b0;

        // ----------------------------------------------------
        // Final Scorecard
        // ----------------------------------------------------
        #20;
        $display("\n=======================================================");
        $display(" rv_icache Verification Scorecard");
        $display(" Total Passed: %0d", tests_passed);
        $display(" Total Failed: %0d", tests_failed);
        $display("=======================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED] rv_icache 100% verified.");
        end else begin
            $fatal(1, "[TESTBENCH FAILED] Found %0d failures.", tests_failed);
        end
        $finish;
    end
endmodule

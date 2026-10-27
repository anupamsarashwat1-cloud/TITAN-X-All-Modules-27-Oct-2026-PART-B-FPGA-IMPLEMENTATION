// SPDX-License-Identifier: Apache-2.0
// Fresh, self-checking testbench for rv_dcache module
// SMVDU-TITAN-X Microprocessor Verification Suite
`timescale 1ns/1ps
`include "params.vh"

module tb_fresh_rv_dcache;
    localparam ADDR_W = 40;
    localparam DATA_W = 64;

    reg                 clk;
    reg                 rst_n;
    reg  [ADDR_W-1:0]   cpu_addr;
    reg  [DATA_W-1:0]   cpu_wdata;
    reg  [DATA_W/8-1:0] cpu_wstrb;
    reg                 cpu_req;
    reg                 cpu_wr;
    reg  [2:0]          cpu_size;
    wire [DATA_W-1:0]   cpu_rdata;
    wire                cpu_valid;
    wire                cpu_stall;

    reg                 is_lr;
    reg                 is_sc;
    reg  [ADDR_W-1:0]   lr_addr_in;
    reg                 lr_valid_in;
    wire                sc_success;

    reg                 flush_all;
    reg                 flush_addr_en;
    reg  [ADDR_W-1:0]   flush_addr;
    wire                flush_busy;

    // AXI4 Read
    wire                m_arvalid;
    reg                 m_arready;
    wire [ADDR_W-1:0]   m_araddr;
    wire [7:0]          m_arlen;
    wire [2:0]          m_arsize;
    wire [1:0]          m_arburst;
    wire                m_arlock;
    reg                 m_rvalid;
    wire                m_rready;
    reg  [DATA_W-1:0]   m_rdata;
    reg                 m_rlast;
    reg  [1:0]          m_rresp;

    // AXI4 Write
    wire                m_awvalid;
    reg                 m_awready;
    wire [ADDR_W-1:0]   m_awaddr;
    wire [7:0]          m_awlen;
    wire [2:0]          m_awsize;
    wire [1:0]          m_awburst;
    wire                m_wvalid;
    reg                 m_wready;
    wire [DATA_W-1:0]   m_wdata;
    wire [DATA_W/8-1:0] m_wstrb;
    wire                m_wlast;
    reg                 m_bvalid;
    wire                m_bready;
    reg  [1:0]          m_bresp;

    // Snoop
    reg                 snoop_valid;
    reg  [ADDR_W-1:0]   snoop_addr;
    wire                snoop_ack;

    integer tests_passed = 0;
    integer tests_failed = 0;

    // Clock: 100MHz (10ns period)
    always #5 clk = ~clk;

    // Instantiate DUT
    rv_dcache #(
        .WAYS       (8),
        .SETS       (64),
        .LINE_BYTES (64),
        .ADDR_W     (ADDR_W),
        .DATA_W     (DATA_W)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .cpu_addr       (cpu_addr),
        .cpu_wdata      (cpu_wdata),
        .cpu_wstrb      (cpu_wstrb),
        .cpu_req        (cpu_req),
        .cpu_wr         (cpu_wr),
        .cpu_size       (cpu_size),
        .cpu_rdata      (cpu_rdata),
        .cpu_valid      (cpu_valid),
        .cpu_stall      (cpu_stall),
        .is_lr          (is_lr),
        .is_sc          (is_sc),
        .lr_addr_in     (lr_addr_in),
        .lr_valid_in    (lr_valid_in),
        .sc_success     (sc_success),
        .flush_all      (flush_all),
        .flush_addr_en  (flush_addr_en),
        .flush_addr     (flush_addr),
        .flush_busy     (flush_busy),
        .m_arvalid      (m_arvalid),
        .m_arready      (m_arready),
        .m_araddr       (m_araddr),
        .m_arlen        (m_arlen),
        .m_arsize       (m_arsize),
        .m_arburst      (m_arburst),
        .m_arlock       (m_arlock),
        .m_rvalid       (m_rvalid),
        .m_rready       (m_rready),
        .m_rdata        (m_rdata),
        .m_rlast        (m_rlast),
        .m_rresp        (m_rresp),
        .m_awvalid      (m_awvalid),
        .m_awready      (m_awready),
        .m_awaddr       (m_awaddr),
        .m_awlen        (m_awlen),
        .m_awsize       (m_awsize),
        .m_awburst      (m_awburst),
        .m_wvalid       (m_wvalid),
        .m_wready       (m_wready),
        .m_wdata        (m_wdata),
        .m_wstrb        (m_wstrb),
        .m_wlast        (m_wlast),
        .m_bvalid       (m_bvalid),
        .m_bready       (m_bready),
        .m_bresp        (m_bresp),
        .snoop_valid    (snoop_valid),
        .snoop_addr     (snoop_addr),
        .snoop_type     (2'b00),
        .snoop_ack      (snoop_ack),
        .snoop_data_valid(),
        .snoop_data     (),
        .ecc_1bit       (),
        .ecc_2bit       ()
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

    // Helper task to deliver read refill burst
    task deliver_read_refill(input [63:0] base_word);
        integer beat;
        begin
            while (!m_arvalid) @(posedge clk);
            @(posedge clk); #1;
            m_arready = 1'b1;
            @(posedge clk); #1;
            m_arready = 1'b0;

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

    // Helper task to service write eviction burst
    task service_write_eviction(output [63:0] first_beat_data);
        integer beat;
        begin
            while (!m_awvalid) @(posedge clk);
            @(posedge clk); #1;
            m_awready = 1'b1;
            @(posedge clk); #1;
            m_awready = 1'b0;

            for (beat = 0; beat < 8; beat = beat + 1) begin
                while (!m_wvalid) @(posedge clk);
                if (beat == 0) first_beat_data = m_wdata;
                @(posedge clk); #1;
                m_wready = 1'b1;
                @(posedge clk); #1;
                m_wready = 1'b0;
            end

            // Deliver B response
            while (!m_bready) @(posedge clk);
            @(posedge clk); #1;
            m_bvalid = 1'b1;
            m_bresp  = 2'b00;
            @(posedge clk); #1;
            m_bvalid = 1'b0;
        end
    endtask

    reg [63:0] evicted_beat0;

    initial begin
        $dumpfile("verification_waves/rv_dcache.vcd");
        $dumpvars(0, tb_fresh_rv_dcache);

        clk           = 0;
        rst_n         = 0;
        cpu_addr      = 0;
        cpu_wdata     = 0;
        cpu_wstrb     = 0;
        cpu_req       = 0;
        cpu_wr        = 0;
        cpu_size      = 3'b011; // 64-bit D
        is_lr         = 0;
        is_sc         = 0;
        lr_addr_in    = 0;
        lr_valid_in   = 0;
        flush_all     = 0;
        flush_addr_en = 0;
        flush_addr    = 0;
        m_arready     = 0;
        m_rvalid      = 0;
        m_rdata       = 0;
        m_rlast       = 0;
        m_rresp       = 0;
        m_awready     = 0;
        m_wready      = 0;
        m_bvalid      = 0;
        m_bresp       = 0;
        snoop_valid   = 0;
        snoop_addr    = 0;

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
        check("Test 1.3: Reset flush_busy == 0", flush_busy == 1'b0);
        check("Test 1.4: Reset m_arvalid == 0", m_arvalid == 1'b0);
        check("Test 1.5: Reset m_awvalid == 0", m_awvalid == 1'b0);

        // ----------------------------------------------------
        // Test 2: Cold Load Miss & Refill
        // Read 64-bit at 0x8000_0000
        // ----------------------------------------------------
        @(posedge clk); #1;
        cpu_addr = 40'h00_8000_0000;
        cpu_req  = 1'b1;
        cpu_wr   = 1'b0;
        cpu_size = 3'b011; // D

        @(posedge clk); #1;
        check("Test 2.1: Cold miss asserts cpu_stall", cpu_stall == 1'b1);
        check("Test 2.2: Miss asserts m_arvalid", m_arvalid == 1'b1);
        check("Test 2.3: m_arlen == 7 (8 beats)", m_arlen == 8'd7);

        // Deliver refill with base word 0x0123_4567_89AB_CDEF
        deliver_read_refill(64'h0123_4567_89AB_CDEF);

        // Wait for refill install
        while (cpu_stall) @(posedge clk);
        @(posedge clk); #1;
        check("Test 2.4: cpu_valid asserts after refill", cpu_valid == 1'b1);
        check("Test 2.5: Correct 64-bit load data", cpu_rdata == 64'h0123_4567_89AB_CDEF);
        cpu_req = 1'b0;

        // ----------------------------------------------------
        // Test 3: Sub-Word Load Alignment (LBU, LB, LH, LWU)
        // ----------------------------------------------------
        // Read byte at offset 0 (0xEF)
        @(posedge clk); #1;
        cpu_addr = 40'h00_8000_0000;
        cpu_req  = 1'b1;
        cpu_size = 3'b100; // LBU
        @(posedge clk); #1;
        check("Test 3.1: LBU at offset 0 returns 0xEF", cpu_rdata == 64'h0000_0000_0000_00EF);

        // Read byte at offset 1 (0xCD)
        cpu_addr = 40'h00_8000_0001;
        @(posedge clk); #1;
        check("Test 3.2: LBU at offset 1 returns 0xCD", cpu_rdata == 64'h0000_0000_0000_00CD);

        // Read signed byte at offset 7 (0x01)
        cpu_addr = 40'h00_8000_0007;
        cpu_size = 3'b000; // LB
        @(posedge clk); #1;
        check("Test 3.3: LB at offset 7 returns 0x01", cpu_rdata == 64'h0000_0000_0000_0001);

        // Read signed halfword at offset 2 (0x89AB -> MSB 1 -> sign extended)
        cpu_addr = 40'h00_8000_0002;
        cpu_size = 3'b001; // LH
        @(posedge clk); #1;
        check("Test 3.4: LH at offset 2 sign-extended", cpu_rdata == 64'hFFFF_FFFF_FFFF_89AB);

        // Read zero-extended word at offset 0 (0x89AB_CDEF)
        cpu_addr = 40'h00_8000_0000;
        cpu_size = 3'b110; // LWU
        @(posedge clk); #1;
        check("Test 3.5: LWU at offset 0 zero-extended", cpu_rdata == 64'h0000_0000_89AB_CDEF);
        cpu_req = 1'b0;

        // ----------------------------------------------------
        // Test 4: Store Hit & Byte Lane Steering
        // Store 0xAABB_CCDD_EEFF_0011 into 0x8000_0000
        // ----------------------------------------------------
        @(posedge clk); #1;
        cpu_addr  = 40'h00_8000_0000;
        cpu_wdata = 64'hAABB_CCDD_EEFF_0011;
        cpu_wstrb = 8'hFF;
        cpu_wr    = 1'b1;
        cpu_req   = 1'b1;
        cpu_size  = 3'b011; // D

        @(posedge clk); #1;
        check("Test 4.1: Store hit asserts cpu_valid immediately", cpu_valid == 1'b1);
        cpu_req = 1'b0;
        cpu_wr  = 1'b0;

        // Read back stored value
        @(posedge clk); #1;
        cpu_addr = 40'h00_8000_0000;
        cpu_req  = 1'b1;
        @(posedge clk); #1;
        check("Test 4.2: Read-after-store returns updated data",
              cpu_rdata == 64'hAABB_CCDD_EEFF_0011);
        cpu_req = 1'b0;

        // ----------------------------------------------------
        // Test 5: Full Cache Flush with Dirty Eviction
        // ----------------------------------------------------
        @(posedge clk); #1;
        flush_all = 1'b1;
        @(posedge clk); #1;
        flush_all = 1'b0;

        // Wait for flush to start
        while (!flush_busy) @(posedge clk);

        // Service eviction burst initiated by flush scanner
        fork
            begin
                service_write_eviction(evicted_beat0);
            end
            begin
                // Wait for flush to complete (scans all 512 entries)
                while (flush_busy) @(posedge clk);
            end
        join

        check("Test 5.1: Evicted line contains modified store data",
              evicted_beat0 == 64'hAABB_CCDD_EEFF_0011);
        check("Test 5.2: Flush completes flush_busy == 0", flush_busy == 1'b0);

        // ----------------------------------------------------
        // Test 6: LR/SC Reservation Matching
        // ----------------------------------------------------
        @(posedge clk); #1;
        is_sc       = 1'b1;
        lr_valid_in = 1'b1;
        lr_addr_in  = 40'h00_8000_0000;
        cpu_addr    = 40'h00_8000_0008; // same line (offset 8)
        @(posedge clk); #1;
        check("Test 6.1: SC succeeds on reservation match", sc_success == 1'b1);

        // Mismatched reservation address
        lr_addr_in  = 40'h00_9000_0000;
        @(posedge clk); #1;
        check("Test 6.2: SC fails on reservation address mismatch", sc_success == 1'b0);

        is_sc       = 1'b0;
        lr_valid_in = 1'b0;

        // ----------------------------------------------------
        // Final Scorecard
        // ----------------------------------------------------
        #20;
        $display("\n=======================================================");
        $display(" rv_dcache Verification Scorecard");
        $display(" Total Passed: %0d", tests_passed);
        $display(" Total Failed: %0d", tests_failed);
        $display("=======================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED] rv_dcache 100% verified.");
        end else begin
            $fatal(1, "[TESTBENCH FAILED] Found %0d failures.", tests_failed);
        end
        $finish;
    end
endmodule

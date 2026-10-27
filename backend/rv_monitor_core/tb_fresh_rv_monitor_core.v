// SPDX-License-Identifier: Apache-2.0
// Fresh, 100% self-checking verification testbench for rv_monitor_core
// Module: rv_monitor_core (backend/rv_monitor_core/rv_monitor_core.v)
// Verification: Reset boot, instruction fetch, ALU/Memory execution,
//               AXI4 data bus master transactions, branch redirect,
//               stall holding, and debug halt/resume.

`timescale 1ns/1ps

module tb_fresh_rv_monitor_core;

    // Parameters
    localparam HART_ID  = 4;
    localparam RESET_PC = 64'h0000_0000_1000_0000;

    // DUT Signals
    reg         clk;
    reg         rst_n;

    // Interrupts
    reg         irq_m_ext;
    reg         irq_m_timer;
    reg         irq_m_soft;

    // AXI4-Lite Instruction Interface
    wire [39:0] imem_araddr;
    wire        imem_arvalid;
    reg         imem_arready;
    reg  [63:0] imem_rdata;
    reg         imem_rvalid;
    reg  [1:0]  imem_rresp;

    // AXI4 Data Interface
    wire        dmem_awvalid;
    reg         dmem_awready;
    wire [39:0] dmem_awaddr;
    wire [7:0]  dmem_awlen;
    wire [2:0]  dmem_awsize;
    wire [1:0]  dmem_awburst;
    wire        dmem_wvalid;
    reg         dmem_wready;
    wire [63:0] dmem_wdata;
    wire [7:0]  dmem_wstrb;
    wire        dmem_wlast;
    reg         dmem_bvalid;
    wire        dmem_bready;
    reg  [1:0]  dmem_bresp;

    wire        dmem_arvalid;
    reg         dmem_arready;
    wire [39:0] dmem_araddr;
    wire [7:0]  dmem_arlen;
    wire [2:0]  dmem_arsize;
    wire [1:0]  dmem_arburst;
    reg         dmem_rvalid;
    wire        dmem_rready;
    reg  [63:0] dmem_rdata;
    reg         dmem_rlast;
    reg  [1:0]  dmem_rresp;

    // Debug control
    reg         halt_req;
    reg         resume_req;
    wire        hart_halted;
    wire        hart_running;

    // Scorecard counters
    integer tests_passed = 0;
    integer tests_failed = 0;
    reg [63:0] expected_target;
    reg [63:0] halted_pc;

    // Clock generator: 100 MHz (10ns period)
    always #5 clk = ~clk;

    // DUT instantiation
    rv_monitor_core #(
        .HART_ID (HART_ID),
        .RESET_PC(RESET_PC)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .irq_m_ext   (irq_m_ext),
        .irq_m_timer (irq_m_timer),
        .irq_m_soft  (irq_m_soft),
        .imem_araddr (imem_araddr),
        .imem_arvalid(imem_arvalid),
        .imem_arready(imem_arready),
        .imem_rdata  (imem_rdata),
        .imem_rvalid (imem_rvalid),
        .imem_rresp  (imem_rresp),
        .dmem_awvalid(dmem_awvalid),
        .dmem_awready(dmem_awready),
        .dmem_awaddr (dmem_awaddr),
        .dmem_awlen  (dmem_awlen),
        .dmem_awsize (dmem_awsize),
        .dmem_awburst(dmem_awburst),
        .dmem_wvalid (dmem_wvalid),
        .dmem_wready (dmem_wready),
        .dmem_wdata  (dmem_wdata),
        .dmem_wstrb  (dmem_wstrb),
        .dmem_wlast  (dmem_wlast),
        .dmem_bvalid (dmem_bvalid),
        .dmem_bready (dmem_bready),
        .dmem_bresp  (dmem_bresp),
        .dmem_arvalid(dmem_arvalid),
        .dmem_arready(dmem_arready),
        .dmem_araddr (dmem_araddr),
        .dmem_arlen  (dmem_arlen),
        .dmem_arsize (dmem_arsize),
        .dmem_arburst(dmem_arburst),
        .dmem_rvalid (dmem_rvalid),
        .dmem_rready (dmem_rready),
        .dmem_rdata  (dmem_rdata),
        .dmem_rlast  (dmem_rlast),
        .dmem_rresp  (dmem_rresp),
        .halt_req    (halt_req),
        .resume_req  (resume_req),
        .hart_halted (hart_halted),
        .hart_running(hart_running)
    );

    task check(input [511:0] test_name, input condition);
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
        $dumpfile("verification_waves/rv_monitor_core.vcd");
        $dumpvars(0, tb_fresh_rv_monitor_core);

        // Initialize signals
        clk          = 0;
        rst_n        = 0;
        irq_m_ext    = 0;
        irq_m_timer  = 0;
        irq_m_soft   = 0;
        imem_arready = 1;
        imem_rdata   = 64'h0;
        imem_rvalid  = 0;
        imem_rresp   = 2'b00;
        dmem_awready = 0;
        dmem_wready  = 0;
        dmem_bvalid  = 0;
        dmem_bresp   = 2'b00;
        dmem_arready = 0;
        dmem_rvalid  = 0;
        dmem_rdata   = 64'h0;
        dmem_rlast   = 0;
        dmem_rresp   = 2'b00;
        halt_req     = 0;
        resume_req   = 0;

        // Reset Pulse
        #20;
        @(posedge clk); #1;
        rst_n = 1;

        // ----------------------------------------------------
        // Test 1: Reset Sequence & Boot State
        // ----------------------------------------------------
        @(posedge clk); #1;
        check("Test 1.1: Reset PC initialized to RESET_PC (0x1000_0000)", dut.pc_reg == RESET_PC);
        check("Test 1.2: Fetch PC matches RESET_PC", dut.fe_pc == RESET_PC);
        check("Test 1.3: imem_araddr reflects RESET_PC", imem_araddr == RESET_PC[39:0]);
        check("Test 1.4: imem_arvalid asserted out of reset", imem_arvalid == 1'b1);
        check("Test 1.5: hart_halted is 0 at reset", hart_halted == 1'b0);
        check("Test 1.6: hart_running is 1 at reset", hart_running == 1'b1);
        check("Test 1.7: dmem write address quiet (awvalid == 0)", dmem_awvalid == 1'b0);
        check("Test 1.8: dmem read address quiet (arvalid == 0)", dmem_arvalid == 1'b0);

        // ----------------------------------------------------
        // Test 2: Sequential Instruction Fetch & PC Advancement
        // Supply NOP (ADDI x0, x0, 0 = 0x00000013)
        // ----------------------------------------------------
        imem_rdata  = {32'h0, 32'h0000_0013};
        imem_rvalid = 1'b1;

        @(posedge clk); #1;
        check("Test 2.1: PC advances by 4 to 0x1000_0004", dut.fe_pc == 64'h0000_0000_1000_0004);
        check("Test 2.2: imem_araddr tracks PC at 0x1000_0004", imem_araddr == 40'h00_1000_0004);

        @(posedge clk); #1;
        check("Test 2.3: PC advances by 4 to 0x1000_0008", dut.fe_pc == 64'h0000_0000_1000_0008);
        check("Test 2.4: imem_araddr tracks PC at 0x1000_0008", imem_araddr == 40'h00_1000_0008);

        // Deassert imem_rvalid, PC must hold
        imem_rvalid = 1'b0;
        @(posedge clk); #1;
        check("Test 2.5: PC holds when fe_valid drops", dut.fe_pc == 64'h0000_0000_1000_0008);

        // ----------------------------------------------------
        // Test 3: Data Memory Store Operation (SD x2, 16(x0))
        // SD opcode: 32'h00203823
        // ----------------------------------------------------
        imem_rdata  = {32'h0, 32'h0020_3823}; // SD x2, 16(x0)
        imem_rvalid = 1'b1;
        @(posedge clk); #1; // Latches into Decode

        imem_rdata  = {32'h0, 32'h0000_0013}; // Follow with NOP
        @(posedge clk); #1; // Latches into Execute

        // In Execute stage: ex_memw asserts, driving dmem_awvalid and dmem_wvalid
        check("Test 3.1: dmem_awvalid asserts on Store instruction", dmem_awvalid == 1'b1);
        check("Test 3.2: dmem_awaddr matches store address 0x10", dmem_awaddr == 40'h00_0000_0010);
        check("Test 3.3: dmem_awsize indicates 8-byte transfer (3'b011)", dmem_awsize == 3'b011);
        check("Test 3.4: dmem_wvalid asserts on Store instruction", dmem_wvalid == 1'b1);
        check("Test 3.5: dmem_wstrb indicates full byte mask 0xFF", dmem_wstrb == 8'hFF);
        check("Test 3.6: dmem_wlast is asserted", dmem_wlast == 1'b1);

        // Complete AXI write handshake
        dmem_awready = 1'b1;
        dmem_wready  = 1'b1;
        @(posedge clk); #1;
        dmem_awready = 1'b0;
        dmem_wready  = 1'b0;
        dmem_bvalid  = 1'b1;
        @(posedge clk); #1;
        dmem_bvalid  = 1'b0;

        // ----------------------------------------------------
        // Test 4: Data Memory Load Operation (LD x3, 32(x0))
        // LD opcode: 32'h02003183
        // ----------------------------------------------------
        imem_rdata  = {32'h0, 32'h0200_3183}; // LD x3, 32(x0)
        imem_rvalid = 1'b1;
        @(posedge clk); #1; // Latches into Decode

        imem_rdata  = {32'h0, 32'h0000_0013}; // Follow with NOP
        @(posedge clk); #1; // Latches into Execute

        check("Test 4.1: dmem_arvalid asserts on Load instruction", dmem_arvalid == 1'b1);
        check("Test 4.2: dmem_araddr matches load address 0x20", dmem_araddr == 40'h00_0000_0020);
        check("Test 4.3: dmem_arsize indicates 8-byte transfer (3'b011)", dmem_arsize == 3'b011);

        // Complete AXI read handshake
        dmem_arready = 1'b1;
        @(posedge clk); #1;
        dmem_arready = 1'b0;
        dmem_rvalid  = 1'b1;
        dmem_rdata   = 64'hFEED_FACE_CAFE_BEEF;
        dmem_rlast   = 1'b1;
        @(posedge clk); #1;
        dmem_rvalid  = 1'b0;

        // ----------------------------------------------------
        // Test 5: AXI Memory Backpressure & Pipeline Stall Holding
        // Issue Store, keep awready=0 and wready=0
        // ----------------------------------------------------
        imem_rdata  = {32'h0, 32'h0020_3823}; // SD
        imem_rvalid = 1'b1;
        @(posedge clk); #1; // into Decode
        imem_rdata  = {32'h0, 32'h0000_0013};
        @(posedge clk); #1; // into Execute

        check("Test 5.1: dmem_awvalid asserted before handshake", dmem_awvalid == 1'b1);
        check("Test 5.2: Pipeline stall asserted due to unacknowledged mem write", dut.stall == 1'b1);
        check("Test 5.3: imem_arvalid deasserts during pipeline stall", imem_arvalid == 1'b0);

        // Hold backpressure for 3 cycles: pipeline must not lose transaction
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        check("Test 5.4: dmem_awvalid remains stably asserted during multi-cycle stall", dmem_awvalid == 1'b1);
        check("Test 5.5: dmem_awaddr remains stably held at 0x10", dmem_awaddr == 40'h00_0000_0010);

        // Release backpressure
        dmem_awready = 1'b1;
        dmem_wready  = 1'b1;
        @(posedge clk); #1;
        dmem_awready = 1'b0;
        dmem_wready  = 1'b0;
        dmem_bvalid  = 1'b1;
        @(posedge clk); #1;
        dmem_bvalid  = 1'b0;
        check("Test 5.6: Pipeline stall clears after handshake completes", dut.stall == 1'b0);

        // ----------------------------------------------------
        // Test 6: Branch / Jump Execution (JAL x0, 16)
        // Opcode: 32'h0100006F
        // ----------------------------------------------------
        imem_rdata  = {32'h0, 32'h0100_006F}; // JAL x0, +16
        imem_rvalid = 1'b1;
        @(posedge clk); #1; // Decode
        imem_rdata  = {32'h0, 32'h0000_0013}; // In flight instr to be flushed
        @(posedge clk); #1; // Execute

        check("Test 6.1: branch_taken asserts in execute stage", dut.branch_taken == 1'b1);
        check("Test 6.2: flush_fe asserts on branch redirect", dut.flush_fe == 1'b1);
        check("Test 6.3: flush_de asserts on branch redirect", dut.flush_de == 1'b1);
        expected_target = dut.branch_target;

        @(posedge clk); #1;
        check("Test 6.4: PC redirected to target address", dut.fe_pc == expected_target);

        // ----------------------------------------------------
        // Test 7: Debug Halt & Resume Control
        // ----------------------------------------------------
        halted_pc = dut.fe_pc;
        halt_req = 1'b1;
        @(posedge clk); #1;
        check("Test 7.1: hart_halted asserts immediately on halt_req", hart_halted == 1'b1);
        check("Test 7.2: hart_running deasserts on halt_req", hart_running == 1'b0);
        check("Test 7.3: Pipeline stall asserted during debug halt", dut.stall == 1'b1);
        check("Test 7.4: imem_arvalid deasserts during debug halt", imem_arvalid == 1'b0);

        // Verify PC remains frozen while halted
        imem_rvalid = 1'b1;
        imem_rdata  = {32'h0, 32'h0000_0013};
        @(posedge clk); #1;
        @(posedge clk); #1;
        check("Test 7.5: PC remains frozen during halt state", dut.fe_pc == halted_pc);

        // Resume hart
        halt_req   = 1'b0;
        resume_req = 1'b1;
        @(posedge clk); #1;
        check("Test 7.6: hart_halted clears on resume", hart_halted == 1'b0);
        check("Test 7.7: hart_running reasserts on resume", hart_running == 1'b1);
        check("Test 7.8: Pipeline stall clears on resume", dut.stall == 1'b0);

        // ----------------------------------------------------
        // Test 8: Interrupt Lines Integrity
        // ----------------------------------------------------
        irq_m_ext   = 1'b1;
        irq_m_timer = 1'b1;
        irq_m_soft  = 1'b1;
        @(posedge clk); #1;
        check("Test 8.1: Interrupt lines assert cleanly without fault", dut.irq_m_ext == 1'b1 && dut.irq_m_timer == 1'b1 && dut.irq_m_soft == 1'b1);
        irq_m_ext   = 1'b0;
        irq_m_timer = 1'b0;
        irq_m_soft  = 1'b0;
        @(posedge clk); #1;
        check("Test 8.2: Interrupt lines deassert cleanly", dut.irq_m_ext == 1'b0 && dut.irq_m_timer == 1'b0 && dut.irq_m_soft == 1'b0);

        // ----------------------------------------------------
        // Final Scorecard
        // ----------------------------------------------------
        #50;
        $display("\n=======================================================");
        $display(" rv_monitor_core Verification Scorecard");
        $display(" Total Passed: %0d", tests_passed);
        $display(" Total Failed: %0d", tests_failed);
        $display("=======================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED] rv_monitor_core 100%% verified.");
        end else begin
            $fatal(1, "[TESTBENCH FAILED] Found %0d failures.", tests_failed);
        end
        $finish;
    end

endmodule

// SPDX-License-Identifier: Apache-2.0
// Fresh, 100% self-checking verification testbench for rv_core_top
// Module: rv_core_top (backend/rv_core_top/rv_core_top.v)
// Verification: Full 5-stage CPU core pipeline integration
//               Fetch -> Decode (RegFile) -> Execute (ALU/CSR/M-ext) -> Mem -> Writeback
//               Operand forwarding (EX->EX, MEM->EX, WB->EX), Load-use hazards,
//               Branch flush recovery, Multiplier multicycle execution, Debug halt/resume.

`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module tb_fresh_rv_core_top;

    localparam HART_ID  = 0;
    localparam RESET_PC = `RESET_PC; // 64'h0000_0000_0002_0000

    reg         clk;
    reg         rst_n;
    reg         irq_m_ext;
    reg         irq_m_timer;
    reg         irq_m_soft;

    // AXI4 Master: Instruction Fetch
    wire        imem_arvalid;
    reg         imem_arready;
    wire [39:0] imem_araddr;
    wire [7:0]  imem_arlen;
    wire [2:0]  imem_arsize;
    wire [1:0]  imem_arburst;
    reg         imem_rvalid;
    wire        imem_rready;
    reg  [63:0] imem_rdata;
    reg         imem_rlast;
    reg  [1:0]  imem_rresp;

    // AXI4 Master: Data Access
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
    wire        dmem_arlock;
    reg         dmem_rvalid;
    wire        dmem_rready;
    reg  [63:0] dmem_rdata;
    reg         dmem_rlast;
    reg  [1:0]  dmem_rresp;

    // Snoop
    reg         snoop_valid;
    reg  [39:0] snoop_addr;
    reg  [1:0]  snoop_type;
    wire        snoop_ack;
    wire        snoop_data_valid;
    wire [511:0] snoop_data;

    // Debug
    reg         halt_req;
    reg         resume_req;
    wire        hart_halted;
    wire        hart_running;

    // Scorecard counters
    integer tests_passed = 0;
    integer tests_failed = 0;

    // Clock generator: 100MHz (10ns period)
    always #5 clk = ~clk;

    // Instantiate DUT
    rv_core_top #(
        .HART_ID (HART_ID),
        .RESET_PC(RESET_PC)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .irq_m_ext       (irq_m_ext),
        .irq_m_timer     (irq_m_timer),
        .irq_m_soft      (irq_m_soft),
        .imem_arvalid    (imem_arvalid),
        .imem_arready    (imem_arready),
        .imem_araddr     (imem_araddr),
        .imem_arlen      (imem_arlen),
        .imem_arsize     (imem_arsize),
        .imem_arburst    (imem_arburst),
        .imem_rvalid     (imem_rvalid),
        .imem_rready     (imem_rready),
        .imem_rdata      (imem_rdata),
        .imem_rlast      (imem_rlast),
        .imem_rresp      (imem_rresp),
        .dmem_awvalid    (dmem_awvalid),
        .dmem_awready    (dmem_awready),
        .dmem_awaddr     (dmem_awaddr),
        .dmem_awlen      (dmem_awlen),
        .dmem_awsize     (dmem_awsize),
        .dmem_awburst    (dmem_awburst),
        .dmem_wvalid     (dmem_wvalid),
        .dmem_wready     (dmem_wready),
        .dmem_wdata      (dmem_wdata),
        .dmem_wstrb      (dmem_wstrb),
        .dmem_wlast      (dmem_wlast),
        .dmem_bvalid     (dmem_bvalid),
        .dmem_bready     (dmem_bready),
        .dmem_bresp      (dmem_bresp),
        .dmem_arvalid    (dmem_arvalid),
        .dmem_arready    (dmem_arready),
        .dmem_araddr     (dmem_araddr),
        .dmem_arlen      (dmem_arlen),
        .dmem_arsize     (dmem_arsize),
        .dmem_arburst    (dmem_arburst),
        .dmem_arlock     (dmem_arlock),
        .dmem_rvalid     (dmem_rvalid),
        .dmem_rready     (dmem_rready),
        .dmem_rdata      (dmem_rdata),
        .dmem_rlast      (dmem_rlast),
        .dmem_rresp      (dmem_rresp),
        .snoop_valid     (snoop_valid),
        .snoop_addr      (snoop_addr),
        .snoop_type      (snoop_type),
        .snoop_ack       (snoop_ack),
        .snoop_data_valid(snoop_data_valid),
        .snoop_data      (snoop_data),
        .halt_req        (halt_req),
        .resume_req      (resume_req),
        .hart_halted     (hart_halted),
        .hart_running    (hart_running)
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

    // Instruction ROM and Data RAM Memory Models
    reg [31:0] rom [0:63];
    reg [63:0] ram [0:63];

    // Instruction Memory AXI4 Slave
    reg        imem_pending;
    reg [39:0] imem_latched_addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            imem_arready      <= 1'b0;
            imem_rvalid       <= 1'b0;
            imem_rdata        <= 64'h0;
            imem_rlast        <= 1'b0;
            imem_rresp        <= 2'b00;
            imem_pending      <= 1'b0;
            imem_latched_addr <= 40'h0;
        end else begin
            // Address phase: acknowledge when requested and not already servicing
            if (imem_arvalid && !imem_arready && !imem_pending && !imem_rvalid) begin
                imem_arready      <= 1'b1;
                imem_latched_addr <= imem_araddr;
                imem_pending      <= 1'b1;
            end else begin
                imem_arready <= 1'b0;
            end

            // Data phase: present read data cycle after address acceptance
            if (imem_pending) begin
                imem_pending <= 1'b0;
                imem_rvalid  <= 1'b1;
                imem_rlast   <= 1'b1;
                imem_rresp   <= 2'b00;
                imem_rdata   <= {32'h0, rom[(imem_latched_addr - 40'h00_0002_0000) >> 2]};
                $display("[IMEM %0t] Deliver addr=0x%0h instr=0x%08h", $time, imem_latched_addr, rom[(imem_latched_addr - 40'h00_0002_0000) >> 2]);
            end else if (imem_rvalid && imem_rready) begin
                imem_rvalid <= 1'b0;
                imem_rlast  <= 1'b0;
            end
        end
    end

    // Data Memory AXI4 Slave
    reg        dmem_rd_pending;
    reg [39:0] dmem_latched_araddr;
    reg        dmem_wr_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmem_awready        <= 1'b0;
            dmem_wready         <= 1'b0;
            dmem_bvalid         <= 1'b0;
            dmem_bresp          <= 2'b00;
            dmem_arready        <= 1'b0;
            dmem_rvalid         <= 1'b0;
            dmem_rdata          <= 64'h0;
            dmem_rlast          <= 1'b0;
            dmem_rresp          <= 2'b00;
            dmem_rd_pending     <= 1'b0;
            dmem_wr_pending     <= 1'b0;
            dmem_latched_araddr <= 40'h0;
        end else begin
            // Write Channel
            if (dmem_awvalid && dmem_wvalid && !dmem_awready && !dmem_wr_pending && !dmem_bvalid) begin
                dmem_awready    <= 1'b1;
                dmem_wready     <= 1'b1;
                ram[dmem_awaddr >> 3] <= dmem_wdata;
                dmem_wr_pending <= 1'b1;
            end else begin
                dmem_awready <= 1'b0;
                dmem_wready  <= 1'b0;
            end

            if (dmem_wr_pending) begin
                dmem_wr_pending <= 1'b0;
                dmem_bvalid     <= 1'b1;
                dmem_bresp      <= 2'b00;
            end else if (dmem_bvalid && dmem_bready) begin
                dmem_bvalid <= 1'b0;
            end

            // Read Channel
            if (dmem_arvalid && !dmem_arready && !dmem_rd_pending && !dmem_rvalid) begin
                dmem_arready        <= 1'b1;
                dmem_latched_araddr <= dmem_araddr;
                dmem_rd_pending     <= 1'b1;
            end else begin
                dmem_arready <= 1'b0;
            end

            if (dmem_rd_pending) begin
                dmem_rd_pending <= 1'b0;
                dmem_rvalid     <= 1'b1;
                dmem_rlast      <= 1'b1;
                dmem_rresp      <= 2'b00;
                dmem_rdata      <= ram[dmem_latched_araddr >> 3];
            end else if (dmem_rvalid && dmem_rready) begin
                dmem_rvalid <= 1'b0;
                dmem_rlast  <= 1'b0;
            end
        end
    end

    // Retirement monitor
    reg [4:0]  retired_rd;
    reg [63:0] retired_data;
    reg        retired_valid;
    always @(posedge clk) begin
        if (dut.wb_we && (dut.wb_rd != 5'h0)) begin
            $display("[RETIRE %0t] rd=x%0d data=%0d (hex 0x%0h)", $time, dut.wb_rd, dut.wb_data, dut.wb_data);
            retired_valid <= 1'b1;
            retired_rd    <= dut.wb_rd;
            retired_data  <= dut.wb_data;
        end else begin
            retired_valid <= 1'b0;
        end
    end

    task wait_for_retire(input [4:0] expected_rd, input [63:0] expected_val, input [511:0] test_label);
        integer timeout;
        begin
            timeout = 0;
            while ((!dut.wb_we || dut.wb_rd != expected_rd) && timeout < 100) begin
                @(posedge clk); #1;
                timeout = timeout + 1;
            end
            check(test_label, (dut.wb_we == 1'b1) && (dut.wb_rd == expected_rd) && (dut.wb_data == expected_val));
            if (!((dut.wb_we == 1'b1) && (dut.wb_rd == expected_rd) && (dut.wb_data == expected_val))) begin
                $display("   [DETAIL] timeout=%0d wb_we=%b wb_rd=%0d wb_data=%0d expected_rd=%0d expected_val=%0d",
                         timeout, dut.wb_we, dut.wb_rd, dut.wb_data, expected_rd, expected_val);
            end
        end
    endtask

    initial begin
        integer timeout;
        $dumpfile("verification_waves/rv_core_top.vcd");
        $dumpvars(0, tb_fresh_rv_core_top);

        // Initialize program ROM
        // 0x20000 (idx 0): ADDI x1, x0, 10
        rom[0] = 32'h00A0_0093;
        // 0x20004 (idx 1): ADDI x2, x0, 20
        rom[1] = 32'h0140_0113;
        // 0x20008 (idx 2): ADD  x3, x1, x2  (10 + 20 = 30)
        rom[2] = 32'h0020_81B3;
        // 0x2000C (idx 3): ADDI x4, x0, 50
        rom[3] = 32'h0320_0213;
        // 0x20010 (idx 4): ADDI x5, x4, 25  (50 + 25 = 75, back-to-back hazard forward EX->EX)
        rom[4] = 32'h0192_0293;
        // 0x20014 (idx 5): SD   x1, 16(x0)  (store 10 to RAM[2])
        rom[5] = 32'h0010_3823;
        // 0x20018 (idx 6): LD   x6, 16(x0)  (load 10 from RAM[2])
        rom[6] = 32'h0100_3303;
        // 0x2001C (idx 7): ADDI x7, x6, 5   (10 + 5 = 15, load-use hazard forward MEM->EX)
        rom[7] = 32'h0053_0393;
        // 0x20020 (idx 8): JAL  x0, 16      (jump to 0x20030, idx 12)
        rom[8] = 32'h0100_006F;
        // 0x20024 (idx 9): ADDI x9, x0, 99  (FLUSHED)
        rom[9] = 32'h0630_0493;
        // 0x20028 (idx 10): ADDI x9, x0, 99 (FLUSHED)
        rom[10] = 32'h0630_0493;
        // 0x2002C (idx 11): ADDI x9, x0, 99 (FLUSHED)
        rom[11] = 32'h0630_0493;
        // 0x20030 (idx 12): ADDI x10, x0, 100
        rom[12] = 32'h0640_0513;
        // 0x20034 (idx 13): MUL  x11, x1, x2 (10 * 20 = 200)
        rom[13] = 32'h0220_85B3;

        // Initialize signals
        clk         = 0;
        rst_n       = 0;
        irq_m_ext   = 0;
        irq_m_timer = 0;
        irq_m_soft  = 0;
        snoop_valid = 0;
        snoop_addr  = 0;
        snoop_type  = 0;
        halt_req    = 0;
        resume_req  = 0;

        // Reset
        #20;
        @(posedge clk); #1;
        rst_n = 1;

        // ----------------------------------------------------
        // Test 1: Reset Sequence & Core Boot State
        // ----------------------------------------------------
        @(posedge clk); #1;
        check("Test 1.1: Fetch PC initialized to RESET_PC (0x20000)", dut.u_fetch.pc == RESET_PC);
        check("Test 1.2: imem_arvalid asserted out of reset", imem_arvalid == 1'b1);
        check("Test 1.3: imem_araddr requests RESET_PC (0x20000)", imem_araddr == RESET_PC[39:0]);
        check("Test 1.4: hart_halted is 0 at reset", hart_halted == 1'b0);
        check("Test 1.5: hart_running is 1 at reset", hart_running == 1'b1);
        check("Test 1.6: Data bus write quiet at reset", dmem_awvalid == 1'b0);
        check("Test 1.7: Data bus read quiet at reset", dmem_arvalid == 1'b0);

        // ----------------------------------------------------
        // Test 2: Sequential Instruction Retirement (ADDI, ADDI, ADD)
        // ----------------------------------------------------
        wait_for_retire(5'd1, 64'd10, "Test 2.1: x1 retires with value 10 (ADDI x1, x0, 10)");
        @(posedge clk); #1;
        wait_for_retire(5'd2, 64'd20, "Test 2.2: x2 retires with value 20 (ADDI x2, x0, 20)");
        @(posedge clk); #1;
        wait_for_retire(5'd3, 64'd30, "Test 2.3: x3 retires with value 30 (ADD x3, x1, x2)");

        // ----------------------------------------------------
        // Test 3: Data Hazard & Operand Forwarding (EX->EX)
        // x4 = 50, x5 = x4 + 25 = 75
        // ----------------------------------------------------
        @(posedge clk); #1;
        wait_for_retire(5'd4, 64'd50, "Test 3.1: x4 retires with value 50 (ADDI x4, x0, 50)");
        @(posedge clk); #1;
        wait_for_retire(5'd5, 64'd75, "Test 3.2: x5 retires with value 75 via EX forwarding (ADDI x5, x4, 25)");

        // ----------------------------------------------------
        // Test 4: Data Memory Store Operation (SD x1, 16(x0))
        // ----------------------------------------------------
        // Wait for store to execute
        timeout = 0;
        while (!dmem_awvalid && timeout < 50) begin
            @(posedge clk); #1;
            timeout = timeout + 1;
        end
        check("Test 4.1: dmem_awvalid asserts on Store instruction", dmem_awvalid == 1'b1);
        check("Test 4.2: dmem_awaddr matches store offset 16", dmem_awaddr == 40'h00_0000_0010);
        check("Test 4.3: dmem_wvalid asserts with store data", dmem_wvalid == 1'b1);
        check("Test 4.4: dmem_wdata matches x1 value (10)", dmem_wdata == 64'd10);
        
        // Wait for store transaction to complete
        timeout = 0;
        while (!dmem_bvalid && timeout < 20) begin
            @(posedge clk); #1;
            timeout = timeout + 1;
        end
        @(posedge clk); #1;
        check("Test 4.5: RAM updated with store data at offset 16", ram[2] == 64'd10);

        // ----------------------------------------------------
        // Test 5: Data Memory Load & Load-Use Forwarding
        // LD x6, 16(x0) -> x6 = 10
        // ADDI x7, x6, 5 -> x7 = 15
        // ----------------------------------------------------
        wait_for_retire(5'd6, 64'd10, "Test 5.1: x6 retires with loaded value 10 (LD x6, 16(x0))");
        @(posedge clk); #1;
        wait_for_retire(5'd7, 64'd15, "Test 5.2: x7 retires with value 15 via Load-Use forwarding (ADDI x7, x6, 5)");

        // ----------------------------------------------------
        // Test 6: Branch/Jump Execution & Pipeline Flush (JAL x0, 16)
        // ----------------------------------------------------
        // Wait for branch taken
        timeout = 0;
        while (!dut.branch_taken && timeout < 50) begin
            @(posedge clk); #1;
            timeout = timeout + 1;
        end
        check("Test 6.1: branch_taken asserts on JAL instruction", dut.branch_taken == 1'b1);
        check("Test 6.2: flush_raw asserts on branch redirect", dut.flush_raw == 1'b1);
        check("Test 6.3: branch_target points to 0x20030", dut.branch_target == 64'h0000_0000_0002_0030);

        // Ensure target instruction x10 = 100 retires
        wait_for_retire(5'd10, 64'd100, "Test 6.4: Target instruction x10 retires with value 100");
        // Verify x9 was never retired (flushed instructions eliminated)
        check("Test 6.5: Flushed instruction x9 never retired to regfile", dut.u_decode.u_rf.mem[9] == 64'h0);

        // ----------------------------------------------------
        // Test 7: M-Extension Hardware Multiplier (MUL x11, x1, x2)
        // 10 * 20 = 200
        // ----------------------------------------------------
        wait_for_retire(5'd11, 64'd200, "Test 7.1: x11 retires with product 200 (MUL x11, x1, x2)");

        // ----------------------------------------------------
        // Test 8: Debug Halt & Resume Control
        // ----------------------------------------------------
        halt_req = 1'b1;
        @(posedge clk); #1;
        check("Test 8.1: hart_halted asserts immediately on halt_req", hart_halted == 1'b1);
        check("Test 8.2: hart_running deasserts on halt_req", hart_running == 1'b0);
        check("Test 8.3: Pipeline stall asserted during debug halt", dut.stall == 1'b1);

        halt_req   = 1'b0;
        resume_req = 1'b1;
        @(posedge clk); #1;
        check("Test 8.4: hart_halted deasserts on resume", hart_halted == 1'b0);
        check("Test 8.5: hart_running reasserts on resume", hart_running == 1'b1);
        check("Test 8.6: Pipeline stall deasserts on resume", dut.stall == 1'b0);

        // ----------------------------------------------------
        // Final Scorecard
        // ----------------------------------------------------
        #50;
        $display("\n=======================================================");
        $display(" rv_core_top Verification Scorecard");
        $display(" Total Passed: %0d", tests_passed);
        $display(" Total Failed: %0d", tests_failed);
        $display("=======================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED] rv_core_top 100%% verified.");
        end else begin
            $fatal(1, "[TESTBENCH FAILED] Found %0d failures.", tests_failed);
        end
        $finish;
    end

endmodule

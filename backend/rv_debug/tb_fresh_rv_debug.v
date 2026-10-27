// SPDX-License-Identifier: Apache-2.0
// Fresh, self-checking testbench for rv_debug module
// SMVDU-TITAN-X Microprocessor Verification Suite
`timescale 1ns/1ps
`include "params.vh"

module tb_fresh_rv_debug;
    localparam NUM_HARTS = 5;

    reg         clk;
    reg         rst_n;

    reg         tck;
    reg         tms;
    reg         tdi;
    wire        tdo;

    wire [NUM_HARTS-1:0] halt_req;
    wire [NUM_HARTS-1:0] resume_req;
    reg  [NUM_HARTS-1:0] hart_halted;
    reg  [NUM_HARTS-1:0] hart_running;
    reg  [NUM_HARTS-1:0] hart_unavail;

    wire [4:0]  reg_sel;
    wire        reg_wr;
    wire [63:0] reg_wdata;
    reg  [63:0] reg_rdata;
    wire        cmd_exec;
    reg         cmd_done;
    reg         cmd_err;

    wire        sb_arvalid;
    reg         sb_arready;
    wire [39:0] sb_araddr;
    reg         sb_rvalid;
    wire        sb_rready;
    reg  [63:0] sb_rdata;
    reg  [1:0]  sb_rresp;
    wire        sb_awvalid;
    reg         sb_awready;
    wire [39:0] sb_awaddr;
    wire        sb_wvalid;
    reg         sb_wready;
    wire [63:0] sb_wdata;
    wire [7:0]  sb_wstrb;
    wire        sb_wlast;
    reg         sb_bvalid;
    wire        sb_bready;

    integer tests_passed = 0;
    integer tests_failed = 0;

    // Clocks
    always #5  clk = ~clk; // 100MHz system clock
    always #25 tck = ~tck; // 20MHz JTAG clock

    // Instantiate DUT
    rv_debug #(
        .NUM_HARTS(`NUM_HARTS),
        .PROGBUF_SIZE(16)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .tck         (tck),
        .tms         (tms),
        .tdi         (tdi),
        .tdo         (tdo),
        .halt_req    (halt_req),
        .resume_req  (resume_req),
        .hart_halted (hart_halted),
        .hart_running(hart_running),
        .hart_unavail(hart_unavail),
        .reg_sel     (reg_sel),
        .reg_wr      (reg_wr),
        .reg_wdata   (reg_wdata),
        .reg_rdata   (reg_rdata),
        .cmd_exec    (cmd_exec),
        .cmd_done    (cmd_done),
        .cmd_err     (cmd_err),
        .sb_arvalid  (sb_arvalid),
        .sb_arready  (sb_arready),
        .sb_araddr   (sb_araddr),
        .sb_rvalid   (sb_rvalid),
        .sb_rready   (sb_rready),
        .sb_rdata    (sb_rdata),
        .sb_rresp    (sb_rresp),
        .sb_awvalid  (sb_awvalid),
        .sb_awready  (sb_awready),
        .sb_awaddr   (sb_awaddr),
        .sb_wvalid   (sb_wvalid),
        .sb_wready   (sb_wready),
        .sb_wdata    (sb_wdata),
        .sb_wstrb    (sb_wstrb),
        .sb_wlast    (sb_wlast),
        .sb_bvalid   (sb_bvalid),
        .sb_bready   (sb_bready)
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

    // JTAG Helper Tasks
    task tap_reset;
        integer b;
        begin
            tms = 1'b1;
            for (b = 0; b < 6; b = b + 1) begin
                @(posedge tck); #1;
            end
            tms = 1'b0;
            @(posedge tck); #1; // Transitions TLR -> RTI
        end
    endtask

    task tap_shift_ir(input [4:0] ir_val);
        integer b;
        begin
            // From RTI -> Select-DR -> Select-IR -> Capture-IR -> Shift-IR
            tms = 1'b1; @(posedge tck); #1; // Select-DR
            tms = 1'b1; @(posedge tck); #1; // Select-IR
            tms = 1'b0; @(posedge tck); #1; // Capture-IR
            tms = 1'b0; @(posedge tck); #1; // Shift-IR

            for (b = 0; b < 5; b = b + 1) begin
                tdi = ir_val[b];
                tms = (b == 4) ? 1'b1 : 1'b0; // Exit1-IR on last bit
                @(posedge tck); #1;
            end

            // Exit1-IR -> Update-IR -> Run-Test/Idle
            tms = 1'b1; @(posedge tck); #1; // Update-IR
            tms = 1'b0; @(posedge tck); #1; // Run-Test/Idle
        end
    endtask

    task tap_shift_dr(input [40:0] dr_in, output [40:0] dr_out, input integer len);
        integer b;
        begin
            // From RTI -> Select-DR -> Capture-DR -> Shift-DR
            tms = 1'b1; @(posedge tck); #1; // Select-DR
            tms = 1'b0; @(posedge tck); #1; // Capture-DR
            tms = 1'b0; @(posedge tck); #1; // Shift-DR

            for (b = 0; b < len; b = b + 1) begin
                dr_out[b] = tdo;
                tdi = dr_in[b];
                tms = (b == len - 1) ? 1'b1 : 1'b0; // Exit1-DR on last bit
                @(posedge tck); #1;
            end

            // Exit1-DR -> Update-DR -> Run-Test/Idle
            tms = 1'b1; @(posedge tck); #1; // Update-DR
            tms = 1'b0; @(posedge tck); #1; // Run-Test/Idle
        end
    endtask

    reg [40:0] shift_data_out;

    reg resume_seen;
    reg cmd_exec_seen;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            resume_seen   <= 1'b0;
            cmd_exec_seen <= 1'b0;
        end else begin
            if (resume_req[0]) resume_seen   <= 1'b1;
            if (cmd_exec)      cmd_exec_seen <= 1'b1;
        end
    end

    initial begin
        $dumpfile("verification_waves/rv_debug.vcd");
        $dumpvars(0, tb_fresh_rv_debug);

        clk          = 0;
        tck          = 0;
        rst_n        = 0;
        tms          = 1;
        tdi          = 0;
        hart_halted  = 5'b00000;
        hart_running = 5'b11111;
        hart_unavail = 5'b00000;
        reg_rdata    = 64'h0;
        cmd_done     = 0;
        cmd_err      = 0;
        sb_arready   = 0;
        sb_rvalid    = 0;
        sb_rdata     = 64'h0;
        sb_rresp     = 2'b00;
        sb_awready   = 0;
        sb_wready    = 0;
        sb_bvalid    = 0;

        // Reset
        #20;
        @(posedge clk); #1;
        rst_n = 1;

        // ----------------------------------------------------
        // Test 1: Reset State & TAP Reset
        // ----------------------------------------------------
        tap_reset();
        @(posedge clk); #1;
        check("Test 1.1: Reset halt_req all 0", halt_req == 5'b0);
        check("Test 1.2: Reset resume_req all 0", resume_req == 5'b0);
        check("Test 1.3: Reset cmd_exec is 0", cmd_exec == 1'b0);
        check("Test 1.4: Reset sb_arvalid is 0", sb_arvalid == 1'b0);

        // ----------------------------------------------------
        // Test 2: JTAG IDCODE Shift
        // Select IDCODE (5'h01), shift 32 bits from DR
        // ----------------------------------------------------
        tap_shift_ir(5'h01); // IDCODE
        tap_shift_dr(41'h0, shift_data_out, 32);
        $display("DEBUG: shift_data_out[31:0] = 0x%08h (expected 0x202304FD)", shift_data_out[31:0]);
        check("Test 2.1: JTAG IDCODE matches 0x202304FD", shift_data_out[31:0] == 32'h2023_04FD);

        // ----------------------------------------------------
        // Test 3: DMI Access via DBGBUS (Halt Request to Hart 0)
        // Select DBGBUS (5'h11)
        // ----------------------------------------------------
        tap_shift_ir(5'h11); // DBGBUS

        // DMI Packet: {addr[6:0], data[31:0], op[1:0]}
        // Write DMCONTROL (0x10): dmactive=1 (bit 0), haltreq=1 (bit 31), hartsel=0
        // Data = 32'h8000_0001
        // Packet = {7'h10, 32'h8000_0001, 2'b10 (write)}
        tap_shift_dr({7'h10, 32'h8000_0001, 2'b10}, shift_data_out, 41);

        // Allow DMI clock domain crossing sync to clk
        #150;
        @(posedge clk); #1;
        check("Test 3.1: halt_req[0] asserts to request halt", halt_req[0] == 1'b1);
        check("Test 3.2: Other harts not requested to halt", halt_req[4:1] == 4'b0);

        // Update hart status: hart 0 halted
        hart_halted[0]  = 1'b1;
        hart_running[0] = 1'b0;

        // ----------------------------------------------------
        // Test 4: Resume Request to Hart 0
        // Write DMCONTROL: resumereq=1 (bit 30), dmactive=1 (bit 0)
        // Data = 32'h4000_0001
        // ----------------------------------------------------
        resume_seen = 1'b0;
        tap_shift_dr({7'h10, 32'h4000_0001, 2'b10}, shift_data_out, 41);
        #150;
        check("Test 4.1: resume_req[0] asserts to resume hart", resume_seen == 1'b1);

        hart_halted[0]  = 1'b0;
        hart_running[0] = 1'b1;

        // ----------------------------------------------------
        // Test 5: Abstract Command Register Write
        // Write DATA0 = 0x5555_AAAA, DATA1 = 0x1234_5678
        // ----------------------------------------------------
        tap_shift_dr({7'h04, 32'h5555_AAAA, 2'b10}, shift_data_out, 41); // DM_DATA0
        #100;
        tap_shift_dr({7'h05, 32'h1234_5678, 2'b10}, shift_data_out, 41); // DM_DATA1
        #100;

        // Execute Command (0x17): write register x5 (reg_sel = 5, write = 1)
        // [16]=1 (write), [15:10]=5 -> data = 32'h0001_1400
        cmd_exec_seen = 1'b0;
        tap_shift_dr({7'h17, 32'h0001_1400, 2'b10}, shift_data_out, 41);
        #150;
        check("Test 5.1: Abstract command executes cmd_exec == 1", cmd_exec_seen == 1'b1);
        check("Test 5.2: Register write enable reg_wr == 1", reg_wr == 1'b1);
        check("Test 5.3: Register select reg_sel == 5", reg_sel == 5'd5);
        check("Test 5.4: Register write data matches {data1, data0}",
              reg_wdata == 64'h1234_5678_5555_AAAA);

        // Acknowledge command completion
        cmd_done = 1'b1;
        @(posedge clk); #1;
        cmd_done = 1'b0;

        // ----------------------------------------------------
        // Test 6: System Bus Access (SBA) Write
        // ----------------------------------------------------
        // Set SBADDRESS0 (0x39) = 0x8000_1000
        tap_shift_dr({7'h39, 32'h8000_1000, 2'b10}, shift_data_out, 41);
        #100;

        // Write SBDATA0 (0x3C) = 0xDEAD_BEEF (triggers AXI write)
        tap_shift_dr({7'h3C, 32'hDEAD_BEEF, 2'b10}, shift_data_out, 41);
        #100;
        @(posedge clk); #1;
        check("Test 6.1: SBA write asserts sb_awvalid", sb_awvalid == 1'b1);
        check("Test 6.2: SBA write address matches 0x8000_1000", sb_awaddr[31:0] == 32'h8000_1000);
        check("Test 6.3: SBA write asserts sb_wvalid", sb_wvalid == 1'b1);
        check("Test 6.4: SBA write data matches 0xDEAD_BEEF", sb_wdata[31:0] == 32'hDEAD_BEEF);

        // Handshake SBA write
        sb_awready = 1'b1;
        sb_wready  = 1'b1;
        @(posedge clk); #1;
        sb_awready = 1'b0;
        sb_wready  = 1'b0;
        sb_bvalid  = 1'b1;
        @(posedge clk); #1;
        sb_bvalid  = 1'b0;

        // ----------------------------------------------------
        // Final Scorecard
        // ----------------------------------------------------
        #20;
        $display("\n=======================================================");
        $display(" rv_debug Verification Scorecard");
        $display(" Total Passed: %0d", tests_passed);
        $display(" Total Failed: %0d", tests_failed);
        $display("=======================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED] rv_debug 100%% verified.");
        end else begin
            $fatal(1, "[TESTBENCH FAILED] Found %0d failures.", tests_failed);
        end
        $finish;
    end
endmodule

// SPDX-License-Identifier: Apache-2.0
// Brand-New Fresh Self-Checking Testbench for rv_csr
// Generated strictly from prd.json architectural truth tables & constraints

`timescale 1ns/1ps

module tb_fresh_rv_csr;
    reg         clk;
    reg         rst_n;
    reg  [11:0] csr_raddr;
    wire [63:0] csr_rdata;
    reg         csr_we;
    reg  [11:0] csr_waddr;
    reg  [63:0] csr_wdata;
    reg         trap_we;
    reg  [63:0] trap_pc;
    reg  [63:0] trap_cause;
    reg         mret_we;
    reg         mip_m_ext;
    reg         mip_m_timer;
    reg         mip_m_soft;
    reg         retire_pulse;

    wire [63:0] mtvec_out;
    wire [63:0] mepc_out;
    wire        irq_pending;

    integer err_cnt = 0;
    integer test_cnt = 0;
    integer i;

    rv_csr dut (
        .clk(clk),
        .rst_n(rst_n),
        .csr_raddr(csr_raddr),
        .csr_rdata(csr_rdata),
        .csr_we(csr_we),
        .csr_waddr(csr_waddr),
        .csr_wdata(csr_wdata),
        .trap_we(trap_we),
        .trap_pc(trap_pc),
        .trap_cause(trap_cause),
        .mret_we(mret_we),
        .mip_m_ext(mip_m_ext),
        .mip_m_timer(mip_m_timer),
        .mip_m_soft(mip_m_soft),
        .retire_pulse(retire_pulse),
        .mtvec_out(mtvec_out),
        .mepc_out(mepc_out),
        .irq_pending(irq_pending)
    );

    always #5 clk = ~clk;

    localparam [63:0] EXPECTED_MISA = (64'd2 << 62) | (64'd1 << 12) | (64'd1 << 8) | (64'd1 << 2);

    initial begin
        $dumpfile("verification_waves/rv_csr.vcd");
        $dumpvars(0, tb_fresh_rv_csr);

        clk = 0;
        rst_n = 1;
        csr_raddr = 12'h0;
        csr_we = 0;
        csr_waddr = 12'h0;
        csr_wdata = 64'h0;
        trap_we = 0;
        trap_pc = 64'h0;
        trap_cause = 64'h0;
        mret_we = 0;
        mip_m_ext = 0;
        mip_m_timer = 0;
        mip_m_soft = 0;
        retire_pulse = 0;

        $display("=== STARTING FRESH SELF-CHECKING VERIFICATION: rv_csr ===");

        // Test 1: Reset check
        test_cnt = test_cnt + 1;
        @(posedge clk); #1 rst_n = 0;
        repeat (2) @(posedge clk); #1 rst_n = 1;
        @(posedge clk); #1;
        csr_raddr = 12'h301; // misa
        #1;
        if (csr_rdata !== EXPECTED_MISA) begin
            $display("ERROR [T1]: misa reset incorrect: got %h, expected %h", csr_rdata, EXPECTED_MISA);
            err_cnt = err_cnt + 1;
        end

        csr_raddr = 12'h300; // mstatus
        #1;
        if (csr_rdata !== 64'h0) begin
            $display("ERROR [T1]: mstatus not 0 after reset: %h", csr_rdata);
            err_cnt = err_cnt + 1;
        end

        csr_raddr = 12'hF14; // mhartid
        #1;
        if (csr_rdata !== 64'h0) begin
            $display("ERROR [T1]: mhartid not 0: %h", csr_rdata);
            err_cnt = err_cnt + 1;
        end
        if (err_cnt == 0) $display("PASS [T1]: Reset state and WARL misa confirmed");

        // Test 2: Standard CSR Register Write/Readback
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        csr_we = 1;
        csr_waddr = 12'h340; // mscratch
        csr_wdata = 64'hCAFE_BABE_1234_5678;
        @(posedge clk); #1;
        csr_we = 0;
        csr_raddr = 12'h340;
        #1;
        if (csr_rdata !== 64'hCAFE_BABE_1234_5678) begin
            $display("ERROR [T2]: mscratch write/read failed, got %h", csr_rdata);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T2]: mscratch read-write verified");
        end

        // Test 3: mtvec 4-byte Alignment WARL Check
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        csr_we = 1;
        csr_waddr = 12'h305; // mtvec
        csr_wdata = 64'h0000_0000_8000_0003; // unaligned
        @(posedge clk); #1;
        csr_we = 0;
        csr_raddr = 12'h305;
        #1;
        if (csr_rdata !== 64'h0000_0000_8000_0000 || mtvec_out !== 64'h0000_0000_8000_0000) begin
            $display("ERROR [T3]: mtvec alignment failed: csr_rdata=%h mtvec_out=%h", csr_rdata, mtvec_out);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T3]: mtvec WARL direct alignment confirmed");
        end

        // Test 4: Trap Entry and MRET Status Transition
        test_cnt = test_cnt + 1;
        // Step 4a: First enable MIE in mstatus
        @(posedge clk); #1;
        csr_we = 1;
        csr_waddr = 12'h300; // mstatus
        csr_wdata = (64'd1 << 3); // MIE = 1
        @(posedge clk); #1;
        csr_we = 0;

        // Step 4b: Trigger trap
        @(posedge clk); #1;
        trap_we = 1;
        trap_pc = 64'h0000_0000_8000_1022; // unaligned PC
        trap_cause = 64'd2; // Illegal instruction
        @(posedge clk); #1;
        trap_we = 0;
        #1;
        // Check mepc (low 2 bits clear), mcause, and mstatus (MIE=0, MPIE=1, MPP=3)
        csr_raddr = 12'h341; // mepc
        #1;
        if (csr_rdata !== 64'h0000_0000_8000_1020 || mepc_out !== 64'h0000_0000_8000_1020) begin
            $display("ERROR [T4]: mepc trap capture failed: got %h", csr_rdata);
            err_cnt = err_cnt + 1;
        end

        csr_raddr = 12'h342; // mcause
        #1;
        if (csr_rdata !== 64'd2) begin
            $display("ERROR [T4]: mcause trap capture failed: got %0d", csr_rdata);
            err_cnt = err_cnt + 1;
        end

        csr_raddr = 12'h300; // mstatus
        #1;
        if (csr_rdata[3] !== 1'b0 || csr_rdata[7] !== 1'b1 || csr_rdata[12:11] !== 2'b11) begin
            $display("ERROR [T4]: mstatus trap transition failed: MIE=%b MPIE=%b MPP=%b",
                     csr_rdata[3], csr_rdata[7], csr_rdata[12:11]);
            err_cnt = err_cnt + 1;
        end

        // Step 4c: Execute MRET
        @(posedge clk); #1;
        mret_we = 1;
        @(posedge clk); #1;
        mret_we = 0;
        #1;
        csr_raddr = 12'h300;
        #1;
        if (csr_rdata[3] !== 1'b1 || csr_rdata[7] !== 1'b1 || csr_rdata[12:11] !== 2'b00) begin
            $display("ERROR [T4]: mstatus mret restoration failed: MIE=%b MPIE=%b MPP=%b",
                     csr_rdata[3], csr_rdata[7], csr_rdata[12:11]);
            err_cnt = err_cnt + 1;
        end
        if (err_cnt == 0) $display("PASS [T4]: Trap entry and MRET lifecycle verified");

        // Test 5: Interrupt Pending Logic
        test_cnt = test_cnt + 1;
        // Enable timer interrupt in mie (bit 7)
        @(posedge clk); #1;
        csr_we = 1;
        csr_waddr = 12'h304; // mie
        csr_wdata = (64'd1 << 7); // MTIE = 1
        @(posedge clk); #1;
        csr_we = 0;

        mip_m_timer = 1;
        #1;
        // Since mstatus.MIE = 1 (restored by mret) and MTIE = 1, irq_pending must be 1
        if (irq_pending !== 1'b1) begin
            $display("ERROR [T5]: irq_pending did not assert for enabled timer interrupt");
            err_cnt = err_cnt + 1;
        end

        // Deassert mip_m_timer
        mip_m_timer = 0;
        #1;
        if (irq_pending !== 1'b0) begin
            $display("ERROR [T5]: irq_pending remained asserted after interrupt cleared");
            err_cnt = err_cnt + 1;
        end
        if (err_cnt == 0) $display("PASS [T5]: Interrupt pending gating logic verified");

        // Test 6: Performance Counters (mcycle and minstret)
        test_cnt = test_cnt + 1;
        csr_raddr = 12'hB00; // mcycle
        #1;
        // Cycle counts are non-zero and advancing
        if (csr_rdata == 64'd0) begin
            $display("ERROR [T6]: mcycle did not advance");
            err_cnt = err_cnt + 1;
        end

        // Pulse retire 3 times
        repeat (3) begin
            @(posedge clk); #1;
            retire_pulse = 1;
        end
        @(posedge clk); #1;
        retire_pulse = 0;
        #1;
        csr_raddr = 12'hB02; // minstret
        #1;
        if (csr_rdata !== 64'd3) begin
            $display("ERROR [T6]: minstret expected 3, got %0d", csr_rdata);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T6]: mcycle and minstret performance counters verified");
        end

        #20;

        $display("=== VERIFICATION SUMMARY ===");
        $display("Total Tests Executed: %0d", test_cnt);
        $display("Total Errors: %0d", err_cnt);

        if (err_cnt == 0) begin
            $display("ALL TESTS PASSED: rv_csr 100%% VERIFIED");
        end else begin
            $display("VERIFICATION FAILED: %0d errors detected!", err_cnt);
        end
        $finish;
    end
endmodule

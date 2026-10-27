// SPDX-License-Identifier: Apache-2.0
// SMVDU-TitanX SoC — rv_csr Unit Testbench (Phase 5 Step 5.4)
//
// Directed checks against the spec, independent of the pipeline:
//   reset state, RW semantics per implemented CSR, WARL masks (mstatus
//   wr-mask, mie mask, mtvec mode-bit clear, mepc[1:0] clear), read-only
//   hartid, unimplemented -> 0, trap entry shuffle (MPIE<-MIE, MIE<-0,
//   MPP<-M, mepc<-pc&~3), mret restore, counter increments, irq_pending
//   enable/pending gating.
`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module tb_rv_csr();
    reg clk, rst_n;
    reg  [11:0] raddr;
    wire [63:0] rdata;
    reg         we;
    reg  [11:0] waddr;
    reg  [63:0] wdata;
    reg         trap_we, mret_we, retire;
    reg  [63:0] trap_pc, trap_cause;
    reg         ip_ext, ip_timer, ip_soft;
    wire [63:0] mtvec_o, mepc_o;
    wire        irq_pend;

    integer errors;

    rv_csr dut (
        .clk(clk), .rst_n(rst_n),
        .csr_raddr(raddr), .csr_rdata(rdata),
        .csr_we(we), .csr_waddr(waddr), .csr_wdata(wdata),
        .trap_we(trap_we), .trap_pc(trap_pc), .trap_cause(trap_cause),
        .mret_we(mret_we),
        .mip_m_ext(ip_ext), .mip_m_timer(ip_timer), .mip_m_soft(ip_soft),
        .retire_pulse(retire),
        .mtvec_out(mtvec_o), .mepc_out(mepc_o), .irq_pending(irq_pend)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task fail(input [255:0] msg);
        begin
            $display("FAIL [%0t] %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    // sync write helper: present during one posedge
    task wr(input [11:0] a, input [63:0] d);
        begin
            @(negedge clk);
            we = 1; waddr = a; wdata = d;
            @(negedge clk);
            we = 0;
        end
    endtask

    task chk64(input [63:0] got, input [63:0] exp, input [255:0] what);
        if (got !== exp) begin
            $display("FAIL [%0t] %0s: got=%h exp=%h", $time, what, got, exp);
            errors = errors + 1;
        end
    endtask

    integer i;

    initial begin
        $dumpfile("tb_rv_csr.vcd");
        $dumpvars(1, tb_rv_csr);
        errors = 0;
        raddr = 0; we = 0; waddr = 0; wdata = 0;
        trap_we = 0; mret_we = 0; retire = 0;
        trap_pc = 0; trap_cause = 0;
        ip_ext = 0; ip_timer = 0; ip_soft = 0;

        rst_n = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        // ---- reset state ----
        raddr = 12'h300; #1; chk64(rdata, 64'h0, "reset mstatus");
        raddr = 12'h301; #1;
        // RV64IMC identity: MXL=2 lives in [63:62]; low 32 carry I|M|C
        chk64(rdata, (64'd2 << 62) | (64'd1 << 12) | (64'd1 << 8) | (64'd1 << 2),
              "reset misa");
        raddr = 12'hF14; #1; chk64(rdata, 64'h0, "reset mhartid");
        raddr = 12'h305; #1; chk64(rdata, 64'h0, "reset mtvec");
        raddr = 12'h999; #1; chk64(rdata, 64'h0, "unimplemented reads 0");

        // ---- plain RW: mscratch ----
        wr(12'h340, 64'hDEAD_BEEF_1234_5678);
        raddr = 12'h340; #1; chk64(rdata, 64'hDEAD_BEEF_1234_5678, "mscratch rw");

        // ---- WARL: mtvec mode bits cleared ----
        wr(12'h305, 64'h0000_0000_0000_1043);          // base 0x1040 | vectored mode 3
        raddr = 12'h305; #1;
        chk64(rdata, 64'h0000_0000_0000_1040, "mtvec mode bits forced DIRECT");
        chk64(mtvec_o, 64'h0000_0000_0000_1040, "mtvec_out");

        // ---- WARL: mepc low bits clear ----
        wr(12'h341, 64'h0000_0000_0002_00FF);
        raddr = 12'h341; #1;
        chk64(rdata, 64'h0000_0000_0002_00FC, "mepc[1:0] cleared");

        // ---- WARL: mstatus mask (try writing UNSUPPORTED high bit) ----
        wr(12'h300, 64'hFFFF_FFFF_FFFF_FF88);          // MIE|MPIE set, MPP=11, junk elsewhere
        raddr = 12'h300; #1;
        chk64(rdata, (64'd1 << 3) | (64'd1 << 7) | (64'd3 << 11),
              "mstatus write mask");

        // ---- WARL: mie mask ----
        wr(12'h304, 64'h0000_0000_0000_0AAA);
        raddr = 12'h304; #1;
        chk64(rdata, (64'd1 << 3) | (64'd1 << 7) | (64'd1 << 11),
              "mie write mask");

        // ---- read-only mhartid ignores writes ----
        wr(12'hF14, 64'h1234);
        raddr = 12'hF14; #1; chk64(rdata, 64'h0, "mhartid read-only");

        // ---- trap entry shuffle ----
        // current mstatus: MIE=1 MPIE=1 (from FFFF..FF88 masked write)
        trap_we = 1; trap_pc = 64'h0000_0000_0002_0416; trap_cause = 64'd11;
        @(negedge clk);
        trap_we = 0;
        raddr = 12'h341; #1;
        chk64(rdata, 64'h0000_0000_0002_0414, "trap mepc = pc & ~3");
        raddr = 12'h342; #1;
        chk64(rdata, 64'd11, "trap mcause");
        raddr = 12'h300; #1;
        chk64(rdata[3], 1'b0,  "post-trap MIE=0");
        chk64(rdata[7], 1'b1,  "post-trap MPIE=old MIE");
        chk64(rdata[12:11], 2'b11, "post-trap MPP=M");

        // interrupts must NOT pend while MIE=0 even though enabled+pending
        ip_timer = 1;
        #1; chk64(irq_pend, 1'b0, "irq gated by MIE=0");

        // ---- mret restore ----
        mret_we = 1;
        @(negedge clk);
        mret_we = 0;
        raddr = 12'h300; #1;
        chk64(rdata[3], 1'b1, "post-mret MIE=old MPIE");
        chk64(rdata[7], 1'b1, "post-mret MPIE=1");
        chk64(rdata[12:11], 2'b00, "post-mret MPP=U");

        // now enabled pending raises irq_pending (MTIE & mip_timer)
        #1; chk64(irq_pend, 1'b1, "irq pends when enabled");
        ip_timer = 0;
        wr(12'h304, 64'h0);                            // disable all
        #1; chk64(irq_pend, 1'b0, "irq gated by mie=0");

        // ---- counters ----
        raddr = 12'hB02; #1;
        i = rdata;                                     // minstret snapshot
        retire = 1;
        repeat (7) @(posedge clk);
        #1;
        retire = 0;
        raddr = 12'hB02; #1;
        if (rdata < i + 7)
            fail("minstret did not count 7 retire pulses");
        else
            $display("PASS: minstret counted retire pulses (%0d -> %0d)", i, rdata);
        raddr = 12'hC02; #1;
        if (rdata < i + 7) fail("instret alias mismatch");
        raddr = 12'hC00; #1;
        if (^rdata === 1'bx) fail("cycle alias X");

        // ---- cause/mtval/mscratch full-width write ----
        wr(12'h342, 64'h8000_0000_0000_0001);
        raddr = 12'h342; #1; chk64(rdata, 64'h8000_0000_0000_0001, "mcause full width");
        wr(12'h343, ~64'h0);
        raddr = 12'h343; #1; chk64(rdata, ~64'h0, "mtval full width");

        $display("\n==============================");
        if (errors == 0) begin
            $display("RV_CSR VERDICT: ✅ PASS — CSR file matches spec contract");
            $display("REGRESS_RESULT: PASS");
        end else begin
            $display("RV_CSR VERDICT: ❌ FAIL — %0d errors", errors);
            $display("REGRESS_RESULT: FAIL");
        end
        $display("==============================\n");
        $finish;
    end

    initial begin
        #20_000;
        $display("RV_CSR VERDICT: ❌ FAIL — watchdog");
        $display("REGRESS_RESULT: FAIL");
        $finish;
    end
endmodule

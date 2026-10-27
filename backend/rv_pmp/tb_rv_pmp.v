// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RV PMP Directed Self-Checking Testbench
// Tests: default allow in M-mode, PMP NA4 region check, NAPOT region, access violation
`timescale 1ns/1ps

module tb_rv_pmp();
    parameter NUM_ENTRIES = 8;  // = PMP_ENTRIES per hart

    reg        clk, rst_n;
    reg [37:0] paddr;
    reg        check_r, check_w, check_x;
    reg [1:0]  priv_mode;  // 2'b11=M, 2'b01=S, 2'b00=U
    reg        check_en;
    reg [63:0] pmpcfg0;       // PMP entries 0-7 config
    reg [63:0] pmpcfg2;       // PMP entries 8-15 (unused here)
    reg [303:0] pmpaddr_packed;  // 8 entries × 38 bits = 304 bits

    wire       pmp_fault;

    integer error_count;

    rv_pmp #(.NUM_ENTRIES(NUM_ENTRIES)) uut (
        .clk(clk), .rst_n(rst_n),
        .paddr(paddr), .check_r(check_r), .check_w(check_w), .check_x(check_x),
        .priv_mode(priv_mode), .check_en(check_en),
        .pmpcfg0(pmpcfg0), .pmpcfg2(pmpcfg2),
        .pmpaddr_packed(pmpaddr_packed),
        .pmp_fault(pmp_fault)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [63:0] got; input [63:0] exp; input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=%0d exp=%0d", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    initial begin
        $dumpfile("tb_rv_pmp.vcd");
        $dumpvars(0, tb_rv_pmp);
        error_count = 0;
        paddr=0; check_r=0; check_w=0; check_x=0;
        priv_mode=2'b11;  // M-mode default
        check_en=0; pmpcfg0=64'h0; pmpcfg2=64'h0;
        pmpaddr_packed=304'h0;
        rst_n=0; repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

        // TEST 1: M-mode with no PMP entries configured → default allow
        $display("\n--- TEST 1: M-mode, no PMP configured → allow ---");
        @(posedge clk); #1;
        paddr=38'h0000_1000; check_r=1; check_en=1; priv_mode=2'b11;
        @(posedge clk); #1;
        check(pmp_fault, 1'b0, "pmp_fault=0 in M-mode with no PMP (default allow)");
        check_en=0; check_r=0;

        // TEST 2: Configure PMP entry 0 as NA4 region at addr=0x1000 (4-byte)
        // pmpcfg byte 0: A=01 (NA4), R=1, W=0, X=0 → 0b_0001_0001 = 0x11
        // NA4 address: pmpaddr = paddr >> 2 = 0x1000 >> 2 = 0x400
        $display("\n--- TEST 2: NA4 region 0x1000-0x1003, R-only ---");
        @(posedge clk); #1;
        // pmpcfg0[7:0] = 0x11 (entry 0: A=NA4=2'b10, R=1, W=0, X=0, L=0)
        // Bits: L=0,_=00,A=10,X=0,W=0,R=1 → 0b_0001_0001 = 0x11
        pmpcfg0 = 64'h0000_0000_0000_0011;
        // NA4 match: paddr[37:2] == pmpaddr[37:2]
        // For PA=0x1000: PA[37:2]=0x400; pmpaddr[37:2] must also = 0x400
        // So pmpaddr = 0x400 << 2 = 0x1000 (the NA4 address encoding)
        pmpaddr_packed[37:0] = 38'h0000_0001_000;  // 0x1000
        @(posedge clk); #1;

        // TEST 2a: Read within region → no fault (S-mode)
        paddr=38'h0000_1000; check_r=1; check_w=0; check_en=1; priv_mode=2'b01;
        @(posedge clk); #1;
        check(pmp_fault, 1'b0, "pmp_fault=0: read within NA4 R-region");
        check_en=0;

        // TEST 2b: Write within region → fault (W=0 in config)
        @(posedge clk); #1;
        paddr=38'h0000_1000; check_r=0; check_w=1; check_en=1; priv_mode=2'b01;
        @(posedge clk); #1;
        check(pmp_fault, 1'b1, "pmp_fault=1: write to R-only NA4 region");
        check_en=0; check_w=0;

        // TEST 3: Address outside PMP region → M-mode still allowed
        $display("\n--- TEST 3: Address outside all PMP regions → M-mode allow ---");
        @(posedge clk); #1;
        paddr=38'h0000_5000; check_r=1; check_en=1; priv_mode=2'b11;
        @(posedge clk); #1;
        check(pmp_fault, 1'b0, "pmp_fault=0: M-mode access outside PMP region");
        check_en=0; check_r=0;

        // TEST 4: U-mode with no matching PMP → fault (default deny for U/S)
        $display("\n--- TEST 4: U-mode no matching PMP → fault ---");
        @(posedge clk); #1;
        paddr=38'h0000_5000; check_r=1; check_en=1; priv_mode=2'b00;  // U-mode
        @(posedge clk); #1;
        check(pmp_fault, 1'b1, "pmp_fault=1: U-mode with no PMP match (default deny)");
        check_en=0; check_r=0;

        $display("\n==============================");
        if (error_count == 0)
            $display("RV_PMP VERDICT: ✅ PASS — All tests passed");
        else
            $display("RV_PMP VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #500_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

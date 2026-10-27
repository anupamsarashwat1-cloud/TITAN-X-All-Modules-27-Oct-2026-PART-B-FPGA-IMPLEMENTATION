// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — ECDSA Engine Directed Self-Checking Testbench
// Register map (paddr[11:8]):
//   0: paddr[7:0]==0x00 → ctrl_reg R/W; paddr[7:0]==0x04 → stat_reg (R)
//   1: hash_ram[paddr[5:2]]  (W: message hash)
//   2: key_ram[paddr[5:2]]   (W: private/public key)
//   3: r_ram[paddr[5:2]]     (W: signature R component)
//   4: s_ram[paddr[5:2]]     (W: signature S component)
// ctrl_reg: [0]=start, [1]=mode (0=P256,1=P384), [2]=op (0=verify,1=sign)
`timescale 1ns/1ps

module tb_ecdsa_engine();

    reg        clk;
    reg        rst_n;
    reg [31:0] paddr;
    reg        psel;
    reg        penable;
    reg        pwrite;
    reg [31:0] pwdata;
    wire[31:0] prdata;
    wire       pready;
    wire       pslverr;
    wire       ecdsa_irq;

    integer error_count;

    ecdsa_engine uut (
        .clk(clk), .rst_n(rst_n),
        .paddr(paddr), .psel(psel), .penable(penable), .pwrite(pwrite),
        .pwdata(pwdata), .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .ecdsa_irq(ecdsa_irq)
    );

    initial clk = 0;
    always #3.6 clk = ~clk;

    task apb_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk); #1;
            paddr = addr; pwdata = data; psel = 1; penable = 0; pwrite = 1;
            @(posedge clk); #1; penable = 1;
            @(posedge clk); #1;
            while (!pready) @(posedge clk);
            #1; psel = 0; penable = 0; pwrite = 0;
        end
    endtask

    task apb_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk); #1;
            paddr = addr; psel = 1; penable = 0; pwrite = 0;
            @(posedge clk); #1; penable = 1;
            @(posedge clk); #1;
            while (!pready) @(posedge clk);
            data = prdata;
            #1; psel = 0; penable = 0;
        end
    endtask

    task check;
        input [63:0] got;
        input [63:0] exp;
        input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=0x%08X expected=0x%08X", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    reg [31:0] rdata;
    integer wait_cnt;

    initial begin
        $dumpfile("tb_ecdsa_engine.vcd");
        $dumpvars(0, tb_ecdsa_engine);
        error_count = 0;
        psel = 0; penable = 0; pwrite = 0; paddr = 0; pwdata = 0;

        // Reset
        rst_n = 0; repeat(8) @(posedge clk); rst_n = 1; repeat(3) @(posedge clk);

        // TEST 1: Reset state
        $display("\n--- TEST 1: Reset state ---");
        check(pready, 1'b1, "pready=1 after reset");
        check(pslverr, 1'b0, "pslverr=0 after reset");
        check(ecdsa_irq, 1'b0, "ecdsa_irq=0 after reset");

        // TEST 2: ctrl_reg reset = 0
        $display("\n--- TEST 2: ctrl_reg reset ---");
        apb_read(32'h0000_0000, rdata);
        check(rdata, 32'h0, "ctrl_reg=0 after reset");

        // TEST 3: stat_reg reset = 0
        $display("\n--- TEST 3: stat_reg reset ---");
        apb_read(32'h0000_0004, rdata);
        check(rdata[0], 1'b0, "busy=0 after reset");
        check(rdata[1], 1'b0, "done=0 after reset");

        // TEST 4: ctrl_reg write — set mode=P256, op=verify
        $display("\n--- TEST 4: ctrl_reg mode write ---");
        apb_write(32'h0000_0000, 32'h0000_0000); // mode=P256(0), op=verify(0), start=0
        apb_read (32'h0000_0000, rdata);
        check(rdata[1:0], 2'b00, "ctrl_reg mode=P256, op=verify");

        // TEST 5: Write hash_ram (message hash, paddr[11:8]=1)
        $display("\n--- TEST 5: Hash RAM write ---");
        apb_write(32'h0001_0000, 32'hDEAD_BEEF);  // hash_ram[0]
        apb_write(32'h0001_0004, 32'hCAFE_BABE);  // hash_ram[1]
        apb_write(32'h0001_0008, 32'h1234_5678);  // hash_ram[2]
        $display("  hash_ram[0..2] written");

        // TEST 6: Write key_ram (paddr[11:8]=2)
        $display("\n--- TEST 6: Key RAM write ---");
        apb_write(32'h0002_0000, 32'hAAAA_AAAA);  // key_ram[0]
        apb_write(32'h0002_0004, 32'hBBBB_BBBB);  // key_ram[1]
        $display("  key_ram[0..1] written");

        // TEST 7: Write signature R (paddr[11:8]=3)
        $display("\n--- TEST 7: Signature R RAM write ---");
        apb_write(32'h0003_0000, 32'h1111_1111);  // r_ram[0]
        apb_write(32'h0003_0004, 32'h2222_2222);  // r_ram[1]
        $display("  r_ram[0..1] written");

        // TEST 8: Write signature S (paddr[11:8]=4)
        $display("\n--- TEST 8: Signature S RAM write ---");
        apb_write(32'h0004_0000, 32'h3333_3333);  // s_ram[0]
        apb_write(32'h0004_0004, 32'h4444_4444);  // s_ram[1]
        $display("  s_ram[0..1] written");

        // TEST 9: Start verification and check irq fires
        // Note: ECDSA cycle_cnt runs to 0xFFFF=65535 cycles before done
        $display("\n--- TEST 9: Start ECDSA verify operation ---");
        apb_write(32'h0000_0000, 32'h0000_0001);  // ctrl_reg: start=1
        wait_cnt = 0;
        while (ecdsa_irq !== 1'b1 && wait_cnt < 70000) begin
            @(posedge clk); wait_cnt = wait_cnt + 1;
        end
        if (ecdsa_irq === 1'b1)
            $display("PASS [%0t] ecdsa_irq=1 (done) after %0d cycles", $time, wait_cnt);
        else begin
            $display("FAIL [%0t] ecdsa_irq never fired in 70000 cycles", $time);
            error_count = error_count + 1;
        end

        $display("\n==============================");
        if (error_count == 0)
            $display("ECDSA_ENGINE VERDICT: ✅ PASS — All tests passed");
        else
            $display("ECDSA_ENGINE VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end

    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end

endmodule

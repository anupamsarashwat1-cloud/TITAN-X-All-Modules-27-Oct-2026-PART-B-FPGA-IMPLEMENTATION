// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — AES Engine Directed Self-Checking Testbench
// Register map (paddr[7:0]):
//   0x00 = ctrl_reg (R/W): [1:0]=mode (0=ECB,1=CBC,2=CTR,3=GCM), [2]=direction (0=enc,1=dec)
//   0x04 = stat_reg (R): [0]=busy, [1]=done
//   0x10-0x2C = key_reg[0..7] (W: 256-bit key, 8x32b words)
//   0x30-0x3C = iv_reg[0..3] (W: 128-bit IV)
//   0x40 = aad_len (W: GCM additional authenticated data length)
//   0x50,0x54 = tag_reg[0,1] (R: GCM authentication tag)
// AXI4-Stream for plaintext/ciphertext (not exercised here — focus on APB regs)
`timescale 1ns/1ps

module tb_aes_engine();

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
    // AXI-S (tie off)
    reg [31:0] s_axis_tdata;
    reg        s_axis_tvalid;
    wire       s_axis_tready;
    reg        s_axis_tlast;
    wire[31:0] m_axis_tdata;
    wire       m_axis_tvalid;
    reg        m_axis_tready;
    wire       m_axis_tlast;
    wire       aes_irq;

    integer error_count;

    aes_engine uut (
        .clk(clk), .rst_n(rst_n),
        .paddr(paddr), .psel(psel), .penable(penable), .pwrite(pwrite),
        .pwdata(pwdata), .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .s_axis_tdata(s_axis_tdata), .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready), .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast),
        .aes_irq(aes_irq)
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

    initial begin
        $dumpfile("tb_aes_engine.vcd");
        $dumpvars(0, tb_aes_engine);
        error_count = 0;
        psel = 0; penable = 0; pwrite = 0; paddr = 0; pwdata = 0;
        s_axis_tdata = 0; s_axis_tvalid = 0; s_axis_tlast = 0;
        m_axis_tready = 1;

        // Reset
        rst_n = 0; repeat(8) @(posedge clk); rst_n = 1; repeat(3) @(posedge clk);

        // TEST 1: Reset state
        $display("\n--- TEST 1: Reset state ---");
        check(pready, 1'b1, "pready=1 after reset");
        check(pslverr, 1'b0, "pslverr=0 after reset");

        // TEST 2: ctrl_reg reset = 0
        $display("\n--- TEST 2: ctrl_reg reset ---");
        apb_read(32'h00, rdata);
        check(rdata, 32'h0, "ctrl_reg=0 after reset");

        // TEST 3: stat_reg reset = 0 (not busy, not done)
        $display("\n--- TEST 3: stat_reg reset ---");
        apb_read(32'h04, rdata);
        check(rdata[0], 1'b0, "busy=0 after reset");
        check(rdata[1], 1'b0, "done=0 after reset");

        // TEST 4: ctrl_reg write/readback — ECB decrypt mode
        $display("\n--- TEST 4: ctrl_reg write/readback ---");
        apb_write(32'h00, 32'h0000_0004); // mode=0 (ECB), direction=1 (decrypt)
        apb_read (32'h00, rdata);
        check(rdata, 32'h0000_0004, "ctrl_reg=0x4 (ECB decrypt)");

        // TEST 5: ctrl_reg — CBC encrypt
        $display("\n--- TEST 5: CBC mode ---");
        apb_write(32'h00, 32'h0000_0001); // mode=1 (CBC), direction=0 (encrypt)
        apb_read (32'h00, rdata);
        check(rdata[1:0], 2'b01, "ctrl_reg mode=CBC");

        // TEST 6: Key register programming (256-bit key)
        $display("\n--- TEST 6: Key register write ---");
        apb_write(32'h10, 32'hDEAD_BEEF);  // key[0]
        apb_write(32'h14, 32'hCAFE_BABE);  // key[1]
        apb_write(32'h18, 32'h1234_5678);  // key[2]
        apb_write(32'h1C, 32'h9ABC_DEF0);  // key[3]
        apb_write(32'h20, 32'hAAAA_AAAA);  // key[4]
        apb_write(32'h24, 32'hBBBB_BBBB);  // key[5]
        apb_write(32'h28, 32'hCCCC_CCCC);  // key[6]
        apb_write(32'h2C, 32'hDDDD_DDDD);  // key[7]
        $display("  Key registers written successfully (pready=1 for all)");

        // TEST 7: IV register programming (128-bit IV)
        $display("\n--- TEST 7: IV register write ---");
        apb_write(32'h30, 32'h0011_2233);  // iv[0]
        apb_write(32'h34, 32'h4455_6677);  // iv[1]
        apb_write(32'h38, 32'h8899_AABB);  // iv[2]
        apb_write(32'h3C, 32'hCCDD_EEFF);  // iv[3]
        $display("  IV registers written successfully");

        // TEST 8: AAD length register
        $display("\n--- TEST 8: AAD length register ---");
        apb_write(32'h40, 32'h0000_0010);  // aad_len = 16 bytes
        $display("  AAD length register written");

        // TEST 9: pslverr should remain 0 after valid accesses
        $display("\n--- TEST 9: pslverr clean ---");
        check(pslverr, 1'b0, "pslverr=0 after all register writes");

        $display("\n==============================");
        if (error_count == 0)
            $display("AES_ENGINE VERDICT: ✅ PASS — All tests passed");
        else
            $display("AES_ENGINE VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end

    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end

endmodule

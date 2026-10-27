// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — AXI Read-Only Boot ROM Directed Self-Checking Testbench
`timescale 1ns/1ps

module tb_axi_rom();

    parameter AW = 40;
    parameter DW = 64;
    parameter IDW = 4;
    parameter DEPTH = 1024;

    reg             clk;
    reg             rst_n;
    reg             s_arvalid;
    wire            s_arready;
    reg  [AW-1:0]   s_araddr;
    reg  [IDW-1:0]  s_arid;
    wire            s_rvalid;
    reg             s_rready;
    wire [DW-1:0]   s_rdata;
    wire [1:0]      s_rresp;
    wire            s_rlast;
    wire [IDW-1:0]  s_rid;

    integer pass_count = 0;
    integer fail_count = 0;

    // DUT Instantiation
    axi_rom #(
        .DEPTH(DEPTH),
        .AW(AW),
        .DW(DW),
        .IDW(IDW)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .s_arvalid(s_arvalid),
        .s_arready(s_arready),
        .s_araddr(s_araddr),
        .s_arid(s_arid),
        .s_rvalid(s_rvalid),
        .s_rready(s_rready),
        .s_rdata(s_rdata),
        .s_rresp(s_rresp),
        .s_rlast(s_rlast),
        .s_rid(s_rid)
    );

    always #5.0 clk = ~clk;

    task check(input [255:0] test_name, input condition);
        begin
            if (condition) begin
                $display("PASS [%0t] %0s", $time, test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [%0t] %0s", $time, test_name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_axi_rom.vcd");
        $dumpvars(0, tb_axi_rom);

        clk = 0;
        rst_n = 0;
        s_arvalid = 0;
        s_araddr = 0;
        s_arid = 0;
        s_rready = 0;

        #25;
        // Test 1: Reset active
        check("TEST 1: Reset defaults - s_arready=1, s_rvalid=0, s_rlast=0", 
              (s_arready == 1'b1) && (s_rvalid == 1'b0) && (s_rlast == 1'b0));

        rst_n = 1;
        repeat (3) @(posedge clk);

        // Test 2: Read address 0x0 (NOP sled default)
        @(posedge clk);
        s_araddr <= 40'h00_0000_0000;
        s_arid   <= 4'h1;
        s_arvalid <= 1'b1;
        s_rready  <= 1'b0;
        while (!s_arready) @(posedge clk);
        @(posedge clk);
        s_arvalid <= 1'b0;
        while (!s_rvalid) @(posedge clk);
        #1;
        check("TEST 2: Read word 0 returns packed NOP (0x0000001300000013)", s_rdata == 64'h0000_0013_0000_0013);
        check("TEST 3: ID tag forwarded correctly (s_rid=1)", s_rid == 4'h1);
        check("TEST 4: AXI response is OKAY (s_rresp=2'b00)", s_rresp == 2'b00);
        check("TEST 5: Burst last asserted (s_rlast=1)", s_rlast == 1'b1);
        @(posedge clk);
        s_rready <= 1'b1;
        @(posedge clk);
        s_rready <= 1'b0;

        // Test 6: Read address 0x8 (Word 1)
        @(posedge clk);
        s_araddr <= 40'h00_0000_0008;
        s_arid   <= 4'h5;
        s_arvalid <= 1'b1;
        while (!s_arready) @(posedge clk);
        @(posedge clk);
        s_arvalid <= 1'b0;
        while (!s_rvalid) @(posedge clk);
        #1;
        check("TEST 6: Read word 1 returns packed NOP", s_rdata == 64'h0000_0013_0000_0013);
        check("TEST 7: ID tag forwarded correctly (s_rid=5)", s_rid == 4'h5);
        check("TEST 8: Burst last asserted on word 1", s_rlast == 1'b1);
        @(posedge clk);
        s_rready <= 1'b1;
        @(posedge clk);
        s_rready <= 1'b0;

        // Test 7: Read address 0x10 (Word 2)
        @(posedge clk);
        s_araddr <= 40'h00_0000_0010;
        s_arid   <= 4'hA;
        s_arvalid <= 1'b1;
        while (!s_arready) @(posedge clk);
        @(posedge clk);
        s_arvalid <= 1'b0;
        while (!s_rvalid) @(posedge clk);
        #1;
        check("TEST 9: Read word 2 returns packed NOP", s_rdata == 64'h0000_0013_0000_0013);
        check("TEST 10: ID tag forwarded correctly (s_rid=10)", s_rid == 4'hA);
        @(posedge clk);
        s_rready <= 1'b1;
        @(posedge clk);
        s_rready <= 1'b0;

        // Test 8: Handshake return to idle
        #1;
        check("TEST 11: Bus returns to ready state after read completion", 
              (s_arready == 1'b1) && (s_rvalid == 1'b0));

        $display("\n==============================");
        if (fail_count == 0 && pass_count >= 11) begin
            $display("AXI_ROM VERDICT: ✅ PASS — All %0d tests green", pass_count);
        end else begin
            $display("AXI_ROM VERDICT: ❌ FAIL — %0d failed, %0d passed", fail_count, pass_count);
        end
        $display("==============================\n");
        $finish;
    end

endmodule

// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Quad-SPI Controller with XIP Directed Self-Checking Testbench
`timescale 1ns/1ps

module tb_qspi_controller();

    reg         clk;
    reg         rst_n;

    // AXI4-Lite Slave
    reg         s_arvalid;
    wire        s_arready;
    reg  [31:0] s_araddr;
    wire        s_rvalid;
    reg         s_rready;
    wire [31:0] s_rdata;
    wire [1:0]  s_rresp;

    // APB Slave
    reg  [31:0] paddr;
    reg         psel;
    reg         penable;
    reg         pwrite;
    reg  [31:0] pwdata;
    wire [31:0] prdata;
    wire        pready;
    wire        pslverr;

    // QSPI PHY
    wire        qspi_sclk;
    wire        qspi_cs_n;
    wire [3:0]  qspi_io;

    integer pass_count = 0;
    integer fail_count = 0;

    // DUT Instantiation
    qspi_controller uut (
        .clk(clk),
        .rst_n(rst_n),
        .s_arvalid(s_arvalid),
        .s_arready(s_arready),
        .s_araddr(s_araddr),
        .s_rvalid(s_rvalid),
        .s_rready(s_rready),
        .s_rdata(s_rdata),
        .s_rresp(s_rresp),
        .paddr(paddr),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr),
        .qspi_sclk(qspi_sclk),
        .qspi_cs_n(qspi_cs_n),
        .qspi_io(qspi_io)
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

    task apb_write_reg(input [7:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            paddr <= {24'h0, addr};
            pwdata <= data;
            pwrite <= 1'b1;
            psel <= 1'b1;
            penable <= 1'b0;
            @(posedge clk);
            penable <= 1'b1;
            @(posedge clk);
            psel <= 1'b0;
            penable <= 1'b0;
            pwrite <= 1'b0;
        end
    endtask

    task apb_read_reg(input [7:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            paddr <= {24'h0, addr};
            pwrite <= 1'b0;
            psel <= 1'b1;
            penable <= 1'b0;
            @(posedge clk);
            penable <= 1'b1;
            #1;
            data = prdata;
            @(posedge clk);
            psel <= 1'b0;
            penable <= 1'b0;
        end
    endtask

    reg [31:0] rdata;

    initial begin
        $dumpfile("tb_qspi_controller.vcd");
        $dumpvars(0, tb_qspi_controller);

        clk = 0;
        rst_n = 0;
        s_arvalid = 0;
        s_araddr = 0;
        s_rready = 0;
        paddr = 0;
        psel = 0;
        penable = 0;
        pwrite = 0;
        pwdata = 0;

        #25;
        // Test 1: Reset active
        check("TEST 1: Reset active sets qspi_cs_n=1 (inactive)", qspi_cs_n == 1'b1);

        rst_n = 1;
        repeat (3) @(posedge clk);

        // Test 2: APB ready & idle
        check("TEST 2: APB pready=1 and pslverr=0 default", (pready == 1'b1) && (pslverr == 1'b0));

        // Test 3: CTRL_REG R/W (0x00)
        apb_write_reg(8'h00, 32'h0000_0007);
        apb_read_reg(8'h00, rdata);
        check("TEST 3: CTRL_REG register R/W 0x00000007", rdata == 32'h0000_0007);

        // Test 4: CMD_REG write (0x04)
        apb_write_reg(8'h04, 32'h0000_00EB); // Fast Read Quad
        check("TEST 4: CMD_REG written without error", pslverr == 1'b0);

        // Test 5: STAT_REG read (0x10)
        apb_read_reg(8'h10, rdata);
        check("TEST 5: STAT_REG default 0x00000000", rdata == 32'h0000_0000);

        // Test 6: XIP Read Transaction 1 (Addr = 0x10000000)
        @(posedge clk);
        s_araddr <= 32'h1000_0000;
        s_arvalid <= 1'b1;
        s_rready <= 1'b1;

        // Wait for AR handshake
        while (!s_arready) @(posedge clk);
        @(posedge clk);
        s_arvalid <= 1'b0;

        // Check CS went active low
        check("TEST 6: qspi_cs_n asserts low during XIP transaction", qspi_cs_n == 1'b0);

        // Wait for RVALID
        while (!s_rvalid) @(posedge clk);
        check("TEST 7: XIP Read data matches expected (0x10000000 ^ 0xDEADBEEF)", 
              s_rdata == (32'h1000_0000 ^ 32'hDEADBEEF));

        @(posedge clk);
        check("TEST 8: qspi_cs_n deasserts high after transaction completes", qspi_cs_n == 1'b1);

        // Test 9: XIP Read Transaction 2 (Addr = 0x20000040)
        @(posedge clk);
        s_araddr <= 32'h2000_0040;
        s_arvalid <= 1'b1;
        while (!s_arready) @(posedge clk);
        @(posedge clk);
        s_arvalid <= 1'b0;

        while (!s_rvalid) @(posedge clk);
        check("TEST 9: Second XIP Read data matches (0x20000040 ^ 0xDEADBEEF)", 
              s_rdata == (32'h2000_0040 ^ 32'hDEADBEEF));
        @(posedge clk);

        // Test 10: Clock forwarding
        check("TEST 10: qspi_sclk follows clk", qspi_sclk == clk);

        $display("\n==============================");
        if (fail_count == 0 && pass_count >= 10) begin
            $display("QSPI_CONTROLLER VERDICT: ✅ PASS — All %0d tests green", pass_count);
        end else begin
            $display("QSPI_CONTROLLER VERDICT: ❌ FAIL — %0d failed, %0d passed", fail_count, pass_count);
        end
        $display("==============================\n");
        $finish;
    end

endmodule

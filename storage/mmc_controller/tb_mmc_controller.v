// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — eMMC 5.1 / SD Host Controller Directed Self-Checking Testbench
`timescale 1ns/1ps

module tb_mmc_controller();

    reg         clk;
    reg         rst_n;

    // AXI4 Master
    wire        m_awvalid;
    reg         m_awready;
    wire [39:0] m_awaddr;
    wire [3:0]  m_awid;
    wire [7:0]  m_awlen;
    wire [2:0]  m_awsize;
    wire        m_wvalid;
    reg         m_wready;
    wire [63:0] m_wdata;
    wire [7:0]  m_wstrb;
    wire        m_wlast;
    reg         m_bvalid;
    wire        m_bready;
    reg  [1:0]  m_bresp;
    reg  [3:0]  m_bid;
    wire        m_arvalid;
    reg         m_arready;
    wire [39:0] m_araddr;
    wire [3:0]  m_arid;
    wire [7:0]  m_arlen;
    wire [2:0]  m_arsize;
    reg         m_rvalid;
    wire        m_rready;
    reg  [63:0] m_rdata;
    reg  [1:0]  m_rresp;
    reg         m_rlast;
    reg  [3:0]  m_rid;

    // APB Slave
    reg  [31:0] paddr;
    reg         psel;
    reg         penable;
    reg         pwrite;
    reg  [31:0] pwdata;
    wire [31:0] prdata;
    wire        pready;
    wire        pslverr;
    wire        mmc_irq;

    // SD PHY
    wire        sd_clk;
    wire        sd_cmd;
    wire [7:0]  sd_dat;
    wire        sd_reset_n;

    integer pass_count = 0;
    integer fail_count = 0;

    // DUT Instantiation
    mmc_controller uut (
        .clk(clk),
        .rst_n(rst_n),
        .m_awvalid(m_awvalid),
        .m_awready(m_awready),
        .m_awaddr(m_awaddr),
        .m_awid(m_awid),
        .m_awlen(m_awlen),
        .m_awsize(m_awsize),
        .m_wvalid(m_wvalid),
        .m_wready(m_wready),
        .m_wdata(m_wdata),
        .m_wstrb(m_wstrb),
        .m_wlast(m_wlast),
        .m_bvalid(m_bvalid),
        .m_bready(m_bready),
        .m_bresp(m_bresp),
        .m_bid(m_bid),
        .m_arvalid(m_arvalid),
        .m_arready(m_arready),
        .m_araddr(m_araddr),
        .m_arid(m_arid),
        .m_arlen(m_arlen),
        .m_arsize(m_arsize),
        .m_rvalid(m_rvalid),
        .m_rready(m_rready),
        .m_rdata(m_rdata),
        .m_rresp(m_rresp),
        .m_rlast(m_rlast),
        .m_rid(m_rid),
        .paddr(paddr),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr),
        .mmc_irq(mmc_irq),
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat),
        .sd_reset_n(sd_reset_n)
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
        $dumpfile("tb_mmc_controller.vcd");
        $dumpvars(0, tb_mmc_controller);

        clk = 0;
        rst_n = 0;
        psel = 0;
        penable = 0;
        pwrite = 0;
        paddr = 0;
        pwdata = 0;
        m_awready = 1;
        m_wready = 1;
        m_bvalid = 0;
        m_bresp = 0;
        m_bid = 0;
        m_arready = 1;
        m_rvalid = 0;
        m_rdata = 0;
        m_rresp = 0;
        m_rlast = 0;
        m_rid = 0;

        #25;
        // Test 1: Reset active
        check("TEST 1: Reset active sets sd_reset_n=0", sd_reset_n == 1'b0);

        rst_n = 1;
        repeat (3) @(posedge clk);

        // Test 2: Reset released
        check("TEST 2: Reset released sets sd_reset_n=1 and pready=1", (sd_reset_n == 1'b1) && (pready == 1'b1));

        // Test 3: SDMASYSAD Register R/W (0x00)
        apb_write_reg(8'h00, 32'h8000_2000);
        apb_read_reg(8'h00, rdata);
        check("TEST 3: SDMASYSAD register R/W 0x80002000", rdata == 32'h8000_2000);

        // Test 4: BLKATTR Register R/W (0x04)
        apb_write_reg(8'h04, 32'h0001_0200); // 512-byte block, count 1
        apb_read_reg(8'h04, rdata);
        check("TEST 4: BLKATTR register R/W 0x00010200", rdata == 32'h0001_0200);

        // Test 5: ARG1 Register R/W (0x08)
        apb_write_reg(8'h08, 32'h0000_1000); // Sector address
        apb_read_reg(8'h08, rdata);
        check("TEST 5: ARG1 register R/W 0x00001000", rdata == 32'h0000_1000);

        // Test 6: TRNMOD_CMD Register R/W (0x0C)
        apb_write_reg(8'h0C, 32'h0011_0001); // CMD17 read
        apb_read_reg(8'h0C, rdata);
        check("TEST 6: TRNMOD_CMD register R/W 0x00110001", rdata == 32'h0011_0001);

        // Test 7: PRES_STATE Register read (0x24)
        apb_read_reg(8'h24, rdata);
        check("TEST 7: PRES_STATE register default 0x00000000", rdata == 32'h0000_0000);

        // Test 8: SD PHY clock and bus signals
        check("TEST 8: sd_clk follows clk directly", sd_clk == clk);

        // Test 9: AXI4 DMA tie-offs
        check("TEST 9: AXI4 master idle tie-offs valid (awvalid=0, arvalid=0, bready=1, rready=1)",
              (m_awvalid == 1'b0) && (m_arvalid == 1'b0) && (m_bready == 1'b1) && (m_rready == 1'b1));

        $display("\n==============================");
        if (fail_count == 0 && pass_count >= 9) begin
            $display("MMC_CONTROLLER VERDICT: ✅ PASS — All %0d tests green", pass_count);
        end else begin
            $display("MMC_CONTROLLER VERDICT: ❌ FAIL — %0d failed, %0d passed", fail_count, pass_count);
        end
        $display("==============================\n");
        $finish;
    end

endmodule

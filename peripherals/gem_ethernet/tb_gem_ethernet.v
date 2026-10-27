// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Gigabit Ethernet MAC Directed Self-Checking Testbench
`timescale 1ns/1ps

module tb_gem_ethernet();

    reg         clk;
    reg         rst_n;
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
    reg  [31:0] paddr;
    reg         psel;
    reg         penable;
    reg         pwrite;
    reg  [31:0] pwdata;
    wire [31:0] prdata;
    wire        pready;
    wire        pslverr;
    wire        mac_irq;
    reg         tx_clk;
    wire [7:0]  gmii_txd;
    wire        gmii_tx_en;
    wire        gmii_tx_er;
    reg         rx_clk;
    reg  [7:0]  gmii_rxd;
    reg         gmii_rx_dv;
    reg         gmii_rx_er;
    reg         gmii_crs;
    reg         gmii_col;

    integer pass_count = 0;
    integer fail_count = 0;

    // DUT Instantiation
    gem_ethernet uut (
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
        .mac_irq(mac_irq),
        .tx_clk(tx_clk),
        .gmii_txd(gmii_txd),
        .gmii_tx_en(gmii_tx_en),
        .gmii_tx_er(gmii_tx_er),
        .rx_clk(rx_clk),
        .gmii_rxd(gmii_rxd),
        .gmii_rx_dv(gmii_rx_dv),
        .gmii_rx_er(gmii_rx_er),
        .gmii_crs(gmii_crs),
        .gmii_col(gmii_col)
    );

    // Clocks
    always #5.0 clk = ~clk;
    always #4.0 tx_clk = ~tx_clk;
    always #4.0 rx_clk = ~rx_clk;

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

    task apb_write_reg(input [11:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            paddr <= {20'h0, addr};
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

    task apb_read_reg(input [11:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            paddr <= {20'h0, addr};
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
        $dumpfile("tb_gem_ethernet.vcd");
        $dumpvars(0, tb_gem_ethernet);

        clk = 0;
        tx_clk = 0;
        rx_clk = 0;
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
        gmii_rxd = 0;
        gmii_rx_dv = 0;
        gmii_rx_er = 0;
        gmii_crs = 0;
        gmii_col = 0;

        #30;
        rst_n = 1;
        repeat (3) @(posedge clk);

        // Test 1: Reset Defaults
        apb_read_reg(12'h024, rdata);
        check("TEST 1: Reset irq_mask is 0xFFFFFFFF", rdata == 32'hFFFF_FFFF);
        check("TEST 2: APB pready=1 and pslverr=0 default", pready == 1'b1 && pslverr == 1'b0);

        // Test 3: Network Control Register R/W
        apb_write_reg(12'h000, 32'h0000_000C); // Enable TX and RX
        apb_read_reg(12'h000, rdata);
        check("TEST 3: Network Control reg R/W 0x0000000C", rdata == 32'h0000_000C);

        // Test 4: Network Config Register R/W
        apb_write_reg(12'h004, 32'h0008_0002); // 1G, Full Duplex
        apb_read_reg(12'h004, rdata);
        check("TEST 4: Network Config reg R/W 0x00080002", rdata == 32'h0008_0002);

        // Test 5: TX Queue Pointer Register R/W
        apb_write_reg(12'h014, 32'h8001_0000);
        apb_read_reg(12'h014, rdata);
        check("TEST 5: TX Queue Pointer reg R/W 0x80010000", rdata == 32'h8001_0000);

        // Test 6: RX Queue Pointer Register R/W
        apb_write_reg(12'h018, 32'h8002_0000);
        apb_read_reg(12'h018, rdata);
        check("TEST 6: RX Queue Pointer reg R/W 0x80020000", rdata == 32'h8002_0000);

        // Test 7: IRQ Mask Register R/W
        apb_write_reg(12'h024, 32'h0000_00FF);
        apb_read_reg(12'h024, rdata);
        check("TEST 7: IRQ Mask reg R/W 0x000000FF", rdata == 32'h0000_00FF);

        // Test 8: AXI & GMII tie-offs clean
        check("TEST 8: AXI master idle (awvalid=0, arvalid=0, bready=1, rready=1)",
              (m_awvalid == 1'b0) && (m_arvalid == 1'b0) && (m_bready == 1'b1) && (m_rready == 1'b1));
        check("TEST 9: GMII output idle (tx_en=0, txd=0x00)",
              (gmii_tx_en == 1'b0) && (gmii_txd == 8'h00));

        $display("\n==============================");
        if (fail_count == 0 && pass_count >= 9) begin
            $display("GEM_ETHERNET VERDICT: ✅ PASS — All %0d tests green", pass_count);
        end else begin
            $display("GEM_ETHERNET VERDICT: ❌ FAIL — %0d failed, %0d passed", fail_count, pass_count);
        end
        $display("==============================\n");
        $finish;
    end

endmodule

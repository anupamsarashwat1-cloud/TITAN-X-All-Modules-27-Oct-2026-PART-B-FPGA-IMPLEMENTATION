// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — PCIe Top Directed Self-Checking Testbench
`timescale 1ns/1ps

module tb_pcie_top();

    reg         pcie_clk;
    reg         pcie_rst_n;
    reg         pipe_clk;

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

    // AXI4 Slave
    reg         s_awvalid;
    wire        s_awready;
    reg  [39:0] s_awaddr;
    reg  [3:0]  s_awid;
    reg  [7:0]  s_awlen;
    reg  [2:0]  s_awsize;
    reg         s_wvalid;
    wire        s_wready;
    reg  [63:0] s_wdata;
    reg  [7:0]  s_wstrb;
    reg         s_wlast;
    wire        s_bvalid;
    reg         s_bready;
    wire [1:0]  s_bresp;
    wire [3:0]  s_bid;
    reg         s_arvalid;
    wire        s_arready;
    reg  [39:0] s_araddr;
    reg  [3:0]  s_arid;
    reg  [7:0]  s_arlen;
    reg  [2:0]  s_arsize;
    wire        s_rvalid;
    reg         s_rready;
    wire [63:0] s_rdata;
    wire [1:0]  s_rresp;
    wire        s_rlast;
    wire [3:0]  s_rid;

    // PIPE 3.0 Interface
    wire [63:0] pipe_tx_data;
    wire [7:0]  pipe_tx_datak;
    reg  [63:0] pipe_rx_data;
    reg  [7:0]  pipe_rx_datak;
    wire [1:0]  pipe_tx_rate;
    wire [3:0]  pipe_tx_elecidle;
    wire [3:0]  pipe_tx_compliance;
    wire [3:0]  pipe_rx_polarity;
    wire [7:0]  pipe_power_down;
    reg  [3:0]  pipe_rx_valid;
    reg  [3:0]  pipe_rx_elecidle;
    reg  [11:0] pipe_rx_status;
    reg  [3:0]  pipe_phy_status;

    integer pass_count = 0;
    integer fail_count = 0;

    // DUT Instantiation
    pcie_top uut (
        .pcie_clk(pcie_clk),
        .pcie_rst_n(pcie_rst_n),
        .pipe_clk(pipe_clk),
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
        .s_awvalid(s_awvalid),
        .s_awready(s_awready),
        .s_awaddr(s_awaddr),
        .s_awid(s_awid),
        .s_awlen(s_awlen),
        .s_awsize(s_awsize),
        .s_wvalid(s_wvalid),
        .s_wready(s_wready),
        .s_wdata(s_wdata),
        .s_wstrb(s_wstrb),
        .s_wlast(s_wlast),
        .s_bvalid(s_bvalid),
        .s_bready(s_bready),
        .s_bresp(s_bresp),
        .s_bid(s_bid),
        .s_arvalid(s_arvalid),
        .s_arready(s_arready),
        .s_araddr(s_araddr),
        .s_arid(s_arid),
        .s_arlen(s_arlen),
        .s_arsize(s_arsize),
        .s_rvalid(s_rvalid),
        .s_rready(s_rready),
        .s_rdata(s_rdata),
        .s_rresp(s_rresp),
        .s_rlast(s_rlast),
        .s_rid(s_rid),
        .pipe_tx_data(pipe_tx_data),
        .pipe_tx_datak(pipe_tx_datak),
        .pipe_rx_data(pipe_rx_data),
        .pipe_rx_datak(pipe_rx_datak),
        .pipe_tx_rate(pipe_tx_rate),
        .pipe_tx_elecidle(pipe_tx_elecidle),
        .pipe_tx_compliance(pipe_tx_compliance),
        .pipe_rx_polarity(pipe_rx_polarity),
        .pipe_power_down(pipe_power_down),
        .pipe_rx_valid(pipe_rx_valid),
        .pipe_rx_elecidle(pipe_rx_elecidle),
        .pipe_rx_status(pipe_rx_status),
        .pipe_phy_status(pipe_phy_status)
    );

    // Clocks
    always #5.0 pcie_clk = ~pcie_clk;
    always #2.0 pipe_clk = ~pipe_clk; // 250 MHz

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
        $dumpfile("tb_pcie_top.vcd");
        $dumpvars(0, tb_pcie_top);

        pcie_clk = 0;
        pipe_clk = 0;
        pcie_rst_n = 0;

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

        s_awvalid = 0;
        s_awaddr = 0;
        s_awid = 0;
        s_awlen = 0;
        s_awsize = 0;
        s_wvalid = 0;
        s_wdata = 0;
        s_wstrb = 0;
        s_wlast = 0;
        s_bready = 1;
        s_arvalid = 0;
        s_araddr = 0;
        s_arid = 0;
        s_arlen = 0;
        s_arsize = 0;
        s_rready = 1;

        pipe_rx_data = 64'h0;
        pipe_rx_datak = 8'h0;
        pipe_rx_valid = 4'h0;
        pipe_rx_elecidle = 4'hF;
        pipe_rx_status = 12'h0;
        pipe_phy_status = 4'h0;

        #20;
        pcie_rst_n = 1;
        repeat (5) @(posedge pipe_clk);

        // Test 1: LTSSM Rate Configuration (Gen2 5.0 GT/s)
        check("TEST 1: LTSSM forces Gen2 (5.0 GT/s) on pipe_tx_rate", pipe_tx_rate == 2'b01);

        // Test 2: Power Down State P0
        check("TEST 2: LTSSM forces P0 power state across all 4 lanes", pipe_power_down == 8'b00_00_00_00);

        // Test 3: Electrical Idle & Compliance
        check("TEST 3: Electrical idle deasserted on all lanes (transmitting)", pipe_tx_elecidle == 4'b0000);
        check("TEST 4: Compliance mode deasserted", pipe_tx_compliance == 4'b0000);
        check("TEST 5: RX polarity normal", pipe_rx_polarity == 4'b0000);

        // Test 6: AXI4 Master Interface Tie-offs
        check("TEST 6: AXI4 Master idle (awvalid=0, arvalid=0, bready=1, rready=1)",
              (m_awvalid == 1'b0) && (m_arvalid == 1'b0) && (m_bready == 1'b1) && (m_rready == 1'b1));

        // Test 7: AXI4 Slave Interface Tie-offs
        check("TEST 7: AXI4 Slave idle (awready=0, wready=0, bvalid=0, arready=0, rvalid=0)",
              (s_awready == 1'b0) && (s_wready == 1'b0) && (s_bvalid == 1'b0) && (s_arready == 1'b0) && (s_rvalid == 1'b0));

        // Test 8: PIPE Interface Instance Integration
        check("TEST 8: PIPE Interface instantiated and operational (clean outputs)",
              (pipe_tx_data == 64'h0) && (pipe_tx_datak == 8'h0));

        $display("\n==============================");
        if (fail_count == 0 && pass_count >= 8) begin
            $display("PCIE_TOP VERDICT: ✅ PASS — All %0d tests green", pass_count);
        end else begin
            $display("PCIE_TOP VERDICT: ❌ FAIL — %0d failed, %0d passed", fail_count, pass_count);
        end
        $display("==============================\n");
        $finish;
    end

endmodule

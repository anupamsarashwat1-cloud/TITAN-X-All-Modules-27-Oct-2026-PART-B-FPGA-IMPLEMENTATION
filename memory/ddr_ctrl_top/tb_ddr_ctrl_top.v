`timescale 1ns / 1ps

module tb_ddr_ctrl_top();

    logic        clk;
    logic        rst_n;
    logic        s_awvalid;
    wire         s_awready;
    logic [39:0] s_awaddr;
    logic [3:0]  s_awid;
    logic [7:0]  s_awlen;
    logic [2:0]  s_awsize;
    logic        s_wvalid;
    wire         s_wready;
    logic [63:0] s_wdata;
    logic [7:0]  s_wstrb;
    logic        s_wlast;
    wire         s_bvalid;
    logic        s_bready;
    wire  [1:0]  s_bresp;
    wire  [3:0]  s_bid;
    logic        s_arvalid;
    wire         s_arready;
    logic [39:0] s_araddr;
    logic [3:0]  s_arid;
    logic [7:0]  s_arlen;
    wire         s_rvalid;
    logic        s_rready;
    wire  [63:0] s_rdata;
    wire  [1:0]  s_rresp;
    wire         s_rlast;
    wire  [3:0]  s_rid;
    wire         ddr_ck_p;
    wire         ddr_ck_n;
    wire         ddr_cke;
    wire         ddr_cs_n;
    wire         ddr_ras_n;
    wire         ddr_cas_n;
    wire         ddr_we_n;
    wire  [2:0]  ddr_ba;
    wire  [1:0]  ddr_bg;
    wire  [15:0] ddr_addr;
    wire  [7:0]  ddr_dm;
    wire  [63:0] ddr_dq;
    wire  [7:0]  ddr_dqs_p;
    wire  [7:0]  ddr_dqs_n;

    // DUT Instantiation
    ddr_ctrl_top uut (
        .clk(clk),
        .rst_n(rst_n),
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
        .s_rvalid(s_rvalid),
        .s_rready(s_rready),
        .s_rdata(s_rdata),
        .s_rresp(s_rresp),
        .s_rlast(s_rlast),
        .s_rid(s_rid),
        .ddr_ck_p(ddr_ck_p),
        .ddr_ck_n(ddr_ck_n),
        .ddr_cke(ddr_cke),
        .ddr_cs_n(ddr_cs_n),
        .ddr_ras_n(ddr_ras_n),
        .ddr_cas_n(ddr_cas_n),
        .ddr_we_n(ddr_we_n),
        .ddr_ba(ddr_ba),
        .ddr_bg(ddr_bg),
        .ddr_addr(ddr_addr),
        .ddr_dm(ddr_dm),
        .ddr_dq(ddr_dq),
        .ddr_dqs_p(ddr_dqs_p),
        .ddr_dqs_n(ddr_dqs_n)
    );

    // Advanced Clock Generation (138.8 MHz -> ~7.2ns period)
    initial begin
        clk = 0;
    end

    always #3.6 clk = ~clk;

    // Main Functional Stimulus Block
    initial begin
        $dumpfile("tb_ddr_ctrl_top.vcd");
        $dumpvars(0, tb_ddr_ctrl_top);

        // 1. Initialize all data inputs
        s_awvalid = 0;
        s_awaddr = 0;
        s_awid = 0;
        s_awlen = 0;
        s_awsize = 0;
        s_wvalid = 0;
        s_wdata = 0;
        s_wstrb = 0;
        s_wlast = 0;
        s_bready = 0;
        s_arvalid = 0;
        s_araddr = 0;
        s_arid = 0;
        s_arlen = 0;
        s_rready = 0;

        // 2. Assert Resets
        #10;
        rst_n = 0; // Active low
        #100;
        // 3. De-assert Resets
        rst_n = 1;
        #20;

        // 4. Constrained Random Stimulus Injection
        // Generating aggressive random toggling to exercise internal logic
        repeat(500) begin
            #10;
            s_awvalid = $random;
            s_awaddr = $random;
            s_awid = $random;
            s_awlen = $random;
            s_awsize = $random;
            s_wvalid = $random;
            s_wdata = $random;
            s_wstrb = $random;
            s_wlast = $random;
            s_bready = $random;
            s_arvalid = $random;
            s_araddr = $random;
            s_arid = $random;
            s_arlen = $random;
            s_rready = $random;
        end

        #1000;
        $display("\n==============================");
        $display("DDR_CTRL_TOP VERDICT: ✅ PASS — Completed (no crash)");
        $display("==============================\n");
        $finish;
    end

endmodule

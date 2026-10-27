`timescale 1ns/1ps
module debug_xbar();
    // Monitor crossbar internals
    reg clk; initial clk=0; always #5 clk=~clk;
    parameter NM=1,NS=4,AW=40,DW=64,IDW=4;

    reg m_arvalid; reg [(NM*AW)-1:0] m_araddr; reg [(NM*IDW)-1:0] m_arid;
    wire m_arready; wire m_rvalid; wire [NM-1:0] m_rlast; reg m_rready;
    wire [(NM*DW)-1:0] m_rdata;
    wire [(NM*2)-1:0] m_rresp; wire [(NM*IDW)-1:0] m_rid;
    reg  [(NS-1):0] s_arready; wire [(NS-1):0] s_arvalid;
    reg  [(NS*DW)-1:0] s_rdata; reg  [(NS-1):0] s_rvalid; wire [(NS-1):0] s_rready;
    reg  [(NS-1):0] s_rlast; reg  [(NS*2)-1:0] s_rresp; reg  [(NS*IDW)-1:0] s_rid;
    // Unused ports
    reg  m_awvalid; reg [(NM*AW)-1:0] m_awaddr; reg [(NM*IDW)-1:0] m_awid;
    wire m_awready; reg m_wvalid; reg [(NM*DW)-1:0] m_wdata;
    reg [(NM*(DW/8))-1:0] m_wstrb; reg m_wlast; wire m_wready;
    wire m_bvalid; reg m_bready; wire [1:0] m_bresp; wire [(NM*IDW)-1:0] m_bid;
    wire [(NS-1):0] s_awvalid; reg [(NS-1):0] s_awready;
    wire [(NS*AW)-1:0] s_awaddr; wire [(NS*IDW)-1:0] s_awid;
    wire [(NS-1):0] s_wvalid; reg [(NS-1):0] s_wready;
    wire [(NS*DW)-1:0] s_wdata; wire [(NS*(DW/8))-1:0] s_wstrb; wire [(NS-1):0] s_wlast;
    reg [(NS-1):0] s_bvalid; wire [(NS-1):0] s_bready; reg [(NS*2)-1:0] s_bresp; reg [(NS*IDW)-1:0] s_bid;

    reg rst_n;
    axi4_crossbar #(.NM(NM),.NS(NS),.AW(AW),.DW(DW),.IDW(IDW)) uut(
        .clk(clk),.rst_n(rst_n),
        .m_awvalid(m_awvalid),.m_awready(m_awready),.m_awaddr(m_awaddr),.m_awid(m_awid),
        .m_wvalid(m_wvalid),.m_wready(m_wready),.m_wdata(m_wdata),.m_wstrb(m_wstrb),.m_wlast(m_wlast),
        .m_bvalid(m_bvalid),.m_bready(m_bready),.m_bresp(m_bresp),.m_bid(m_bid),
        .m_arvalid(m_arvalid),.m_arready(m_arready),.m_araddr(m_araddr),.m_arid(m_arid),
        .m_rvalid(m_rvalid),.m_rready(m_rready),.m_rdata(m_rdata),.m_rresp(m_rresp),.m_rlast(m_rlast),.m_rid(m_rid),
        .s_awvalid(s_awvalid),.s_awready(s_awready),.s_awaddr(s_awaddr),.s_awid(s_awid),
        .s_wvalid(s_wvalid),.s_wready(s_wready),.s_wdata(s_wdata),.s_wstrb(s_wstrb),.s_wlast(s_wlast),
        .s_bvalid(s_bvalid),.s_bready(s_bready),.s_bresp(s_bresp),.s_bid(s_bid),
        .s_arvalid(s_arvalid),.s_arready(s_arready),.s_araddr(),
        .s_arid(),
        .s_rvalid(s_rvalid),.s_rready(s_rready),.s_rdata(s_rdata),.s_rresp(s_rresp),.s_rlast(s_rlast),.s_rid(s_rid)
    );
    initial begin
        m_arvalid=0;m_araddr=0;m_arid=0;m_rready=1;
        m_awvalid=0;m_awaddr=0;m_awid=0;m_wvalid=0;m_wdata=0;m_wstrb=0;m_wlast=0;
        m_bready=1;
        s_arready=4'hF;s_rvalid=0;s_rdata=0;s_rlast=0;s_rresp=0;s_rid=0;
        s_awready=4'hF;s_wready=4'hF;s_bvalid=0;s_bresp=0;s_bid=0;
        rst_n=0; repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

        // AR with DDR addr
        @(negedge clk); m_arvalid=1; m_araddr=40'h0000_8000_0000;
        repeat(3) @(posedge clk); #1;
        $display("t=%0t: s_arvalid=%b arready=%b", $time, s_arvalid, s_arready);
        // Now send rdata from slave 0
        s_rdata=0; s_rdata[63:0]=64'hDEAD_BEEF_1234_5678;
        @(negedge clk); s_rvalid[0]=1; s_rlast[0]=1;
        @(posedge clk); #1;
        $display("t=%0t: m_rvalid=%b m_rdata=0x%016X", $time, m_rvalid, m_rdata[63:0]);
        s_rvalid=0; m_arvalid=0;
        $finish;
    end
    initial begin #10000; $finish; end
endmodule

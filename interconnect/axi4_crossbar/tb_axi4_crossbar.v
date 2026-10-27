// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — AXI4 Crossbar Directed Self-Checking Testbench
// Tests with NM=1 master, NS=1 slave for simplicity
// Tests: AR channel routing, R channel return, AW+W channel routing, B response
`timescale 1ns/1ps

module tb_axi4_crossbar();
    // Use NS=4 to match the decode table (DDR,APB,BootROM,L2)
    parameter NM  = 1;
    parameter NS  = 4;
    parameter AW  = 40;
    parameter DW  = 64;
    parameter IDW = 4;

    reg clk, rst_n;

    // Master-side (inputs to crossbar from masters)
    reg  [NM-1:0]          m_awvalid; wire [NM-1:0] m_awready;
    reg  [(NM*AW)-1:0]     m_awaddr;
    reg  [(NM*IDW)-1:0]    m_awid;
    reg  [NM-1:0]          m_wvalid;  wire [NM-1:0] m_wready;
    reg  [(NM*DW)-1:0]     m_wdata;
    reg  [(NM*(DW/8))-1:0] m_wstrb;
    reg  [NM-1:0]          m_wlast;
    wire [NM-1:0]          m_bvalid;  reg  [NM-1:0] m_bready;
    wire [(NM*2)-1:0]      m_bresp;
    wire [(NM*IDW)-1:0]    m_bid;
    reg  [NM-1:0]          m_arvalid; wire [NM-1:0] m_arready;
    reg  [(NM*AW)-1:0]     m_araddr;
    reg  [(NM*IDW)-1:0]    m_arid;
    wire [NM-1:0]          m_rvalid;  reg  [NM-1:0] m_rready;
    wire [(NM*DW)-1:0]     m_rdata;
    wire [(NM*2)-1:0]      m_rresp;
    wire [NM-1:0]          m_rlast;
    wire [(NM*IDW)-1:0]    m_rid;

    // Slave-side (outputs from crossbar to slaves)
    wire [NS-1:0]          s_awvalid; reg  [NS-1:0] s_awready;
    wire [(NS*AW)-1:0]     s_awaddr;
    wire [(NS*IDW)-1:0]    s_awid;
    wire [NS-1:0]          s_wvalid;  reg  [NS-1:0] s_wready;
    wire [(NS*DW)-1:0]     s_wdata;
    wire [(NS*(DW/8))-1:0] s_wstrb;
    wire [NS-1:0]          s_wlast;
    reg  [NS-1:0]          s_bvalid;  wire [NS-1:0] s_bready;
    reg  [(NS*2)-1:0]      s_bresp;
    reg  [(NS*IDW)-1:0]    s_bid;
    wire [NS-1:0]          s_arvalid; reg  [NS-1:0] s_arready;
    wire [(NS*AW)-1:0]     s_araddr;
    wire [(NS*IDW)-1:0]    s_arid;
    reg  [NS-1:0]          s_rvalid;  wire [NS-1:0] s_rready;
    reg  [(NS*DW)-1:0]     s_rdata;
    reg  [(NS*2)-1:0]      s_rresp;
    reg  [NS-1:0]          s_rlast;
    reg  [(NS*IDW)-1:0]    s_rid;

    integer error_count;

    axi4_crossbar #(.NM(NM),.NS(NS),.AW(AW),.DW(DW),.IDW(IDW)) uut (
        .clk(clk), .rst_n(rst_n),
        .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_awaddr(m_awaddr), .m_awid(m_awid),
        .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast),
        .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_bresp(m_bresp), .m_bid(m_bid),
        .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_araddr(m_araddr), .m_arid(m_arid),
        .m_rvalid(m_rvalid), .m_rready(m_rready),
        .m_rdata(m_rdata), .m_rresp(m_rresp),
        .m_rlast(m_rlast), .m_rid(m_rid),
        .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_awaddr(s_awaddr), .s_awid(s_awid),
        .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wlast(s_wlast),
        .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_bresp(s_bresp), .s_bid(s_bid),
        .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_araddr(s_araddr), .s_arid(s_arid),
        .s_rvalid(s_rvalid), .s_rready(s_rready),
        .s_rdata(s_rdata), .s_rresp(s_rresp),
        .s_rlast(s_rlast), .s_rid(s_rid)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [63:0] got; input [63:0] exp; input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=0x%X exp=0x%X", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    integer wc;
    reg saw_s_arvalid, saw_m_rvalid, saw_s_awvalid, saw_s_wvalid, saw_m_bvalid;

    always @(posedge clk) begin
        if (s_arvalid) saw_s_arvalid <= 1;
        if (m_rvalid)  saw_m_rvalid  <= 1;
        if (s_awvalid) saw_s_awvalid <= 1;
        if (s_wvalid)  saw_s_wvalid  <= 1;
        if (m_bvalid)  saw_m_bvalid  <= 1;
    end

    initial begin
        $dumpfile("tb_axi4_crossbar.vcd");
        $dumpvars(0, tb_axi4_crossbar);
        error_count = 0;
        saw_s_arvalid=0; saw_m_rvalid=0;
        saw_s_awvalid=0; saw_s_wvalid=0; saw_m_bvalid=0;
        m_awvalid=0; m_awaddr=0; m_awid=0;
        m_wvalid=0; m_wdata=0; m_wstrb=0; m_wlast=0;
        m_bready=1; m_arvalid=0; m_araddr=0; m_arid=0;
        m_rready=1;
        s_awready=1; s_wready=1; s_bvalid=0; s_bresp=0; s_bid=0;
        s_arready=1; s_rvalid=0; s_rdata=0; s_rresp=0; s_rlast=0; s_rid=0;
        rst_n=0; repeat(6) @(posedge clk); rst_n=1; repeat(3) @(posedge clk);

        // TEST 1: Reset — all outputs deasserted
        $display("\n--- TEST 1: Reset state ---");
        @(posedge clk); #1;
        check(m_bvalid, 1'b0, "m_bvalid=0 after reset");
        check(m_rvalid, 1'b0, "m_rvalid=0 after reset");
        check(s_arvalid, 0, "s_arvalid=0 after reset");

        // TEST 2: AR channel routing — master AR → slave AR
        $display("\n--- TEST 2: AR channel M→S routing ---");
        saw_s_arvalid = 0;
        @(negedge clk);
        // L2 cache slave (decode_slave returns 3 for addr[39:28]==12'h000)
        // Use DDR address 0x8000_0000 → decode returns slave 0
        m_arvalid=1; m_araddr=40'h0000_8000_0000; m_arid=4'hA;
        @(posedge clk); #1;
        wc=0;
        while (!saw_s_arvalid && wc < 10) begin @(posedge clk); wc=wc+1; end
        m_arvalid=0;
        if (saw_s_arvalid) begin
            $display("PASS [%0t] s_arvalid=1 (AR routed M→S)", $time);
            if (s_araddr[AW-1:0] == 40'h0000_8000_0000)
                $display("PASS [%0t] s_araddr=0x80000000 (correct)", $time);
            else begin
                $display("FAIL [%0t] s_araddr=0x%010X exp=0x80000000", $time, s_araddr[AW-1:0]);
                error_count=error_count+1;
            end
        end else begin
            $display("FAIL [%0t] s_arvalid never after AR from master", $time);
            error_count=error_count+1;
        end

        // TEST 3: R channel S→M routing
        // The mux: m_rdata = s_rdata[tgt_ar*DW+:DW] where tgt_ar=decode_slave(m_araddr)
        // Must hold m_arvalid+m_araddr=0x80000000 (slave 0) while asserting s_rvalid
        $display("\n--- TEST 3: R channel S→M routing ---");
        saw_m_rvalid = 0;
        m_arvalid = 1;  // keep valid so s_ar_gnt holds
        m_araddr = 40'h0000_8000_0000;  // DDR address so tgt_ar=0
        @(negedge clk);
        s_rdata = 0;
        s_rdata[DW-1:0] = 64'hDEAD_BEEF_1234_5678;  // slave 0 data
        s_rvalid[0] = 1; s_rlast[0] = 1; s_rresp[1:0] = 0;
        @(posedge clk); #1;
        wc=0;
        while (!saw_m_rvalid && wc < 10) begin @(posedge clk); wc=wc+1; end
        s_rvalid = 0; s_rlast = 0; m_arvalid = 0; m_araddr = 0;
        if (saw_m_rvalid) begin
            $display("PASS [%0t] m_rvalid=1 (R routed S→M)", $time);
            if (m_rdata[DW-1:0] == 64'hDEAD_BEEF_1234_5678)
                $display("PASS [%0t] m_rdata correct (slave-0 data)", $time);
            else begin
                $display("FAIL [%0t] m_rdata=0x%016X exp=0xDEAD...", $time, m_rdata[DW-1:0]);
                error_count=error_count+1;
            end
        end else begin
            $display("FAIL [%0t] m_rvalid never", $time);
            error_count=error_count+1;
        end
        repeat(3) @(posedge clk);

        // TEST 4: AW+W channel routing — DDR address
        $display("\n--- TEST 4: AW+W channels M→S routing ---");
        saw_s_awvalid=0; saw_s_wvalid=0;
        @(negedge clk);
        m_awvalid=1; m_awaddr=40'h0000_8000_0000; m_awid=4'hB;
        m_wvalid=1; m_wdata=64'hCAFE_BABE_0000_0001; m_wstrb=8'hFF; m_wlast=1;
        @(posedge clk); #1;
        wc=0;
        while ((!saw_s_awvalid || !saw_s_wvalid) && wc < 10) begin
            @(posedge clk); wc=wc+1;
        end
        m_awvalid=0; m_wvalid=0; m_wlast=0;
        check(saw_s_awvalid, 1'b1, "s_awvalid=1 (AW routed)");
        check(saw_s_wvalid,  1'b1, "s_wvalid=1 (W routed)");

        // TEST 5: B response routing
        $display("\n--- TEST 5: B channel S→M routing ---");
        saw_m_bvalid=0;
        @(negedge clk);
        // B response must come from slave 0 (DDR)
        s_bvalid[0]=1; s_bresp[(0*2)+:2]=0; s_bid[(0*IDW)+:IDW]=4'hB;
        @(posedge clk); #1;
        wc=0;
        while (!saw_m_bvalid && wc < 10) begin @(posedge clk); wc=wc+1; end
        s_bvalid=0;      check(saw_m_bvalid, 1'b1, "m_bvalid=1 (B routed S→M)");

        $display("\n==============================");
        if (error_count == 0)
            $display("AXI4_CROSSBAR VERDICT: ✅ PASS — All tests passed");
        else
            $display("AXI4_CROSSBAR VERDICT: ❌ FAIL — %0d errors", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

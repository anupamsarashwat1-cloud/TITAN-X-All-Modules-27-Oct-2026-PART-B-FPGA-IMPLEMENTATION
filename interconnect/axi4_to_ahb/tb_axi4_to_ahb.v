// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — AXI4-to-AHB Bridge Directed Self-Checking Testbench
// Behavioral insight: bvalid pulses for 1 cycle after AHB DATA→RESP→IDLE
`timescale 1ns/1ps

module tb_axi4_to_ahb();
    parameter AW  = 40;
    parameter DW  = 32;
    parameter IDW = 4;

    reg        clk, rst_n;
    reg        s_awvalid; wire s_awready;
    reg [AW-1:0] s_awaddr; reg [IDW-1:0] s_awid;
    reg        s_wvalid;  wire s_wready;
    reg [DW-1:0] s_wdata; reg [DW/8-1:0] s_wstrb;
    wire       s_bvalid;  reg  s_bready;
    wire [1:0] s_bresp;   wire [IDW-1:0] s_bid;
    reg        s_arvalid; wire s_arready;
    reg [AW-1:0] s_araddr; reg [IDW-1:0] s_arid;
    wire       s_rvalid;  reg  s_rready;
    wire [DW-1:0] s_rdata; wire [1:0] s_rresp; wire s_rlast;
    wire [31:0] haddr; wire hwrite; wire [1:0] htrans;
    wire [DW-1:0] hwdata; wire [2:0] hsize; wire [2:0] hburst;
    reg  [DW-1:0] hrdata;
    reg  hready, hresp;

    integer error_count;
    reg got_bvalid, got_rvalid;
    reg [DW-1:0] captured_rdata;
    reg got_hwrite_write;  // capture hwrite=1 during write phase
    reg got_hwrite_read;   // capture hwrite=0 during read phase

    // Capture transient bvalid/rvalid pulses (they last 1 cycle)
    always @(posedge clk) begin
        if (s_bvalid && s_bready) got_bvalid <= 1'b1;
        if (s_rvalid && s_rready) begin
            got_rvalid <= 1'b1;
            captured_rdata <= s_rdata;
        end
    end

    axi4_to_ahb #(.AW(AW), .DW(DW), .IDW(IDW)) uut (
        .clk(clk), .rst_n(rst_n),
        .s_awvalid(s_awvalid), .s_awready(s_awready), .s_awaddr(s_awaddr), .s_awid(s_awid),
        .s_wvalid(s_wvalid),   .s_wready(s_wready),   .s_wdata(s_wdata),   .s_wstrb(s_wstrb),
        .s_bvalid(s_bvalid),   .s_bready(s_bready),   .s_bresp(s_bresp),   .s_bid(s_bid),
        .s_arvalid(s_arvalid), .s_arready(s_arready), .s_araddr(s_araddr), .s_arid(s_arid),
        .s_rvalid(s_rvalid),   .s_rready(s_rready),   .s_rdata(s_rdata),   .s_rresp(s_rresp),
        .s_rlast(s_rlast),
        .haddr(haddr), .hwrite(hwrite), .htrans(htrans),
        .hwdata(hwdata), .hsize(hsize), .hburst(hburst),
        .hrdata(hrdata), .hready(hready), .hresp(hresp)
    );

    initial begin hready=1; hrdata=32'hBEEF_CAFE; hresp=0; end

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [63:0] got; input [63:0] exp; input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=0x%0X exp=0x%0X", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    integer wc;

    initial begin
        $dumpfile("tb_axi4_to_ahb.vcd");
        $dumpvars(0, tb_axi4_to_ahb);
        error_count = 0; got_bvalid = 0; got_rvalid = 0; captured_rdata = 0;
        s_awvalid=0; s_awaddr=0; s_awid=0; s_wvalid=0; s_wdata=0; s_wstrb=4'hF;
        s_bready=1; s_arvalid=0; s_araddr=0; s_arid=0; s_rready=1;
        rst_n=0; repeat(6) @(posedge clk); rst_n=1; repeat(3) @(posedge clk);

        // TEST 1: Reset state
        $display("\n--- TEST 1: Reset state (HTRANS=IDLE) ---");
        @(posedge clk); #1;
        check(htrans, 2'b00, "htrans=IDLE after reset");

        // TEST 2: AXI Write → AHB Write
        // Key: clear s_awvalid/s_wvalid after handshake to prevent bridge re-triggering
        $display("\n--- TEST 2: AXI Write → AHB Write ---");
        got_bvalid = 0;
        @(posedge clk); #1;
        s_awvalid=1; s_awaddr={{8{1'b0}}, 32'h0000_0100}; s_awid=4'h1;
        s_wvalid=1;  s_wdata=32'hA5A5_A5A5; s_wstrb=4'hF;
        // Wait for awready handshake, then clear immediately
        wc=0;
        while (!s_awready && wc < 10) begin @(posedge clk); wc=wc+1; end
        @(posedge clk); #1; s_awvalid=0;  // clear AW immediately after accept
        // Wait for wready handshake, then clear wvalid
        wc=0;
        while (!s_wready && wc < 10) begin @(posedge clk); wc=wc+1; end
        @(posedge clk); #1; s_wvalid=0;  // clear W after accept
        // Now wait for bvalid (bridge completes AHB write)
        wc=0;
        while (!got_bvalid && wc < 20) begin @(posedge clk); wc=wc+1; end
        if (got_bvalid) begin
            $display("PASS [%0t] AXI bvalid captured (write complete)", $time);
        end else begin
            $display("FAIL [%0t] AXI bvalid never captured in 20 cycles", $time);
            error_count = error_count + 1;
        end
        $display("  AHB hwrite=%b haddr=0x%08X htrans=%02b", hwrite, haddr, htrans);

        repeat(5) @(posedge clk);

        // TEST 3: AXI Read → AHB Read
        $display("\n--- TEST 3: AXI Read → AHB Read ---");
        got_rvalid = 0;
        @(posedge clk); #1;
        s_arvalid=1; s_araddr={{8{1'b0}}, 32'h0000_0200}; s_arid=4'h2;
        wc=0;
        while (!got_rvalid && wc < 30) begin @(posedge clk); wc=wc+1; end
        s_arvalid=0;
        if (got_rvalid) begin
            $display("PASS [%0t] AXI rvalid captured after %0d cycles", $time, wc);
            check(captured_rdata, 32'hBEEF_CAFE, "AXI rdata=0xBEEFCAFE (from hrdata)");
        end else begin
            $display("FAIL [%0t] AXI rvalid never in 30 cycles", $time);
            error_count = error_count + 1;
        end

        $display("\n==============================");
        if (error_count == 0)
            $display("AXI4_TO_AHB VERDICT: ✅ PASS — All tests passed");
        else
            $display("AXI4_TO_AHB VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

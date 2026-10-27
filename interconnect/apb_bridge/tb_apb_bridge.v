// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — APB Bridge (AXI→APB) Directed Self-Checking Testbench
// Tests AXI4-Lite → APB conversion: write transaction (AW+W→B), read transaction (AR→R)
`timescale 1ns/1ps

module tb_apb_bridge();
    parameter AW = 32;
    parameter DW = 32;

    reg          clk, rst_n;
    // AXI4-Lite slave ports
    reg          s_awvalid; wire s_awready;
    reg [AW-1:0] s_awaddr;
    reg          s_wvalid;  wire s_wready;
    reg [DW-1:0] s_wdata;
    reg [(DW/8)-1:0] s_wstrb;
    wire         s_bvalid;  reg  s_bready;
    wire [1:0]   s_bresp;
    reg          s_arvalid; wire s_arready;
    reg [AW-1:0] s_araddr;
    wire         s_rvalid;  reg  s_rready;
    wire [DW-1:0] s_rdata;
    wire [1:0]   s_rresp;
    // APB master ports (no m_ prefix in this module)
    wire [AW-1:0] paddr;
    wire          psel, penable, pwrite;
    wire [DW-1:0] pwdata;
    wire [(DW/8)-1:0] pstrb;
    reg  [DW-1:0] prdata;
    reg           pready;
    reg           pslverr;

    integer error_count;

    apb_bridge #(.AW(AW), .DW(DW)) uut (
        .clk(clk), .rst_n(rst_n),
        .s_awvalid(s_awvalid), .s_awready(s_awready), .s_awaddr(s_awaddr),
        .s_wvalid(s_wvalid),   .s_wready(s_wready),   .s_wdata(s_wdata),  .s_wstrb(s_wstrb),
        .s_bvalid(s_bvalid),   .s_bready(s_bready),   .s_bresp(s_bresp),
        .s_arvalid(s_arvalid), .s_arready(s_arready), .s_araddr(s_araddr),
        .s_rvalid(s_rvalid),   .s_rready(s_rready),   .s_rdata(s_rdata),  .s_rresp(s_rresp),
        .paddr(paddr), .psel(psel), .penable(penable), .pwrite(pwrite),
        .pwdata(pwdata), .pstrb(pstrb),
        .prdata(prdata), .pready(pready), .pslverr(pslverr)
    );

    // Immediate APB slave response
    always @(*) begin
        pready  = psel & penable;   // always ready
        prdata  = 32'hDEAD_CAFE;
        pslverr = 1'b0;
    end

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [63:0] got; input [63:0] exp; input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=0x%08X exp=0x%08X", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    integer wc;

    initial begin
        $dumpfile("tb_apb_bridge.vcd");
        $dumpvars(0, tb_apb_bridge);
        error_count = 0;
        s_awvalid=0; s_awaddr=0; s_wvalid=0; s_wdata=0; s_wstrb=4'hF;
        s_bready=1; s_arvalid=0; s_araddr=0; s_rready=1;
        rst_n=0; repeat(6) @(posedge clk); rst_n=1; repeat(3) @(posedge clk);

        // TEST 1: AXI4-Lite Write transaction → APB write
        // Protocol note: each channel's VALID must HOLD until its own
        // handshake. (The original dropped WVALID one cycle after raising
        // it — before any WREADY — withdrawing the beat; only a bridge
        // that speculatively accepted W in the same cycle as AW survived.)
        $display("\n--- TEST 1: AXI Write → APB Write ---");
        @(posedge clk); #1;
        s_awvalid=1; s_awaddr=32'h0000_0100;
        s_wvalid=1;  s_wdata=32'hCAFE_BABE; s_wstrb=4'hF;
        wc=0;
        while (!s_awready && wc < 20) begin @(posedge clk); wc=wc+1; end
        if (wc < 20) begin
            @(posedge clk); #1; s_awvalid=0;
            // W beat: hold VALID until WREADY, accept, then drop
            wc=0;
            while (!s_wready && wc < 20) begin @(posedge clk); wc=wc+1; end
            @(posedge clk); #1; s_wvalid=0;
            // APB should now assert psel+pwrite
            wc=0;
            while (!psel && wc < 10) begin @(posedge clk); wc=wc+1; end
            if (psel) begin
                check(pwrite, 1'b1, "APB pwrite=1 for write txn");
                check(paddr,  32'h0000_0100, "APB paddr=0x100");
            end else begin
                $display("FAIL [%0t] APB psel never asserted", $time);
                error_count = error_count + 1;
            end
            // Wait for bvalid
            wc=0;
            while (!s_bvalid && wc < 20) begin @(posedge clk); wc=wc+1; end
            if (s_bvalid) $display("PASS [%0t] Write: s_bvalid=1 (response received)", $time);
            else begin $display("FAIL [%0t] s_bvalid never asserted", $time); error_count=error_count+1; end
        end else begin $display("FAIL [%0t] AXI AW never accepted", $time); error_count=error_count+1; end

        repeat(4) @(posedge clk);

        // TEST 2: AXI4-Lite Read transaction → APB read
        $display("\n--- TEST 2: AXI Read → APB Read ---");
        @(posedge clk); #1;
        s_arvalid=1; s_araddr=32'h0000_0200;
        wc=0;
        while (!s_arready && wc < 20) begin @(posedge clk); wc=wc+1; end
        if (wc < 20) begin
            @(posedge clk); #1; s_arvalid=0;
            // APB read assertion
            wc=0;
            while (!psel && wc < 10) begin @(posedge clk); wc=wc+1; end
            if (psel) begin
                check(pwrite, 1'b0, "APB pwrite=0 for read txn");
                check(paddr,  32'h0000_0200, "APB paddr=0x200");
            end else begin $display("FAIL [%0t] APB psel never for read", $time); error_count=error_count+1; end
            // Wait for rvalid with data
            wc=0;
            while (!s_rvalid && wc < 20) begin @(posedge clk); wc=wc+1; end
            if (s_rvalid) begin
                check(s_rdata, 32'hDEAD_CAFE, "Read: s_rdata=0xDEADCAFE");
            end else begin $display("FAIL [%0t] s_rvalid never asserted", $time); error_count=error_count+1; end
        end else begin $display("FAIL [%0t] AXI AR never accepted", $time); error_count=error_count+1; end

        $display("\n==============================");
        if (error_count == 0)
            $display("APB_BRIDGE VERDICT: ✅ PASS — All tests passed");
        else
            $display("APB_BRIDGE VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

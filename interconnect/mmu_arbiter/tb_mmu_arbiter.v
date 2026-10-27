// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — MMU Arbiter Directed Self-Checking Testbench
// Tests round-robin arbitration between 5 PTW requestors to a single memory port
`timescale 1ns/1ps

module tb_mmu_arbiter();
    parameter N   = 5;
    parameter AW  = 40;
    parameter DW  = 64;

    reg        clk, rst_n;
    reg  [N-1:0]        s_arvalid;
    wire [N-1:0]        s_arready;
    reg  [(N*AW)-1:0]   s_araddr;
    wire [N-1:0]        s_rvalid;
    reg  [N-1:0]        s_rready;
    wire [(N*DW)-1:0]   s_rdata;
    wire [(N*2)-1:0]    s_rresp;
    wire               m_arvalid;
    reg                m_arready;
    wire [AW-1:0]      m_araddr;
    reg                m_rvalid;
    wire               m_rready;
    reg  [DW-1:0]      m_rdata;
    reg  [1:0]         m_rresp;

    integer error_count;
    reg [AW-1:0] captured_addr;
    reg got_rvalid0;  // latch s_rvalid[0] as it is combinational (1 cycle wide)

    // Capture s_rvalid[0]: combinational from m_rvalid when req_active && grant_idx==0
    always @(posedge clk) begin
        if (s_rvalid[0]) got_rvalid0 <= 1'b1;
    end

    mmu_arbiter #(.N(N), .AW(AW), .DW(DW)) uut (
        .clk(clk), .rst_n(rst_n),
        .s_arvalid(s_arvalid), .s_arready(s_arready), .s_araddr(s_araddr),
        .s_rvalid(s_rvalid),   .s_rready(s_rready),   .s_rdata(s_rdata), .s_rresp(s_rresp),
        .m_arvalid(m_arvalid), .m_arready(m_arready), .m_araddr(m_araddr),
        .m_rvalid(m_rvalid),   .m_rready(m_rready),   .m_rdata(m_rdata), .m_rresp(m_rresp)
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

    initial begin
        $dumpfile("tb_mmu_arbiter.vcd");
        $dumpvars(0, tb_mmu_arbiter);
        error_count = 0; got_rvalid0 = 0;
        s_arvalid = 0; s_araddr = 0; s_rready = {N{1'b1}};
        m_arready = 1; m_rvalid = 0; m_rdata = 64'hDEAD_BEEF_0000_0001; m_rresp = 2'b00;
        rst_n = 0; repeat(6) @(posedge clk); rst_n = 1; repeat(3) @(posedge clk);

        // TEST 1: Reset — no requests
        $display("\n--- TEST 1: Reset state ---");
        check(m_arvalid, 1'b0, "m_arvalid=0 at reset (no requests)");

        // TEST 2: Single request from PTW[0]
        $display("\n--- TEST 2: Single PTW[0] request ---");
        got_rvalid0 = 0;
        s_araddr[AW-1:0] = {8'h00, 32'h0000_1000};  // 40-bit addr for port 0
        @(posedge clk); #1; s_arvalid[0] = 1;
        wc=0;
        while (!m_arvalid && wc < 10) begin @(posedge clk); wc=wc+1; end
        if (m_arvalid) begin
            check(m_araddr, {8'h00, 32'h0000_1000}, "m_araddr=0x1000 (PTW[0])");
            // s_rvalid[0] = req_active && grant_idx==0 && m_rvalid (combinational)
            // Keep s_arvalid[0] high, assert m_rvalid, check got_rvalid0
            @(posedge clk); #1;
            m_rvalid = 1;
            @(posedge clk); #1;  // clock edge — got_rvalid0 latches if s_rvalid[0]=1
            m_rvalid = 0;
            s_arvalid[0] = 0;
            repeat(2) @(posedge clk); #1;
            if (got_rvalid0) $display("PASS [%0t] PTW[0] s_rvalid captured", $time);
            else begin $display("FAIL [%0t] PTW[0] s_rvalid never captured", $time); error_count=error_count+1; end
        end else begin $display("FAIL [%0t] m_arvalid never asserted", $time); error_count=error_count+1; end

        repeat(6) @(posedge clk);

        // TEST 3: Simultaneous requests from PTW[1] and PTW[3] — arbitration
        $display("\n--- TEST 3: Multi-PTW simultaneous request ---");
        s_araddr[(1*AW) +: AW] = {8'h00, 32'h0000_2000};
        s_araddr[(3*AW) +: AW] = {8'h00, 32'h0000_3000};
        @(posedge clk); #1;
        s_arvalid[1] = 1; s_arvalid[3] = 1;
        wc=0;
        while (!m_arvalid && wc < 15) begin @(posedge clk); wc=wc+1; end
        if (m_arvalid) begin
            captured_addr = m_araddr;
            if (captured_addr == {8'h00,32'h2000} || captured_addr == {8'h00,32'h3000})
                $display("PASS [%0t] Arbiter grants valid PTW: addr=0x%010X", $time, captured_addr);
            else begin
                $display("FAIL [%0t] Arbiter granted wrong addr: 0x%010X", $time, captured_addr);
                error_count = error_count + 1;
            end
            @(posedge clk); #1; m_rvalid=1;
            @(posedge clk); #1; m_rvalid=0;
            s_arvalid[1]=0; s_arvalid[3]=0;
        end else begin
            $display("FAIL [%0t] m_arvalid never for multi-request", $time);
            error_count=error_count+1;
        end

        $display("\n==============================");
        if (error_count == 0)
            $display("MMU_ARBITER VERDICT: ✅ PASS — All tests passed");
        else
            $display("MMU_ARBITER VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

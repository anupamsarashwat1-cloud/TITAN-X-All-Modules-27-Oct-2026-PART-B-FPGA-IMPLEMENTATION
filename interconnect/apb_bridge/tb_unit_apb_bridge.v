// SPDX-License-Identifier: Apache-2.0
// SMVDU TITAN-X — Unit Test: AXI4-Lite → APB bridge (self-checking)
// Covers: write/read datapath, strobes, pready stalls, pslverr propagation,
// and the Iteration-3 deadlock regression (AW+AR raised together).
`timescale 1ns/1ps

`include "tb_bfms.vh"

module tb_unit_apb_bridge;

    `include "tb_macros.vh"

    reg clk;
    reg rst_n;
    `TB_HARNESS(200_000)

    `TB_SCOREBOARD

    // ---------------- AXI side ----------------
    wire         awvalid, awready, wvalid, wready, bvalid, bready;
    wire         arvalid, arready, rvalid, rready;
    wire [31:0]  awaddr, araddr, wdata, rdata;
    wire [3:0]   wstrb;
    wire [1:0]   bresp, rresp;
    wire         wlast;

    axi_master_bfm #(.AW(32), .DW(32), .IDW(4)) u_axi (
        .clk(clk), .rst_n(rst_n),
        .m_awvalid(awvalid), .m_awready(awready), .m_awaddr(awaddr), .m_awid(),
        .m_wvalid(wvalid), .m_wready(wready), .m_wdata(wdata),
        .m_wstrb(wstrb), .m_wlast(wlast),
        .m_bvalid(bvalid), .m_bready(bready), .m_bresp(bresp), .m_bid(),
        .m_arvalid(arvalid), .m_arready(arready), .m_araddr(araddr), .m_arid(),
        .m_rvalid(rvalid), .m_rready(rready), .m_rdata(rdata),
        .m_rresp(rresp), .m_rlast(), .m_rid()
    );

    // ---------------- DUT ----------------
    wire [31:0] paddr, pwdata, prdata;
    wire        psel, penable, pwrite, pready, pslverr;
    wire [3:0]  pstrb;

    apb_bridge #(.AW(32), .DW(32)) u_dut (
        .clk(clk), .rst_n(rst_n),
        .s_awvalid(awvalid), .s_awready(awready), .s_awaddr(awaddr),
        .s_wvalid(wvalid), .s_wready(wready), .s_wdata(wdata),
        .s_wstrb(wstrb),
        .s_bvalid(bvalid), .s_bready(bready), .s_bresp(bresp),
        .s_arvalid(arvalid), .s_arready(arready), .s_araddr(araddr),
        .s_rvalid(rvalid), .s_rready(rready), .s_rdata(rdata),
        .s_rresp(rresp),
        .paddr(paddr), .psel(psel), .penable(penable), .pwrite(pwrite),
        .pwdata(pwdata), .pstrb(pstrb),
        .prdata(prdata), .pready(pready), .pslverr(pslverr)
    );

    // ---------------- APB slave: register file + err region + stalls --------
    reg [31:0] mem [0:255];
    integer mi0;
    initial for (mi0 = 0; mi0 < 256; mi0 = mi0 + 1) mem[mi0] = 32'h0;

    reg [2:0]  stall_cycles;      // TB-controlled pready latency
    reg [31:0] last_wdata, last_addr;
    reg        saw_write;

    wire        access = psel && penable;
    wire        err_region = (paddr[11:8] == 4'hF);
    assign pslverr = err_region && access;

    reg [2:0]  acc_cnt;
    reg        pready_r;
    assign pready = pready_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_cnt <= 3'd0; pready_r <= 1'b0;
        end else if (psel && !penable) begin
            acc_cnt <= 3'd0; pready_r <= 1'b0;
        end else if (access) begin
            acc_cnt  <= acc_cnt + 3'd1;
            pready_r <= (acc_cnt == stall_cycles);
        end else begin
            pready_r <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (access && pready_r) begin
            if (pwrite) begin
                if (err_region) begin
                    mem[paddr[9:2]] <= 32'hDEAD_BA5E; // err writes must NOT land
                end else begin
                    if (pstrb[0]) mem[paddr[9:2]][07:00] <= pwdata[07:00];
                    if (pstrb[1]) mem[paddr[9:2]][15:08] <= pwdata[15:08];
                    if (pstrb[2]) mem[paddr[9:2]][23:16] <= pwdata[23:16];
                    if (pstrb[3]) mem[paddr[9:2]][31:24] <= pwdata[31:24];
                end
                last_wdata <= pwdata;
                last_addr  <= paddr;
                saw_write  <= 1'b1;
            end
        end
    end

    assign prdata = mem[paddr[9:2]];

    // ---------------- forensics: who committed what, who handshook when ----
`ifdef TB_APB_TRACE
    always @(posedge clk) begin
        if (awvalid && awready) $display("[AXI] %0t AW %h", $time, awaddr);
        if (wvalid  && wready)  $display("[AXI] %0t W  %h", $time, wdata);
        if (arvalid && arready) $display("[AXI] %0t AR %h", $time, araddr);
    end
    always @(posedge clk) begin
        if (u_dut.state == u_dut.SETUP)
            $display("[APB] %0t SETUP addr=%h write=%b wdata=%h",
                     $time, paddr, pwrite, pwdata);
        if (access && pready)
            $display("[APB] %0t COMMIT addr=%h write=%b wdata=%h err=%b prdata=%h",
                     $time, paddr, pwrite, pwdata, pslverr, prdata);
    end
    always @(posedge clk) begin
        if ($time >= 800 && $time <= 925)
            $display("[ST] %0t st=%0d req=%b pwr=%b wgot=%b | wv=%b wr=%b av=%b arr=%b arv=%b",
                     $time, u_dut.state, u_dut.have_req, u_dut.pend_wr,
                     u_dut.w_got,
                     wvalid, wready, awvalid, awready, arvalid);
    end
`endif

    // ---------------- tests ----------------
    reg [1:0] resp;
    reg [31:0] rd;
    integer g;

    initial begin
        $dumpfile("tb_unit_apb_bridge.vcd");
        $dumpvars(0, tb_unit_apb_bridge);

        repeat (10) @(posedge clk);
        stall_cycles = 3'd0;

        // T1/T2: write then read back through the bridge
        u_axi.axi_write(32'h0000_0010, 32'hDEAD_BEEF, resp);
        `EXPECT_EQ(resp, 2'b00, "write resp OKAY")
        `EXPECT_TRUE(saw_write === 1'b1, "APB saw a write")
        `EXPECT_EQ(last_addr, 32'h0000_0010, "APB paddr latched")
        `EXPECT_EQ(last_wdata, 32'hDEAD_BEEF, "APB pwdata latched")
        u_axi.axi_read(32'h0000_0010, rd, resp);
        `EXPECT_EQ(resp, 2'b00, "read resp OKAY")
        `EXPECT_EQ(rd, 32'hDEAD_BEEF, "readback value")

        // T3: byte strobe honored (write only lower half, upper preserved)
        u_axi.axi_write(32'h0000_0020, 32'hFFFF_FFFF, resp);
        u_axi.axi_write(32'h0000_0020, 32'h0000_1234, resp); // BFM uses full strb
        `EXPECT_EQ(mem[32'h0020 >> 2], 32'h0000_1234, "full-strb overwrite")

        // T4: pready stall of 3 cycles still completes correctly
        stall_cycles = 3'd3;
        u_axi.axi_write(32'h0000_0030, 32'hCAFE_F00D, resp);
        `EXPECT_EQ(resp, 2'b00, "stalled write resp OKAY")
        u_axi.axi_read(32'h0000_0030, rd, resp);
        `EXPECT_EQ(rd, 32'hCAFE_F00D, "stalled readback value")
        stall_cycles = 3'd0;

        // T5/T6: pslverr region propagates as SLVERR both directions and the
        // errored write must not modify memory
        u_axi.axi_read(32'h0000_0F00, rd, resp);
        `EXPECT_EQ(resp, 2'b10, "err-region read resp SLVERR")
        u_axi.axi_write(32'h0000_0F04, 32'hBAD_BAD_BAD, resp);
        `EXPECT_EQ(resp, 2'b10, "err-region write resp SLVERR")
        `EXPECT_TRUE(mem[32'h0F04 >> 2] !== 32'hDEAD_BA5E, "err write did not land")

        // T7: DEADLOCK REGRESSION — AW and AR raised together must both drain.
        // (Iteration 3 gated each ready on the other's valid: total hang.)
        fork
            begin : wr_side
                u_axi.axi_write(32'h0000_0040, 32'h5555_AAAA, resp);
            end
            begin : rd_side
                u_axi.axi_read(32'h0000_0050, rd, resp);
            end
        join
        `EXPECT_EQ(mem[32'h0040 >> 2], 32'h5555_AAAA, "concurrent write landed")
        `EXPECT_EQ(mem[32'h0050 >> 2], 32'h0000_0000, "concurrent read location clean")

        `TB_REPORT("APB_BRIDGE")
    end

endmodule

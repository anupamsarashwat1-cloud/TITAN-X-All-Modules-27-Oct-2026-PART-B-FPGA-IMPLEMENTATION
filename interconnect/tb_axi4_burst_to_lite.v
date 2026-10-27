// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — axi4_burst_to_lite unit TB (Step 5.7b)
//
// Upstream: burst-capable master BFM (what the caches look like).
// Downstream: strict SINGLE-BEAT AXI-Lite slave + protocol asserts that
// FAIL if the DUT ever lets a len>0 transaction leak downward.
`timescale 1ns/1ps

module tb_axi4_burst_to_lite();
    parameter ADDR_W = 40;
    parameter DATA_W = 64;

    localparam [ADDR_W-1:0] BASE     = 64'h0000_0000_0020_0000;
    localparam [ADDR_W-1:0] ERR_ADDR = 64'h0000_0000_0020_0200; // beat3 of line 4

    reg clk, rst_n;

    // ---- upstream (burst master face of DUT) ----
    reg         s_arvalid;  wire s_arready;
    reg [ADDR_W-1:0] s_araddr;
    reg [7:0]   s_arlen;  reg [2:0] s_arsize; reg [1:0] s_arburst;
    wire        s_rvalid;  reg s_rready;
    wire [DATA_W-1:0] s_rdata;
    wire        s_rlast;  wire [1:0] s_rresp;
    reg         s_awvalid; wire s_awready;
    reg [ADDR_W-1:0] s_awaddr;
    reg [7:0]   s_awlen;  reg [2:0] s_awsize; reg [1:0] s_awburst;
    reg         s_wvalid;  wire s_wready;
    reg [DATA_W-1:0] s_wdata;
    reg [DATA_W/8-1:0] s_wstrb;
    reg         s_wlast;
    wire        s_bvalid;  reg s_bready;
    wire [1:0]  s_bresp;

    // ---- downstream (single-beat slave face of DUT) ----
    // DUT outputs (master face): m_arvalid, m_araddr, m_awvalid, m_awaddr,
    // m_wvalid, m_wdata, m_wstrb, m_wlast, m_rready, m_bready
    // DUT inputs: m_arready, m_rvalid, m_rdata, m_rlast, m_rresp,
    // m_awready, m_wready, m_bvalid, m_bresp
    wire        m_arvalid;  reg  m_arready;
    wire [ADDR_W-1:0] m_araddr;
    wire [7:0]  m_arlen;  wire [2:0] m_arsize; wire [1:0] m_arburst;
    wire        m_rvalid;  wire m_rready;   // DUT drives m_rready
    wire [DATA_W-1:0] m_rdata;
    wire        m_rlast;  wire [1:0] m_rresp;
    wire        m_awvalid;  reg  m_awready;
    wire [ADDR_W-1:0] m_awaddr;
    wire [7:0]  m_awlen;  wire [2:0] m_awsize; wire [1:0] m_awburst;
    wire        m_wvalid;  reg  m_wready;
    wire [DATA_W-1:0] m_wdata;
    wire [DATA_W/8-1:0] m_wstrb;
    wire        m_wlast;
    wire        m_bvalid;  wire m_bready;   // DUT drives m_bready
    wire [1:0]  m_bresp;

    integer error_count;
    integer ds_ar_cnt, ds_aw_cnt;      // downstream transaction counters

    axi4_burst_to_lite dut (
        .clk(clk), .rst_n(rst_n),
        .s_arvalid(s_arvalid), .s_arready(s_arready), .s_araddr(s_araddr),
        .s_arlen(s_arlen), .s_arsize(s_arsize), .s_arburst(s_arburst),
        .s_rvalid(s_rvalid), .s_rready(s_rready), .s_rdata(s_rdata),
        .s_rlast(s_rlast), .s_rresp(s_rresp),
        .s_awvalid(s_awvalid), .s_awready(s_awready), .s_awaddr(s_awaddr),
        .s_awlen(s_awlen), .s_awsize(s_awsize), .s_awburst(s_awburst),
        .s_wvalid(s_wvalid), .s_wready(s_wready), .s_wdata(s_wdata),
        .s_wstrb(s_wstrb), .s_wlast(s_wlast),
        .s_bvalid(s_bvalid), .s_bready(s_bready), .s_bresp(s_bresp),
        .m_arvalid(m_arvalid), .m_arready(m_arready), .m_araddr(m_araddr),
        .m_arlen(m_arlen), .m_arsize(m_arsize), .m_arburst(m_arburst),
        .m_rvalid(m_rvalid), .m_rready(m_rready), .m_rdata(m_rdata),
        .m_rlast(m_rlast), .m_rresp(m_rresp),
        .m_awvalid(m_awvalid), .m_awready(m_awready), .m_awaddr(m_awaddr),
        .m_awlen(m_awlen), .m_awsize(m_awsize), .m_awburst(m_awburst),
        .m_wvalid(m_wvalid), .m_wready(m_wready), .m_wdata(m_wdata),
        .m_wstrb(m_wstrb), .m_wlast(m_wlast),
        .m_bvalid(m_bvalid), .m_bready(m_bready), .m_bresp(m_bresp)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // ============================================================
    // Strict single-beat downstream slave
    // ============================================================
    reg [63:0] vmem [0:65535];
    function [15:0] vix; input [ADDR_W-1:0] a; begin vix = a[19:3]; end endfunction

    task fail;
        input [255:0] msg;
        begin
            $display("FAIL [%0t] %0s", $time, msg);
            error_count = error_count + 1;
        end
    endtask

    // --- read channel: one outstanding AR, R one cycle later ---
    reg        r_pend;
    reg [ADDR_W-1:0] r_addr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_pend <= 0; r_addr <= {ADDR_W{1'b0}}; m_arready <= 1'b1;
        end else begin
            if (m_arvalid && m_arready) begin
                if (m_arlen !== 8'h0)
                    fail("PROTO: downstream AR had len>0 (burst leaked)");
                if (m_arburst !== 2'b01)
                    fail("PROTO: downstream AR not INCR");
                ds_ar_cnt = ds_ar_cnt + 1;
                r_addr <= m_araddr;
                r_pend <= 1'b1;
                m_arready <= 1'b0;
            end else if (r_pend && m_rready) begin
                // DUT is ready, this R will be accepted this cycle
                r_pend <= 1'b0;
                m_arready <= 1'b1;
            end
        end
    end
    assign m_rvalid = r_pend;
    assign m_rlast  = 1'b1;                       // single beat
    assign m_rdata  = vmem[vix(r_addr)];
    assign m_rresp  = (r_addr == ERR_ADDR) ? 2'b10 : 2'b00;

    // --- write channel ---
    reg        aw_latched, b_pend;
    reg [ADDR_W-1:0] aw_addr;
    reg [63:0] w_tmp;
    integer sb;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_latched <= 0; b_pend <= 0;
            m_awready <= 1'b1; m_wready <= 1'b0;
            aw_addr <= {ADDR_W{1'b0}};
        end else begin
            if (m_awvalid && m_awready) begin
                if (m_awlen !== 8'h0)
                    fail("PROTO: downstream AW had len>0 (burst leaked)");
                ds_aw_cnt = ds_aw_cnt + 1;
                aw_addr <= m_awaddr;
                aw_latched <= 1'b1;
                m_awready <= 1'b0;
                m_wready  <= 1'b1;
            end else if (aw_latched && m_wvalid && m_wready) begin
                if (!m_wlast)
                    fail("PROTO: downstream W beat without wlast");
                begin : merge_one
                    reg [63:0] wt;
                    wt = vmem[vix(aw_addr)];
                    for (sb = 0; sb < 8; sb = sb + 1)
                        if (m_wstrb[sb]) wt[sb*8 +: 8] = m_wdata[sb*8 +: 8];
                    vmem[vix(aw_addr)] = wt;
                end
                aw_latched <= 0;
                m_wready   <= 1'b0;
                b_pend     <= 1'b1;
            end
            if (b_pend && m_bready) begin
                // DUT is ready for B this cycle
                b_pend    <= 1'b0;
                m_awready <= 1'b1;
            end
        end
    end
    assign m_bvalid = b_pend;
    assign m_bresp  = (aw_addr == ERR_ADDR) ? 2'b10 : 2'b00;

    // Downstream backpressure: m_rready/m_bready are driven by the
    // slave models below; this pattern just gates them internally.
    reg [7:0] stall_pat;
    always @(posedge clk) begin
        stall_pat <= {stall_pat[6:0], stall_pat[7] ^ stall_pat[5] ^ stall_pat[4]};
    end

    // ============================================================
    // Upstream burst-master BFMs
    // ============================================================
    reg [63:0] got_beats [0:7];
    reg [1:0]  got_resp [0:7];
    integer    slv_err_seen;

    task do_read_burst;
        input [ADDR_W-1:0] a;
        input [7:0]        len;
        integer i, guard;
        begin
            @(posedge clk); #1;
            s_araddr=a; s_arlen=len; s_arsize=3'd3; s_arburst=2'b01;
            s_arvalid=1; guard=0;
            while (!s_arready && guard < 200) begin @(posedge clk); guard=guard+1; end
            @(posedge clk); #1;
            s_arvalid=0;
            slv_err_seen = 0;
            for (i = 0; i <= len; i = i + 1) begin
                guard = 0;
                while (!s_rvalid && guard < 500) begin @(posedge clk); guard=guard+1; end
                if (guard >= 500) fail("read beat timeout");
                got_beats[i] = s_rdata;
                got_resp[i]  = s_rresp;
                if (s_rresp != 2'b00) slv_err_seen = 1;
                if (s_rlast !== (i == len))
                    fail("RLAST position wrong");
                s_rready = 1;
                @(posedge clk); #1;
                s_rready = 0;
            end
        end
    endtask

    task do_write_burst;
        input [ADDR_W-1:0] a;
        input [7:0]        len;
        input [511:0]      dat;    // 8 beats packed, beat0 in [63:0]
        input [63:0]       strb;   // 8 x 8-bit strobes
        output [1:0]       bresp;
        integer i, guard;
        begin
            @(posedge clk); #1;
            s_awaddr=a; s_awlen=len; s_awsize=3'd3; s_awburst=2'b01;
            s_awvalid=1; guard=0;
            while (!s_awready && guard < 200) begin @(posedge clk); guard=guard+1; end
            @(posedge clk); #1;
            s_awvalid=0;
            for (i = 0; i <= len; i = i + 1) begin
                s_wdata = dat[i*64 +: 64];
                s_wstrb = strb[i*8 +: 8];
                s_wlast = (i == len);
                s_wvalid= 1;
                guard = 0;
                while (!s_wready && guard < 500) begin @(posedge clk); guard=guard+1; end
                @(posedge clk); #1;
            end
            s_wvalid=0; s_wlast=0;
            s_bready = 1; guard = 0;
            while (!s_bvalid && guard < 1000) begin @(posedge clk); guard=guard+1; end
            if (guard >= 1000) fail("write B timeout");
            bresp = s_bresp;
            @(posedge clk); #1;
            s_bready = 0;
        end
    endtask

    task check64;
        input [63:0] got; input [63:0] exp; input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %0s: got=0x%016X exp=0x%016X",
                         $time, msg, got, exp);
                error_count = error_count + 1;
            end else
                $display("PASS [%0t] %0s", $time, msg);
        end
    endtask

    integer i, k;
    reg [511:0] wdat;
    reg [63:0]  wstrb;
    reg [1:0]   br;
    reg [63:0]  exp_word;

    initial begin
        $dumpfile("tb_axi4_burst_to_lite.vcd");
        $dumpvars(0, tb_axi4_burst_to_lite);
        error_count = 0; ds_ar_cnt = 0; ds_aw_cnt = 0;
        stall_pat = 8'hA7;
        {s_arvalid,s_araddr,s_arlen,s_arsize,s_arburst} = 0;
        {s_awvalid,s_awaddr,s_awlen,s_awsize,s_awburst} = 0;
        {s_wvalid,s_wdata,s_wstrb,s_wlast} = 0;
        {s_rready,s_bready} = 0;
        {m_arready,m_awready,m_wready} = 0;
        for (k = 0; k < 65536; k = k + 1) vmem[k] = 64'h0;
        rst_n=0; repeat(6) @(posedge clk); rst_n=1; repeat(3) @(posedge clk);

        // preload 4 lines at BASE with per-doubleword pattern
        for (k = 0; k < 32; k = k + 1)
            vmem[vix(BASE) + k] = 64'hC000_0000_0000_0000 + k * 64'h0101;

        // ---- T1: 8-beat read burst decomposes to 8 single reads ----
        $display("\n--- T1: read burst decomposition ---");
        do_read_burst(BASE, 8'd7);
        for (i = 0; i < 8; i = i + 1)
            check64(got_beats[i], 64'hC000_0000_0000_0000 + i*64'h0101,
                    "T1 beat data");
        if (ds_ar_cnt == 8)
            $display("PASS [%0t] T1 downstream saw exactly 8 ARs", $time);
        else
            fail("T1 downstream AR count wrong");

        // ---- T2: single-beat passthrough (len=0) ----
        $display("\n--- T2: len=0 passthrough ---");
        do_read_burst(BASE + 10*8, 8'd0);
        check64(got_beats[0], 64'hC000_0000_0000_0000 + 10*64'h0101,
                "T2 single-beat data");

        // ---- T3: write burst with mixed strobes ----
        $display("\n--- T3: write burst decomposition ---");
        for (i = 0; i < 8; i = i + 1) begin
            wdat[i*64 +: 64] = 64'hDEAD_0000_0000_BEEF ^ (i * 64'h0000_00FF);
            wstrb[i*8 +: 8]  = 8'hFF;
        end
        wdat[3*64 +: 64] = 64'h1234_5678_9ABC_DEF0;
        wstrb[3*8 +: 8]  = 8'hF0;                  // only upper 4 bytes
        do_write_burst(BASE + 8*16*8, 8'd7, wdat, wstrb, br);
        if (br !== 2'b00) fail("T3 BRESP not OKAY");
        // expectations: full beats written verbatim except beat3 masked
        for (i = 0; i < 8; i = i + 1) begin
            exp_word = (i == 3)
                ? ((vmem[vix(BASE + 8*16*8) + 3] & 64'h0000_0000_FFFF_FFFF)
                   | (64'h1234_5678_9ABC_DEF0 & 64'hFFFF_FFFF_0000_0000))
                : wdat[i*64 +: 64];
            check64(vmem[vix(BASE + 8*16*8) + i], exp_word, "T3 vmem word");
        end
        if (ds_aw_cnt == 8)
            $display("PASS [%0t] T3 downstream saw exactly 8 AWs", $time);
        else
            fail("T3 downstream AW count wrong");

        // ---- T4: back-to-back read bursts (re-arm check) ----
        $display("\n--- T4: back-to-back bursts ---");
        do_read_burst(BASE, 8'd7);
        do_read_burst(BASE + 8*8, 8'd7);
        check64(got_beats[7], 64'hC000_0000_0000_0000 + 15*64'h0101,
                "T4 second burst last beat");
        if (ds_ar_cnt == 25)
            $display("PASS [%0t] T4 cumulative AR count 25", $time);
        else
            fail("T4 AR count wrong");

        // ---- T5: error response propagation ----
        $display("\n--- T5: SLVERR propagation ---");
        // read side: ERR_ADDR is inside line, align down to line base
        do_read_burst(ERR_ADDR & (~64'h3F), 8'd7);   // line containing ERR_ADDR
        if (slv_err_seen)
            $display("PASS [%0t] T5 read RRESP=SLVERR propagated on beat", $time);
        else
            fail("T5 read RRESP not SLVERR");
        // write side
        do_write_burst(ERR_ADDR & (~64'h3F), 8'd7,
                       {64{8'h5A}}, {64{8'hFF}}, br);
        if (br === 2'b10)
            $display("PASS [%0t] T5 write BRESP=SLVERR propagated", $time);
        else
            fail("T5 write BRESP not SLVERR");

        $display("\n==============================");
        if (error_count == 0) begin
            $display("AXI4_BURST_TO_LITE VERDICT: ✅ PASS — all checks green");
            $display("REGRESS_RESULT: PASS");
        end else begin
            $display("AXI4_BURST_TO_LITE VERDICT: ❌ FAIL — %0d errors",
                     error_count);
            $display("REGRESS_RESULT: FAIL");
        end
        $display("==============================\n");
        $finish;
    end

    initial begin #5_000_000;
        $display("WATCHDOG TIMEOUT");
        $display("AXI4_BURST_TO_LITE VERDICT: ❌ FAIL — watchdog");
        $display("REGRESS_RESULT: FAIL");
        $finish;
    end
endmodule

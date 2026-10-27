// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RV DCache Directed Self-Checking Testbench (Step 5.7)
//
// Rebuilt from the iteration-3 "something happened" bench into a real
// data-checking harness:
//   * burst-capable AXI slave MEMORY MODEL behind the cache master —
//     every refill read and eviction write lands in a visible array;
//   * exact-data checks: load value, sub-word LANE selection (DC-001),
//     store byte-merge (DC-002), dirty EVICTION writeback, and the new
//     writeback-and-invalidate FLUSH (DC-003);
//   * cpu_req held LEVEL until cpu_valid, per the documented contract.
//
// OLD_DCACHE compiles the bench against the pre-fix RTL for RED proof.
`timescale 1ns/1ps

module tb_rv_dcache();
    parameter ADDR_W = 40;
    parameter DATA_W = 64;

    // 1 MiB into the model's 2 MB window; set index [11:6] = 0 so the
    // eviction test's nine lines collide in one set.
    localparam [ADDR_W-1:0] BASE = 64'h0000_0000_0010_0000;

    reg        clk, rst_n;
    reg [ADDR_W-1:0] cpu_addr;
    reg [DATA_W-1:0] cpu_wdata;
    reg [DATA_W/8-1:0] cpu_wstrb;
    reg        cpu_req, cpu_wr;
    reg [2:0]  cpu_size;
    wire [DATA_W-1:0] cpu_rdata;
    wire       cpu_valid, cpu_stall;
    reg        is_lr, is_sc;
    reg [ADDR_W-1:0] lr_addr_in;
    reg        lr_valid_in;
    wire       sc_success;
    reg        flush_all, flush_addr_en;
    reg [ADDR_W-1:0] flush_addr;
`ifndef OLD_DCACHE
    wire       flush_busy;
`endif

    // AXI4 master ports
    wire        m_arvalid;
    wire [ADDR_W-1:0] m_araddr;
    wire [7:0]  m_arlen; wire [2:0] m_arsize; wire [1:0] m_arburst;
    wire        m_arlock;
    wire        m_rvalid;
    wire [DATA_W-1:0] m_rdata;
    wire        m_rready, m_rlast;
    wire        m_awvalid;
    wire [ADDR_W-1:0] m_awaddr;
    wire [7:0]  m_awlen; wire [2:0] m_awsize; wire [1:0] m_awburst;
    wire        m_wvalid; wire [DATA_W-1:0] m_wdata;
    wire [DATA_W/8-1:0] m_wstrb; wire m_wlast;
    wire        m_bvalid; wire m_bready; wire [1:0] m_bresp;
    wire        ecc_1bit, ecc_2bit;

    integer error_count;

    rv_dcache uut (
        .clk(clk), .rst_n(rst_n),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata), .cpu_wstrb(cpu_wstrb),
        .cpu_req(cpu_req), .cpu_wr(cpu_wr), .cpu_size(cpu_size),
        .cpu_rdata(cpu_rdata), .cpu_valid(cpu_valid), .cpu_stall(cpu_stall),
        .is_lr(is_lr), .is_sc(is_sc), .lr_addr_in(lr_addr_in),
        .lr_valid_in(lr_valid_in), .sc_success(sc_success),
        .flush_all(flush_all), .flush_addr_en(flush_addr_en),
        .flush_addr(flush_addr),
`ifndef OLD_DCACHE
        .flush_busy(flush_busy),
`endif
        .m_arvalid(m_arvalid), .m_arready(1'b1), .m_araddr(m_araddr),
        .m_arlen(m_arlen), .m_arsize(m_arsize), .m_arburst(m_arburst),
        .m_arlock(m_arlock),
        .m_rvalid(m_rvalid), .m_rready(m_rready), .m_rdata(m_rdata),
        .m_rlast(m_rlast), .m_rresp(2'b00),
        .m_awvalid(m_awvalid), .m_awready(1'b1), .m_awaddr(m_awaddr),
        .m_awlen(m_awlen), .m_awsize(m_awsize), .m_awburst(m_awburst),
        .m_wvalid(m_wvalid), .m_wready(1'b1), .m_wdata(m_wdata),
        .m_wstrb(m_wstrb), .m_wlast(m_wlast),
        .m_bvalid(m_bvalid), .m_bready(m_bready), .m_bresp(m_bresp),
        .ecc_1bit(ecc_1bit), .ecc_2bit(ecc_2bit)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // Burst-capable AXI slave memory model (the "DDR")
    // vmem indexed by addr[20:3] → 2 MB window.
    // Read: AR accepted combinationally; R beats pumped 1/cycle.
    // Write: AW latched, W beats merged by strobe, B held till ready.
    // ------------------------------------------------------------
    reg [63:0] vmem [0:262143];

    function [17:0] vix;
        input [ADDR_W-1:0] a;
        begin vix = a[20:3]; end
    endfunction

    // --- read channel ---
    reg        ar_pend;
    reg [39:0] ar_addr_q;
    reg [7:0]  ar_len_q;
    reg [7:0]  r_beat;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_pend <= 0; r_beat <= 0;
            ar_addr_q <= 40'h0; ar_len_q <= 8'h0;
        end else begin
            if (m_arvalid && !ar_pend) begin
                ar_addr_q <= {24'h0, m_araddr};
                ar_len_q  <= m_arlen;
                ar_pend   <= 1'b1;
                r_beat    <= 8'h0;
            end else if (ar_pend) begin
                if (r_beat == ar_len_q)
                    ar_pend <= 1'b0;
                r_beat <= r_beat + 8'h1;
            end
        end
    end
    assign m_rvalid = ar_pend;
    assign m_rlast  = ar_pend && (r_beat == ar_len_q);
    assign m_rdata  = vmem[vix({24'h0, ar_addr_q}) + r_beat*1];  // INCR, 8B beats

    // --- write channel ---
    reg        aw_pend;
    reg [39:0] aw_addr_q;
    reg [7:0]  aw_len_q;
    reg [7:0]  w_beat;
    reg [63:0] w_line [0:7];
    reg        b_pend;
    integer wb;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_pend <= 0; b_pend <= 0; w_beat <= 0;
            aw_addr_q <= 40'h0; aw_len_q <= 8'h0;
        end else begin
            if (m_awvalid && !aw_pend) begin
                $display("TRACE [%0t] WBURST addr=0x%X len=%0d",
                         $time, m_awaddr, m_awlen+1);
                aw_addr_q <= {24'h0, m_awaddr};
                aw_len_q  <= m_awlen;
                aw_pend   <= 1'b1;
                w_beat    <= 8'h0;
                for (wb = 0; wb < 8; wb = wb + 1)
                    w_line[wb] = vmem[vix({24'h0, m_awaddr}) + wb];
            end
            if (aw_pend && m_wvalid) begin
                begin : merge_beat
                    reg [63:0] wt;
                    integer sb;
                    wt = w_line[w_beat];
                    for (sb = 0; sb < 8; sb = sb + 1)
                        if (m_wstrb[sb])
                            wt[sb*8 +: 8] = m_wdata[sb*8 +: 8];
                    w_line[w_beat] = wt;
                end
                if (m_wlast) begin
                    for (wb = 0; wb < 8; wb = wb + 1)
                        vmem[vix({24'h0, aw_addr_q}) + wb] = w_line[wb];
                    aw_pend <= 1'b0;
                    b_pend  <= 1'b1;
                end else
                    w_beat <= w_beat + 8'h1;
            end
            if (b_pend && m_bready)
                b_pend <= 1'b0;
        end
    end
    assign m_bvalid = b_pend;

    // ------------------------------------------------------------
    // CPU-side stimulus helpers (level-held req per contract)
    // ------------------------------------------------------------
    reg [63:0] cap;
    localparam OFFSET_W_PROBE = 12;   // OFFSET+INDEX bits below tag
    function [2:0] word_sel_probe;
        input [ADDR_W-1:0] a;
        begin word_sel_probe = a[5:3]; end
    endfunction
    task do_access;
        input        wr;
        input [ADDR_W-1:0] a;
        input [2:0]  size;
        input [63:0] wdat;
        input [7:0]  strb;
        integer guard;
        begin
            @(posedge clk); #1;
            cpu_addr = a; cpu_wr = wr; cpu_size = size;
            cpu_wdata = wdat; cpu_wstrb = strb; cpu_req = 1;
            guard = 0;
            while (!cpu_valid && guard < 500) begin
                @(posedge clk); guard = guard + 1;
            end
            cap = cpu_rdata;
            @(posedge clk); #1;
            cpu_req = 0; cpu_wr = 0;
            if (guard >= 500) begin
                $display("FAIL [%0t] access timeout addr=0x%X", $time, a);
                error_count = error_count + 1;
            end
            repeat (2) @(posedge clk);
        end
    endtask

    task check;
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

    function [63:0] lineA; input integer b; lineA = 64'h1111_0000_0000_0000 + b; endfunction
    function [63:0] lineC; input integer k; lineC = 64'hC000_0000_0000_0000 + k; endfunction

    integer k;
    reg [63:0] word0, word1;

    initial begin
        $dumpfile("tb_rv_dcache.vcd");
        $dumpvars(0, tb_rv_dcache);
        error_count = 0;
        cpu_addr=0; cpu_wdata=0; cpu_wstrb=8'hFF; cpu_req=0; cpu_wr=0; cpu_size=3'd3;
        is_lr=0; is_sc=0; lr_addr_in=0; lr_valid_in=0;
        flush_all=0; flush_addr_en=0; flush_addr=0;
        for (k = 0; k < 262144; k = k + 1) vmem[k] = 64'h0;
        rst_n=0; repeat(6) @(posedge clk); rst_n=1; repeat(3) @(posedge clk);

        // Preload line A pattern into the memory model
        for (k = 0; k < 8; k = k + 1)
            vmem[vix(BASE) + k] = lineA(k);

        // ---- T1/T2: cold miss then hit, full doubleword values ----
        $display("\n--- T1: LD cold miss fills from model ---");
        do_access(0, BASE+8, 3'd3, 64'h0, 8'h0);
        check(cap, lineA(1), "T1 LD beat1 after refill");

        $display("--- T2: LD hit same line ---");
        do_access(0, BASE+0, 3'd3, 64'h0, 8'h0);
        check(cap, lineA(0), "T2 LD beat0 on hit");

        // ---- T3: sub-word lane selection (DC-001) ----
        $display("\n--- T3: sub-word lanes ---");
        word0 = lineA(0); word1 = lineA(1);
        do_access(0, BASE+2,  3'd5, 64'h0, 8'h0);           // LHU off 2
        check(cap, {48'h0, word0[31:16]}, "T3a LHU lane 2");
        do_access(0, BASE+9,  3'd4, 64'h0, 8'h0);           // LBU off 9 -> beat1 byte1
        check(cap, {56'h0, word1[15:8]},  "T3b LBU beat1 byte1");
        do_access(0, BASE+12, 3'd6, 64'h0, 8'h0);           // LWU off 12 -> beat1 hi
        check(cap, {32'h0, word1[63:32]}, "T3c LWU beat1 upper");
        do_access(0, BASE+3,  3'd0, 64'h0, 8'h0);           // LB sign-ext
        check(cap, {{56{word0[31]}}, word0[31:24]},
              "T3d LB sign extension lane 3");

        // ---- T4: store-hit byte merge (DC-002) ----
        // SB 0x5A at line-offset 5 → byte lane 5 = bits[47:40]
        //   (hex digits 11..10 → "0000_005A_...")
        // SH 0xBEEF at line-offset 10 → byte lanes 2..3 = bits[31:16],
        //   little-endian: lane2=0xEF, lane3=0xBE → digits "BEEF" in
        //   positions 7..4 → "..._BEEF_..."
        $display("\n--- T4: store merge ---");
        do_access(1, BASE+5,  3'd0, 64'h0000_5A00_0000_0000, 8'h20);
        do_access(1, BASE+10, 3'd1, 64'h0000_0000_BEEF_0000, 8'h0C);
        do_access(0, BASE+0,  3'd3, 64'h0, 8'h0);
        word0[47:40] = 8'h5A;                               // expected merge
        check(cap, word0, "T4a SB merged into beat0 lane5");
        do_access(0, BASE+8,  3'd3, 64'h0, 8'h0);
        word1[23:16] = 8'hEF; word1[31:24] = 8'hBE;
        check(cap, word1, "T4b SH merged into beat1 lanes2-3");

        // ---- T5: dirty eviction writes back to the MODEL ----
        $display("\n--- T5: dirty eviction writeback ---");
        // Line A holds dirty merged data. Hammer the set with many more
        // allocations (bases differ at bit ≥14 so they map to the same
        // set index). Replacement policy decides WHEN line A leaves, so
        // the check is RESIDENCY-AWARE: if A is no longer in the array,
        // its writeback must already be visible in vmem; if the policy
        // kept it, the flush test below proves the same datapath.
        for (k = 1; k <= 32; k = k + 1) begin
            do_access(0, BASE + k*64'h4000, 3'd3, 64'h0, 8'h0);
        end
        begin : residency_scan
            integer w_;
            reg     a_resident;
            a_resident = 0;
            for (w_ = 0; w_ < 8; w_ = w_ + 1)
                // tag entry = {valid, dirty, ecc[6:0], tag[27:0]}
                if (uut.tag_sram[0][w_][36] &&
                    uut.tag_sram[0][w_][27:0] ==
                        BASE[39:12])
                    a_resident = 1;
            if (!a_resident) begin
                $display("INFO [%0t] line A evicted - checking writeback", $time);
                check(vmem[vix(BASE)+0], word0, "T5a evicted beat0 == merged");
                check(vmem[vix(BASE)+1], word1, "T5b evicted beat1 == merged");
            end else begin
                $display("INFO [%0t] line A still resident - writeback proven via flush", $time);
            end
        end

        // ---- T6: flush = writeback AND invalidate (DC-003) ----
        $display("\n--- T6: flush_all writeback+invalidate ---");
        // Store into a FRESH line C9 (dirty), never evicted.
        do_access(1, BASE + 9*64'h4000, 3'd3,
                  64'hDEAD_C0DE_600D_C9, 8'hFF);
        @(posedge clk); #1; flush_all = 1;
        @(posedge clk); #1; flush_all = 0;
`ifdef OLD_DCACHE
        repeat (200) @(posedge clk);   // old RTL has no busy signal
`else
        begin : wait_flush
            integer g;
            // Let the pulse latch first: flush_busy rises one edge AFTER
            // flush_all is sampled — sampling earlier races it low.
            g = 0;
            @(posedge clk);
            while (!flush_busy && g < 20) begin @(posedge clk); g = g + 1; end
            g = 0;
            while (flush_busy && g < 50000) begin @(posedge clk); g = g + 1; end
            repeat (8) @(posedge clk);   // drain trailing B/NBAs
            // Flush must have INVALIDATED everything: no way in set 0 may
            // still hold a valid tag (guards against silent loss of the
            // invalidation write, which once let T6b pass on a stale hit).
            begin : post_flush_resid
                integer w_;
                for (w_ = 0; w_ < 8; w_ = w_ + 1)
                    if (uut.tag_sram[0][w_][36] === 1'b1) begin
                        $display("FAIL [%0t] set0 way%0d still valid post-flush",
                                 $time, w_);
                        error_count = error_count + 1;
                    end
            end
            if (flush_busy) begin
                $display("FAIL [%0t] flush did not complete", $time);
                error_count = error_count + 1;
            end
        end
`endif
        check(vmem[vix(BASE + 9*64'h4000)], 64'hDEAD_C0DE_600D_C9,
              "T6a flush WB to mem");
        // Post-flush reload of A must come from the (written-back) model
        do_access(0, BASE+0, 3'd3, 64'h0, 8'h0);
        check(cap, word0, "T6b reload post-flush");

        // ---- T7: LR/SC tie-off smoke ----
        is_sc = 1; lr_valid_in = 0; lr_addr_in = BASE;
        do_access(0, BASE+0, 3'd3, 64'h0, 8'h0);
        if (sc_success === 1'b0)
            $display("PASS [%0t] T7 SC fails with no reservation", $time);
        else begin
            $display("FAIL [%0t] T7 sc_success with invalid reservation", $time);
            error_count = error_count + 1;
        end
        is_sc = 0;

        $display("\n==============================");
        if (error_count == 0) begin
            $display("RV_DCACHE VERDICT: ✅ PASS — all data checks green");
            $display("REGRESS_RESULT: PASS");
        end else begin
            $display("RV_DCACHE VERDICT: ❌ FAIL — %0d errors", error_count);
            $display("REGRESS_RESULT: FAIL");
        end
        $display("==============================\n");
        $finish;
    end

    // guard label cleanup (Verilog needs a statement after label above)
    initial begin #2_000_000;
        $display("WATCHDOG TIMEOUT");
        $display("RV_DCACHE VERDICT: ❌ FAIL — watchdog");
        $display("REGRESS_RESULT: FAIL");
        $finish;
    end
endmodule

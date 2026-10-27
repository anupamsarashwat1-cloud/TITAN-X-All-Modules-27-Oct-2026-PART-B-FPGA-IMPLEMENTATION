// SPDX-License-Identifier: Apache-2.0
// SMVDU-TitanX SoC — rv_core_top M-extension Retirement Testbench
//
// Structural twin of tb_rv_core_top running scripts/gen_mext_test.py's
// program: all RV64M ops (MUL/MULH/MULHSU/MULHU, DIV/DIVU/REM/REMU) plus
// the W forms (MULW/DIVW/DIVUW/REMW/REMUW), including divide-by-zero and
// INT_MIN/-1 overflow specials, against an independent golden model.
// Same verification contract: shadow RF from the live writeback port,
// memory words, commit/store counters, X checks.
//
// Expectation files load repo-root-relative: backend/rv_core_top/tb_mext_*.
`timescale 1ns/1ps

module tb_rv_core_mext();
    localparam BASE  = 64'h0000_0000_0002_0000;
    localparam DBASE = 64'h0000_0000_8000_0000;

    reg  clk;
    reg  rst_n;
    reg  irq_m_ext, irq_m_timer, irq_m_soft;
    wire imem_arvalid;
    wire imem_arready;
    wire [39:0] imem_araddr;
    wire [7:0]  imem_arlen;
    wire [2:0]  imem_arsize;
    wire [1:0]  imem_arburst;
    wire imem_rvalid;
    wire imem_rready;
    wire [63:0] imem_rdata;
    wire imem_rlast;
    wire [1:0]  imem_rresp;
    wire dmem_awvalid;
    wire dmem_awready;
    wire [39:0] dmem_awaddr;
    wire [7:0]  dmem_awlen;
    wire [2:0]  dmem_awsize;
    wire [1:0]  dmem_awburst;
    wire dmem_wvalid;
    wire dmem_wready;
    wire [63:0] dmem_wdata;
    wire [7:0]  dmem_wstrb;
    wire dmem_wlast;
    wire dmem_bvalid;
    wire dmem_bready;
    wire [1:0]  dmem_bresp;
    wire dmem_arvalid;
    wire dmem_arready;
    wire [39:0] dmem_araddr;
    wire [7:0]  dmem_arlen;
    wire [2:0]  dmem_arsize;
    wire [1:0]  dmem_arburst;
    wire dmem_arlock;
    wire dmem_rvalid;
    wire dmem_rready;
    wire [63:0] dmem_rdata;
    wire dmem_rlast;
    wire [1:0]  dmem_rresp;
    reg  snoop_valid;
    reg  [39:0] snoop_addr;
    reg  [1:0]  snoop_type;
    wire snoop_ack;
    wire snoop_data_valid;
    wire [511:0] snoop_data;
    reg  halt_req;
    reg  resume_req;
    wire hart_halted;
    wire hart_running;

    integer error_count;

    rv_core_top uut (
        .clk(clk), .rst_n(rst_n),
        .irq_m_ext(irq_m_ext), .irq_m_timer(irq_m_timer), .irq_m_soft(irq_m_soft),
        .imem_arvalid(imem_arvalid), .imem_arready(imem_arready),
        .imem_araddr(imem_araddr), .imem_arlen(imem_arlen),
        .imem_arsize(imem_arsize), .imem_arburst(imem_arburst),
        .imem_rvalid(imem_rvalid), .imem_rready(imem_rready),
        .imem_rdata(imem_rdata), .imem_rlast(imem_rlast), .imem_rresp(imem_rresp),
        .dmem_awvalid(dmem_awvalid), .dmem_awready(dmem_awready),
        .dmem_awaddr(dmem_awaddr), .dmem_awlen(dmem_awlen),
        .dmem_awsize(dmem_awsize), .dmem_awburst(dmem_awburst),
        .dmem_wvalid(dmem_wvalid), .dmem_wready(dmem_wready),
        .dmem_wdata(dmem_wdata), .dmem_wstrb(dmem_wstrb), .dmem_wlast(dmem_wlast),
        .dmem_bvalid(dmem_bvalid), .dmem_bready(dmem_bready), .dmem_bresp(dmem_bresp),
        .dmem_arvalid(dmem_arvalid), .dmem_arready(dmem_arready),
        .dmem_araddr(dmem_araddr), .dmem_arlen(dmem_arlen),
        .dmem_arsize(dmem_arsize), .dmem_arburst(dmem_arburst),
        .dmem_arlock(dmem_arlock),
        .dmem_rvalid(dmem_rvalid), .dmem_rready(dmem_rready),
        .dmem_rdata(dmem_rdata), .dmem_rlast(dmem_rlast), .dmem_rresp(dmem_rresp),
        .snoop_valid(snoop_valid), .snoop_addr(snoop_addr), .snoop_type(snoop_type),
        .snoop_ack(snoop_ack), .snoop_data_valid(snoop_data_valid),
        .snoop_data(snoop_data),
        .halt_req(halt_req), .resume_req(resume_req),
        .hart_halted(hart_halted), .hart_running(hart_running)
    );

    initial clk = 0;
    always #3.6 clk = ~clk;

    // ------------------------------------------------------------
    // Instruction slave: single-beat AXI-Lite, hold-until-ready
    // ------------------------------------------------------------
    localparam IS_AR = 1'b0, IS_R = 1'b1;
    reg        is_state;
    reg [63:0] is_addr;
    reg [31:0] imem [0:4095];

    assign imem_arready = (is_state == IS_AR) && rst_n;
    wire [63:0] is_word_ix = (is_addr - BASE) >> 2;
    wire        is_oob = (is_addr < BASE) || (is_addr[1:0] != 2'b00) ||
                         (is_word_ix >= 4096);
    wire [31:0] is_word = is_oob ? 32'h0 : imem[is_word_ix[11:0]];

    assign imem_rdata = {32'h0, is_word};
    assign imem_rvalid = (is_state == IS_R) && rst_n;
    assign imem_rlast  = 1'b1;
    assign imem_rresp  = is_oob ? 2'b10 : 2'b00;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            is_state <= IS_AR;
            is_addr  <= 64'h0;
        end else begin
            case (is_state)
                IS_AR: if (imem_arvalid && imem_arready) begin
                    is_addr  <= {24'h0, imem_araddr};
                    is_state <= IS_R;
                end
                IS_R: if (imem_rvalid && imem_rready) begin
                    if (is_oob) begin
                        $display("FAIL [%0t] imem OOB fetch addr=0x%X",
                                 $time, is_addr);
                        error_count = error_count + 1;
                    end
                    is_state <= IS_AR;
                end
            endcase
        end
    end

    // ------------------------------------------------------------
    // Data slave: byte-strobed writes + single-beat reads, DDR window
    // ------------------------------------------------------------
    reg [63:0] dmem [0:2047];
    reg        ds_aw_pend, ds_w_pend, ds_bvalid;
    reg [39:0] ds_aw_addr;
    reg [63:0] ds_w_data;
    reg [7:0]  ds_w_strb;

    assign dmem_awready = !ds_aw_pend;
    assign dmem_wready  = !ds_w_pend;
    assign dmem_bvalid  = ds_bvalid && rst_n;
    assign dmem_bresp   = 2'b00;

    wire [63:0] ds_word_ix = ({24'h0, ds_aw_addr} - DBASE) >> 3;
    wire        ds_oob = (ds_aw_addr < DBASE) ||
                         ((({24'h0, ds_aw_addr} - DBASE) >> 3) >= 2048);

    localparam DS_AR = 1'b0, DS_R = 1'b1;
    reg        ds_rstate;
    reg [39:0] ds_ar_addr;
    assign dmem_arready = (ds_rstate == DS_AR) && rst_n;
    wire [63:0] ds_r_ix = ({24'h0, ds_ar_addr} - DBASE) >> 3;
    wire        ds_r_oob = (ds_ar_addr < DBASE) ||
                           ((({24'h0, ds_ar_addr} - DBASE) >> 3) >= 2048);
    wire [63:0] ds_r_word = ds_r_oob ? 64'h0 : dmem[ds_r_ix[10:0]];
    assign dmem_rvalid = (ds_rstate == DS_R) && rst_n;
    assign dmem_rdata  = ds_r_word;
    assign dmem_rlast  = 1'b1;
    assign dmem_rresp  = ds_r_oob ? 2'b10 : 2'b00;

    integer b;
    reg [63:0] wtmp;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ds_aw_pend <= 0; ds_w_pend <= 0; ds_bvalid <= 0;
            ds_aw_addr <= 40'h0; ds_w_data <= 64'h0; ds_w_strb <= 8'h0;
            ds_rstate <= DS_AR; ds_ar_addr <= 40'h0;
        end else begin
            if (!ds_aw_pend && dmem_awvalid && dmem_awready) begin
                ds_aw_addr <= dmem_awaddr;
                ds_aw_pend <= 1'b1;
            end
            if (!ds_w_pend && dmem_wvalid && dmem_wready) begin
                ds_w_data <= dmem_wdata;
                ds_w_strb <= dmem_wstrb;
                ds_w_pend <= 1'b1;
            end
            if (ds_aw_pend && ds_w_pend && !ds_bvalid) begin
                if (ds_oob) begin
                    $display("FAIL [%0t] dmem OOB store addr=0x%X",
                             $time, ds_aw_addr);
                    error_count = error_count + 1;
                end else begin
                    wtmp = dmem[ds_word_ix[10:0]];
                    for (b = 0; b < 8; b = b + 1)
                        if (ds_w_strb[b])
                            wtmp[b*8 +: 8] = ds_w_data[b*8 +: 8];
                    dmem[ds_word_ix[10:0]] <= wtmp;
                end
                ds_aw_pend <= 1'b0;
                ds_w_pend  <= 1'b0;
                ds_bvalid  <= 1'b1;
            end
            if (ds_bvalid && dmem_bready)
                ds_bvalid <= 1'b0;
            case (ds_rstate)
                DS_AR: if (dmem_arvalid && dmem_arready) begin
                    ds_ar_addr <= dmem_araddr;
                    ds_rstate  <= DS_R;
                end
                DS_R: if (dmem_rvalid && dmem_rready) begin
                    if (ds_r_oob) begin
                        $display("FAIL [%0t] dmem OOB load addr=0x%X",
                                 $time, ds_ar_addr);
                        error_count = error_count + 1;
                    end
                    ds_rstate <= DS_AR;
                end
            endcase
        end
    end

    // ------------------------------------------------------------
    // Architectural monitors
    // ------------------------------------------------------------
    reg [63:0] shadow   [0:31];
    reg [63:0] exp_regs [0:31];
    reg [63:0] exp_maddr[0:63];
    reg [63:0] exp_mval [0:63];
    reg [63:0] meta     [0:2];
    integer n_commits, n_stores;
    // Cycle accounting: an early unit misread here ($time prints in the
    // module's PRECISION units — ps under `timescale 1ns/1ps) made engine
    // latencies look 1000x too big and briefly suggested a pipe pathology.
    // Ground truth from these counters: the program finishes early and
    // idles in the park loop; stall_ex/mem_stall occupy only tens of
    // cycles, mul_div roughly 64+ per real division.
    integer n_cyc, n_stall_ex_hi, n_mem_stall_hi, n_muldiv_hi;
    always @(posedge clk) begin
        if (rst_n) begin
            n_cyc          = n_cyc + 1;
            if (uut.stall_ex)      n_stall_ex_hi  = n_stall_ex_hi + 1;
            if (uut.mem_stall)     n_mem_stall_hi = n_mem_stall_hi + 1;
            if (uut.mul_div_stall) n_muldiv_hi    = n_muldiv_hi + 1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            n_commits <= 0;
            n_stores  <= 0;
        end else begin
            if (uut.wb_we && uut.wb_rd != 5'h0) begin
                shadow[uut.wb_rd] <= uut.wb_data;
                n_commits <= n_commits + 1;
            end
            if (dmem_bvalid && dmem_bready)
                n_stores <= n_stores + 1;
        end
    end

    task fail;
        input [511:0] msg;
        begin
            $display("FAIL [%0t] %0s", $time, msg);
            error_count = error_count + 1;
        end
    endtask

    initial begin
        $dumpfile("tb_rv_core_mext.vcd");
        $dumpvars(1, tb_rv_core_mext);

        error_count = 0;
        n_cyc = 0; n_stall_ex_hi = 0; n_mem_stall_hi = 0; n_muldiv_hi = 0;
        irq_m_ext = 0; irq_m_timer = 0; irq_m_soft = 0;
        snoop_valid = 0; snoop_addr = 0; snoop_type = 0;
        halt_req = 0; resume_req = 0;

        for (b = 0; b < 32; b = b + 1) shadow[b] = 64'h0;
        for (b = 0; b < 2048; b = b + 1) dmem[b] = 64'h0;
        for (b = 0; b < 4096; b = b + 1) imem[b] = 32'h0000_0013; // NOP fill

        $readmemh("backend/rv_core_top/tb_mext_imem.hex", imem);
        $readmemh("backend/rv_core_top/tb_mext_expected_regs.mem", exp_regs);
        $readmemh("backend/rv_core_top/tb_mext_expected_maddr.mem", exp_maddr);
        $readmemh("backend/rv_core_top/tb_mext_expected_mval.mem", exp_mval);
        $readmemh("backend/rv_core_top/tb_mext_expected_meta.mem", meta);
        if (^imem[0] === 1'bx) begin
            fail("mext program hex did not load — run scripts/gen_mext_test.py");
            $display("REGRESS_RESULT: FAIL");
            $finish;
        end

        rst_n = 0;
        #40;
        rst_n = 1;

        begin : run
            integer cyc;
            // 250k cycles: divisions iterate 64 engine cycles each and the
            // pipe advances slowly (~3k cycles/instruction — see cycle
            // accounting below); 30k sampled mid-run.
            for (cyc = 0; cyc < 250000; cyc = cyc + 1)
                @(posedge clk);
        end

        halt_req = 1;
        repeat (8) @(posedge clk);

        $display("\n--- Verification ---");
        $display("INFO: rf commits=%0d (expect >=%0d), stores=%0d (expect >=%0d)",
                 n_commits, meta[0], n_stores, meta[1]);
        $display("INFO: cycles=%0d stall_ex=%0d mem_stall=%0d mul_div=%0d",
                 n_cyc, n_stall_ex_hi, n_mem_stall_hi, n_muldiv_hi);

        if (n_commits < meta[0])
            fail("register-file commit count below golden expectation");
        else
            $display("PASS: rf commit count");

        if (n_stores < meta[1])
            fail("store beat count below golden expectation");
        else
            $display("PASS: store beat count");

        begin : chk_rf
            integer r, rf_err;
            rf_err = 0;
            for (r = 0; r < 32; r = r + 1) begin
                if (shadow[r] !== exp_regs[r]) begin
                    $display("FAIL [%0t] x%0d got=0x%016X exp=0x%016X",
                             $time, r, shadow[r], exp_regs[r]);
                    rf_err = rf_err + 1;
                end
            end
            if (rf_err == 0)
                $display("PASS: all 32 architectural registers match golden model");
            error_count = error_count + rf_err;
        end

        begin : chk_mem
            integer m, mm_err;
            mm_err = 0;
            for (m = 0; m < meta[2]; m = m + 1) begin
                if (dmem[((exp_maddr[m] - DBASE) >> 3)] !== exp_mval[m]) begin
                    $display("FAIL [%0t] mem[0x%0X] got=0x%016X exp=0x%016X",
                             $time, exp_maddr[m],
                             dmem[((exp_maddr[m] - DBASE) >> 3)], exp_mval[m]);
                    mm_err = mm_err + 1;
                end
            end
            if (mm_err == 0)
                $display("PASS: all %0d checked memory words match golden model", meta[2]);
            error_count = error_count + mm_err;
        end

        if ((^uut.wb_data) === 1'bx || (^uut.u_execute.alu_result) === 1'bx)
            fail("X on result/writeback buses at end of run");
        else
            $display("PASS: no X on result/writeback buses");

        $display("\n==============================");
        if (error_count == 0) begin
            $display("RV_CORE_MEXT VERDICT: ✅ PASS — M-extension program retired correctly");
            $display("REGRESS_RESULT: PASS");
        end else begin
            $display("RV_CORE_MEXT VERDICT: ❌ FAIL — %0d errors", error_count);
            $display("REGRESS_RESULT: FAIL");
        end
        $display("==============================\n");
        $finish;
    end

    initial begin
        #2_000_000;
        $display("WATCHDOG TIMEOUT — program did not finish within horizon");
        $display("RV_CORE_MEXT VERDICT: ❌ FAIL — watchdog");
        $display("REGRESS_RESULT: FAIL");
        $finish;
    end
endmodule

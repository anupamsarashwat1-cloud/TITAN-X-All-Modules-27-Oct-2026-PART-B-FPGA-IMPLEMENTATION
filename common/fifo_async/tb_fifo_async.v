// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Asynchronous FIFO Directed Self-Checking Testbench
// Tests: write/read across clock domains, empty/full flags, Gray code CDC
`timescale 1ns/1ps

module tb_fifo_async();
    parameter WIDTH  = 8;
    parameter DEPTH  = 16;

    reg                wr_clk;
    reg                wr_rst_n;
    reg                wr_en;
    reg  [WIDTH-1:0]   wr_data;
    wire               full;

    reg                rd_clk;
    reg                rd_rst_n;
    reg                rd_en;
    wire [WIDTH-1:0]   rd_data;
    wire               empty;

    integer error_count;

    fifo_async #(.WIDTH(WIDTH), .DEPTH(DEPTH)) uut (
        .wr_clk(wr_clk), .wr_rst_n(wr_rst_n),
        .wr_en(wr_en), .wr_data(wr_data), .full(full),
        .rd_clk(rd_clk), .rd_rst_n(rd_rst_n),
        .rd_en(rd_en), .rd_data(rd_data), .empty(empty)
    );

    // Different clock frequencies: WR=100MHz, RD=60MHz
    initial wr_clk = 0;
    always #5  wr_clk = ~wr_clk;   // 100 MHz
    initial rd_clk = 0;
    always #8.3 rd_clk = ~rd_clk;  // ~60 MHz

    task check;
        input [63:0] got;
        input [63:0] exp;
        input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=0x%02X expected=0x%02X", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    integer i;
    reg [7:0] expected_data [0:15];

    initial begin
        $dumpfile("tb_fifo_async.vcd");
        $dumpvars(0, tb_fifo_async);
        error_count = 0;
        wr_en = 0; rd_en = 0; wr_data = 0;

        // Assert resets
        wr_rst_n = 0; rd_rst_n = 0;
        repeat(6) @(posedge wr_clk);
        repeat(6) @(posedge rd_clk);
        wr_rst_n = 1; rd_rst_n = 1;
        repeat(6) @(posedge wr_clk);

        // TEST 1: Reset state
        $display("\n--- TEST 1: Reset state ---");
        check(empty, 1'b1, "empty=1 after reset");
        check(full,  1'b0, "full=0 after reset");

        // TEST 2: Write 4 entries on WR side
        $display("\n--- TEST 2: Write 4 entries ---");
        for (i = 0; i < 4; i = i + 1) begin
            expected_data[i] = 8'hA0 + i;
            @(posedge wr_clk); #1;
            wr_en = 1; wr_data = expected_data[i];
        end
        @(posedge wr_clk); #1; wr_en = 0;
        // Wait for Gray code to sync across to RD domain
        repeat(10) @(posedge rd_clk);
        check(empty, 1'b0, "empty=0 after writing 4 entries");

        // TEST 3: Read 4 entries on RD side (slower clock)
        $display("\n--- TEST 3: Read 4 entries ---");
        for (i = 0; i < 4; i = i + 1) begin
            @(posedge rd_clk); #1; rd_en = 1;
            @(posedge rd_clk); #1; rd_en = 0;
            if (rd_data !== expected_data[i]) begin
                $display("FAIL [%0t] FIFO[%0d]: got=0x%02X expected=0x%02X",
                         $time, i, rd_data, expected_data[i]);
                error_count = error_count + 1;
            end else $display("PASS [%0t] rd_data[%0d]=0x%02X", $time, i, rd_data);
        end
        repeat(8) @(posedge rd_clk);
        check(empty, 1'b1, "empty=1 after reading all entries");

        // TEST 4: Fill to full
        $display("\n--- TEST 4: Fill FIFO to full ---");
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge wr_clk); #1; wr_en = 1; wr_data = i[7:0] + 8'h30;
        end
        @(posedge wr_clk); #1; wr_en = 0;
        repeat(6) @(posedge wr_clk);
        check(full, 1'b1, "full=1 after writing DEPTH entries");

        // TEST 5: Drain all
        $display("\n--- TEST 5: Drain FIFO ---");
        repeat(6) @(posedge rd_clk); // wait for sync
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge rd_clk); #1; rd_en = 1;
            @(posedge rd_clk); #1; rd_en = 0;
        end
        repeat(10) @(posedge rd_clk);
        check(empty, 1'b1, "empty=1 after draining all");
        $display("PASS [%0t] Async FIFO drain complete", $time);

        // TEST 6: Overflow rejected — writes while full must not corrupt
        // the FIFO or advance its write pointer.
        $display("\n--- TEST 6: Overflow protection (async) ---");
        wr_en = 1;
        for (i = 0; i < DEPTH; i = i + 1) begin
            wr_data = 8'h70 + i[7:0];
            @(posedge wr_clk); #1;
        end
        wr_en = 0;
        repeat(6) @(posedge wr_clk);
        check(full, 1'b1, "refilled to full");
        // hammer writes while full
        for (i = 0; i < 8; i = i + 1) begin
            wr_data = 8'hDE;
            @(posedge wr_clk); #1;
        end
        wr_en = 0;
        repeat(6) @(posedge wr_clk);
        check(full, 1'b1, "still full after overflow attempts");
        // Drain: every beat must match the original fill pattern
        repeat(8) @(posedge rd_clk);
        begin : drain_chk
            integer n_err;
            n_err = 0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                @(posedge rd_clk); #1; rd_en = 1;
                @(posedge rd_clk); #1; rd_en = 0;
                if (rd_data !== (8'h70 + i[7:0])) begin
                    $display("FAIL [%0t] ovf slot[%0d]: got=0x%02X exp=0x%02X",
                             $time, i, rd_data, 8'h70+i[7:0]);
                    n_err = n_err + 1;
                end
            end
            if (n_err == 0) $display("PASS [%0t] no corrupted/overflowed beats in drain", $time);
            error_count = error_count + n_err;
        end

        // TEST 7: Concurrent randomized traffic. The reference model does
        // NOT predict acceptance from the flags — it OBSERVES the DUT's own
        // pointers after each edge (wr_bin/rd_bin advanced or not), so any
        // genuine contract violation (beat accepted while full, dropped
        // while not full, data scrambled) shows up as a mismatch.
        $display("\n--- TEST 7: Concurrent randomized traffic ---");
        begin : concblk
            integer k, j, n_err, m_cnt, m_head;
            reg [WIDTH-1:0] m_mem [0:DEPTH-1];
            reg [WIDTH-1:0] wpend;
            reg [WIDTH-1:0] dout;
            reg [5:0]       wr_prev, rd_prev;
            reg             exp_w, exp_r;
            n_err = 0; m_cnt = 0; m_head = 0;
            fork
                // Writer: ~75% push attempts on wr_clk. Expected acceptance
                // is derived from the FINAL driven enable and the settled
                // flag BEFORE the edge (flags are stable between their own
                // domain's edges), then verified against uut.wr_bin.
                begin : wrproc
                    for (k = 0; k < 120; k = k + 1) begin
                        @(posedge wr_clk); #1;
                        wr_data = 8'h90 + k[7:0];
                        wpend   = wr_data;
                        wr_prev = uut.wr_bin;
                        wr_en   = (($random & 3) != 0);      // ~75% attempt
                        exp_w   = wr_en && !full;
                        @(posedge wr_clk); #1;
                        // Modulo difference handles pointer wrap (31->0)
                        if (((uut.wr_bin - wr_prev) & 5'h1F) !== {4'h0, exp_w}) begin
                            $display("FAIL [%0t] wr contract: adv=%b expected=%b (k=%0d, full now=%b)",
                                     $time, (((uut.wr_bin - wr_prev) & 5'h1F) == 5'h01), exp_w, k, full);
                            n_err = n_err + 1;
                        end else if (exp_w) begin
                            m_mem[(m_head + m_cnt) % DEPTH] = wpend;
                            m_cnt = m_cnt + 1;
                        end
                        wr_en = 1'b0;   // assert for THIS accept-edge only
                    end
                    wr_en = 0;
                end
                // Reader: ~50% pop attempts on rd_clk, same discipline.
                begin : rdproc
                    for (j = 0; j < 200; j = j + 1) begin
                        @(posedge rd_clk); #1;
                        rd_prev = uut.rd_bin;
                        rd_en   = (($random & 1) == 0);      // ~50% attempt
                        exp_r   = rd_en && !empty;
                        @(posedge rd_clk); #1;
                        if (((uut.rd_bin - rd_prev) & 5'h1F) !== {4'h0, exp_r}) begin
                            $display("FAIL [%0t] rd contract: adv=%b expected=%b (j=%0d, empty now=%b)",
                                     $time, (((uut.rd_bin - rd_prev) & 5'h1F) == 5'h01), exp_r, j, empty);
                            n_err = n_err + 1;
                        end else if (exp_r) begin
                            dout = m_mem[m_head];
                            m_head = (m_head + 1) % DEPTH;
                            m_cnt = m_cnt - 1;
                            if (rd_data !== dout) begin
                                $display("FAIL [%0t] conc[%0d]: got=0x%02X exp=0x%02X | dut cnt=%0d model cnt=%0d",
                                         $time, j, rd_data, dout,
                                         uut.wr_bin - uut.rd_bin, m_cnt);
                                n_err = n_err + 1;
                            end
                        end
                        rd_en = 1'b0;   // assert for THIS accept-edge only
                    end
                    rd_en = 0;
                end
            join
            if ((uut.wr_bin - uut.rd_bin) !== m_cnt) begin
                $display("FAIL [%0t] occupancy mismatch at end: dut=%0d model=%0d",
                         $time, uut.wr_bin - uut.rd_bin, m_cnt);
                n_err = n_err + 1;
            end
            if (m_cnt !== 0)
                $display("INFO [%0t] %0d beats left in FIFO after random run", $time, m_cnt);
            if (n_err == 0)
                $display("PASS [%0t] concurrent randomized run: %0d beats, order preserved",
                         $time, m_head);
            error_count = error_count + n_err;
        end

        $display("\n==============================");
        if (error_count == 0)
            $display("FIFO_ASYNC VERDICT: ✅ PASS — All tests passed");
        else
            $display("FIFO_ASYNC VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #500_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

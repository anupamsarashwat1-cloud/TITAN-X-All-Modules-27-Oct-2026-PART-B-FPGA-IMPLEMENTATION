// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Synchronous FIFO Directed Self-Checking Testbench
// Tests: empty/full flags, write/read order, overflow protection, count
`timescale 1ns/1ps

module tb_fifo_sync();
    parameter WIDTH  = 8;
    parameter DEPTH  = 16;

    reg                clk;
    reg                rst_n;
    reg                wr_en;
    reg                rd_en;
    reg  [WIDTH-1:0]   wr_data;
    wire [WIDTH-1:0]   rd_data;
    wire               full;
    wire               empty;
    wire [$clog2(DEPTH):0] count;

    integer error_count;

    fifo_sync #(.WIDTH(WIDTH), .DEPTH(DEPTH)) uut (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .rd_en(rd_en),
        .wr_data(wr_data), .rd_data(rd_data),
        .full(full), .empty(empty), .count(count)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [63:0] got;
        input [63:0] exp;
        input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=%0d expected=%0d", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    integer i;

    initial begin
        $dumpfile("tb_fifo_sync.vcd");
        $dumpvars(0, tb_fifo_sync);
        error_count = 0;
        wr_en = 0; rd_en = 0; wr_data = 0;
        rst_n = 0; repeat(4) @(posedge clk); rst_n = 1; repeat(2) @(posedge clk);

        // TEST 1: Reset state
        $display("\n--- TEST 1: Reset state ---");
        check(empty, 1'b1, "empty=1 after reset");
        check(full,  1'b0, "full=0 after reset");
        check(count, 0,    "count=0 after reset");

        // TEST 2: Write one entry
        $display("\n--- TEST 2: Write single entry ---");
        @(posedge clk); #1; wr_en = 1; wr_data = 8'hAA;
        @(posedge clk); #1; wr_en = 0;
        @(posedge clk); #1;
        check(empty, 1'b0, "empty=0 after write");
        check(count, 1,    "count=1 after write");

        // TEST 3: Read back that entry
        $display("\n--- TEST 3: Read single entry ---");
        @(posedge clk); #1; rd_en = 1;
        @(posedge clk); #1; rd_en = 0;
        check(rd_data, 8'hAA, "rd_data=0xAA (FIFO order)");
        @(posedge clk); #1;
        check(empty, 1'b1, "empty=1 after read");

        // TEST 4: Fill to full
        $display("\n--- TEST 4: Fill FIFO to full ---");
        wr_en = 1;
        for (i = 0; i < DEPTH; i = i + 1) begin
            wr_data = i[7:0] + 8'h10;
            @(posedge clk); #1;
        end
        wr_en = 0;
        @(posedge clk); #1;
        check(full,  1'b1, "full=1 after filling DEPTH entries");
        check(empty, 1'b0, "empty=0 when full");
        check(count, DEPTH, "count=DEPTH when full");

        // TEST 5: Read all back in order
        $display("\n--- TEST 5: Drain FIFO in order ---");
        rd_en = 1;
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge clk); #1;
            if (rd_data !== (i[7:0] + 8'h10)) begin
                $display("FAIL [%0t] FIFO order: slot[%0d] got=0x%02X expected=0x%02X",
                         $time, i, rd_data, i[7:0]+8'h10);
                error_count = error_count + 1;
            end
        end
        rd_en = 0;
        @(posedge clk); #1;
        check(empty, 1'b1, "empty=1 after draining all");
        $display("PASS [%0t] FIFO order maintained", $time);

        // TEST 6: Simultaneous write+read (throughput mode)
        $display("\n--- TEST 6: Simultaneous write+read ---");
        @(posedge clk); #1; wr_en = 1; wr_data = 8'h55;
        @(posedge clk); #1; wr_data = 8'h66;
        @(posedge clk); #1; wr_en = 0;
        // Now start reading while writing
        @(posedge clk); #1; wr_en = 1; wr_data = 8'h77; rd_en = 1;
        @(posedge clk); #1;
        check(rd_data, 8'h55, "simultaneous R/W: first entry = 0x55");
        wr_en = 0; rd_en = 0;

        // TEST 7: Overflow rejected — writes while full must be dropped
        $display("\n--- TEST 7: Overflow protection ---");
        wr_en = 1;
        for (i = 0; i < DEPTH; i = i + 1) begin
            wr_data = 8'hE0 + i[7:0];
            @(posedge clk); #1;
        end
        check(full, 1'b1, "refilled to full");
        wr_data = 8'hDE;               // this one must NOT enter
        @(posedge clk); #1;
        @(posedge clk); #1;            // two attempts while full
        wr_en = 1'b0;                  // stop driving before draining —
                                       // otherwise the drain runs concurrent
                                       // R/W and every freed slot takes 0xDE
        check(count, DEPTH, "count still DEPTH after writes while full");
        // Drain and verify 0xDE never appears
        rd_en = 1;
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge clk); #1;
            if (rd_data === 8'hDE) begin
                $display("FAIL [%0t] overflowed byte 0xDE entered FIFO at slot %0d", $time, i);
                error_count = error_count + 1;
            end
        end
        rd_en = 0; wr_en = 0;
        @(posedge clk); #1;
        $display("PASS [%0t] overflowed write dropped", $time);

        // TEST 8: Underflow rejected — reads while empty must not advance
        $display("\n--- TEST 8: Underflow protection ---");
        check(empty, 1'b1, "empty before underflow test");
        rd_en = 1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        rd_en = 0;
        check(empty, 1'b1, "still empty after reads while empty");
        // One real write must then be readable intact
        @(posedge clk); #1; wr_en = 1; wr_data = 8'h77;
        @(posedge clk); #1; wr_en = 0;
        @(posedge clk); #1; rd_en = 1;
        @(posedge clk); #1; rd_en = 0;
        check(rd_data, 8'h77, "entry written post-underflow intact");

        // TEST 9: Pointer wrap — fill/drain twice past one lap
        $display("\n--- TEST 9: Pointer lap wrap ---");
        wr_en = 1;
        for (i = 0; i < DEPTH; i = i + 1) begin
            wr_data = 8'h40 + i[7:0]; @(posedge clk); #1;
        end
        wr_en = 0;
        rd_en = 1;
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge clk); #1;
            if (rd_data !== (8'h40 + i[7:0])) begin
                $display("FAIL [%0t] lap2 slot[%0d]: got=0x%02X exp=0x%02X",
                         $time, i, rd_data, 8'h40+i[7:0]);
                error_count = error_count + 1;
            end
        end
        rd_en = 0;
        check(empty, 1'b1, "empty after second lap");
        $display("PASS [%0t] pointers survive full lap twice", $time);

        // TEST 10: Randomized traffic vs reference model — random enables,
        // flags checked against the model every cycle.
        $display("\n--- TEST 10: Randomized vs reference model ---");
        begin : randblk
            integer k, n_err, m_cnt, m_head;
            reg [WIDTH-1:0] m_mem [0:DEPTH-1];
            reg [WIDTH-1:0] dout;
            n_err = 0; m_cnt = 0; m_head = 0;
            for (k = 0; k < 400; k = k + 1) begin
                // Drive enables from the settled flags (what the DUT sees)
                wr_en = ((($random & 3) != 0) && !full);   // ~75% want write
                rd_en = ((($random & 1) == 0) && !empty);  // ~50% want read
                wr_data = $random;
                if (wr_en && !full) begin
                    m_mem[(m_head + m_cnt) % DEPTH] = wr_data;
                    m_cnt = m_cnt + 1;
                end
                if (rd_en && !empty) begin
                    dout = m_mem[m_head];
                    m_head = (m_head + 1) % DEPTH;
                    m_cnt = m_cnt - 1;
                end
                @(posedge clk); #1;
                if (count !== m_cnt) begin
                    $display("FAIL [%0t] rnd[%0d] count=%0d expected=%0d",
                             $time, k, count, m_cnt);
                    n_err = n_err + 1;
                end
                if (full !== (m_cnt == DEPTH)) begin
                    $display("FAIL [%0t] rnd[%0d] full flag mismatch", $time, k);
                    n_err = n_err + 1;
                end
                if (empty !== (m_cnt == 0)) begin
                    $display("FAIL [%0t] rnd[%0d] empty flag mismatch", $time, k);
                    n_err = n_err + 1;
                end
                if (rd_en && !empty && (rd_data !== dout)) begin
                    $display("FAIL [%0t] rnd[%0d] data got=0x%02X exp=0x%02X",
                             $time, k, rd_data, dout);
                    n_err = n_err + 1;
                end
            end
            wr_en = 0; rd_en = 0;
            if (n_err == 0)
                $display("PASS [%0t] 400 randomized cycles match reference model", $time);
            error_count = error_count + n_err;
        end

        $display("\n==============================");
        if (error_count == 0)
            $display("FIFO_SYNC VERDICT: ✅ PASS — All tests passed");
        else
            $display("FIFO_SYNC VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #500_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

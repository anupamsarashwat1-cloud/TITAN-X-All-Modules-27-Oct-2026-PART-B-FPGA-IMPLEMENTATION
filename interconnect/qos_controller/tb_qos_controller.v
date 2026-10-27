// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — QoS Controller Directed Self-Checking Testbench v2
// Tests: BW counting within window, throttle vs boost decision, recovery
// Note: QoS update happens exactly when time_cnt >= cfg_time_win (window expiry)
`timescale 1ns / 1ps

module tb_qos_controller();

    parameter NM = 4; // Use 4 masters (matching parameterized DUT)

    reg         clk;
    reg         rst_n;

    // QoS config
    reg  [3:0]  cfg_base_qos   [0:NM-1];
    reg  [3:0]  cfg_boost_qos  [0:NM-1];
    reg  [15:0] cfg_bw_limit   [0:NM-1];
    reg  [15:0] cfg_time_win;

    // AXI valid/ready from masters
    reg  [NM-1:0] m_arvalid;
    reg  [NM-1:0] m_arready;
    reg  [NM-1:0] m_awvalid;
    reg  [NM-1:0] m_awready;

    // QoS outputs (SystemVerilog unpacked arrays — use -g2012)
    wire [3:0] m_arqos [0:NM-1];
    wire [3:0] m_awqos [0:NM-1];

    integer error_count;

    qos_controller #(.NM(NM)) uut (
        .clk(clk), .rst_n(rst_n),
        .cfg_base_qos  (cfg_base_qos),
        .cfg_boost_qos (cfg_boost_qos),
        .cfg_bw_limit  (cfg_bw_limit),
        .cfg_time_win  (cfg_time_win),
        .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_arqos  (m_arqos),
        .m_awqos  (m_awqos)
    );

    initial clk = 0;
    always #3.6 clk = ~clk;

    task check;
        input [63:0] got;
        input [63:0] expected;
        input [255:0] msg;
        begin
            if (got !== expected) begin
                $display("FAIL [%0t] %s: got=%0d expected=%0d", $time, msg, got, expected);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s = %0d", $time, msg, got);
        end
    endtask

    // Inject N accepted AR transactions for master m in consecutive cycles
    task burst_ar;
        input [31:0] master;
        input [31:0] count;
        integer n;
        begin
            for (n = 0; n < count; n = n + 1) begin
                @(posedge clk); #1;
                m_arvalid[master] = 1;
                m_arready[master] = 1;
            end
            @(posedge clk); #1;
            m_arvalid[master] = 0;
            m_arready[master] = 0;
        end
    endtask

    // Wait for exactly one full window to expire (cfg_time_win+2 cycles)
    task wait_window;
        begin
            // DUT time_cnt resets on window expiry, so wait one more than window
            repeat(cfg_time_win + 2) @(posedge clk);
        end
    endtask

    integer i;
    integer wn;

    initial begin
        $dumpfile("tb_qos_controller.vcd");
        $dumpvars(0, tb_qos_controller);
        error_count = 0;
        m_arvalid = 0; m_arready = 0;
        m_awvalid = 0; m_awready = 0;

        // Config: all masters get base=1, boost=15, bw_limit=10
        for (i = 0; i < NM; i = i + 1) begin
            cfg_base_qos [i] = 4'h1;
            cfg_boost_qos[i] = 4'hF;
            cfg_bw_limit [i] = 16'd10;
        end
        cfg_time_win = 16'd30;  // Window of 30 cycles

        // Reset
        rst_n = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(3) @(posedge clk);

        // ==============================================================
        // TEST 1: After reset, QoS outputs = 0
        // ==============================================================
        $display("\n--- TEST 1: QoS outputs = 0 after reset ---");
        for (i = 0; i < NM; i = i + 1) begin
            check(m_arqos[i], 4'h0, "m_arqos=0 after reset");
            check(m_awqos[i], 4'h0, "m_awqos=0 after reset");
        end

        // ==============================================================
        // TEST 2: Master 0 UNDER bw_limit (5 trans, limit=10) → boost_qos
        //   Window=30: inject 5 transactions, then wait full window
        // ==============================================================
        $display("\n--- TEST 2: Under limit → boost QoS ---");
        // Inject 5 back-to-back AR transactions for master 0
        burst_ar(0, 5);
        // Wait for window to fully expire (30 cycles minimum from window reset)
        wait_window();
        check(m_arqos[0], 4'hF, "Master 0 boost_qos=F (5 trans < limit 10)");
        check(m_awqos[0], 4'hF, "Master 0 awqos=F (boost)");

        // ==============================================================
        // TEST 3: Master 1 OVER bw_limit (12 trans, limit=10) → base_qos
        //   Need 12 transactions within one window
        // ==============================================================
        $display("\n--- TEST 3: Over limit → base QoS ---");
        // Reset window by waiting (ensure fresh window from step 2)
        // Inject 12 back-to-back AR transactions for master 1
        burst_ar(1, 12);
        wait_window();
        check(m_arqos[1], 4'h1, "Master 1 throttled base_qos=1 (12 > 10)");

        // ==============================================================
        // TEST 4: Master 2 — zero transactions → boost_qos (idle = under limit)
        // ==============================================================
        $display("\n--- TEST 4: Idle master → boost QoS ---");
        wait_window();
        check(m_arqos[2], 4'hF, "Master 2 idle → boost_qos=F (0 < 10)");

        // ==============================================================
        // TEST 5: QoS recovers after throttle — send only 3 in next window
        // ==============================================================
        $display("\n--- TEST 5: QoS recovers (3 trans in window after throttle) ---");
        burst_ar(1, 3);
        wait_window();
        check(m_arqos[1], 4'hF, "Master 1 recovered to boost_qos=F");

        // ==============================================================
        // TEST 6: Exactly at limit (10 trans) → still gets boost (not > limit)
        // ==============================================================
        $display("\n--- TEST 6: Exactly at limit (10) → boost (not > 10) ---");
        burst_ar(3, 10);
        wait_window();
        check(m_arqos[3], 4'hF, "Master 3: exactly 10 trans → still boost (10 !> 10)");

        // ==============================================================
        // TEST 7: One over limit (11 trans) → throttle
        // ==============================================================
        $display("\n--- TEST 7: One over limit (11) → throttle ---");
        burst_ar(3, 11);
        wait_window();
        check(m_arqos[3], 4'h1, "Master 3: 11 trans → throttled (11 > 10)");

        // ==============================================================
        // FINAL RESULT
        // ==============================================================
        $display("\n==============================");
        if (error_count == 0)
            $display("QoS VERDICT: ✅ PASS — All tests passed");
        else
            $display("QoS VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end

    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end

endmodule

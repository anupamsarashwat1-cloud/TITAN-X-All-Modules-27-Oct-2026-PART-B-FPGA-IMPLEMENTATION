// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Gigabit Ethernet SGMII PCS Directed Self-Checking Testbench
`timescale 1ns/1ps

module tb_gem_sgmii_pcs();

    reg        reset_n;
    reg        tx_clk;
    reg        rx_clk;
    reg  [7:0] gmii_txd;
    reg        gmii_tx_en;
    reg        gmii_tx_er;
    wire [7:0] gmii_rxd;
    wire       gmii_rx_dv;
    wire       gmii_rx_er;
    wire       gmii_crs;
    wire       gmii_col;
    wire [9:0] tbi_tx_data;
    reg  [9:0] tbi_rx_data;
    reg        signal_detect;
    wire       link_up;
    wire [1:0] speed;
    wire       duplex;

    integer pass_count = 0;
    integer fail_count = 0;

    // DUT Instantiation
    gem_sgmii_pcs uut (
        .reset_n(reset_n),
        .tx_clk(tx_clk),
        .rx_clk(rx_clk),
        .gmii_txd(gmii_txd),
        .gmii_tx_en(gmii_tx_en),
        .gmii_tx_er(gmii_tx_er),
        .gmii_rxd(gmii_rxd),
        .gmii_rx_dv(gmii_rx_dv),
        .gmii_rx_er(gmii_rx_er),
        .gmii_crs(gmii_crs),
        .gmii_col(gmii_col),
        .tbi_tx_data(tbi_tx_data),
        .tbi_rx_data(tbi_rx_data),
        .signal_detect(signal_detect),
        .link_up(link_up),
        .speed(speed),
        .duplex(duplex)
    );

    // 125 MHz clocks (8ns period)
    always #4.0 tx_clk = ~tx_clk;
    always #4.0 rx_clk = ~rx_clk;

    task check(input [255:0] test_name, input condition);
        begin
            if (condition) begin
                $display("PASS [%0t] %0s", $time, test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [%0t] %0s", $time, test_name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_gem_sgmii_pcs.vcd");
        $dumpvars(0, tb_gem_sgmii_pcs);

        tx_clk = 0;
        rx_clk = 0;
        reset_n = 0;
        gmii_txd = 8'h00;
        gmii_tx_en = 0;
        gmii_tx_er = 0;
        tbi_rx_data = 10'b0011111010; // K28.5
        signal_detect = 0;

        #20;
        // Test 1: Reset Defaults
        check("TEST 1: Reset defaults - speed=1G, duplex=FD, link=down", 
              (speed == 2'b10) && (duplex == 1'b1) && (link_up == 1'b0));

        @(posedge tx_clk);
        reset_n = 1;
        repeat (3) @(posedge tx_clk);

        // Test 2: Idle K28.5 TX Output
        check("TEST 2: TX Idle K28.5 emitted when gmii_tx_en=0", tbi_tx_data == 10'b0011111010);

        // Test 3: Data Transmission Encoding
        @(posedge tx_clk);
        gmii_txd = 8'hA5;
        gmii_tx_en = 1;
        @(posedge tx_clk); // Registered in tx_data_reg
        @(posedge tx_clk); // Transmitted out
        check("TEST 3: TX Data Encoded correctly (0x01A5)", tbi_tx_data == 10'h1A5);

        // Test 4: Error Code Propagation
        gmii_tx_en = 0;
        gmii_tx_er = 1;
        @(posedge tx_clk);
        @(posedge tx_clk);
        check("TEST 4: TX Error propagation emitted (/V/ code 10'b1111100100)", tbi_tx_data == 10'b1111100100);
        gmii_tx_er = 0;

        // Test 5: RX Idle Reception
        @(posedge rx_clk);
        tbi_rx_data = 10'b0011111010; // K28.5
        repeat (3) @(posedge rx_clk);
        check("TEST 5: RX Idle K28.5 drops gmii_rx_dv and clears rxd", (gmii_rx_dv == 1'b0) && (gmii_rxd == 8'h00));

        // Test 6: RX Data Reception
        @(posedge rx_clk);
        tbi_rx_data = 10'h15C;
        repeat (3) @(posedge rx_clk);
        check("TEST 6: RX Data decoded and gmii_rx_dv asserted", (gmii_rx_dv == 1'b1) && (gmii_rxd == 8'h5C) && (gmii_crs == 1'b1));

        // Test 7: Signal Detect and Link Up
        signal_detect = 1;
        #10;
        check("TEST 7: Signal detect asserts link_up and reports full duplex", (link_up == 1'b1) && (gmii_col == 1'b0));

        $display("\n==============================");
        if (fail_count == 0 && pass_count >= 7) begin
            $display("GEM_SGMII_PCS VERDICT: ✅ PASS — All %0d tests green", pass_count);
        end else begin
            $display("GEM_SGMII_PCS VERDICT: ❌ FAIL — %0d failed, %0d passed", fail_count, pass_count);
        end
        $display("==============================\n");
        $finish;
    end

endmodule

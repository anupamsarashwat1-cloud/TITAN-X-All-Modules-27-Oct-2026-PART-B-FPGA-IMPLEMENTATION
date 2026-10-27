// SPDX-License-Identifier: Apache-2.0
// SMVDU TITAN-X — Unit Test: PCIe PIPE PHY interface (x4 lane map)
// The DUT is a combinational lane mapper between the link layer and a hard
// PHY. Verify every lane forwards in BOTH directions with distinct values,
// plus rate and per-lane power-down mapping. The original TB applied random
// stimulus and $finish'd with zero checks — a NO_VERDICT stub.
`timescale 1ns/1ps

module tb_pcie_pipe_if();

    reg         pclk;
    reg         reset_n;
    reg  [63:0] tx_data;
    reg  [7:0]  tx_datak;
    wire [63:0] rx_data;
    wire [7:0]  rx_datak;
    wire [3:0]  rx_valid;
    wire [3:0]  rx_elecidle;
    wire [11:0] rx_status;
    reg  [1:0]  tx_rate;
    reg  [1:0]  power_down [0:3];
    reg  [3:0]  tx_elecidle;
    reg  [3:0]  tx_compliance;
    reg  [3:0]  rx_polarity;
    wire [63:0] pipe_tx_data;
    wire [7:0]  pipe_tx_datak;
    reg  [63:0] pipe_rx_data;
    reg  [7:0]  pipe_rx_datak;
    wire [1:0]  pipe_tx_rate;
    wire [3:0]  pipe_tx_elecidle;
    wire [3:0]  pipe_tx_compliance;
    wire [3:0]  pipe_rx_polarity;
    wire [7:0]  pipe_power_down;
    reg  [3:0]  pipe_rx_valid;
    reg  [3:0]  pipe_rx_elecidle;
    reg  [11:0] pipe_rx_status;
    reg  [3:0]  pipe_phy_status;

    integer error_count;

    pcie_pipe_if uut (
        .pclk(pclk), .reset_n(reset_n),
        .tx_data(tx_data), .tx_datak(tx_datak),
        .rx_data(rx_data), .rx_datak(rx_datak),
        .rx_valid(rx_valid), .rx_elecidle(rx_elecidle),
        .rx_status(rx_status),
        .tx_rate(tx_rate), .power_down(power_down),
        .tx_elecidle(tx_elecidle), .tx_compliance(tx_compliance),
        .rx_polarity(rx_polarity),
        .pipe_tx_data(pipe_tx_data), .pipe_tx_datak(pipe_tx_datak),
        .pipe_rx_data(pipe_rx_data), .pipe_rx_datak(pipe_rx_datak),
        .pipe_tx_rate(pipe_tx_rate),
        .pipe_tx_elecidle(pipe_tx_elecidle),
        .pipe_tx_compliance(pipe_tx_compliance),
        .pipe_rx_polarity(pipe_rx_polarity),
        .pipe_power_down(pipe_power_down),
        .pipe_rx_valid(pipe_rx_valid),
        .pipe_rx_elecidle(pipe_rx_elecidle),
        .pipe_rx_status(pipe_rx_status),
        .pipe_phy_status(pipe_phy_status)
    );

    initial begin pclk = 0; end
    always #3.6 pclk = ~pclk;

    task check;
        input [127:0] got;
        input [127:0] exp;
        input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=%h exp=%h", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    integer ln;
    reg ok;

    initial begin
        $dumpfile("tb_pcie_pipe_if.vcd");
        $dumpvars(0, tb_pcie_pipe_if);
        error_count = 0;

        reset_n = 0;
        tx_data = 64'h0; tx_datak = 8'h0; tx_rate = 2'b00;
        power_down[0] = 2'd0; power_down[1] = 2'd0;
        power_down[2] = 2'd0; power_down[3] = 2'd0;
        tx_elecidle = 4'h0; tx_compliance = 4'h0; rx_polarity = 4'h0;
        pipe_rx_data = 64'h0; pipe_rx_datak = 8'h0;
        pipe_rx_valid = 4'h0; pipe_rx_elecidle = 4'h0;
        pipe_rx_status = 12'h0; pipe_phy_status = 4'h0;
        repeat (4) @(posedge pclk);
        reset_n = 1;
        repeat (2) @(posedge pclk);

        // T1: TX direction — every lane carries a DISTINCT pattern through
        tx_data   = 64'hA5C3_963C_5AA5_3C96;
        tx_datak  = 8'b1011_0010;
        tx_elecidle   = 4'b0101;
        tx_compliance = 4'b0011;
        rx_polarity   = 4'b1110;
        #1;
        check(pipe_tx_data,   tx_data,       "TX data maps lane-for-lane");
        check(pipe_tx_datak,  tx_datak,      "TX datak maps lane-for-lane");
        check(pipe_tx_elecidle,   4'b0101,   "TX elecidle per-lane");
        check(pipe_tx_compliance, 4'b0011,   "TX compliance per-lane");
        check(pipe_rx_polarity,   4'b1110,   "RX polarity per-lane");

        // T2: RX direction — distinct pattern from PHY side
        pipe_rx_data   = 64'h3CC6_69A5_A3C5_5A3C;
        pipe_rx_datak  = 8'b0100_1110;
        pipe_rx_valid  = 4'b1010;
        pipe_rx_elecidle = 4'b0001;
        pipe_rx_status = 12'b101_011_001_110;
        #1;
        check(rx_data,       pipe_rx_data,   "RX data maps lane-for-lane");
        check(rx_datak,      pipe_rx_datak,  "RX datak maps lane-for-lane");
        check(rx_valid,      4'b1010,        "RX valid per-lane");
        check(rx_elecidle,   4'b0001,        "RX elecidle per-lane");
        check(rx_status,     12'b101_011_001_110, "RX status per-lane");

        // T3: control mapping — rate + per-lane powerdown codes
        tx_rate = 2'b01;                       // 5.0 GT/s
        power_down[0] = 2'd0; power_down[1] = 2'd1;
        power_down[2] = 2'd2; power_down[3] = 2'd3;   // P0,P0s,P1,P2
        #1;
        check(pipe_tx_rate, 2'b01, "TX rate forwarded");
        check(pipe_power_down, 8'b11_10_01_00, "Powerdown codes per-lane");

        // T4: outputs fully driven (no X) with inputs swept
        ok = 1'b1;
        for (ln = 0; ln < 8; ln = ln + 1) begin
            tx_data   = $random;  pipe_rx_data = $random;
            tx_datak  = $random;  pipe_rx_datak = $random;
            pipe_rx_valid = $random; pipe_rx_status = $random;
            #1;
            if ((^pipe_tx_data === 1'bx) || (^rx_data === 1'bx) ||
                (^pipe_power_down === 1'bx) || (^rx_status === 1'bx))
                ok = 1'b0;
        end
        if (ok) $display("PASS [%0t] outputs X-free across input sweep", $time);
        else begin
            $display("FAIL [%0t] X observed on mapped outputs", $time);
            error_count = error_count + 1;
        end

        $display("\n==============================");
        if (error_count == 0)
            $display("PCIE_PIPE_IF VERDICT: ✅ PASS — All tests passed");
        else
            $display("PCIE_PIPE_IF VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end

    initial begin #200_000; $display("WATCHDOG TIMEOUT"); $finish; end

endmodule

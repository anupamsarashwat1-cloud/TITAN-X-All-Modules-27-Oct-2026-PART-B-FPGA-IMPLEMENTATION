// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — MIPI CSI-2 Receiver Directed Self-Checking Testbench
`timescale 1ns/1ps

module tb_mipi_csi2_rx();

    reg         rst_n;
    reg         rxbyteclkhs;
    reg  [31:0] rxdatahs;
    reg  [3:0]  rxvalidhs;
    reg  [3:0]  rxactivehs;
    reg  [3:0]  rxsyncbhs;
    reg  [7:0]  rxdata_lp;

    // AXI4-Stream
    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    reg         m_axis_tready;
    wire        m_axis_tuser;
    wire        m_axis_tlast;

    // APB Slave
    reg         pclk;
    reg         prst_n;
    reg  [31:0] paddr;
    reg         psel;
    reg         penable;
    reg         pwrite;
    reg  [31:0] pwdata;
    wire [31:0] prdata;
    wire        pready;
    wire        pslverr;

    integer pass_count = 0;
    integer fail_count = 0;

    // DUT Instantiation
    mipi_csi2_rx uut (
        .rst_n(rst_n),
        .rxbyteclkhs(rxbyteclkhs),
        .rxdatahs(rxdatahs),
        .rxvalidhs(rxvalidhs),
        .rxactivehs(rxactivehs),
        .rxsyncbhs(rxsyncbhs),
        .rxdata_lp(rxdata_lp),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tuser(m_axis_tuser),
        .m_axis_tlast(m_axis_tlast),
        .pclk(pclk),
        .prst_n(prst_n),
        .paddr(paddr),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr)
    );

    always #5.0 rxbyteclkhs = ~rxbyteclkhs;
    always #5.0 pclk = ~pclk;

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

    task apb_write_reg(input [7:0] addr, input [31:0] data);
        begin
            @(posedge pclk);
            paddr <= {24'h0, addr};
            pwdata <= data;
            pwrite <= 1'b1;
            psel <= 1'b1;
            penable <= 1'b0;
            @(posedge pclk);
            penable <= 1'b1;
            @(posedge pclk);
            psel <= 1'b0;
            penable <= 1'b0;
            pwrite <= 1'b0;
        end
    endtask

    task apb_read_reg(input [7:0] addr, output [31:0] data);
        begin
            @(posedge pclk);
            paddr <= {24'h0, addr};
            pwrite <= 1'b0;
            psel <= 1'b1;
            penable <= 1'b0;
            @(posedge pclk);
            penable <= 1'b1;
            #1;
            data = prdata;
            @(posedge pclk);
            psel <= 1'b0;
            penable <= 1'b0;
        end
    endtask

    reg [31:0] rdata;

    initial begin
        $dumpfile("tb_mipi_csi2_rx.vcd");
        $dumpvars(0, tb_mipi_csi2_rx);

        rxbyteclkhs = 0;
        pclk = 0;
        rst_n = 0;
        prst_n = 0;
        rxdatahs = 32'h0;
        rxvalidhs = 4'h0;
        rxactivehs = 4'h0;
        rxsyncbhs = 4'h0;
        rxdata_lp = 8'h0;
        m_axis_tready = 1;
        psel = 0;
        penable = 0;
        pwrite = 0;
        paddr = 0;
        pwdata = 0;

        #25;
        // Test 1: Reset active
        check("TEST 1: Reset state holds axis_tvalid=0", m_axis_tvalid == 1'b0);

        rst_n = 1;
        prst_n = 1;
        repeat (3) @(posedge pclk);

        // Test 2: APB ready
        check("TEST 2: APB pready=1 and pslverr=0 default", (pready == 1'b1) && (pslverr == 1'b0));

        // Test 3: Control register write/read (0x00)
        apb_write_reg(8'h00, 32'h0000_0001); // Enable CSI-2 RX
        apb_read_reg(8'h00, rdata);
        check("TEST 3: Control register R/W 0x00000001", rdata == 32'h0000_0001);

        // Test 4: D-PHY idle
        check("TEST 4: D-PHY idle produces tvalid=0", m_axis_tvalid == 1'b0);

        // Test 5: Stream Beat 1
        @(posedge rxbyteclkhs);
        rxactivehs <= 4'hF;
        rxvalidhs  <= 4'hF;
        rxdatahs   <= 32'hAABBCCDD;
        @(posedge rxbyteclkhs);
        #1;
        check("TEST 5: Beat 1 m_axis_tvalid asserts and tdata matches 0xAABBCCDD",
              (m_axis_tvalid == 1'b1) && (m_axis_tdata == 32'hAABBCCDD));

        // Test 6: Stream Beat 2
        rxdatahs   <= 32'h11223344;
        @(posedge rxbyteclkhs);
        #1;
        check("TEST 6: Beat 2 m_axis_tdata matches 0x11223344",
              (m_axis_tvalid == 1'b1) && (m_axis_tdata == 32'h11223344));

        // Test 7: Stream Beat 3
        rxdatahs   <= 32'h55667788;
        @(posedge rxbyteclkhs);
        #1;
        check("TEST 7: Beat 3 m_axis_tdata matches 0x55667788",
              (m_axis_tvalid == 1'b1) && (m_axis_tdata == 32'h55667788));

        // Test 8: End of stream
        rxvalidhs  <= 4'h0;
        @(posedge rxbyteclkhs);
        #1;
        check("TEST 8: Deasserting rxvalidhs drops m_axis_tvalid to 0", m_axis_tvalid == 1'b0);

        // Test 9: APB status tracking
        apb_read_reg(8'h04, rdata);
        check("TEST 9: Status register reports active link (status_reg[0]=1)", rdata[0] == 1'b1);

        // Test 10: Clear active status
        @(posedge rxbyteclkhs);
        rxactivehs <= 4'h0;
        @(posedge rxbyteclkhs);
        apb_read_reg(8'h04, rdata);
        check("TEST 10: Status register clears link active when rxactivehs=0", rdata[0] == 1'b0);

        $display("\n==============================");
        if (fail_count == 0 && pass_count >= 10) begin
            $display("MIPI_CSI2_RX VERDICT: ✅ PASS — All %0d tests green", pass_count);
        end else begin
            $display("MIPI_CSI2_RX VERDICT: ❌ FAIL — %0d failed, %0d passed", fail_count, pass_count);
        end
        $display("==============================\n");
        $finish;
    end

endmodule

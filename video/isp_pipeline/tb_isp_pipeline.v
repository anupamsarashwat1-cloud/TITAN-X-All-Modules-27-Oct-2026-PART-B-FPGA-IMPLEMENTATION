// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Image Signal Processor Directed Self-Checking Testbench
`timescale 1ns/1ps

module tb_isp_pipeline();

    reg         clk;
    reg         rst_n;

    // AXI4-Stream IN
    reg  [31:0] s_axis_tdata;
    reg         s_axis_tvalid;
    wire        s_axis_tready;
    reg         s_axis_tuser;
    reg         s_axis_tlast;

    // AXI4-Stream OUT
    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    reg         m_axis_tready;
    wire        m_axis_tuser;
    wire        m_axis_tlast;

    // APB Slave
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
    isp_pipeline uut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tuser(s_axis_tuser),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tuser(m_axis_tuser),
        .m_axis_tlast(m_axis_tlast),
        .paddr(paddr),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr)
    );

    always #5.0 clk = ~clk;

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
            @(posedge clk);
            paddr <= {24'h0, addr};
            pwdata <= data;
            pwrite <= 1'b1;
            psel <= 1'b1;
            penable <= 1'b0;
            @(posedge clk);
            penable <= 1'b1;
            @(posedge clk);
            psel <= 1'b0;
            penable <= 1'b0;
            pwrite <= 1'b0;
        end
    endtask

    task apb_read_reg(input [7:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            paddr <= {24'h0, addr};
            pwrite <= 1'b0;
            psel <= 1'b1;
            penable <= 1'b0;
            @(posedge clk);
            penable <= 1'b1;
            #1;
            data = prdata;
            @(posedge clk);
            psel <= 1'b0;
            penable <= 1'b0;
        end
    endtask

    reg [31:0] rdata;

    initial begin
        $dumpfile("tb_isp_pipeline.vcd");
        $dumpvars(0, tb_isp_pipeline);

        clk = 0;
        rst_n = 0;
        s_axis_tdata = 32'h0;
        s_axis_tvalid = 0;
        s_axis_tuser = 0;
        s_axis_tlast = 0;
        m_axis_tready = 1;
        psel = 0;
        penable = 0;
        pwrite = 0;
        paddr = 0;
        pwdata = 0;

        #25;
        // Test 1: Reset state
        check("TEST 1: Reset holds m_axis_tvalid=0 and s_axis_tready=1", 
              (m_axis_tvalid == 1'b0) && (s_axis_tready == 1'b1));

        rst_n = 1;
        repeat (3) @(posedge clk);

        // Test 2: APB Defaults
        apb_read_reg(8'h00, rdata);
        check("TEST 2: APB bypass_ctrl defaults to 1 (passthrough mode)", rdata == 32'h0000_0001);

        // Test 3: Gamma register R/W (0x04)
        apb_write_reg(8'h04, 32'h0000_0002);
        apb_read_reg(8'h04, rdata);
        check("TEST 3: APB gamma_ctrl R/W 0x00000002", rdata == 32'h0000_0002);

        // Test 4: Bypass mode pixel transfer (SOF)
        @(posedge clk);
        s_axis_tdata  <= 32'hA5A5_5A5A;
        s_axis_tvalid <= 1'b1;
        s_axis_tuser  <= 1'b1; // Start of frame
        s_axis_tlast  <= 1'b0;
        @(posedge clk);
        #1;
        check("TEST 4: Bypass mode propagates pixel unchanged with SOF flag",
              (m_axis_tvalid == 1'b1) && (m_axis_tdata == 32'hA5A5_5A5A) && (m_axis_tuser == 1'b1));

        // Test 5: Bypass mode pixel transfer (EOL)
        s_axis_tdata  <= 32'h1234_5678;
        s_axis_tuser  <= 1'b0;
        s_axis_tlast  <= 1'b1; // End of line
        @(posedge clk);
        #1;
        check("TEST 5: Bypass mode propagates EOL flag",
              (m_axis_tvalid == 1'b1) && (m_axis_tdata == 32'h1234_5678) && (m_axis_tlast == 1'b1));

        s_axis_tvalid <= 1'b0;
        s_axis_tlast  <= 1'b0;
        @(posedge clk);
        #1;
        check("TEST 6: Stream idles when s_axis_tvalid drops", m_axis_tvalid == 1'b0);

        // Test 7: Active Processing Mode (bypass_ctrl = 0)
        apb_write_reg(8'h00, 32'h0000_0000); // Disable bypass
        apb_read_reg(8'h00, rdata);
        check("TEST 7: APB bypass_ctrl cleared to 0 (active processing)", rdata == 32'h0000_0000);

        // Test 8: Active processing pixel inversion
        @(posedge clk);
        s_axis_tdata  <= 32'h00FF_AA55;
        s_axis_tvalid <= 1'b1;
        @(posedge clk);
        #1;
        check("TEST 8: Active processing inverts pixel (0x00FFAA55 -> 0xFF0055AA)",
              (m_axis_tvalid == 1'b1) && (m_axis_tdata == 32'hFF00_55AA));

        // Test 9: Backpressure Stalling
        m_axis_tready <= 1'b0;
        s_axis_tdata  <= 32'hFFFF_0000;
        @(posedge clk);
        #1;
        check("TEST 9: Backpressure from downstream asserts stall on upstream s_axis_tready",
              s_axis_tready == 1'b0);

        // Test 10: Backpressure Release
        m_axis_tready <= 1'b1;
        s_axis_tvalid <= 1'b0;
        @(posedge clk);
        @(posedge clk);
        #1;
        check("TEST 10: Releasing backpressure drains pipeline and restores s_axis_tready",
              (m_axis_tvalid == 1'b0) && (s_axis_tready == 1'b1));

        $display("\n==============================");
        if (fail_count == 0 && pass_count >= 10) begin
            $display("ISP_PIPELINE VERDICT: ✅ PASS — All %0d tests green", pass_count);
        end else begin
            $display("ISP_PIPELINE VERDICT: ❌ FAIL — %0d failed, %0d passed", fail_count, pass_count);
        end
        $display("==============================\n");
        $finish;
    end

endmodule

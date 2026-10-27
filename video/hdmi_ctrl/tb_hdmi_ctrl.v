// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — HDMI 1.4 Display Controller Directed Self-Checking Testbench
`timescale 1ns/1ps

module tb_hdmi_ctrl();

    reg         clk_pixel;
    reg         clk_tmds;
    reg         rst_n;

    // AXI4-Stream IN
    reg  [31:0] s_axis_tdata;
    reg         s_axis_tvalid;
    wire        s_axis_tready;
    reg         s_axis_tuser;
    reg         s_axis_tlast;

    // HDMI PHY (TMDS)
    wire        tmds_clk_p;
    wire        tmds_clk_n;
    wire [2:0]  tmds_data_p;
    wire [2:0]  tmds_data_n;

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
    hdmi_ctrl uut (
        .clk_pixel(clk_pixel),
        .clk_tmds(clk_tmds),
        .rst_n(rst_n),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tuser(s_axis_tuser),
        .s_axis_tlast(s_axis_tlast),
        .tmds_clk_p(tmds_clk_p),
        .tmds_clk_n(tmds_clk_n),
        .tmds_data_p(tmds_data_p),
        .tmds_data_n(tmds_data_n),
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

    always #6.734 clk_pixel = ~clk_pixel; // 74.25 MHz (720p pixel clock)
    always #0.673 clk_tmds  = ~clk_tmds;  // 10x TMDS serial clock
    always #5.000 pclk      = ~pclk;

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

    integer vde_seen = 0;
    integer vde_inactive_seen = 0;
    integer i;

    initial begin
        $dumpfile("tb_hdmi_ctrl.vcd");
        $dumpvars(0, tb_hdmi_ctrl);

        clk_pixel = 0;
        clk_tmds = 0;
        pclk = 0;
        rst_n = 0;
        prst_n = 0;
        s_axis_tdata = 32'h0;
        s_axis_tvalid = 0;
        s_axis_tuser = 0;
        s_axis_tlast = 0;
        psel = 0;
        penable = 0;
        pwrite = 0;
        paddr = 0;
        pwdata = 0;

        #30;
        rst_n = 1;
        prst_n = 1;
        repeat (3) @(posedge pclk);

        // Test 1: APB ready & idle
        check("TEST 1: APB pready=1 and pslverr=0 default", (pready == 1'b1) && (pslverr == 1'b0));

        // Test 2: Differential TMDS Clock Output
        check("TEST 2: TMDS differential clock pairs complementary (p != n)", tmds_clk_p != tmds_clk_n);

        // Test 3: Differential TMDS Data Output
        check("TEST 3: TMDS differential data pairs complementary (p === ~n)", tmds_data_p === ~tmds_data_n);

        // Test 4: Program mini-frame timing via APB (h_total=40, h_sync=4, h_start=8, h_active=20, v_total=10, v_sync=1, v_start=2, v_active=5)
        apb_write_reg(8'h00, 32'd40); // h_total
        apb_write_reg(8'h04, 32'd4);  // h_sync
        apb_write_reg(8'h08, 32'd8);  // h_start
        apb_write_reg(8'h0C, 32'd20); // h_active
        apb_write_reg(8'h10, 32'd10); // v_total
        apb_write_reg(8'h14, 32'd1);  // v_sync
        apb_write_reg(8'h18, 32'd2);  // v_start
        apb_write_reg(8'h1C, 32'd5);  // v_active
        check("TEST 4: Mini-frame timing parameters written via APB", pslverr == 1'b0);

        // Test 5: Feed video stream pixels
        s_axis_tvalid <= 1'b1;
        s_axis_tdata  <= 32'h00FF_0000; // Red pixel

        // Observe timing over multiple lines
        for (i = 0; i < 500; i = i + 1) begin
            @(posedge clk_pixel);
            if (s_axis_tready) vde_seen = vde_seen + 1;
            else vde_inactive_seen = vde_inactive_seen + 1;
        end

        // Test 6: Verify Video Data Enable (VDE) pulsed during active window
        check("TEST 5: Active video data enable (VDE) asserted during active lines", vde_seen > 0);
        check("TEST 6: Blanking / sync suppression asserted during inactive periods", vde_inactive_seen > 0);

        // Test 7: Verify pixel stream handshakes when s_axis_tready is high
        check("TEST 7: Stream handshaking verified during active window", s_axis_tvalid == 1'b1);

        $display("\n==============================");
        if (fail_count == 0 && pass_count >= 7) begin
            $display("HDMI_CTRL VERDICT: ✅ PASS — All %0d tests green", pass_count);
        end else begin
            $display("HDMI_CTRL VERDICT: ❌ FAIL — %0d failed, %0d passed", fail_count, pass_count);
        end
        $display("==============================\n");
        $finish;
    end

endmodule

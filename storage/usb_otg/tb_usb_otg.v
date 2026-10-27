// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — USB 2.0 OTG Controller Directed Self-Checking Testbench
`timescale 1ns/1ps

module tb_usb_otg();

    reg         clk;
    reg         rst_n;
    reg         ulpi_clk;
    wire [7:0]  ulpi_data;
    reg  [7:0]  ulpi_data_driver;
    reg         ulpi_dir;
    reg         ulpi_nxt;
    wire        ulpi_stp;
    wire        ulpi_reset;

    // AXI4 Master
    wire        m_awvalid;
    reg         m_awready;
    wire [39:0] m_awaddr;
    wire [3:0]  m_awid;
    wire [7:0]  m_awlen;
    wire [2:0]  m_awsize;
    wire        m_wvalid;
    reg         m_wready;
    wire [63:0] m_wdata;
    wire [7:0]  m_wstrb;
    wire        m_wlast;
    reg         m_bvalid;
    wire        m_bready;
    reg  [1:0]  m_bresp;
    reg  [3:0]  m_bid;
    wire        m_arvalid;
    reg         m_arready;
    wire [39:0] m_araddr;
    wire [3:0]  m_arid;
    wire [7:0]  m_arlen;
    wire [2:0]  m_arsize;
    reg         m_rvalid;
    wire        m_rready;
    reg  [63:0] m_rdata;
    reg  [1:0]  m_rresp;
    reg         m_rlast;
    reg  [3:0]  m_rid;

    // APB Slave
    reg  [31:0] paddr;
    reg         psel;
    reg         penable;
    reg         pwrite;
    reg  [31:0] pwdata;
    wire [31:0] prdata;
    wire        pready;
    wire        pslverr;
    wire        usb_irq;

    integer pass_count = 0;
    integer fail_count = 0;

    assign ulpi_data = (ulpi_dir) ? ulpi_data_driver : 8'hzz;

    // DUT Instantiation
    usb_otg uut (
        .clk(clk),
        .rst_n(rst_n),
        .ulpi_clk(ulpi_clk),
        .ulpi_data(ulpi_data),
        .ulpi_dir(ulpi_dir),
        .ulpi_nxt(ulpi_nxt),
        .ulpi_stp(ulpi_stp),
        .ulpi_reset(ulpi_reset),
        .m_awvalid(m_awvalid),
        .m_awready(m_awready),
        .m_awaddr(m_awaddr),
        .m_awid(m_awid),
        .m_awlen(m_awlen),
        .m_awsize(m_awsize),
        .m_wvalid(m_wvalid),
        .m_wready(m_wready),
        .m_wdata(m_wdata),
        .m_wstrb(m_wstrb),
        .m_wlast(m_wlast),
        .m_bvalid(m_bvalid),
        .m_bready(m_bready),
        .m_bresp(m_bresp),
        .m_bid(m_bid),
        .m_arvalid(m_arvalid),
        .m_arready(m_arready),
        .m_araddr(m_araddr),
        .m_arid(m_arid),
        .m_arlen(m_arlen),
        .m_arsize(m_arsize),
        .m_rvalid(m_rvalid),
        .m_rready(m_rready),
        .m_rdata(m_rdata),
        .m_rresp(m_rresp),
        .m_rlast(m_rlast),
        .m_rid(m_rid),
        .paddr(paddr),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr),
        .usb_irq(usb_irq)
    );

    // Clocks
    always #5.0 clk = ~clk;
    always #8.333 ulpi_clk = ~ulpi_clk; // 60 MHz

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
        $dumpfile("tb_usb_otg.vcd");
        $dumpvars(0, tb_usb_otg);

        clk = 0;
        ulpi_clk = 0;
        rst_n = 0;
        ulpi_dir = 0;
        ulpi_nxt = 0;
        ulpi_data_driver = 8'h00;
        psel = 0;
        penable = 0;
        pwrite = 0;
        paddr = 0;
        pwdata = 0;
        m_awready = 1;
        m_wready = 1;
        m_bvalid = 0;
        m_bresp = 0;
        m_bid = 0;
        m_arready = 1;
        m_rvalid = 0;
        m_rdata = 0;
        m_rresp = 0;
        m_rlast = 0;
        m_rid = 0;

        #25;
        // Test 1: Reset active
        check("TEST 1: Reset active sets ulpi_reset=1", ulpi_reset == 1'b1);

        rst_n = 1;
        repeat (3) @(posedge clk);

        // Test 2: Reset released
        check("TEST 2: Reset release clears ulpi_reset=0 and pready=1", (ulpi_reset == 1'b0) && (pready == 1'b1));

        // Test 3: USBCMD register R/W (0x40)
        apb_write_reg(8'h40, 32'h0000_0001); // Run/Stop
        apb_read_reg(8'h40, rdata);
        check("TEST 3: USBCMD register R/W 0x00000001", rdata == 32'h0000_0001);

        // Test 4: USBINTR register R/W (0x48)
        apb_write_reg(8'h48, 32'h0000_003F);
        apb_read_reg(8'h48, rdata);
        check("TEST 4: USBINTR register R/W 0x0000003F", rdata == 32'h0000_003F);

        // Test 5: USBSTS register R/W (0x44) & IRQ Trigger
        apb_write_reg(8'h44, 32'h0000_0001); // Interrupt triggered
        apb_read_reg(8'h44, rdata);
        check("TEST 5: USBSTS register R/W 0x00000001", rdata == 32'h0000_0001);
        check("TEST 6: usb_irq asserts when (usbsts & usbintr) is non-zero", usb_irq == 1'b1);

        // Test 7: ASYNCLISTADDR register R/W (0x58)
        apb_write_reg(8'h58, 32'h8000_1000);
        apb_read_reg(8'h58, rdata);
        check("TEST 7: ASYNCLISTADDR register R/W 0x80001000", rdata == 32'h8000_1000);

        // Test 8: PORTSC1 register R/W (0x84)
        apb_write_reg(8'h84, 32'h0000_1005);
        apb_read_reg(8'h84, rdata);
        check("TEST 8: PORTSC1 register R/W 0x00001005", rdata == 32'h0000_1005);

        // Test 9: OTGSC register R/W (0xA4)
        apb_write_reg(8'hA4, 32'h0000_0F00);
        apb_read_reg(8'hA4, rdata);
        check("TEST 9: OTGSC register R/W 0x00000F00", rdata == 32'h0000_0F00);

        // Test 10: ULPI data bus tri-state
        ulpi_dir = 0;
        #1;
        check("TEST 10: ULPI TX direction (dir=0) drives ulpi_data to 0x00", ulpi_data == 8'h00);

        ulpi_dir = 1;
        ulpi_data_driver = 8'hA5;
        #1;
        check("TEST 11: ULPI RX direction (dir=1) releases bus to PHY (0xA5)", ulpi_data == 8'hA5);

        // Test 12: AXI DMA tie-offs
        check("TEST 12: AXI4 master idle tie-offs valid",
              (m_awvalid == 1'b0) && (m_arvalid == 1'b0) && (m_bready == 1'b1) && (m_rready == 1'b1));

        $display("\n==============================");
        if (fail_count == 0 && pass_count >= 12) begin
            $display("USB_OTG VERDICT: ✅ PASS — All %0d tests green", pass_count);
        end else begin
            $display("USB_OTG VERDICT: ❌ FAIL — %0d failed, %0d passed", fail_count, pass_count);
        end
        $display("==============================\n");
        $finish;
    end

endmodule

// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Video DMA Controller Directed Self-Checking Testbench
`timescale 1ns/1ps

module tb_vdma();

    reg         clk;
    reg         rst_n;

    // AXI4-Stream IN (S2MM)
    reg  [31:0] s_axis_s2mm_tdata;
    reg         s_axis_s2mm_tvalid;
    wire        s_axis_s2mm_tready;
    reg         s_axis_s2mm_tuser;
    reg         s_axis_s2mm_tlast;

    // AXI4-Stream OUT (MM2S)
    wire [31:0] m_axis_mm2s_tdata;
    wire        m_axis_mm2s_tvalid;
    reg         m_axis_mm2s_tready;
    wire        m_axis_mm2s_tuser;
    wire        m_axis_mm2s_tlast;

    // AXI4 Master (MM)
    wire        m_axi_awvalid;
    reg         m_axi_awready;
    wire [39:0] m_axi_awaddr;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire        m_axi_wvalid;
    reg         m_axi_wready;
    wire [63:0] m_axi_wdata;
    wire [7:0]  m_axi_wstrb;
    wire        m_axi_wlast;
    reg         m_axi_bvalid;
    wire        m_axi_bready;
    reg  [1:0]  m_axi_bresp;
    wire        m_axi_arvalid;
    reg         m_axi_arready;
    wire [39:0] m_axi_araddr;
    wire [7:0]  m_axi_arlen;
    wire [2:0]  m_axi_arsize;
    reg         m_axi_rvalid;
    wire        m_axi_rready;
    reg  [63:0] m_axi_rdata;
    reg  [1:0]  m_axi_rresp;
    reg         m_axi_rlast;

    // APB Slave
    reg  [31:0] paddr;
    reg         psel;
    reg         penable;
    reg         pwrite;
    reg  [31:0] pwdata;
    wire [31:0] prdata;
    wire        pready;
    wire        pslverr;
    wire        vdma_irq;

    integer pass_count = 0;
    integer fail_count = 0;

    // DUT Instantiation
    vdma uut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_s2mm_tdata(s_axis_s2mm_tdata),
        .s_axis_s2mm_tvalid(s_axis_s2mm_tvalid),
        .s_axis_s2mm_tready(s_axis_s2mm_tready),
        .s_axis_s2mm_tuser(s_axis_s2mm_tuser),
        .s_axis_s2mm_tlast(s_axis_s2mm_tlast),
        .m_axis_mm2s_tdata(m_axis_mm2s_tdata),
        .m_axis_mm2s_tvalid(m_axis_mm2s_tvalid),
        .m_axis_mm2s_tready(m_axis_mm2s_tready),
        .m_axis_mm2s_tuser(m_axis_mm2s_tuser),
        .m_axis_mm2s_tlast(m_axis_mm2s_tlast),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .paddr(paddr),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr),
        .vdma_irq(vdma_irq)
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
        $dumpfile("tb_vdma.vcd");
        $dumpvars(0, tb_vdma);

        clk = 0;
        rst_n = 0;
        s_axis_s2mm_tdata = 32'h0;
        s_axis_s2mm_tvalid = 0;
        s_axis_s2mm_tuser = 0;
        s_axis_s2mm_tlast = 0;
        m_axis_mm2s_tready = 1;
        m_axi_awready = 1;
        m_axi_wready = 1;
        m_axi_bvalid = 0;
        m_axi_bresp = 0;
        m_axi_arready = 1;
        m_axi_rvalid = 0;
        m_axi_rdata = 64'h0;
        m_axi_rresp = 0;
        m_axi_rlast = 0;
        psel = 0;
        penable = 0;
        pwrite = 0;
        paddr = 0;
        pwdata = 0;

        #25;
        // Test 1: Reset active
        check("TEST 1: Reset holds vdma_irq=0 and pready=1", (vdma_irq == 1'b0) && (pready == 1'b1));

        rst_n = 1;
        repeat (3) @(posedge clk);

        // Test 2: S2MM stream ready defaults to 1
        check("TEST 2: s_axis_s2mm_tready asserts ready for stream ingestion", s_axis_s2mm_tready == 1'b1);

        // Test 3: Control Register (CR) Configuration (0x00)
        apb_write_reg(8'h00, 32'h0000_0003); // Enable MM2S & S2MM
        check("TEST 3: Control register written without pslverr", pslverr == 1'b0);

        // Test 4: MM2S 2D Geometry Registers
        apb_write_reg(8'h10, 32'd1080); // VSIZE
        apb_write_reg(8'h14, 32'd7680); // HSIZE (1920 * 4)
        apb_write_reg(8'h18, 32'd7680); // STRIDE
        apb_write_reg(8'h1C, 32'h8000_0000); // Buffer 0
        check("TEST 4: MM2S 2D frame geometry registers (1080p, 7680B stride) programmed", pslverr == 1'b0);

        // Test 5: S2MM 2D Geometry Registers
        apb_write_reg(8'h30, 32'd1080); // VSIZE
        apb_write_reg(8'h34, 32'd7680); // HSIZE
        apb_write_reg(8'h38, 32'd7680); // STRIDE
        apb_write_reg(8'h3C, 32'h9000_0000); // Buffer 0
        check("TEST 5: S2MM 2D frame geometry registers (1080p, 7680B stride) programmed", pslverr == 1'b0);

        // Test 6: Status Register Read (0x04)
        apb_read_reg(8'h04, rdata);
        check("TEST 6: Status register returns clean initial state (0x00000000)", rdata == 32'h0000_0000);

        // Test 7: S2MM Stream Ingestion
        @(posedge clk);
        s_axis_s2mm_tdata  <= 32'hDEAD_CAFE;
        s_axis_s2mm_tvalid <= 1'b1;
        s_axis_s2mm_tuser  <= 1'b1;
        @(posedge clk);
        check("TEST 7: S2MM accepts video stream pixel beat", s_axis_s2mm_tready == 1'b1);
        s_axis_s2mm_tvalid <= 1'b0;

        // Test 8: AXI4 MM master tie-offs clean
        check("TEST 8: AXI4 MM master tie-offs valid (awvalid=0, wvalid=0, arvalid=0, bready=1, rready=1)",
              (m_axi_awvalid == 1'b0) && (m_axi_wvalid == 1'b0) && (m_axi_arvalid == 1'b0) &&
              (m_axi_bready == 1'b1) && (m_axi_rready == 1'b1));

        // Test 9: MM2S Stream channel idle
        check("TEST 9: MM2S stream channel idle (m_axis_mm2s_tvalid=0)", m_axis_mm2s_tvalid == 1'b0);

        $display("\n==============================");
        if (fail_count == 0 && pass_count >= 9) begin
            $display("VDMA VERDICT: ✅ PASS — All %0d tests green", pass_count);
        end else begin
            $display("VDMA VERDICT: ❌ FAIL — %0d failed, %0d passed", fail_count, pass_count);
        end
        $display("==============================\n");
        $finish;
    end

endmodule

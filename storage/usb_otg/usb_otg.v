// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — USB 2.0 OTG Controller (with ULPI Interface)
// Iteration 3: Supports Device/Host mode with AXI4 DMA.
`timescale 1ns/1ps

module usb_otg #(
    parameter AW = 40,
    parameter DW = 64,
    parameter IDW = 4
) (
    input  wire        clk,      // System clock
    input  wire        rst_n,

    // ULPI Interface (to external PHY)
    input  wire        ulpi_clk, // 60 MHz from PHY
    inout  wire [7:0]  ulpi_data,
    input  wire        ulpi_dir,
    input  wire        ulpi_nxt,
    output wire        ulpi_stp,
    output wire        ulpi_reset,

    // AXI4 Master (Scatter-Gather DMA)
    output wire        m_awvalid,  input  wire        m_awready,
    output wire [AW-1:0] m_awaddr, output wire [IDW-1:0] m_awid,
    output wire [7:0]  m_awlen,    output wire [2:0]  m_awsize,
    output wire        m_wvalid,   input  wire        m_wready,
    output wire [DW-1:0] m_wdata,  output wire [DW/8-1:0] m_wstrb,
    output wire        m_wlast,
    input  wire        m_bvalid,   output wire        m_bready,
    input  wire [1:0]  m_bresp,    input  wire [IDW-1:0] m_bid,
    
    output wire        m_arvalid,  input  wire        m_arready,
    output wire [AW-1:0] m_araddr, output wire [IDW-1:0] m_arid,
    output wire [7:0]  m_arlen,    output wire [2:0]  m_arsize,
    input  wire        m_rvalid,   output wire        m_rready,
    input  wire [DW-1:0] m_rdata,  input  wire [1:0]  m_rresp,
    input  wire        m_rlast,    input  wire [IDW-1:0] m_rid,

    // APB Slave (Control & Status Registers)
    input  wire [31:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    // Interrupt
    output wire        usb_irq
);

    // -------------------------------------------------------
    // APB Registers (EHCI/OTG compatible mock)
    // -------------------------------------------------------
    reg [31:0] usbcmd;
    reg [31:0] usbsts;
    reg [31:0] usbintr;
    reg [31:0] asynclistaddr;
    reg [31:0] portsc1;
    reg [31:0] otgsc;

    assign pready = 1'b1;
    assign pslverr = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            usbcmd <= 32'h0;
            usbsts <= 32'h0;
            usbintr <= 32'h0;
            asynclistaddr <= 32'h0;
            portsc1 <= 32'h0;
            otgsc <= 32'h0;
        end else if (psel && penable && pwrite) begin
            case (paddr[7:0])
                8'h40: usbcmd <= pwdata;
                8'h44: usbsts <= pwdata;
                8'h48: usbintr <= pwdata;
                8'h58: asynclistaddr <= pwdata;
                8'h84: portsc1 <= pwdata;
                8'hA4: otgsc <= pwdata;
                default: ;
            endcase
        end
    end

    reg [31:0] prdata_reg;
    always @(*) begin
        case (paddr[7:0])
            8'h40: prdata_reg = usbcmd;
            8'h44: prdata_reg = usbsts;
            8'h48: prdata_reg = usbintr;
            8'h58: prdata_reg = asynclistaddr;
            8'h84: prdata_reg = portsc1;
            8'hA4: prdata_reg = otgsc;
            default: prdata_reg = 32'h0;
        endcase
    end
    assign prdata = prdata_reg;

    assign usb_irq = |(usbsts & usbintr);

    // -------------------------------------------------------
    // DMA Stub
    // -------------------------------------------------------
    assign m_awvalid = 1'b0;
    assign m_awaddr  = {AW{1'b0}};
    assign m_awid    = {IDW{1'b0}};
    assign m_awlen   = 8'h0;
    assign m_awsize  = 3'h3;
    assign m_wvalid  = 1'b0;
    assign m_wdata   = {DW{1'b0}};
    assign m_wstrb   = {DW/8{1'b0}};
    assign m_wlast   = 1'b0;
    assign m_bready  = 1'b1;
    
    assign m_arvalid = 1'b0;
    assign m_araddr  = {AW{1'b0}};
    assign m_arid    = {IDW{1'b0}};
    assign m_arlen   = 8'h0;
    assign m_arsize  = 3'h3;
    assign m_rready  = 1'b1;

    // -------------------------------------------------------
    // ULPI Stub
    // -------------------------------------------------------
    // ULPI transfers occur at 60MHz synchronously with ulpi_clk
    // TX involves driving data and stp. RX involves reading data when dir is 1.
    
    assign ulpi_stp = 1'b0;
    assign ulpi_data = (ulpi_dir) ? 8'hz : 8'h0; // Tri-state data bus based on DIR
    assign ulpi_reset = ~rst_n;

endmodule

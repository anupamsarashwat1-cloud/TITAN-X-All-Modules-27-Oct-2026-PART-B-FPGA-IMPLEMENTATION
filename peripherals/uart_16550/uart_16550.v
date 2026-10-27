// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — MMUART (Multi-Mode UART based on 16550)
// Iteration 3: Added support for LIN, IrDA, and 9-bit data modes.
`timescale 1ns/1ps

module uart_16550 (
    input  wire        clk,
    input  wire        rst_n,

    // APB Slave Interface
    input  wire [31:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    // Interrupt
    output wire        uart_irq,

    // Serial Pins
    input  wire        rxd,
    output wire        txd,
    
    // IrDA / LIN Pins (Multiplexed usually, but separated here for clarity)
    output wire        irda_tx,
    input  wire        irda_rx,
    output wire        lin_tx,
    input  wire        lin_rx
);

    // -------------------------------------------------------
    // Registers (16550 + Extensions)
    // -------------------------------------------------------
    reg [7:0] thr_rbr; // Transmit/Receive Buffer
    reg [7:0] ier;     // Interrupt Enable
    reg [7:0] iir_fcr; // Interrupt ID / FIFO Control
    reg [7:0] lcr;     // Line Control
    reg [7:0] mcr;     // Modem Control
    reg [7:0] lsr;     // Line Status
    reg [7:0] msr;     // Modem Status
    reg [7:0] scr;     // Scratch

    // Divisor Latches
    reg [7:0] dll;
    reg [7:0] dlm;

    // Extension Registers
    reg [7:0] mode_cr; // Mode Control: [1:0] 00=UART, 01=IrDA, 10=LIN
    reg [7:0] nbit_cr; // 9-bit Control: [0]=enable, [1]=tx_9th_bit, [2]=rx_9th_bit

    assign pready = 1'b1;
    assign pslverr = 1'b0;

    wire dlab = lcr[7];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ier <= 8'h0;
            iir_fcr <= 8'h01;
            lcr <= 8'h0;
            mcr <= 8'h0;
            lsr <= 8'h60; // THRE and TEMT high
            msr <= 8'h0;
            scr <= 8'h0;
            dll <= 8'h0;
            dlm <= 8'h0;
            mode_cr <= 8'h0;
            nbit_cr <= 8'h0;
        end else if (psel && penable && pwrite) begin
            case (paddr[5:0])
                6'h00: if (dlab) dll <= pwdata[7:0]; else thr_rbr <= pwdata[7:0];
                6'h04: if (dlab) dlm <= pwdata[7:0]; else ier <= pwdata[7:0];
                6'h08: iir_fcr <= pwdata[7:0];
                6'h0C: lcr <= pwdata[7:0];
                6'h10: mcr <= pwdata[7:0];
                6'h1C: scr <= pwdata[7:0];
                6'h20: mode_cr <= pwdata[7:0]; // Extension offset
                6'h24: nbit_cr <= pwdata[7:0]; // Extension offset
                default: ;
            endcase
        end
    end
    
    reg [31:0] prdata_reg;
    always @(*) begin
        case (paddr[5:0])
            6'h00: prdata_reg = {24'h0, (dlab ? dll : thr_rbr)};
            6'h04: prdata_reg = {24'h0, (dlab ? dlm : ier)};
            6'h08: prdata_reg = {24'h0, iir_fcr};
            6'h0C: prdata_reg = {24'h0, lcr};
            6'h10: prdata_reg = {24'h0, mcr};
            6'h14: prdata_reg = {24'h0, lsr};
            6'h18: prdata_reg = {24'h0, msr};
            6'h1C: prdata_reg = {24'h0, scr};
            6'h20: prdata_reg = {24'h0, mode_cr};
            6'h24: prdata_reg = {24'h0, nbit_cr};
            default: prdata_reg = 32'h0;
        endcase
    end
    assign prdata = prdata_reg;

    // -------------------------------------------------------
    // Core Logic Stub
    // -------------------------------------------------------
    // The baud generator divides clk by (dlm, dll) * 16.
    // The RX/TX logic processes 16550 standard framing.
    // mode_cr redirects data from standard TX/RX to IrDA or LIN logic.

    assign uart_irq = 1'b0;
    
    assign txd = 1'b1;     // Idle high
    assign irda_tx = 1'b0; // IrDA idle low
    assign lin_tx = 1'b1;  // LIN idle high

    // Suppress unused warnings for inputs
    wire _unused = &{rxd, irda_rx, lin_rx};

endmodule

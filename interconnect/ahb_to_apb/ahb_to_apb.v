// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — AHB3 to APB4 Bridge
`timescale 1ns/1ps
module ahb_to_apb (
    input  wire        clk,
    input  wire        rst_n,
    // AHB3-Lite slave
    input  wire [31:0] haddr,
    input  wire        hwrite,
    input  wire [1:0]  htrans,
    input  wire [31:0] hwdata,
    output reg  [31:0] hrdata,
    output reg         hready_out,
    output wire        hresp,
    // APB4 master
    output reg  [31:0] paddr,
    output reg         psel,
    output reg         penable,
    output reg         pwrite,
    output reg  [31:0] pwdata,
    input  wire [31:0] prdata,
    input  wire        pready,
    input  wire        pslverr
);
    assign hresp = 1'b0;

    localparam PS_IDLE   = 2'd0;
    localparam PS_SETUP  = 2'd1;
    localparam PS_ENABLE = 2'd2;
    localparam PS_DONE   = 2'd3;
    reg [1:0] pstate;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pstate    <= PS_IDLE;
            psel      <= 1'b0;
            penable   <= 1'b0;
            pwrite    <= 1'b0;
            paddr     <= 32'h0;
            pwdata    <= 32'h0;
            hrdata    <= 32'h0;
            hready_out<= 1'b1;
        end else begin
            case (pstate)
                PS_IDLE: begin
                    hready_out <= 1'b1;
                    if (htrans[1]) begin  // NONSEQ or SEQ
                        paddr    <= haddr;
                        pwrite   <= hwrite;
                        pwdata   <= hwdata;
                        psel     <= 1'b1;
                        penable  <= 1'b0;
                        hready_out <= 1'b0;
                        pstate   <= PS_ENABLE;
                    end
                end
                PS_ENABLE: begin
                    penable <= 1'b1;
                    if (pready) begin
                        hrdata     <= prdata;
                        psel       <= 1'b0;
                        penable    <= 1'b0;
                        hready_out <= 1'b1;
                        pstate     <= PS_IDLE;
                    end
                end
                default: pstate <= PS_IDLE;
            endcase
        end
    end
endmodule

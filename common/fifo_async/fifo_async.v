// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Asynchronous FIFO (Gray-code CDC pointers)
`timescale 1ns/1ps
module fifo_async #(
    parameter WIDTH  = 8,
    parameter DEPTH  = 16,
    parameter AWIDTH = $clog2(DEPTH)
) (
    input  wire               wr_clk,
    input  wire               wr_rst_n,
    input  wire               wr_en,
    input  wire [WIDTH-1:0]   wr_data,
    output wire               full,

    input  wire               rd_clk,
    input  wire               rd_rst_n,
    input  wire               rd_en,
    output reg  [WIDTH-1:0]   rd_data,
    output wire               empty
);
    reg [WIDTH-1:0]  mem [0:DEPTH-1];

    // Write domain
    reg [AWIDTH:0] wr_bin, wr_gray;
    // Read domain
    reg [AWIDTH:0] rd_bin, rd_gray;

    // Synchronized pointers
    (* ASYNC_REG = "TRUE" *) reg [AWIDTH:0] wr_gray_s1, wr_gray_s2;
    (* ASYNC_REG = "TRUE" *) reg [AWIDTH:0] rd_gray_s1, rd_gray_s2;

    // Gray encode
    function [AWIDTH:0] bin2gray;
        input [AWIDTH:0] bin;
        bin2gray = (bin >> 1) ^ bin;
    endfunction

    // Gray decode
    function [AWIDTH:0] gray2bin;
        input [AWIDTH:0] gray;
        integer k;
        reg [AWIDTH:0] b;
        begin
            b[AWIDTH] = gray[AWIDTH];
            for (k = AWIDTH-1; k >= 0; k = k-1)
                b[k] = b[k+1] ^ gray[k];
            gray2bin = b;
        end
    endfunction

    wire do_write = wr_en & ~full;
    wire do_read  = rd_en & ~empty;

    // Write clock domain
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_bin  <= {(AWIDTH+1){1'b0}};
            wr_gray <= {(AWIDTH+1){1'b0}};
        end else if (do_write) begin
            mem[wr_bin[AWIDTH-1:0]] <= wr_data;
            wr_bin  <= wr_bin + 1'b1;
            wr_gray <= bin2gray(wr_bin + 1'b1);
        end
    end

    // Read clock domain
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_bin  <= {(AWIDTH+1){1'b0}};
            rd_gray <= {(AWIDTH+1){1'b0}};
            rd_data <= {WIDTH{1'b0}};
        end else begin
            if (do_read) begin
                rd_data <= mem[rd_bin[AWIDTH-1:0]];
                rd_bin  <= rd_bin + 1'b1;
                rd_gray <= bin2gray(rd_bin + 1'b1);
            end
        end
    end

    // Synchronize wr_gray into rd clock domain
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_gray_s1 <= {(AWIDTH+1){1'b0}};
            wr_gray_s2 <= {(AWIDTH+1){1'b0}};
        end else begin
            wr_gray_s1 <= wr_gray;
            wr_gray_s2 <= wr_gray_s1;
        end
    end

    // Synchronize rd_gray into wr clock domain
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_gray_s1 <= {(AWIDTH+1){1'b0}};
            rd_gray_s2 <= {(AWIDTH+1){1'b0}};
        end else begin
            rd_gray_s1 <= rd_gray;
            rd_gray_s2 <= rd_gray_s1;
        end
    end

    // Full: wr_gray == {~rd_gray_s2[AWIDTH:AWIDTH-1], rd_gray_s2[AWIDTH-2:0]}
    assign full  = (wr_gray == {~rd_gray_s2[AWIDTH:AWIDTH-1], rd_gray_s2[AWIDTH-2:0]});
    assign empty = (rd_gray == wr_gray_s2);
endmodule

// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Synchronous FIFO (parameterized)
`timescale 1ns/1ps
module fifo_sync #(
    parameter WIDTH  = 8,
    parameter DEPTH  = 16,
    parameter AWIDTH = $clog2(DEPTH)
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               wr_en,
    input  wire               rd_en,
    input  wire [WIDTH-1:0]   wr_data,
    output reg  [WIDTH-1:0]   rd_data,
    output wire               full,
    output wire               empty,
    output wire [AWIDTH:0]    count
);
    reg [WIDTH-1:0]  mem [0:DEPTH-1];
    reg [AWIDTH:0]   wr_ptr, rd_ptr;

    wire do_write = wr_en & ~full;
    wire do_read  = rd_en & ~empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr  <= {(AWIDTH+1){1'b0}};
            rd_ptr  <= {(AWIDTH+1){1'b0}};
            rd_data <= {WIDTH{1'b0}};
        end else begin
            if (do_write) begin
                mem[wr_ptr[AWIDTH-1:0]] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (do_read) begin
                rd_data <= mem[rd_ptr[AWIDTH-1:0]];
                rd_ptr  <= rd_ptr + 1'b1;
            end
        end
    end

    assign count = wr_ptr - rd_ptr;
    assign full  = (count == DEPTH[AWIDTH:0]);
    assign empty = (count == {(AWIDTH+1){1'b0}});
endmodule

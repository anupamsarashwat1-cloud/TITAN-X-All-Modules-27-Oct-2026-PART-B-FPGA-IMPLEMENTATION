// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RV64I Writeback Stage
`timescale 1ns/1ps
module rv_writeback (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [63:0] result,
    input  wire [4:0]  rd_in,
    input  wire        reg_write,
    input  wire        valid_in,
    // To register file in decode
    output reg  [63:0] wb_data,
    output reg  [4:0]  wb_rd,
    output reg         wb_we,
    // Forwarding
    output wire [63:0] fwd_wb_data,
    output wire [4:0]  fwd_wb_rd,
    output wire        fwd_wb_valid
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_data <= 64'h0;
            wb_rd   <= 5'h0;
            wb_we   <= 1'b0;
        end else begin
            wb_data <= result;
            wb_rd   <= rd_in;
            wb_we   <= reg_write && valid_in && (rd_in != 5'h0);
        end
    end

    assign fwd_wb_data  = wb_data;
    assign fwd_wb_rd    = wb_rd;
    assign fwd_wb_valid = wb_we;
endmodule

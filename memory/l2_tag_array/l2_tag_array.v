// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — L2 Tag Array
// Register-based tag storage: 64 sets, 28-bit tags + valid
`timescale 1ns/1ps
module l2_tag_array #(
    parameter NUM_SETS = 64,
    parameter TAG_W    = 28
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              cs,
    input  wire              we,
    input  wire [5:0]        index,
    input  wire [TAG_W-1:0]  tag_in,
    output wire [TAG_W-1:0]  tag_out,
    output wire              valid_out
);
    reg [TAG_W-1:0] tag_mem  [0:NUM_SETS-1];
    reg             valid_mem[0:NUM_SETS-1];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_SETS; i = i+1) begin
                tag_mem[i]   <= {TAG_W{1'b0}};
                valid_mem[i] <= 1'b0;
            end
        end else if (cs && we) begin
            tag_mem[index]   <= tag_in;
            valid_mem[index] <= 1'b1;
        end
    end

    assign tag_out   = tag_mem[index];
    assign valid_out = valid_mem[index];
endmodule

// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — CDC 2-FF Synchronizer
`timescale 1ns/1ps
module cdc_sync #(
    parameter WIDTH  = 1,
    parameter STAGES = 2
) (
    input  wire               dst_clk,
    input  wire               rst_n,
    input  wire [WIDTH-1:0]   data_in,
    output wire [WIDTH-1:0]   data_out
);
    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] sync_ff [0:STAGES-1];
    integer i;

    always @(posedge dst_clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset EVERY stage — hardcoding stages 0/1 left X on deeper
            // flops when instantiated with STAGES > 2.
            for (i = 0; i < STAGES; i = i + 1)
                sync_ff[i] <= {WIDTH{1'b0}};
        end else begin
            sync_ff[0] <= data_in;
            for (i = 1; i < STAGES; i = i + 1)
                sync_ff[i] <= sync_ff[i-1];
        end
    end

    assign data_out = sync_ff[STAGES-1];
endmodule

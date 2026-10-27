// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Reset Synchronizer
// Synchronizes asynchronous active-low reset deassertion to a clock domain.
// Two-stage pipeline ensures metastability-free reset release.
`timescale 1ns/1ps
module reset_sync #(
    parameter STAGES = 2
) (
    input  wire clk,
    input  wire async_rst_n,   // Asynchronous active-low reset input
    output wire sync_rst_n     // Synchronous active-low reset output
);
    (* ASYNC_REG = "TRUE" *) reg [STAGES-1:0] sync_chain;

    always @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n)
            sync_chain <= {STAGES{1'b0}};
        else
            sync_chain <= {sync_chain[STAGES-2:0], 1'b1};
    end

    assign sync_rst_n = sync_chain[STAGES-1];
endmodule

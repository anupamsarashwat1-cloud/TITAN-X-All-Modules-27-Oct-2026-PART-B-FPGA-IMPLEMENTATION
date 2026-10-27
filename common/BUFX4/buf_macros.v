`timescale 1ns/1ps
// Guarded duplicate of includes/stdcell_stubs.v — safe to compile together.
`ifndef TITANX_STDCELL_STUBS
module BUFX4 (
    input  wire A,
    output wire Y
);
    assign Y = A;
endmodule
`endif

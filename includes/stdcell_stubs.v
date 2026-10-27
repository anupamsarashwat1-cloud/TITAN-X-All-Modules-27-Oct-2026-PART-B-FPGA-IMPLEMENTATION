// Standard cell stub library for 180nm verification
// Canonical home of cell stubs. Guarded so it may be listed on any compile
// line regardless of ../common/* also being present.
`timescale 1ns/1ps
`ifndef TITANX_STDCELL_STUBS
`define TITANX_STDCELL_STUBS

// BUFX4: 4X drive strength buffer
module BUFX4 (
    input  wire A,
    output wire Y
);
    assign Y = A;
endmodule

// ICGX4: Integrated Clock Gating Cell (Latch-based glitch-free clock gate)
module ICGX4 (
    input  wire CLK,
    input  wire EN,
    input  wire TE, // Test Enable / Scan Bypass
    output wire GCLK
);
    reg en_latched;
    always @(CLK or EN or TE) begin
        if (!CLK)
            en_latched = EN | TE;
    end
    assign GCLK = CLK & en_latched;
endmodule

`endif // TITANX_STDCELL_STUBS

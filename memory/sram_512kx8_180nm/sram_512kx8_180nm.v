// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — 512KB SRAM Behavioral Macro
// Target: SCL 180nm CMOS
// Configuration: 524288 words × 8 bits = 4Mb (512KB)
// Note: This is a behavioral simulation model. In physical synthesis,
// this will be replaced by a compiled hard macro from the foundry memory compiler.
`timescale 1ns/1ps

module sram_512kx8_180nm (
    input  wire         CLK,    // Clock
    input  wire         CEN,    // Chip Enable (Active Low)
    input  wire         WEN,    // Write Enable (Active Low)
    input  wire [18:0]  A,      // Address (19 bits for 512K)
    input  wire [7:0]   D,      // Data In
    output reg  [7:0]   Q       // Data Out
);

    // 512K x 8-bit memory array
    // Synthesis tools may struggle with this size if not mapped to block RAMs
    // FPGA synth: will infer UltraRAM or block RAMs.
    reg [7:0] mem [0:524287];

    always @(posedge CLK) begin
        if (!CEN) begin
            if (!WEN) begin
                mem[A] <= D;
                Q <= D; // Write-first or transparent behavior
            end else begin
                Q <= mem[A]; // Read
            end
        end
    end

endmodule

// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — SRAM Hard Macro Simulation Stub
// Module: sram_32x64_180nm
// Description: Behavioral simulation model for SCL 180nm SRAM macro.
//              In physical implementation, replace with foundry-provided hard macro.
//              All ports must be connected — floating dout0 causes LVS failure.
//
// Ports:
//   clk0   : clock
//   csb0   : chip select (active-LOW)
//   web0   : write enable (active-LOW)
//   wmask0 : byte write mask [3:0] (active-HIGH: 1=write this byte)
//   addr0  : address [5:0] (64 rows)
//   din0   : data input [31:0]
//   dout0  : data output [31:0] ← MUST BE CONNECTED (LVS requirement)
`timescale 1ns/1ps
module sram_32x64_180nm (
    input  wire        clk0,
    input  wire        csb0,    // active-low chip select
    input  wire        web0,    // active-low write enable
    input  wire [3:0]  wmask0,  // active-high byte mask
    input  wire [5:0]  addr0,   // 6-bit address (64 locations)
    input  wire [31:0] din0,    // write data
    output reg  [31:0] dout0    // read data — MUST be connected at instantiation
);
    // 64 × 32-bit storage array
    reg [31:0] mem [0:63];

    // Initialize to known state for simulation
    integer i;
    initial begin
        for (i = 0; i < 64; i = i+1)
            mem[i] = 32'h0;
    end

    // Synchronous read/write (write-first behavior on same address)
    always @(posedge clk0) begin
        if (!csb0) begin
            if (!web0) begin
                // Write: byte-masked
                if (wmask0[0]) mem[addr0][7:0]   <= din0[7:0];
                if (wmask0[1]) mem[addr0][15:8]  <= din0[15:8];
                if (wmask0[2]) mem[addr0][23:16] <= din0[23:16];
                if (wmask0[3]) mem[addr0][31:24] <= din0[31:24];
            end
            // Read (even during write — read new data for write-first)
            dout0 <= mem[addr0];
        end else begin
            // Not selected: hold last output (no floating)
            dout0 <= dout0;
        end
    end
endmodule

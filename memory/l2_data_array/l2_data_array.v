// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — L2 Data Array
// Wraps TWO sram_32x64_180nm macros (2 banks).
// CRITICAL FIX: dout0[31:0] from both SRAM macros is properly read and driven
// to dout — this resolves the LVS floating-net issue reported by the PD team.
`timescale 1ns/1ps
module l2_data_array #(
    parameter NUM_BANKS = 2,
    parameter DATA_W    = 32,
    parameter DEPTH     = 64
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bank_sel,    // 0 = bank0, 1 = bank1
    input  wire        cs,          // chip select
    input  wire        we,          // write enable
    input  wire [3:0]  wmask,       // byte write mask
    input  wire [5:0]  addr,        // 64-deep address
    input  wire [31:0] din,         // write data
    output reg  [31:0] dout,        // read data (from selected bank)
    output reg         dout_valid   // 1 cycle after read issued
);
    // Per-bank chip-select signals
    wire csb0_bank0 = ~(cs && !bank_sel);  // active-low CS for bank 0
    wire csb0_bank1 = ~(cs &&  bank_sel);  // active-low CS for bank 1
    wire web0       = ~we;                  // active-low write enable

    // SRAM macro outputs — these MUST be connected (LVS fix)
    wire [31:0] sram_dout_bank0;
    wire [31:0] sram_dout_bank1;

    // Instantiate SRAM macro for Bank 0
    sram_32x64_180nm u_sram_bank0 (
        .clk0  (clk),
        .csb0  (csb0_bank0),
        .web0  (web0),
        .wmask0(wmask),
        .addr0 (addr),
        .din0  (din),
        .dout0 (sram_dout_bank0)   // ← READ: drives 32 nets (was floating — now connected)
    );

    // Instantiate SRAM macro for Bank 1
    sram_32x64_180nm u_sram_bank1 (
        .clk0  (clk),
        .csb0  (csb0_bank1),
        .web0  (web0),
        .wmask0(wmask),
        .addr0 (addr),
        .din0  (din),
        .dout0 (sram_dout_bank1)   // ← READ: drives 32 nets (was floating — now connected)
    );

    // Output MUX — select bank, register for 1-cycle latency
    reg bank_sel_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bank_sel_r <= 1'b0;
            dout       <= 32'h0;
            dout_valid <= 1'b0;
        end else begin
            bank_sel_r <= bank_sel;
            dout_valid <= cs && !we;
            if (cs && !we)
                dout <= bank_sel ? sram_dout_bank1 : sram_dout_bank0;
        end
    end
endmodule

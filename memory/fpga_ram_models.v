// SPDX-License-Identifier: Apache-2.0
// TITAN-X SoC — FPGA Synthesizable Block RAM & UltraRAM Models
// Maps L2 Tag/Data Arrays and On-Chip Memory directly to FPGA primitives:
//   - Inferred true dual-port & single-port synchronous Block RAMs
//   - Byte-write enable granularity (byte-wide write masks)
//   - Synchronous read with optional output register pipeline stage

`timescale 1ns/1ps

module fpga_bram_sp #(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 12,
    parameter DEPTH      = 4096
) (
    input  wire                   clk,
    input  wire                   en,
    input  wire [DATA_WIDTH/8-1:0] we,
    input  wire [ADDR_WIDTH-1:0]  addr,
    input  wire [DATA_WIDTH-1:0]  din,
    output reg  [DATA_WIDTH-1:0]  dout
);

    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] ram [0:DEPTH-1];

    genvar i;
    generate
        for (i = 0; i < DATA_WIDTH/8; i = i + 1) begin : gen_byte_wr
            always @(posedge clk) begin
                if (en && we[i])
                    ram[addr][i*8 +: 8] <= din[i*8 +: 8];
            end
        end
    endgenerate

    always @(posedge clk) begin
        if (en)
            dout <= ram[addr];
    end

endmodule

module fpga_bram_tdp #(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 10,
    parameter DEPTH      = 1024
) (
    // Port A
    input  wire                   clka,
    input  wire                   ena,
    input  wire [DATA_WIDTH/8-1:0] wea,
    input  wire [ADDR_WIDTH-1:0]  addra,
    input  wire [DATA_WIDTH-1:0]  dina,
    output reg  [DATA_WIDTH-1:0]  douta,

    // Port B
    input  wire                   clkb,
    input  wire                   enb,
    input  wire [DATA_WIDTH/8-1:0] web,
    input  wire [ADDR_WIDTH-1:0]  addrb,
    input  wire [DATA_WIDTH-1:0]  dinb,
    output reg  [DATA_WIDTH-1:0]  doutb
);

    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] ram [0:DEPTH-1];

    genvar a_byte;
    generate
        for (a_byte = 0; a_byte < DATA_WIDTH/8; a_byte = a_byte + 1) begin : gen_port_a_wr
            always @(posedge clka) begin
                if (ena && wea[a_byte])
                    ram[addra][a_byte*8 +: 8] <= dina[a_byte*8 +: 8];
            end
        end
    endgenerate

    always @(posedge clka) begin
        if (ena)
            douta <= ram[addra];
    end

    genvar b_byte;
    generate
        for (b_byte = 0; b_byte < DATA_WIDTH/8; b_byte = b_byte + 1) begin : gen_port_b_wr
            always @(posedge clkb) begin
                if (enb && web[b_byte])
                    ram[addrb][b_byte*8 +: 8] <= dinb[b_byte*8 +: 8];
            end
        end
    endgenerate

    always @(posedge clkb) begin
        if (enb)
            doutb <= ram[addrb];
    end

endmodule

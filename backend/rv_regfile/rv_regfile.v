// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RV64 Integer Register File (32 × 64-bit)
//
// Two asynchronous read ports, one synchronous write port.
// Write-first bypass: a read of the register being written THIS edge
// returns the incoming data, matching the architectural write-before-read
// ordering consumers expect across the WB->decode feedback path.
// x0 is architecturally hardwired to zero — writes to it are dropped and
// reads always return 0 regardless of stored content.
`timescale 1ns/1ps
module rv_regfile (
    input  wire        clk,
    input  wire        rst_n,
    // Read port 1
    input  wire [4:0]  rd_addr1,
    output wire [63:0] rd_data1,
    // Read port 2
    input  wire [4:0]  rd_addr2,
    output wire [63:0] rd_data2,
    // Write port
    input  wire        wr_en,
    input  wire [4:0]  wr_addr,
    input  wire [63:0] wr_data
);
    reg [63:0] mem [0:31];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                mem[i] <= 64'h0;
        end else if (wr_en && wr_addr != 5'h0) begin
            mem[wr_addr] <= wr_data;
        end
    end

    assign rd_data1 = (rd_addr1 == 5'h0)              ? 64'h0 :
                      (wr_en && (wr_addr == rd_addr1)) ? wr_data   :
                                                         mem[rd_addr1];
    assign rd_data2 = (rd_addr2 == 5'h0)              ? 64'h0 :
                      (wr_en && (wr_addr == rd_addr2)) ? wr_data   :
                                                         mem[rd_addr2];
endmodule

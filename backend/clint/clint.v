// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — CLINT: Core-Local Interruptor
// Implements: mtime (64-bit), mtimecmp[0:4] (64-bit), msip[0:4]
// Memory map (APB-style, 32-bit access):
//   0x0000 - 0x0013: msip[0..4]  (4 bytes each)
//   0x4000 - 0x4027: mtimecmp[0..4] (8 bytes each, lo then hi)
//   0xBFF8 - 0xBFFF: mtime (8 bytes, lo then hi)
`timescale 1ns/1ps
module clint #(
    parameter NUM_HARTS = 5
) (
    input  wire        clk,
    input  wire        rst_n,
    // APB slave
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [15:0] paddr,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    // Interrupt outputs
    output wire [NUM_HARTS-1:0] msip,
    output wire [NUM_HARTS-1:0] mtip
);
    reg [63:0] mtime;
    reg [63:0] mtimecmp [0:NUM_HARTS-1];
    reg [NUM_HARTS-1:0] msip_reg;

    assign pready = 1'b1;  // Zero-wait APB

    // mtime increments every cycle
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mtime <= 64'h0;
        end else begin
            mtime <= mtime + 64'h1;
        end
    end

    // mtip: timer interrupt when mtime >= mtimecmp
    genvar g;
    generate
        for (g = 0; g < NUM_HARTS; g = g+1) begin : GEN_MTIP
            assign mtip[g] = (mtime >= mtimecmp[g]);
        end
    endgenerate
    assign msip = msip_reg;

    // APB read/write
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msip_reg <= {NUM_HARTS{1'b0}};
            for (i = 0; i < NUM_HARTS; i = i+1)
                mtimecmp[i] <= 64'hFFFF_FFFF_FFFF_FFFF;
            prdata <= 32'h0;
        end else if (psel && penable) begin
            // Write
            if (pwrite) begin
                if (paddr < 16'h0020) begin
                    // msip region: 0x0000 + hart*4
                    if (paddr[5:2] < NUM_HARTS)
                        msip_reg[paddr[5:2]] <= pwdata[0];
                end else if (paddr >= 16'h4000 && paddr < 16'h4028) begin
                    // mtimecmp region
                    case (paddr[5:2])
                        4'd0: mtimecmp[0][31:0]  <= pwdata;
                        4'd1: mtimecmp[0][63:32] <= pwdata;
                        4'd2: mtimecmp[1][31:0]  <= pwdata;
                        4'd3: mtimecmp[1][63:32] <= pwdata;
                        4'd4: mtimecmp[2][31:0]  <= pwdata;
                        4'd5: mtimecmp[2][63:32] <= pwdata;
                        4'd6: mtimecmp[3][31:0]  <= pwdata;
                        4'd7: mtimecmp[3][63:32] <= pwdata;
                        4'd8: mtimecmp[4][31:0]  <= pwdata;
                        4'd9: mtimecmp[4][63:32] <= pwdata;
                        default: ;
                    endcase
                end
            end else begin
                // Read
                if (paddr < 16'h0020) begin
                    if (paddr[5:2] < NUM_HARTS)
                        prdata <= {31'h0, msip_reg[paddr[5:2]]};
                    else
                        prdata <= 32'h0;
                end else if (paddr == 16'hBFF8)
                    prdata <= mtime[31:0];
                else if (paddr == 16'hBFFC)
                    prdata <= mtime[63:32];
                else
                    prdata <= 32'h0;
            end
        end
    end
endmodule

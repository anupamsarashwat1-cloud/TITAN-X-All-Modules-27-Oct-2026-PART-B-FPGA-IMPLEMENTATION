// SPDX-License-Identifier: Apache-2.0
// TITAN-X SoC — AXI Read-Only Boot ROM
// Phase 5: Minimal stub with NOP sled + UART write sequence
`timescale 1ns/1ps
module axi_rom #(
    parameter HEX_FILE = "",
    parameter DEPTH    = 1024,
    parameter AW       = 40,
    parameter DW       = 64,
    parameter IDW      = 4
) (
    input  wire         clk,
    input  wire         rst_n,
    // AXI4 Read-Only Slave
    input  wire         s_arvalid,
    output reg          s_arready,
    input  wire [AW-1:0] s_araddr,
    input  wire [IDW-1:0] s_arid,
    output reg          s_rvalid,
    input  wire         s_rready,
    output reg  [DW-1:0] s_rdata,
    output wire [1:0]   s_rresp,
    output reg          s_rlast,
    output reg  [IDW-1:0] s_rid
);
    // Minimal RISC-V RV64I boot code (NOP sled so CPU fetches cleanly)
    // Real firmware would be loaded via HEX_FILE parameter
    reg [DW-1:0] rom [0:DEPTH-1];
    integer i;
    reg [8*256-1:0] hexfile_arg;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            rom[i] = 64'h0000_0013_0000_0013; // NOP NOP (ADDI x0,x0,0 packed 2x)
        if ($value$plusargs("hex=%s", hexfile_arg))
            $readmemh(hexfile_arg, rom);            // runtime: +hex=path/to/firmware.hex
        else if (HEX_FILE != "")
            $readmemh(HEX_FILE, rom);
    end

    assign s_rresp = 2'b00; // OKAY

    reg [AW-1:0] rd_addr;
    reg [IDW-1:0] rd_id;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_arready <= 1'b1;
            s_rvalid  <= 1'b0;
            s_rlast   <= 1'b0;
            s_rdata   <= {DW{1'b0}};
            s_rid     <= {IDW{1'b0}};
        end else begin
            if (s_arvalid && s_arready) begin
                rd_addr   <= s_araddr;
                rd_id     <= s_arid;
                s_arready <= 1'b0;
                s_rvalid  <= 1'b1;
                s_rlast   <= 1'b1;
                s_rdata   <= s_araddr[2] ? {rom[s_araddr[AW-1:3] & (DEPTH-1)][63:32], rom[s_araddr[AW-1:3] & (DEPTH-1)][63:32]} :
                                           rom[s_araddr[AW-1:3] & (DEPTH-1)];
                s_rid     <= s_arid;
            end else if (s_rvalid && s_rready) begin
                s_rvalid  <= 1'b0;
                s_rlast   <= 1'b0;
                s_arready <= 1'b1;
            end
        end
    end
endmodule

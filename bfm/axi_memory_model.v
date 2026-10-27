// SPDX-License-Identifier: Apache-2.0
// SMVDU TITAN-X — AXI4 Memory Model BFM
// Simple read/write AXI4 slave with 64KB backing store
// Used by: vdma, gem_ethernet, usb_otg, integration tests

`timescale 1ns/1ps

module axi_memory_model #(
    parameter AW  = 40,
    parameter DW  = 64,
    parameter IDW = 4,
    parameter MEM_DEPTH = 8192  // 8K x 64-bit = 64KB
) (
    input  wire        clk,
    input  wire        rst_n,

    // AXI4 Slave Interface
    input  wire        s_awvalid,
    output reg         s_awready,
    input  wire [AW-1:0] s_awaddr,
    input  wire [IDW-1:0] s_awid,
    input  wire [7:0]  s_awlen,
    input  wire [2:0]  s_awsize,

    input  wire        s_wvalid,
    output reg         s_wready,
    input  wire [DW-1:0] s_wdata,
    input  wire [DW/8-1:0] s_wstrb,
    input  wire        s_wlast,

    output reg         s_bvalid,
    input  wire        s_bready,
    output wire [1:0]  s_bresp,
    output reg  [IDW-1:0] s_bid,

    input  wire        s_arvalid,
    output reg         s_arready,
    input  wire [AW-1:0] s_araddr,
    input  wire [IDW-1:0] s_arid,
    input  wire [7:0]  s_arlen,
    input  wire [2:0]  s_arsize,

    output reg         s_rvalid,
    input  wire        s_rready,
    output reg  [DW-1:0] s_rdata,
    output wire [1:0]  s_rresp,
    output reg         s_rlast,
    output reg  [IDW-1:0] s_rid
);

    assign s_bresp = 2'b00;  // OKAY
    assign s_rresp = 2'b00;

    // Backing memory
    reg [DW-1:0] mem [0:MEM_DEPTH-1];

    // Write state
    reg [AW-1:0] wr_addr;
    reg [IDW-1:0] wr_id;
    reg [7:0] wr_len, wr_cnt;
    reg wr_active;

    // Read state
    reg [AW-1:0] rd_addr;
    reg [IDW-1:0] rd_id;
    reg [7:0] rd_len, rd_cnt;
    reg rd_active;

    integer idx;

    // Initialize memory
    initial begin
        for (idx = 0; idx < MEM_DEPTH; idx = idx + 1)
            mem[idx] = {DW{1'b0}};
    end

    wire [12:0] wr_mem_idx = wr_addr[15:3];
    wire [12:0] rd_mem_idx = rd_addr[15:3];

    // Write channel
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_awready <= 1'b1;
            s_wready  <= 1'b0;
            s_bvalid  <= 1'b0;
            wr_active <= 1'b0;
        end else begin
            // B handshake
            if (s_bvalid && s_bready)
                s_bvalid <= 1'b0;

            if (!wr_active) begin
                s_awready <= 1'b1;
                if (s_awvalid && s_awready) begin
                    wr_addr   <= s_awaddr;
                    wr_id     <= s_awid;
                    wr_len    <= s_awlen;
                    wr_cnt    <= 8'h0;
                    s_awready <= 1'b0;
                    s_wready  <= 1'b1;
                    wr_active <= 1'b1;
                end
            end else begin
                if (s_wvalid && s_wready) begin
                    // Byte-lane write with strobe
                    if (wr_mem_idx < MEM_DEPTH) begin
                        if (s_wstrb[0]) mem[wr_mem_idx][ 7: 0] <= s_wdata[ 7: 0];
                        if (s_wstrb[1]) mem[wr_mem_idx][15: 8] <= s_wdata[15: 8];
                        if (s_wstrb[2]) mem[wr_mem_idx][23:16] <= s_wdata[23:16];
                        if (s_wstrb[3]) mem[wr_mem_idx][31:24] <= s_wdata[31:24];
                        if (s_wstrb[4]) mem[wr_mem_idx][39:32] <= s_wdata[39:32];
                        if (s_wstrb[5]) mem[wr_mem_idx][47:40] <= s_wdata[47:40];
                        if (s_wstrb[6]) mem[wr_mem_idx][55:48] <= s_wdata[55:48];
                        if (s_wstrb[7]) mem[wr_mem_idx][63:56] <= s_wdata[63:56];
                    end
                    wr_addr <= wr_addr + (1 << 3);
                    wr_cnt  <= wr_cnt + 1;

                    if (s_wlast || wr_cnt == wr_len) begin
                        s_wready  <= 1'b0;
                        s_bvalid  <= 1'b1;
                        s_bid     <= wr_id;
                        wr_active <= 1'b0;
                    end
                end
            end
        end
    end

    // Read channel
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_arready <= 1'b1;
            s_rvalid  <= 1'b0;
            s_rlast   <= 1'b0;
            rd_active <= 1'b0;
        end else begin
            if (!rd_active) begin
                s_arready <= 1'b1;
                s_rvalid  <= 1'b0;
                if (s_arvalid && s_arready) begin
                    rd_addr   <= s_araddr;
                    rd_id     <= s_arid;
                    rd_len    <= s_arlen;
                    rd_cnt    <= 8'h0;
                    s_arready <= 1'b0;
                    rd_active <= 1'b1;
                end
            end else begin
                if (!s_rvalid || s_rready) begin
                    s_rvalid <= 1'b1;
                    s_rdata  <= (rd_mem_idx < MEM_DEPTH) ? mem[rd_mem_idx] : {DW{1'b0}};
                    s_rid    <= rd_id;
                    s_rlast  <= (rd_cnt == rd_len);
                    rd_addr  <= rd_addr + (1 << 3);

                    if (rd_cnt == rd_len) begin
                        rd_active <= 1'b0;
                        rd_cnt    <= 8'h0;
                    end else begin
                        rd_cnt <= rd_cnt + 1;
                    end
                end
            end
        end
    end

endmodule

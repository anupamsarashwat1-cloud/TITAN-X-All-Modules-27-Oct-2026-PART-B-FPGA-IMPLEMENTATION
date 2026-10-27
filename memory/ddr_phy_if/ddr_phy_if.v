// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — DDR4 PHY Interface
// Iteration 4: deterministic in-model storage + real DDR-style pin activity.
//
// Functional truth (read/write DATA) lives in an internal array indexed by
// the full DDR4 address map {BG, BA, row, col}, so results never depend on
// tristate-pin sampling or clock-phase luck (the failure mode that made every
// read return zero in Iteration 3). The DDR CK/DQS/DQ pins still toggle
// realistically for waveforms; bfm/ddr4_sdram_bfm.v may listen on them but is
// no longer required for correct data.
//
// Modeled capacity (sim): 2-bit BG × 8 banks × 512 rows × 256 cols × 64-bit
// = 32 MB window starting at row 0. Addresses beyond the modeled row/col
// range fold — a documented sim-model limit, not an RTL claim.
`timescale 1ns/1ps
module ddr_phy_if #(
    parameter ROW_BITS  = 9,    // modeled rows  (controller uses up to 16)
    parameter COL_BITS  = 8     // modeled cols  (controller uses 10)
) (
    input  wire        clk,        // System clock (2x DDR rate)
    input  wire        rst_n,
    // DFI-style command interface
    input  wire        dfi_ck_en,
    input  wire        dfi_cs_n,
    input  wire        dfi_ras_n,
    input  wire        dfi_cas_n,
    input  wire        dfi_we_n,
    input  wire [1:0]  dfi_bg,      // NEW: bank group (fixes [16:15] aliasing)
    input  wire [2:0]  dfi_bank,
    input  wire [15:0] dfi_addr,    // row during ACT, col during CAS
    input  wire        dfi_wrdata_valid,
    input  wire [63:0] dfi_wrdata,
    input  wire [7:0]  dfi_wrdata_mask,
    // DFI read data back
    output reg  [63:0] dfi_rddata,
    output reg         dfi_rddata_valid,
    // Physical DDR pins
    output reg         ddr_ck_p,
    output reg         ddr_ck_n,
    output wire        ddr_cke,
    output wire        ddr_cs_n,
    output wire        ddr_ras_n,
    output wire        ddr_cas_n,
    output wire        ddr_we_n,
    output wire [2:0]  ddr_ba,
    output wire [1:0]  ddr_bg,
    output wire [15:0] ddr_addr,
    output wire [7:0]  ddr_dm,
    inout  wire [63:0] ddr_dq,
    inout  wire [7:0]  ddr_dqs_p,
    inout  wire [7:0]  ddr_dqs_n
);
    // -------------------------------------------------------
    // DDR clock: toggles when enabled (pin-level realism only)
    // -------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ddr_ck_p <= 1'b0;
            ddr_ck_n <= 1'b1;
        end else if (dfi_ck_en) begin
            ddr_ck_p <= ~ddr_ck_p;
            ddr_ck_n <= ~ddr_ck_n;
        end else begin
            ddr_ck_p <= 1'b0;
            ddr_ck_n <= 1'b0;
        end
    end

    // Command pins: direct from DFI
    assign ddr_cke   = dfi_ck_en;
    assign ddr_cs_n  = dfi_cs_n;
    assign ddr_ras_n = dfi_ras_n;
    assign ddr_cas_n = dfi_cas_n;
    assign ddr_we_n  = dfi_we_n;
    assign ddr_ba    = dfi_bank;
    assign ddr_bg    = dfi_bg;
    assign ddr_addr  = dfi_addr;
    assign ddr_dm    = dfi_wrdata_valid ? dfi_wrdata_mask : 8'h00;

    // -------------------------------------------------------
    // In-model storage, indexed by the real DDR4 address map.
    // -------------------------------------------------------
    localparam DEPTH = (1 << (2 + 3 + ROW_BITS + COL_BITS));  // words of 64b

    reg [63:0] mem [0:DEPTH-1];
    integer mi;
    initial for (mi = 0; mi < DEPTH; mi = mi + 1) mem[mi] = 64'h0;

    // Open-row tracking inside the model: ACT selects row, PRE closes.
    reg [15:0] open_row  [0:31];   // {bg,bank} = 5 bits
    reg        row_open  [0:31];

    wire       cmd_act  = !dfi_cs_n && !dfi_ras_n &&  dfi_cas_n &&  dfi_we_n;
    wire       cmd_rd   = !dfi_cs_n &&  dfi_ras_n && !dfi_cas_n &&  dfi_we_n;
    wire       cmd_wr   = !dfi_cs_n &&  dfi_ras_n && !dfi_cas_n && !dfi_we_n;
    wire       cmd_pre  = !dfi_cs_n && !dfi_ras_n &&  dfi_cas_n && !dfi_we_n;
    wire [4:0] ba_full  = {dfi_bg, dfi_bank};
    wire [ROW_BITS-1:0] row_idx = open_row[ba_full][ROW_BITS-1:0];
    wire [COL_BITS-1:0] col_idx = dfi_addr[COL_BITS-1:0];

    // -------------------------------------------------------
    // Write path: latch write data at CAS-WR, commit immediately.
    // DQ is also driven for 4 cycles for pin-level realism.
    // -------------------------------------------------------
    reg [63:0] wr_hold;
    reg [2:0]  wr_drive_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_drive_cnt <= 3'd0;
            wr_hold      <= 64'h0;
        end else begin
            if (cmd_wr && dfi_wrdata_valid) begin
                wr_hold      <= dfi_wrdata;
                wr_drive_cnt <= 3'd4;
                if (row_open[ba_full]) begin
                    mem[{ba_full, row_idx, col_idx}] <= dfi_wrdata;
                    `ifdef TB_PHY_TRACE
                    $display("[PHY] %0t WR idx=%05h d=%h (bg=%0d ba=%0d row=%0d col=%0d)",
                             $time, {ba_full, row_idx, col_idx}, dfi_wrdata,
                             dfi_bg, dfi_bank, open_row[ba_full], col_idx);
                    `endif
                end
                // write to closed row is dropped — scheduler always ACTs first
            end else if (wr_drive_cnt != 0)
                wr_drive_cnt <= wr_drive_cnt - 3'd1;
        end
    end

    // -------------------------------------------------------
    // Read path: fixed 2-cycle CAS latency from the internal array —
    // deterministic by construction, no bus sampling. rddata_valid stays
    // asserted with stable data until the next DFI command arrives, so a
    // consumer that starts listening a few cycles after CAS still sees it.
    // -------------------------------------------------------
    reg [1:0] rd_pipe;
    reg [63:0] rd_data_q;
    wire any_cmd = cmd_act | cmd_rd | cmd_wr | cmd_pre;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_pipe          <= 2'b00;
            rd_data_q        <= 64'h0;
            dfi_rddata       <= 64'h0;
            dfi_rddata_valid <= 1'b0;
        end else begin
            rd_pipe          <= {rd_pipe[0], 1'b0};
            if (any_cmd)
                dfi_rddata_valid <= 1'b0;       // new command retires old data
            else if (rd_pipe[1])
                dfi_rddata_valid <= 1'b1;       // set, then held
            if (cmd_rd) begin
                rd_data_q <= row_open[ba_full]
                           ? mem[{ba_full, open_row[ba_full][ROW_BITS-1:0], col_idx}]
                           : 64'h0;   // closed-row read returns 0 (model limit)
`ifdef TB_PHY_TRACE
                $display("[PHY] %0t RD idx=%05h d=%h (bg=%0d ba=%0d row=%0d col=%0d)",
                         $time,
                         {ba_full, open_row[ba_full][ROW_BITS-1:0], col_idx},
                         row_open[ba_full]
                           ? mem[{ba_full, open_row[ba_full][ROW_BITS-1:0], col_idx}]
                           : 64'h0,
                         dfi_bg, dfi_bank, open_row[ba_full], col_idx);
`endif
                rd_pipe <= 2'b01;
            end
            if (rd_pipe[0]) dfi_rddata <= rd_data_q;
        end
    end

    // -------------------------------------------------------
    // ACT/PRE bookkeeping (mirrors scheduler policy)
    // -------------------------------------------------------
    integer pi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (pi = 0; pi < 32; pi = pi + 1) begin
                row_open[pi] <= 1'b0;
                open_row[pi] <= 16'h0;
            end
        end else begin
            if (cmd_act && dfi_ck_en) begin
                open_row[ba_full] <= dfi_addr;
                row_open[ba_full] <= 1'b1;
            end
            if (cmd_pre && dfi_ck_en) begin
                if (dfi_addr[10])
                    for (pi = 0; pi < 32; pi = pi + 1) row_open[pi] <= 1'b0;
                else
                    row_open[ba_full] <= 1'b0;
            end
        end
    end

    // Pin-level DQ/DQS echo (decorative — data truth is internal)
    assign ddr_dq    = (wr_drive_cnt != 0) ? wr_hold : 64'bz;
    assign ddr_dqs_p = (wr_drive_cnt != 0) ? {8{ddr_ck_p}} : 8'bz;
    assign ddr_dqs_n = (wr_drive_cnt != 0) ? {8{ddr_ck_n}} : 8'bz;

endmodule

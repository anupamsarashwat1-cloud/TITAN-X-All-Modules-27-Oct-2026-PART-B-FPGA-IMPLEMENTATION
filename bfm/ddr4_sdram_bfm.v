// SPDX-License-Identifier: Apache-2.0
// SMVDU TITAN-X — DDR4 SDRAM BFM
// Simple DDR4 behavioral model that responds to activate/read/write commands
// Used by: ddr_ctrl_top, ddr_phy_if

`timescale 1ns/1ps

module ddr4_sdram_bfm #(
    parameter ROWS = 1024,
    parameter COLS = 64,
    parameter BANKS = 8
) (
    input  wire        ddr_ck_p,
    input  wire        ddr_ck_n,
    input  wire        ddr_cke,
    input  wire        ddr_cs_n,
    input  wire        ddr_ras_n,
    input  wire        ddr_cas_n,
    input  wire        ddr_we_n,
    input  wire        ddr_act_n,
    input  wire        ddr_reset_n,
    input  wire        ddr_odt,
    input  wire [15:0] ddr_addr,
    input  wire [2:0]  ddr_ba,
    input  wire [1:0]  ddr_bg,
    inout  wire [63:0] ddr_dq,
    inout  wire [7:0]  ddr_dqs_p,
    inout  wire [7:0]  ddr_dqs_n
);

    // Internal memory array (simplified: bank × row × 8 words of 64-bit)
    reg [63:0] mem_array [0:BANKS-1][0:ROWS-1][0:COLS-1];

    // State per bank
    reg [15:0] active_row [0:BANKS-1];
    reg        row_open [0:BANKS-1];

    // Read data driving
    reg [63:0] rd_data;
    reg        rd_valid;
    reg [3:0]  rd_delay;
    reg        drive_dq;

    assign ddr_dq = drive_dq ? rd_data : 64'hzzzz_zzzz_zzzz_zzzz;
    assign ddr_dqs_p = drive_dq ? {8{ddr_ck_p}} : 8'hzz;
    assign ddr_dqs_n = drive_dq ? {8{ddr_ck_n}} : 8'hzz;

    // Command decode — matches ddr_phy_if RAS/CAS/WE outputs (no act_n)
    // ACT  = CS_n=0 RAS=0 CAS=1 WE=1 (act_n not used by this PHY)
    // READ = CS_n=0 RAS=1 CAS=0 WE=1
    // WR   = CS_n=0 RAS=1 CAS=0 WE=0
    // PRE  = CS_n=0 RAS=0 CAS=1 WE=0
    wire cmd_activate = !ddr_cs_n && !ddr_ras_n &&  ddr_cas_n &&  ddr_we_n;
    wire cmd_read     = !ddr_cs_n &&  ddr_ras_n && !ddr_cas_n &&  ddr_we_n;
    wire cmd_write    = !ddr_cs_n &&  ddr_ras_n && !ddr_cas_n && !ddr_we_n;
    wire cmd_pre      = !ddr_cs_n && !ddr_ras_n &&  ddr_cas_n && !ddr_we_n;

    wire [2:0] bank = ddr_ba;
    integer i, j, k;

    // Initialize
    initial begin
        rd_valid = 0;
        drive_dq = 0;
        rd_delay = 0;
        for (i = 0; i < BANKS; i = i + 1) begin
            row_open[i] = 1'b0;
            active_row[i] = 16'h0;
            for (j = 0; j < ROWS; j = j + 1)
                for (k = 0; k < COLS; k = k + 1)
                    mem_array[i][j][k] = 64'h0;
        end
    end

    // Read latency pipeline (CL simulation)
    reg [63:0] rd_pipe [0:7];
    reg [7:0]  rd_pipe_valid;
    
    always @(posedge ddr_ck_p) begin
        if (!ddr_reset_n) begin
            rd_pipe_valid <= 8'h0;
            drive_dq <= 1'b0;
        end else begin
            // Shift pipeline
            rd_pipe_valid <= {rd_pipe_valid[6:0], 1'b0};
            rd_pipe[7] <= rd_pipe[6];
            rd_pipe[6] <= rd_pipe[5];
            rd_pipe[5] <= rd_pipe[4];
            rd_pipe[4] <= rd_pipe[3];
            rd_pipe[3] <= rd_pipe[2];
            rd_pipe[2] <= rd_pipe[1];
            rd_pipe[1] <= rd_pipe[0];

            // Drive DQ on pipeline output (CL=2 — matches PHY 2-cycle capture)
            if (rd_pipe_valid[1]) begin
                rd_data  <= rd_pipe[1];
                drive_dq <= 1'b1;
            end else begin
                drive_dq <= 1'b0;
            end
        end
    end

    always @(posedge ddr_ck_p) begin
        if (ddr_cke && !ddr_cs_n) begin
            // ACTIVATE
            if (cmd_activate) begin
                active_row[bank] <= ddr_addr;
                row_open[bank]   <= 1'b1;
                $display("[DDR4_BFM] ACTIVATE bank=%0d row=0x%04h", bank, ddr_addr);
            end

            // READ — load pipeline; if row not open auto-open for simulation
            if (cmd_read) begin
                if (!row_open[bank]) begin
                    row_open[bank] <= 1'b1;
                end
                rd_pipe[0] <= mem_array[bank][active_row[bank]][ddr_addr[5:0]];
                rd_pipe_valid[0] <= 1'b1;
                $display("[DDR4_BFM] READ bank=%0d col=%0d data=0x%016h",
                    bank, ddr_addr[5:0],
                    mem_array[bank][active_row[bank]][ddr_addr[5:0]]);
            end

            // WRITE — PHY drives ddr_dq on same cycle as CAS-WR (dfi_wrdata_valid=1)
            if (cmd_write) begin
                if (!row_open[bank]) begin
                    active_row[bank] <= ddr_addr[15:0];
                    row_open[bank]   <= 1'b1;
                end
                // Sample DQ now — PHY drives it this cycle via dfi_wrdata_valid
                if (ddr_dq !== 64'hzzzz_zzzz_zzzz_zzzz)
                    mem_array[bank][active_row[bank]][ddr_addr[5:0]] <= ddr_dq;
                $display("[DDR4_BFM] WRITE bank=%0d col=%0d data=0x%016h",
                    bank, ddr_addr[5:0], ddr_dq);
            end

            // PRECHARGE
            if (cmd_pre) begin
                if (ddr_addr[10]) begin
                    // Precharge all
                    for (i = 0; i < BANKS; i = i + 1)
                        row_open[i] <= 1'b0;
                    $display("[DDR4_BFM] PRECHARGE ALL");
                end else begin
                    row_open[bank] <= 1'b0;
                    $display("[DDR4_BFM] PRECHARGE bank=%0d", bank);
                end
            end
        end
    end

endmodule

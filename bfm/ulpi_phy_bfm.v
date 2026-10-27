// SPDX-License-Identifier: Apache-2.0
// SMVDU TITAN-X — ULPI PHY BFM
// Simulates a USB PHY responding to ULPI register read/write commands
// Used by: usb_otg

`timescale 1ns/1ps

module ulpi_phy_bfm (
    input  wire        ulpi_clk,
    input  wire        rst_n,

    // ULPI Interface (directly connects to usb_otg)
    inout  wire [7:0]  ulpi_data,
    output reg         ulpi_dir,
    output reg         ulpi_nxt,
    input  wire        ulpi_stp,
    input  wire        ulpi_reset
);

    reg [7:0] data_out;
    reg       drive_data;

    // PHY register file (16 registers)
    reg [7:0] phy_regs [0:15];

    assign ulpi_data = drive_data ? data_out : 8'hzz;

    // State machine
    localparam IDLE       = 3'd0;
    localparam RX_CMD     = 3'd1;
    localparam REG_WRITE  = 3'd2;
    localparam REG_READ   = 3'd3;
    localparam TX_DATA    = 3'd4;

    reg [2:0] state;
    reg [3:0] reg_addr;
    reg [7:0] cmd_byte;

    integer i;
    initial begin
        for (i = 0; i < 16; i = i + 1)
            phy_regs[i] = 8'h00;
        // PHY vendor ID / product ID defaults
        phy_regs[0] = 8'h24;  // Vendor ID low
        phy_regs[1] = 8'h04;  // Vendor ID high
        phy_regs[2] = 8'h04;  // Product ID low
        phy_regs[3] = 8'h00;  // Product ID high
    end

    always @(posedge ulpi_clk or negedge rst_n) begin
        if (!rst_n || ulpi_reset) begin
            state      <= IDLE;
            ulpi_dir   <= 1'b0;  // PHY not driving
            ulpi_nxt   <= 1'b0;
            drive_data <= 1'b0;
            data_out   <= 8'h00;
        end else begin
            case (state)
                IDLE: begin
                    ulpi_dir   <= 1'b0;
                    ulpi_nxt   <= 1'b0;
                    drive_data <= 1'b0;

                    if (!ulpi_dir && ulpi_data !== 8'hzz && ulpi_data !== 8'h00) begin
                        cmd_byte <= ulpi_data;
                        // Decode ULPI command
                        if (ulpi_data[7:6] == 2'b10) begin
                            // RegWrite: CMD[7:6]=10, addr=[5:2], immediate data in next cycle
                            reg_addr <= ulpi_data[5:2];
                            ulpi_nxt <= 1'b1;
                            state    <= REG_WRITE;
                        end else if (ulpi_data[7:6] == 2'b11) begin
                            // RegRead: CMD[7:6]=11, addr=[5:2]
                            reg_addr <= ulpi_data[5:2];
                            state    <= REG_READ;
                        end else begin
                            // TX command — accept data
                            ulpi_nxt <= 1'b1;
                            state    <= TX_DATA;
                        end
                    end
                end

                REG_WRITE: begin
                    // Link is driving data byte on ulpi_data
                    if (ulpi_nxt) begin
                        phy_regs[reg_addr] <= ulpi_data;
                        ulpi_nxt <= 1'b0;
                        state    <= IDLE;
                        $display("[ULPI_BFM] REG_WRITE: addr=%0d data=0x%02h", reg_addr, ulpi_data);
                    end
                end

                REG_READ: begin
                    // PHY drives data bus with register value
                    ulpi_dir   <= 1'b1;
                    drive_data <= 1'b1;
                    data_out   <= phy_regs[reg_addr];
                    ulpi_nxt   <= 1'b1;
                    $display("[ULPI_BFM] REG_READ: addr=%0d data=0x%02h", reg_addr, phy_regs[reg_addr]);
                    state <= IDLE;
                end

                TX_DATA: begin
                    // Accept TX data until STP
                    if (ulpi_stp) begin
                        ulpi_nxt <= 1'b0;
                        state    <= IDLE;
                        $display("[ULPI_BFM] TX complete (STP received)");
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

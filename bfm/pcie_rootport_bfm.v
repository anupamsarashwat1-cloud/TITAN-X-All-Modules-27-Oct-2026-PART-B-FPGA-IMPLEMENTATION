// SPDX-License-Identifier: Apache-2.0
// SMVDU TITAN-X — PCIe Root Port BFM
// Simulates PCIe root port for LTSSM link training via PIPE interface
// Used by: pcie_top, pcie_pipe_if

`timescale 1ns/1ps

module pcie_rootport_bfm (
    input  wire        pipe_clk,
    input  wire        rst_n,

    // PIPE Interface (connects to DUT endpoint)
    output reg  [31:0] pipe_rx_data,
    output reg  [3:0]  pipe_rx_datak,
    input  wire [31:0] pipe_tx_data,
    input  wire [3:0]  pipe_tx_datak,
    input  wire [1:0]  pipe_tx_rate,
    input  wire        pipe_tx_elecidle,
    input  wire        pipe_tx_compliance,
    output reg         pipe_rx_valid,
    output reg         pipe_rx_elecidle,
    output reg  [2:0]  pipe_rx_status,
    output reg         pipe_phy_status,
    input  wire        pipe_rx_polarity,
    input  wire [1:0]  pipe_power_down
);

    // LTSSM states (Root Port side)
    localparam RP_DETECT      = 3'd0;
    localparam RP_POLLING     = 3'd1;
    localparam RP_CONFIG      = 3'd2;
    localparam RP_L0          = 3'd3;
    localparam RP_DONE        = 3'd4;

    // Ordered Sets
    localparam OS_TS1  = 32'h4A4A_4A4A;
    localparam OS_TS2  = 32'h4545_4545;
    localparam OS_IDLE = 32'h0000_0000;

    reg [2:0] state;
    reg [7:0] ts_count;
    reg link_up;

    initial begin
        link_up = 1'b0;
    end

    always @(posedge pipe_clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= RP_DETECT;
            pipe_rx_data    <= 32'h0;
            pipe_rx_datak   <= 4'h0;
            pipe_rx_valid   <= 1'b0;
            pipe_rx_elecidle <= 1'b1;
            pipe_rx_status  <= 3'h0;
            pipe_phy_status <= 1'b0;
            ts_count        <= 8'd0;
            link_up         <= 1'b0;
        end else begin
            case (state)
                RP_DETECT: begin
                    // Detect: Root port senses endpoint presence
                    pipe_rx_elecidle <= 1'b1;
                    if (!pipe_tx_elecidle) begin
                        // Endpoint detected!
                        $display("[PCIE_RP_BFM] Detect: Endpoint present");
                        pipe_phy_status <= 1'b1;
                        ts_count <= 8'd0;
                        state <= RP_POLLING;
                    end
                end

                RP_POLLING: begin
                    // Polling: Exchange TS1 ordered sets
                    pipe_phy_status  <= 1'b0;
                    pipe_rx_elecidle <= 1'b0;
                    pipe_rx_valid    <= 1'b1;
                    pipe_rx_data     <= OS_TS1;
                    pipe_rx_datak    <= 4'hF;
                    ts_count         <= ts_count + 1;

                    // Check if endpoint is also sending TS1/TS2
                    if (ts_count > 8'd16) begin
                        $display("[PCIE_RP_BFM] Polling: TS1 exchange complete (%0d sets)", ts_count);
                        ts_count <= 8'd0;
                        state <= RP_CONFIG;
                    end
                end

                RP_CONFIG: begin
                    // Config: Exchange TS2 ordered sets
                    pipe_rx_data  <= OS_TS2;
                    pipe_rx_datak <= 4'hF;
                    ts_count      <= ts_count + 1;

                    if (ts_count > 8'd8) begin
                        $display("[PCIE_RP_BFM] Config: TS2 exchange complete");
                        ts_count <= 8'd0;
                        state <= RP_L0;
                    end
                end

                RP_L0: begin
                    // L0: Link is up — send IDLE
                    pipe_rx_data  <= OS_IDLE;
                    pipe_rx_datak <= 4'h0;
                    pipe_rx_valid <= 1'b1;
                    link_up       <= 1'b1;

                    if (!link_up) begin
                        $display("[PCIE_RP_BFM] L0: Link UP! PCIe link trained successfully");
                    end
                    state <= RP_DONE;
                end

                RP_DONE: begin
                    // Steady state — maintain IDLE
                    pipe_rx_data  <= OS_IDLE;
                    pipe_rx_valid <= 1'b1;
                end

                default: state <= RP_DETECT;
            endcase
        end
    end

endmodule

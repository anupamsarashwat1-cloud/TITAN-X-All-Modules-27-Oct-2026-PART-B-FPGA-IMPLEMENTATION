// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — PCIe PIPE PHY Interface
// Iteration 3: PCIe Gen2 (5 GT/s) x4 lanes
// Standard PIPE 3.0 compatible interface mapping
`timescale 1ns/1ps

module pcie_pipe_if #(
    parameter LANES = 4
) (
    input  wire pclk,          // PIPE Clock (250MHz for Gen2 16-bit or 500MHz for 8-bit. We assume 250MHz 16-bit)
    input  wire reset_n,

    // Link Layer Interface (Data & Control)
    input  wire [(LANES*16)-1:0] tx_data,
    input  wire [(LANES*2)-1:0]  tx_datak,
    output wire [(LANES*16)-1:0] rx_data,
    output wire [(LANES*2)-1:0]  rx_datak,
    output wire [LANES-1:0]      rx_valid,
    output wire [LANES-1:0]      rx_elecidle,
    output wire [(LANES*3)-1:0]  rx_status,

    // LTSSM Control
    input  wire [1:0]  tx_rate,           // 00=2.5 GT/s, 01=5.0 GT/s
    input  wire [1:0]  power_down [0:LANES-1], // P0, P0s, P1, P2
    input  wire [LANES-1:0] tx_elecidle,
    input  wire [LANES-1:0] tx_compliance,
    input  wire [LANES-1:0] rx_polarity,

    // Physical PIPE Interface to Hard PHY (e.g., SerDes)
    output wire [(LANES*16)-1:0] pipe_tx_data,
    output wire [(LANES*2)-1:0]  pipe_tx_datak,
    input  wire [(LANES*16)-1:0] pipe_rx_data,
    input  wire [(LANES*2)-1:0]  pipe_rx_datak,
    
    output wire [1:0]  pipe_tx_rate,
    output wire [LANES-1:0] pipe_tx_elecidle,
    output wire [LANES-1:0] pipe_tx_compliance,
    output wire [LANES-1:0] pipe_rx_polarity,
    output wire [(LANES*2)-1:0] pipe_power_down,

    input  wire [LANES-1:0] pipe_rx_valid,
    input  wire [LANES-1:0] pipe_rx_elecidle,
    input  wire [(LANES*3)-1:0] pipe_rx_status,
    input  wire [LANES-1:0] pipe_phy_status
);

    // Simplistic passthrough for simulation/integration of the MAC to a standard PHY
    // In physical implementation, clock crossing or deskew FIFOs may be needed here.
    
    assign pipe_tx_rate = tx_rate;
    
    genvar i;
    generate
        for (i = 0; i < LANES; i = i + 1) begin : pipe_lane_map
            // TX
            assign pipe_tx_data[i*16 +: 16] = tx_data[i*16 +: 16];
            assign pipe_tx_datak[i*2 +: 2]   = tx_datak[i*2 +: 2];
            assign pipe_tx_elecidle[i]       = tx_elecidle[i];
            assign pipe_tx_compliance[i]     = tx_compliance[i];
            assign pipe_rx_polarity[i]       = rx_polarity[i];
            assign pipe_power_down[i*2 +: 2] = power_down[i];
            
            // RX
            assign rx_data[i*16 +: 16] = pipe_rx_data[i*16 +: 16];
            assign rx_datak[i*2 +: 2]   = pipe_rx_datak[i*2 +: 2];
            assign rx_valid[i]          = pipe_rx_valid[i];
            assign rx_elecidle[i]       = pipe_rx_elecidle[i];
            assign rx_status[i*3 +: 3]  = pipe_rx_status[i*3 +: 3];
        end
    endgenerate

endmodule

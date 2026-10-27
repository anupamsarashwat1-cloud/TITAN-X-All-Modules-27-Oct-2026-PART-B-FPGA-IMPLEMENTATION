// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — QoS Controller
// Iteration 3: Dynamically adjusts AXI QoS signals based on bandwidth usage.
// Targets high-bandwidth masters (Video DMA, PCIe, Ethernet).
`timescale 1ns/1ps

module qos_controller #(
    parameter NM = 15, // Total masters
    parameter IDW = 4
) (
    input  wire clk,
    input  wire rst_n,

    // QoS configuration from APB interface (memory mapped registers)
    input  wire [3:0]   cfg_base_qos  [0:NM-1],
    input  wire [3:0]   cfg_boost_qos [0:NM-1],
    input  wire [15:0]  cfg_bw_limit  [0:NM-1], // Bandwidth threshold (transactions per window)
    input  wire [15:0]  cfg_time_win,           // Time window for measurement

    // AXI read/write valid signals to monitor bandwidth usage
    input  wire [NM-1:0] m_arvalid,
    input  wire [NM-1:0] m_arready,
    input  wire [NM-1:0] m_awvalid,
    input  wire [NM-1:0] m_awready,

    // Output QoS signals to replace the default AXI QoS
    output wire [3:0]    m_arqos [0:NM-1],
    output wire [3:0]    m_awqos [0:NM-1]
);

    reg [15:0] time_cnt;
    reg [15:0] bw_cnt [0:NM-1];
    reg [3:0]  cur_arqos [0:NM-1];
    reg [3:0]  cur_awqos [0:NM-1];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            time_cnt <= 16'h0;
            for (i = 0; i < NM; i = i + 1) begin
                bw_cnt[i] <= 16'h0;
                cur_arqos[i] <= 4'h0;
                cur_awqos[i] <= 4'h0;
            end
        end else begin
            // Time window counter
            if (time_cnt >= cfg_time_win) begin
                time_cnt <= 16'h0;
                // Evaluate QoS at the end of window
                for (i = 0; i < NM; i = i + 1) begin
                    if (bw_cnt[i] > cfg_bw_limit[i]) begin
                        // Exceeded bandwidth: lower QoS to base
                        cur_arqos[i] <= cfg_base_qos[i];
                        cur_awqos[i] <= cfg_base_qos[i];
                    end else begin
                        // Within limits: boost QoS
                        cur_arqos[i] <= cfg_boost_qos[i];
                        cur_awqos[i] <= cfg_boost_qos[i];
                    end
                    // Reset BW counter for next window
                    bw_cnt[i] <= 16'h0;
                end
            end else begin
                time_cnt <= time_cnt + 16'h1;
                // Accumulate bandwidth (count accepted transactions)
                for (i = 0; i < NM; i = i + 1) begin
                    if (m_arvalid[i] && m_arready[i]) bw_cnt[i] <= bw_cnt[i] + 16'h1;
                    if (m_awvalid[i] && m_awready[i]) bw_cnt[i] <= bw_cnt[i] + 16'h1;
                end
            end
        end
    end

    // Assign outputs
    genvar g;
    generate
        for (g = 0; g < NM; g = g + 1) begin : gen_qos_out
            assign m_arqos[g] = cur_arqos[g];
            assign m_awqos[g] = cur_awqos[g];
        end
    endgenerate

endmodule

// SPDX-License-Identifier: Apache-2.0
// SMVDU TITAN-X — GMII Frame Generator BFM
// Generates valid Ethernet frames with correct preamble, SFD, and FCS
// Used by: gem_ethernet

`timescale 1ns/1ps

module gmii_frame_gen (
    input  wire        clk_125mhz,
    input  wire        rst_n,

    // GMII TX (to DUT rx port)
    output reg  [7:0]  gmii_rxd,
    output reg         gmii_rx_dv,
    output reg         gmii_rx_er,
    output reg         gmii_crs,
    output reg         gmii_col,

    // Control
    input  wire        send_frame,
    output reg         frame_done
);

    // CRC-32 for Ethernet FCS
    reg [31:0] crc;
    reg [31:0] crc_next;
    integer byte_idx;

    // Frame data storage
    reg [7:0] frame_data [0:127];
    integer frame_len;

    // State
    localparam IDLE     = 3'd0;
    localparam PREAMBLE = 3'd1;
    localparam SFD      = 3'd2;
    localparam PAYLOAD  = 3'd3;
    localparam FCS      = 3'd4;
    localparam IFG      = 3'd5;

    reg [2:0] state;
    reg [3:0] preamble_cnt;
    reg [1:0] fcs_cnt;
    reg [3:0] ifg_cnt;
    reg [31:0] fcs_value;

    // Build a test frame: Broadcast DA, Source SA, EtherType, Payload
    task build_test_frame;
        integer i;
        begin
            // Destination MAC: FF:FF:FF:FF:FF:FF (broadcast)
            frame_data[0]  = 8'hFF; frame_data[1]  = 8'hFF; frame_data[2]  = 8'hFF;
            frame_data[3]  = 8'hFF; frame_data[4]  = 8'hFF; frame_data[5]  = 8'hFF;
            // Source MAC: 00:11:22:33:44:55
            frame_data[6]  = 8'h00; frame_data[7]  = 8'h11; frame_data[8]  = 8'h22;
            frame_data[9]  = 8'h33; frame_data[10] = 8'h44; frame_data[11] = 8'h55;
            // EtherType: 0x0800 (IPv4)
            frame_data[12] = 8'h08; frame_data[13] = 8'h00;
            // Payload: 46 bytes (minimum Ethernet payload)
            for (i = 14; i < 60; i = i + 1)
                frame_data[i] = i[7:0];
            frame_len = 60;
        end
    endtask

    // Simple CRC-32 update (IEEE 802.3)
    function [31:0] crc32_byte;
        input [31:0] crc_in;
        input [7:0] data;
        integer j;
        reg [31:0] c;
        begin
            c = crc_in ^ {24'h0, data};
            for (j = 0; j < 8; j = j + 1) begin
                if (c[0])
                    c = (c >> 1) ^ 32'hEDB88320;
                else
                    c = c >> 1;
            end
            crc32_byte = c;
        end
    endfunction

    initial begin
        build_test_frame();
    end

    always @(posedge clk_125mhz or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            gmii_rxd    <= 8'h00;
            gmii_rx_dv  <= 1'b0;
            gmii_rx_er  <= 1'b0;
            gmii_crs    <= 1'b0;
            gmii_col    <= 1'b0;
            frame_done  <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    gmii_rx_dv <= 1'b0;
                    gmii_crs   <= 1'b0;
                    frame_done <= 1'b0;
                    if (send_frame) begin
                        preamble_cnt <= 4'd0;
                        state <= PREAMBLE;
                        gmii_crs <= 1'b1;
                        $display("[GMII_BFM] Sending Ethernet frame (%0d bytes)", frame_len);
                    end
                end

                PREAMBLE: begin
                    gmii_rx_dv <= 1'b1;
                    gmii_rxd   <= 8'h55;
                    preamble_cnt <= preamble_cnt + 1;
                    if (preamble_cnt == 4'd6)
                        state <= SFD;
                end

                SFD: begin
                    gmii_rxd <= 8'hD5;
                    byte_idx <= 0;
                    crc      <= 32'hFFFFFFFF;
                    state    <= PAYLOAD;
                end

                PAYLOAD: begin
                    gmii_rxd <= frame_data[byte_idx];
                    crc      <= crc32_byte(crc, frame_data[byte_idx]);
                    byte_idx <= byte_idx + 1;
                    if (byte_idx == frame_len - 1) begin
                        fcs_value <= ~crc32_byte(crc, frame_data[byte_idx]);
                        fcs_cnt   <= 2'd0;
                        state     <= FCS;
                    end
                end

                FCS: begin
                    case (fcs_cnt)
                        2'd0: gmii_rxd <= fcs_value[7:0];
                        2'd1: gmii_rxd <= fcs_value[15:8];
                        2'd2: gmii_rxd <= fcs_value[23:16];
                        2'd3: begin
                            gmii_rxd <= fcs_value[31:24];
                            state    <= IFG;
                            ifg_cnt  <= 4'd0;
                        end
                    endcase
                    fcs_cnt <= fcs_cnt + 1;
                end

                IFG: begin
                    gmii_rx_dv <= 1'b0;
                    gmii_crs   <= 1'b0;
                    gmii_rxd   <= 8'h00;
                    ifg_cnt    <= ifg_cnt + 1;
                    if (ifg_cnt == 4'd11) begin
                        frame_done <= 1'b1;
                        state <= IDLE;
                        $display("[GMII_BFM] Frame sent successfully");
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

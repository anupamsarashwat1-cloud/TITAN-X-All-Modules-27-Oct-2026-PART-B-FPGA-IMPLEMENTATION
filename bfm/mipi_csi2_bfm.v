// SPDX-License-Identifier: Apache-2.0
// SMVDU TITAN-X — MIPI CSI-2 BFM
// Generates MIPI CSI-2 packet structure on D-PHY lanes
// Used by: mipi_csi2_rx

`timescale 1ns/1ps

module mipi_csi2_bfm (
    input  wire        rst_n,
    input  wire        rxbyteclkhs,

    // D-PHY lane outputs (to DUT)
    output reg  [31:0] rxdatahs,
    output reg  [3:0]  rxvalidhs,
    output reg  [3:0]  rxactivehs,
    output reg  [3:0]  rxsyncbhs,
    output reg  [7:0]  rxdata_lp,

    // Control
    input  wire        send_frame,
    input  wire [15:0] frame_width,   // pixels per line
    input  wire [15:0] frame_height,  // lines per frame
    output reg         frame_done
);

    // CSI-2 Data Types
    localparam DT_FRAME_START = 6'h00;
    localparam DT_FRAME_END   = 6'h01;
    localparam DT_LINE_START  = 6'h02;
    localparam DT_LINE_END    = 6'h03;
    localparam DT_RAW10       = 6'h2B;

    // State machine
    localparam IDLE       = 4'd0;
    localparam SYNC       = 4'd1;
    localparam SHORT_PKT  = 4'd2;
    localparam LONG_HDR   = 4'd3;
    localparam LONG_DATA  = 4'd4;
    localparam LONG_FTR   = 4'd5;
    localparam LINE_GAP   = 4'd6;
    localparam FRAME_END  = 4'd7;
    localparam DONE       = 4'd8;

    reg [3:0] state;
    reg [15:0] line_cnt, pixel_cnt;
    reg [15:0] frame_num;
    reg [7:0]  gap_cnt;

    initial begin
        frame_num = 16'd0;
    end

    always @(posedge rxbyteclkhs or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            rxdatahs   <= 32'h0;
            rxvalidhs  <= 4'h0;
            rxactivehs <= 4'h0;
            rxsyncbhs  <= 4'h0;
            rxdata_lp  <= 8'h0;
            frame_done <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    rxvalidhs  <= 4'h0;
                    rxactivehs <= 4'h0;
                    frame_done <= 1'b0;
                    if (send_frame) begin
                        frame_num <= frame_num + 1;
                        line_cnt  <= 16'd0;
                        state     <= SYNC;
                        $display("[MIPI_BFM] Frame %0d start (%0dx%0d)", frame_num+1, frame_width, frame_height);
                    end
                end

                SYNC: begin
                    // D-PHY sync byte
                    rxactivehs <= 4'hF;
                    rxsyncbhs  <= 4'hF;
                    rxvalidhs  <= 4'hF;
                    rxdatahs   <= 32'hB8B8B8B8;  // Sync pattern
                    state      <= SHORT_PKT;
                end

                SHORT_PKT: begin
                    // Frame Start short packet: DT=0x00, WC=frame_num
                    rxsyncbhs <= 4'h0;
                    rxdatahs  <= {8'h00, frame_num[7:0], 2'b00, DT_FRAME_START, 8'h00};
                    rxvalidhs <= 4'hF;
                    state     <= LONG_HDR;
                end

                LONG_HDR: begin
                    // Line data header: DT=RAW10, WC=width*5/4
                    rxdatahs <= {8'h00, frame_width[7:0], 2'b00, DT_RAW10, 8'h00};
                    pixel_cnt <= 16'd0;
                    state     <= LONG_DATA;
                end

                LONG_DATA: begin
                    // Send pixel data (RAW10: 4 pixels in 5 bytes)
                    rxdatahs  <= {8'(pixel_cnt+3), 8'(pixel_cnt+2), 8'(pixel_cnt+1), 8'(pixel_cnt)};
                    rxvalidhs <= 4'hF;
                    pixel_cnt <= pixel_cnt + 4;
                    if (pixel_cnt + 4 >= frame_width) begin
                        line_cnt <= line_cnt + 1;
                        gap_cnt  <= 8'd0;
                        state    <= LINE_GAP;
                    end
                end

                LINE_GAP: begin
                    rxvalidhs <= 4'h0;
                    gap_cnt   <= gap_cnt + 1;
                    if (gap_cnt == 8'd3) begin
                        if (line_cnt >= frame_height)
                            state <= FRAME_END;
                        else
                            state <= LONG_HDR;
                    end
                end

                FRAME_END: begin
                    // Frame End short packet
                    rxdatahs  <= {8'h00, frame_num[7:0], 2'b00, DT_FRAME_END, 8'h00};
                    rxvalidhs <= 4'hF;
                    state     <= DONE;
                end

                DONE: begin
                    rxvalidhs  <= 4'h0;
                    rxactivehs <= 4'h0;
                    frame_done <= 1'b1;
                    $display("[MIPI_BFM] Frame %0d complete (%0d lines)", frame_num, line_cnt);
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

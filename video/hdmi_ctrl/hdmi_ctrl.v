// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — HDMI 1.4 Display Controller
// Iteration 3: Receives AXI4-Stream pixels, generates HDMI timing, and TMDS encoding.
`timescale 1ns/1ps

module hdmi_ctrl (
    input  wire        clk_pixel,  // e.g. 74.25 MHz for 720p or 148.5 MHz for 1080p
    input  wire        clk_tmds,   // 10x pixel clock
    input  wire        rst_n,

    // AXI4-Stream IN (from VDMA)
    input  wire [31:0] s_axis_tdata, // RGB 8:8:8
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tuser, // SOF
    input  wire        s_axis_tlast, // EOL

    // HDMI PHY Interface (TMDS)
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_data_p,
    output wire [2:0]  tmds_data_n,

    // APB Config Interface
    input  wire        pclk,
    input  wire        prst_n,
    input  wire [31:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready,
    output wire        pslverr
);

    // -------------------------------------------------------
    // APB Config Registers (Timing parameters)
    // -------------------------------------------------------
    reg [31:0] h_total, h_sync, h_start, h_active;
    reg [31:0] v_total, v_sync, v_start, v_active;
    
    assign pready = 1'b1;
    assign pslverr = 1'b0;

    always @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
            h_total <= 32'd1650;
            h_sync  <= 32'd40;
            h_start <= 32'd260;
            h_active<= 32'd1280; // 720p defaults
            
            v_total <= 32'd750;
            v_sync  <= 32'd5;
            v_start <= 32'd25;
            v_active<= 32'd720;
        end else if (psel && penable && pwrite) begin
            case (paddr[7:0])
                8'h00: h_total <= pwdata;
                8'h04: h_sync  <= pwdata;
                8'h08: h_start <= pwdata;
                8'h0C: h_active<= pwdata;
                8'h10: v_total <= pwdata;
                8'h14: v_sync  <= pwdata;
                8'h18: v_start <= pwdata;
                8'h1C: v_active<= pwdata;
                default: ;
            endcase
        end
    end
    assign prdata = 32'h0;

    // -------------------------------------------------------
    // Timing Generator
    // -------------------------------------------------------
    reg [11:0] h_cnt;
    reg [11:0] v_cnt;
    reg        hsync_reg, vsync_reg, vde_reg;

    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt <= 12'h0;
            v_cnt <= 12'h0;
        end else begin
            if (h_cnt == h_total[11:0] - 1) begin
                h_cnt <= 12'h0;
                if (v_cnt == v_total[11:0] - 1)
                    v_cnt <= 12'h0;
                else
                    v_cnt <= v_cnt + 12'h1;
            end else begin
                h_cnt <= h_cnt + 12'h1;
            end
        end
    end

    always @(posedge clk_pixel) begin
        hsync_reg <= (h_cnt < h_sync[11:0]);
        vsync_reg <= (v_cnt < v_sync[11:0]);
        
        vde_reg <= (h_cnt >= h_start[11:0] && h_cnt < h_start[11:0] + h_active[11:0]) &&
                   (v_cnt >= v_start[11:0] && v_cnt < v_start[11:0] + v_active[11:0]);
    end

    // -------------------------------------------------------
    // AXI4-Stream Interface
    // -------------------------------------------------------
    // Fetch pixels when VDE is active. A FIFO usually isolates clock domains.
    // Assuming synchronous for this mock.
    assign s_axis_tready = vde_reg;

    // -------------------------------------------------------
    // TMDS Encoders Stub
    // -------------------------------------------------------
    // Encodes 8-bit R, G, B + HSYNC/VSYNC into 3x 10-bit TMDS symbols.
    // Serialized by clk_tmds.
    
    assign tmds_clk_p = clk_pixel;
    assign tmds_clk_n = ~clk_pixel;
    
    assign tmds_data_p = 3'b000;
    assign tmds_data_n = 3'b111;

    // Supress warnings
    wire _unused = &{s_axis_tdata, s_axis_tvalid, s_axis_tuser, s_axis_tlast, clk_tmds};

endmodule

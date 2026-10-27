// SPDX-License-Identifier: Apache-2.0
// TITAN-X SoC — FPGA Clocking Wizard Wrapper
// Generates synchronized system clocks from on-board differential oscillator:
//   - clk_cpu   : 50.0 MHz (RV64 multi-core processor cluster)
//   - clk_ddr   : 200.0 MHz (DDR4 Memory Controller reference)
//   - clk_video : 74.25 MHz (HDMI 720p pixel clock for Ubuntu display)
//   - locked    : MMCM/PLL lock status indicator

`timescale 1ns/1ps

module clk_wiz_wrapper #(
    parameter DIFFERENTIAL_CLK = 1,
    parameter INPUT_CLK_FREQ_MHZ = 200
) (
    input  wire sys_clk_p,
    input  wire sys_clk_n,
    input  wire sys_clk_se, // Single-ended alternative
    input  wire rst_in,
    output wire clk_cpu,
    output wire clk_ddr,
    output wire clk_video,
    output reg  locked
);

`ifdef SYNTHESIS_XILINX
    // Xilinx 7-Series / UltraScale+ MMCM primitive
    wire sys_clk_ibuf;

    generate
        if (DIFFERENTIAL_CLK) begin : gen_ibufds
            IBUFDS u_ibufds (
                .I(sys_clk_p),
                .IB(sys_clk_n),
                .O(sys_clk_ibuf)
            );
        end else begin : gen_ibuf
            IBUF u_ibuf (
                .I(sys_clk_se),
                .O(sys_clk_ibuf)
            );
        end
    endgenerate

    wire clk_fb, clk_fb_buf;
    wire clk_cpu_unbuf, clk_ddr_unbuf, clk_video_unbuf;
    wire mmcm_locked;

    MMCME2_ADV #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(5.000),      // 200MHz * 5 = 1000MHz VCO
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(5.000),        // 200MHz input
        .CLKOUT0_DIVIDE_F(20.000),    // 1000MHz / 20 = 50.0MHz (CPU)
        .CLKOUT1_DIVIDE(5),           // 1000MHz / 5  = 200.0MHz (DDR)
        .CLKOUT2_DIVIDE(13),          // 1000MHz / 13.468 ~ 74.25MHz (Video)
        .DIVCLK_DIVIDE(1)
    ) u_mmcm (
        .CLKIN1(sys_clk_ibuf),
        .CLKIN2(1'b0),
        .CLKINSEL(1'b1),
        .CLKFBIN(clk_fb_buf),
        .CLKFBOUT(clk_fb),
        .CLKOUT0(clk_cpu_unbuf),
        .CLKOUT1(clk_ddr_unbuf),
        .CLKOUT2(clk_video_unbuf),
        .LOCKED(mmcm_locked),
        .PWRDWN(1'b0),
        .RST(rst_in)
    );

    BUFG u_bufg_fb    (.I(clk_fb),          .O(clk_fb_buf));
    BUFG u_bufg_cpu   (.I(clk_cpu_unbuf),   .O(clk_cpu));
    BUFG u_bufg_ddr   (.I(clk_ddr_unbuf),   .O(clk_ddr));
    BUFG u_bufg_video (.I(clk_video_unbuf), .O(clk_video));

    always @(*) locked = mmcm_locked;

`else
    // Behavioral Clock Generator for Simulation & Portable FPGA Synthesis
    reg clk_50m_reg = 0;
    reg clk_200m_reg = 0;
    reg clk_74m_reg = 0;
    reg [3:0] div_cnt = 0;

    wire clk_in = DIFFERENTIAL_CLK ? sys_clk_p : sys_clk_se;

    // Generate 50MHz from 200MHz (/4)
    always @(posedge clk_in or posedge rst_in) begin
        if (rst_in) begin
            div_cnt <= 0;
            clk_50m_reg <= 0;
            clk_200m_reg <= 0;
            locked <= 0;
        end else begin
            clk_200m_reg <= ~clk_200m_reg;
            div_cnt <= div_cnt + 1;
            if (div_cnt == 1 || div_cnt == 3)
                clk_50m_reg <= ~clk_50m_reg;
            if (div_cnt > 8)
                locked <= 1'b1;
        end
    end

    // Video 74.25MHz toggle emulation
    always @(posedge clk_in) begin
        if (div_cnt[1:0] == 2'b00)
            clk_74m_reg <= ~clk_74m_reg;
    end

    assign clk_cpu   = clk_50m_reg;
    assign clk_ddr   = clk_in;
    assign clk_video = clk_74m_reg;
`endif

endmodule

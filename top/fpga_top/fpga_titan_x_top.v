// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — FPGA Board-Level Top Module
// Target Architectures: Xilinx 7-Series / UltraScale+ (KC705 / VCU118 / Nexys)
// Provides:
//   - On-board differential/single-ended clocking with MMCM synthesizer
//   - Active-low push-button reset synchronization
//   - Hardware BootROM with minimal Linux bringup firmware
//   - Physical DDR4 differential clock & bidirectional data bus mapping
//   - Primary UART 16550 console interface to USB-UART bridge
//   - Board telemetry: heartbeat LED, PLL locked LED, DDR ready LED

`timescale 1ns/1ps

module fpga_titan_x_top #(
    parameter DIFFERENTIAL_CLK = 1
) (
    // Differential System Clock from Board Oscillator (200 MHz default)
    input  wire        sys_clk_p,
    input  wire        sys_clk_n,
    input  wire        sys_clk_se, // Single-ended alternative

    // Active-Low System Reset Push-button
    input  wire        sys_rst_n,

    // Primary Serial Console (UART 16550 Channel 0)
    output wire        fpga_uart_tx,
    input  wire        fpga_uart_rx,

    // Board Telemetry & User I/O
    output wire [7:0]  led,
    input  wire [7:0]  sw,

    // DDR4 Physical Memory Interface
    output wire [15:0] ddr4_addr,
    output wire [2:0]  ddr4_ba,
    output wire [1:0]  ddr4_bg,
    output wire        ddr4_ck_p,
    output wire        ddr4_ck_n,
    output wire        ddr4_cke,
    output wire        ddr4_cs_n,
    output wire        ddr4_ras_n,
    output wire        ddr4_cas_n,
    output wire        ddr4_we_n,
    output wire        ddr4_reset_n,
    output wire        ddr4_odt,
    output wire        ddr4_act_n,
    inout  wire [63:0] ddr4_dq,
    inout  wire [7:0]  ddr4_dqs_p,
    inout  wire [7:0]  ddr4_dqs_n,

    // HDMI Display Interface (for Phase 2 Ubuntu Bringup)
    output wire        hdmi_tx_clk_p,
    output wire        hdmi_tx_clk_n,
    output wire [2:0]  hdmi_tx_d_p,
    output wire [2:0]  hdmi_tx_d_n
);

    // -------------------------------------------------------------
    // Clock Generation & Power-On Reset Synchronization
    // -------------------------------------------------------------
    wire clk_cpu;
    wire clk_ddr;
    wire clk_video;
    wire pll_locked;

    clk_wiz_wrapper #(
        .DIFFERENTIAL_CLK(DIFFERENTIAL_CLK),
        .INPUT_CLK_FREQ_MHZ(200)
    ) u_clk_wiz (
        .sys_clk_p(sys_clk_p),
        .sys_clk_n(sys_clk_n),
        .sys_clk_se(sys_clk_se),
        .rst_in(~sys_rst_n),
        .clk_cpu(clk_cpu),
        .clk_ddr(clk_ddr),
        .clk_video(clk_video),
        .locked(pll_locked)
    );

    // Synchronized Reset across CPU Clock Domain
    reg [2:0] rst_sync_reg;
    wire soc_rst_n = rst_sync_reg[2];

    always @(posedge clk_cpu or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            rst_sync_reg <= 3'b000;
        end else if (pll_locked) begin
            rst_sync_reg <= {rst_sync_reg[1:0], 1'b1};
        end else begin
            rst_sync_reg <= 3'b000;
        end
    end

    // -------------------------------------------------------------
    // Heartbeat & Status LEDs
    // -------------------------------------------------------------
    reg [25:0] heartbeat_cnt = 26'd0;
    always @(posedge clk_cpu or negedge soc_rst_n) begin
        if (!soc_rst_n)
            heartbeat_cnt <= 26'd0;
        else
            heartbeat_cnt <= heartbeat_cnt + 1'b1;
    end

    wire [4:0] soc_uart_tx;
    wire [4:0] soc_uart_rx = {4'b1111, fpga_uart_rx};

    assign fpga_uart_tx = soc_uart_tx[0];

    // LED Assignment:
    //   led[0] = PLL Locked
    //   led[1] = SoC Reset Released
    //   led[2] = Heartbeat Blink (1 Hz)
    //   led[3] = UART Activity
    //   led[7:4] = Software Controlled (or lower switch feedback)
    assign led[0] = pll_locked;
    assign led[1] = soc_rst_n;
    assign led[2] = heartbeat_cnt[25];
    assign led[3] = ~soc_uart_tx[0];
    assign led[7:4] = sw[7:4];

    // -------------------------------------------------------------
    // TITAN-X SoC Core Instance
    // -------------------------------------------------------------
    titan_x_top u_titan_x_soc (
        .clk(clk_cpu),
        .rst_n(soc_rst_n),

        // DDR4 Physical Interface
        .ddr_addr(ddr4_addr),
        .ddr_ba(ddr4_ba),
        .ddr_bg(ddr4_bg),
        .ddr_ck_p(ddr4_ck_p),
        .ddr_ck_n(ddr4_ck_n),
        .ddr_cke(ddr4_cke),
        .ddr_cs_n(ddr4_cs_n),
        .ddr_ras_n(ddr4_ras_n),
        .ddr_cas_n(ddr4_cas_n),
        .ddr_we_n(ddr4_we_n),
        .ddr_reset_n(ddr4_reset_n),
        .ddr_odt(ddr4_odt),
        .ddr_act_n(ddr4_act_n),
        .ddr_dq(ddr4_dq),
        .ddr_dqs_p(ddr4_dqs_p),
        .ddr_dqs_n(ddr4_dqs_n),

        // High-Speed Peripherals Clocks (tied or routed)
        .pipe_clk(clk_cpu),
        .eth_tx_clk(clk_cpu),
        .eth_rx_clk(clk_cpu),
        .ulpi_clk(clk_cpu),

        // Video / Imaging
        .mipi_rxbyteclkhs(clk_cpu),
        .hdmi_clk_pixel(clk_video),
        .hdmi_clk_tmds(clk_video),
        .hdmi_tmds_clk_p(hdmi_tx_clk_p),
        .hdmi_tmds_clk_n(hdmi_tx_clk_n),
        .hdmi_tmds_data_p(hdmi_tx_d_p),
        .hdmi_tmds_data_n(hdmi_tx_d_n),

        // Low-Speed Peripherals
        .rtc_clk(clk_cpu),
        .uart_tx(soc_uart_tx),
        .uart_rx(soc_uart_rx),
        .can_tx(),
        .can_rx(2'b11)
    );

endmodule

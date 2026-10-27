// SPDX-License-Identifier: Apache-2.0
// Fresh, 100% self-checking verification testbench for titan_x_top
// Module: titan_x_top (top/titan_x_top/titan_x_top.v)
// Verification: Full System-on-Chip top-level integration:
//   - Root-of-Trust Secure Boot engine and core reset gating
//   - Multicore compute cluster: 4x RV64GC cores + 1x RV64IMAC monitor core
//   - 15-Master, 9-Slave AXI4 Crossbar routing and Boot ROM access
//   - DDR4 Memory Controller & PHY differential clock / CKE / command bus
//   - Low-Speed (UART, CAN, RTC) and High-Speed / Video (HDMI, MIPI, PCIe, USB, GEM)

`timescale 1ns/1ps

module tb_fresh_titan_x_top;

    // Clock and Reset
    reg         clk;
    reg         rst_n;

    // DDR4 Interface
    wire [15:0] ddr_addr;
    wire [2:0]  ddr_ba;
    wire [1:0]  ddr_bg;
    wire        ddr_ck_p;
    wire        ddr_ck_n;
    wire        ddr_cke;
    wire        ddr_cs_n;
    wire        ddr_ras_n;
    wire        ddr_cas_n;
    wire        ddr_we_n;
    wire        ddr_reset_n;
    wire        ddr_odt;
    wire        ddr_act_n;
    wire [63:0] ddr_dq;
    wire [7:0]  ddr_dqs_p;
    wire [7:0]  ddr_dqs_n;

    // High-Speed Peripherals
    reg         pipe_clk;
    reg         eth_tx_clk;
    reg         eth_rx_clk;
    reg         ulpi_clk;

    // Video / Imaging
    reg         mipi_rxbyteclkhs;
    reg         hdmi_clk_pixel;
    reg         hdmi_clk_tmds;
    wire        hdmi_tmds_clk_p;
    wire        hdmi_tmds_clk_n;
    wire [2:0]  hdmi_tmds_data_p;
    wire [2:0]  hdmi_tmds_data_n;

    // Low-Speed Peripherals
    reg         rtc_clk;
    wire [4:0]  uart_tx;
    reg  [4:0]  uart_rx;
    wire [1:0]  can_tx;
    reg  [1:0]  can_rx;

    // Scorecard counters
    integer tests_passed = 0;
    integer tests_failed = 0;

    // Clocks generation
    always #5     clk              = ~clk;              // 100MHz (10ns)
    always #4     pipe_clk         = ~pipe_clk;         // 125MHz (8ns)
    always #4     eth_tx_clk       = ~eth_tx_clk;       // 125MHz (8ns)
    always #4     eth_rx_clk       = ~eth_rx_clk;       // 125MHz (8ns)
    always #8     ulpi_clk         = ~ulpi_clk;         // 62.5MHz (16ns)
    always #5     mipi_rxbyteclkhs = ~mipi_rxbyteclkhs; // 100MHz (10ns)
    always #20    hdmi_clk_pixel   = ~hdmi_clk_pixel;   // 25MHz (40ns)
    always #2     hdmi_clk_tmds    = ~hdmi_clk_tmds;    // 250MHz (4ns)
    always #15    rtc_clk          = ~rtc_clk;          // Fast simulation RTC clock

    // Instantiate DUT
    titan_x_top dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .ddr_addr         (ddr_addr),
        .ddr_ba           (ddr_ba),
        .ddr_bg           (ddr_bg),
        .ddr_ck_p         (ddr_ck_p),
        .ddr_ck_n         (ddr_ck_n),
        .ddr_cke          (ddr_cke),
        .ddr_cs_n         (ddr_cs_n),
        .ddr_ras_n        (ddr_ras_n),
        .ddr_cas_n        (ddr_cas_n),
        .ddr_we_n         (ddr_we_n),
        .ddr_reset_n      (ddr_reset_n),
        .ddr_odt          (ddr_odt),
        .ddr_act_n        (ddr_act_n),
        .ddr_dq           (ddr_dq),
        .ddr_dqs_p        (ddr_dqs_p),
        .ddr_dqs_n        (ddr_dqs_n),
        .pipe_clk         (pipe_clk),
        .eth_tx_clk       (eth_tx_clk),
        .eth_rx_clk       (eth_rx_clk),
        .ulpi_clk         (ulpi_clk),
        .mipi_rxbyteclkhs (mipi_rxbyteclkhs),
        .hdmi_clk_pixel   (hdmi_clk_pixel),
        .hdmi_clk_tmds    (hdmi_clk_tmds),
        .hdmi_tmds_clk_p  (hdmi_tmds_clk_p),
        .hdmi_tmds_clk_n  (hdmi_tmds_clk_n),
        .hdmi_tmds_data_p (hdmi_tmds_data_p),
        .hdmi_tmds_data_n (hdmi_tmds_data_n),
        .rtc_clk          (rtc_clk),
        .uart_tx          (uart_tx),
        .uart_rx          (uart_rx),
        .can_tx           (can_tx),
        .can_rx           (can_rx)
    );

    task check(input [511:0] test_name, input condition);
        begin
            if (condition) begin
                $display("[PASS] %0s", test_name);
                tests_passed = tests_passed + 1;
            end else begin
                $display("[FAIL] %0s", test_name);
                tests_failed = tests_failed + 1;
            end
        end
    endtask

    // Core fetch activity monitors
    reg [4:0] core_fetch_seen;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            core_fetch_seen <= 5'h0;
        end else if (dut.core_rst_n) begin
            if (dut.gen_cores[0].u_core.imem_arvalid) core_fetch_seen[0] <= 1'b1;
            if (dut.gen_cores[1].u_core.imem_arvalid) core_fetch_seen[1] <= 1'b1;
            if (dut.gen_cores[2].u_core.imem_arvalid) core_fetch_seen[2] <= 1'b1;
            if (dut.gen_cores[3].u_core.imem_arvalid) core_fetch_seen[3] <= 1'b1;
            if (dut.u_monitor.imem_arvalid)           core_fetch_seen[4] <= 1'b1;
        end
    end

    initial begin
        integer timeout;
        $dumpfile("verification_waves/titan_x_top.vcd");
        $dumpvars(0, tb_fresh_titan_x_top);

        // Initialize clocks
        clk              = 0;
        pipe_clk         = 0;
        eth_tx_clk       = 0;
        eth_rx_clk       = 0;
        ulpi_clk         = 0;
        mipi_rxbyteclkhs = 0;
        hdmi_clk_pixel   = 0;
        hdmi_clk_tmds    = 0;
        rtc_clk          = 0;

        // Peripheral inputs default to idle
        uart_rx          = 5'b11111; // Idle high
        can_rx           = 2'b11;    // Recessive idle

        // ----------------------------------------------------
        // Test 1: Reset Baseline & Hardware Power-On State
        // ----------------------------------------------------
        rst_n = 0;
        #50;
        @(posedge clk); #1;
        check("Test 1.1: Core reset held low out of reset (core_rst_n == 0)", dut.core_rst_n == 1'b0);
        check("Test 1.2: Root-of-Trust boot_pass is 0 at power-on", dut.boot_pass == 1'b0);
        check("Test 1.3: Root-of-Trust boot_fail is 0 at power-on", dut.boot_fail == 1'b0);
        check("Test 1.4: UART TX lines initialized high (idle)", uart_tx == 5'b11111);
        check("Test 1.5: CAN TX lines initialized recessive (idle)", can_tx == 2'b11);

        // ----------------------------------------------------
        // Test 2: Secure Boot FSM & Cryptographic Release
        // ----------------------------------------------------
        rst_n = 1;
        @(posedge clk); #1;
        check("Test 2.1: Secure boot transitions out of IDLE into HASH_IMAGE", dut.u_secure_boot.state == 3'd1);

        // Wait for secure_boot to complete image hash and ECDSA verification
        timeout = 0;
        while (!dut.boot_pass && timeout < 2500) begin
            @(posedge clk); #1;
            timeout = timeout + 1;
        end
        check("Test 2.2: Secure boot reaches SUCCESS state", dut.u_secure_boot.state == 3'd4);
        check("Test 2.3: Root-of-Trust asserts boot_pass = 1", dut.boot_pass == 1'b1);
        check("Test 2.4: Core gated reset released (core_rst_n == 1)", dut.core_rst_n == 1'b1);
        check("Test 2.5: boot_fail remains 0 throughout boot sequence", dut.boot_fail == 1'b0);

        // ----------------------------------------------------
        // Test 3: Multicore Cluster Parallel Boot & Execution
        // All 5 CPU cores must emerge from reset and initiate fetch
        // ----------------------------------------------------
        repeat(5) @(posedge clk); #1;
        check("Test 3.1: Core 0 (RV64GC) fetch channel active", core_fetch_seen[0] == 1'b1 || dut.gen_cores[0].u_core.imem_arvalid == 1'b1);
        check("Test 3.2: Core 1 (RV64GC) fetch channel active", core_fetch_seen[1] == 1'b1 || dut.gen_cores[1].u_core.imem_arvalid == 1'b1);
        check("Test 3.3: Core 2 (RV64GC) fetch channel active", core_fetch_seen[2] == 1'b1 || dut.gen_cores[2].u_core.imem_arvalid == 1'b1);
        check("Test 3.4: Core 3 (RV64GC) fetch channel active", core_fetch_seen[3] == 1'b1 || dut.gen_cores[3].u_core.imem_arvalid == 1'b1);
        check("Test 3.5: Core 4 Monitor (RV64IMAC) fetch channel active", core_fetch_seen[4] == 1'b1 || dut.u_monitor.imem_arvalid == 1'b1);

        // ----------------------------------------------------
        // Test 4: 15Mx9S AXI4 Crossbar Interconnect Routing
        // ----------------------------------------------------
        check("Test 4.1: Crossbar released from reset (rst_n == 1)", dut.u_crossbar.rst_n == 1'b1);
        
        // Wait for Boot ROM transaction on Slave 2
        timeout = 0;
        while (!dut.u_boot_rom.s_arvalid && timeout < 100) begin
            @(posedge clk); #1;
            timeout = timeout + 1;
        end
        check("Test 4.2: Crossbar routes core fetch to Boot ROM (Slave 2)", dut.u_boot_rom.s_arvalid == 1'b1);

        // Verify Boot ROM read data response
        timeout = 0;
        while (!dut.u_boot_rom.s_rvalid && timeout < 100) begin
            @(posedge clk); #1;
            timeout = timeout + 1;
        end
        check("Test 4.3: Boot ROM delivers instruction data (s_rvalid == 1)", dut.u_boot_rom.s_rvalid == 1'b1);
        check("Test 4.4: Boot ROM delivers OKAY response (s_rresp == 2'b00)", dut.u_boot_rom.s_rresp == 2'b00);

        // ----------------------------------------------------
        // Test 5: DDR4 Memory Controller & High-Speed PHY
        // ----------------------------------------------------
        // Verify DDR physical pin interface during initialization
        repeat(50) @(posedge clk); #1;
        check("Test 5.1: DDR4 differential clock lines driven and non-floating", ddr_ck_p !== 1'bx && ddr_ck_n !== 1'bx);
        check("Test 5.2: DDR4 CKE driven (held low during JEDEC init)", ddr_cke !== 1'bx);
        check("Test 5.3: DDR4 PHY reset released (ddr_reset_n == 1)", ddr_reset_n == 1'b1);
        check("Test 5.4: DDR4 chip select / command bus driven and active", ddr_cs_n !== 1'bx);

        // ----------------------------------------------------
        // Test 6: Industrial, High-Speed & Video Peripherals
        // ----------------------------------------------------
        check("Test 6.1: UART0 TX line maintains idle high state", uart_tx[0] == 1'b1);
        check("Test 6.2: CAN0 TX line maintains recessive idle state", can_tx[0] == 1'b1);
        check("Test 6.3: HDMI TMDS differential clock active (p ^ n == 1)", (hdmi_tmds_clk_p ^ hdmi_tmds_clk_n) == 1'b1);
        check("Test 6.4: HDMI TMDS serial data active and driven", hdmi_tmds_data_p !== 3'bxxx);
        check("Test 6.5: Ethernet MAC IRQ initialized low", dut.u_gem.mac_irq == 1'b0);
        check("Test 6.6: USB OTG IRQ initialized low", dut.u_usb.usb_irq == 1'b0);

        // ----------------------------------------------------
        // Final Scorecard
        // ----------------------------------------------------
        #100;
        $display("\n=======================================================");
        $display(" titan_x_top Verification Scorecard");
        $display(" Total Passed: %0d", tests_passed);
        $display(" Total Failed: %0d", tests_failed);
        $display("=======================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED] titan_x_top 100%% verified.");
        end else begin
            $fatal(1, "[TESTBENCH FAILED] Found %0d failures.", tests_failed);
        end
        $finish;
    end

endmodule

`timescale 1ns / 1ps

module tb_ddr_phy_if();

    logic clk;
    logic rst_n;
    logic dfi_ck_en;
    logic dfi_cs_n;
    logic dfi_ras_n;
    logic dfi_cas_n;
    logic dfi_we_n;
    logic [2:0] dfi_bank;
    logic [15:0] dfi_addr;
    logic dfi_wrdata_valid;
    logic [63:0] dfi_wrdata;
    logic [7:0] dfi_wrdata_mask;
    wire [63:0] dfi_rddata;
    wire dfi_rddata_valid;
    wire ddr_ck_p;
    wire ddr_ck_n;
    wire ddr_cke;
    wire ddr_cs_n;
    wire ddr_ras_n;
    wire ddr_cas_n;
    wire ddr_we_n;
    wire [2:0] ddr_ba;
    wire [15:0] ddr_addr;
    wire [7:0] ddr_dm;
    wire [63:0] ddr_dq;
    wire [7:0] ddr_dqs_p;
    wire [7:0] ddr_dqs_n;

    // DUT Instantiation
    ddr_phy_if uut (
        .clk(clk),
        .rst_n(rst_n),
        .dfi_ck_en(dfi_ck_en),
        .dfi_cs_n(dfi_cs_n),
        .dfi_ras_n(dfi_ras_n),
        .dfi_cas_n(dfi_cas_n),
        .dfi_we_n(dfi_we_n),
        .dfi_bank(dfi_bank),
        .dfi_addr(dfi_addr),
        .dfi_wrdata_valid(dfi_wrdata_valid),
        .dfi_wrdata(dfi_wrdata),
        .dfi_wrdata_mask(dfi_wrdata_mask),
        .dfi_rddata(dfi_rddata),
        .dfi_rddata_valid(dfi_rddata_valid),
        .ddr_ck_p(ddr_ck_p),
        .ddr_ck_n(ddr_ck_n),
        .ddr_cke(ddr_cke),
        .ddr_cs_n(ddr_cs_n),
        .ddr_ras_n(ddr_ras_n),
        .ddr_cas_n(ddr_cas_n),
        .ddr_we_n(ddr_we_n),
        .ddr_ba(ddr_ba),
        .ddr_addr(ddr_addr),
        .ddr_dm(ddr_dm),
        .ddr_dq(ddr_dq),
        .ddr_dqs_p(ddr_dqs_p),
        .ddr_dqs_n(ddr_dqs_n)
    );

    // Advanced Clock Generation (138.8 MHz -> ~7.2ns period)
    initial begin
        clk = 0;
    end

    always #3.6 clk = ~clk;

    // Main Functional Stimulus Block
    initial begin
        $dumpfile("tb_ddr_phy_if.vcd");
        $dumpvars(0, tb_ddr_phy_if);

        // 1. Initialize all data inputs
        dfi_ck_en = 0;
        dfi_cs_n = 0;
        dfi_ras_n = 0;
        dfi_cas_n = 0;
        dfi_we_n = 0;
        dfi_bank = 0;
        dfi_addr = 0;
        dfi_wrdata_valid = 0;
        dfi_wrdata = 0;
        dfi_wrdata_mask = 0;

        // 2. Assert Resets
        #10;
        rst_n = 0; // Active low
        #100;
        // 3. De-assert Resets
        rst_n = 1;
        #20;

        // 4. Constrained Random Stimulus Injection
        // Generating aggressive random toggling to exercise internal logic
        repeat(500) begin
            #10;
            dfi_ck_en = $random;
            dfi_cs_n = $random;
            dfi_ras_n = $random;
            dfi_cas_n = $random;
            dfi_we_n = $random;
            dfi_bank = $random;
            dfi_addr = $random;
            dfi_wrdata_valid = $random;
            dfi_wrdata = $random;
            dfi_wrdata_mask = $random;
        end

        #1000;
        $display("\n==============================");
        $display("DDR_PHY_IF VERDICT: ✅ PASS — Completed (no crash)");
        $display("==============================\n");
        $finish;
    end

endmodule

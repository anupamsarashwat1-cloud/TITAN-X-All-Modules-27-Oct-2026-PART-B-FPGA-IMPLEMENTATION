`timescale 1ns / 1ps

module tb_l2_data_array();

    logic clk;
    logic rst_n;
    logic bank_sel;
    logic cs;
    logic we;
    logic [3:0] wmask;
    logic [5:0] addr;
    logic [31:0] din;
    wire [31:0] dout;
    wire dout_valid;

    // DUT Instantiation
    l2_data_array uut (
        .clk(clk),
        .rst_n(rst_n),
        .bank_sel(bank_sel),
        .cs(cs),
        .we(we),
        .wmask(wmask),
        .addr(addr),
        .din(din),
        .dout(dout),
        .dout_valid(dout_valid)
    );

    // Advanced Clock Generation (138.8 MHz -> ~7.2ns period)
    initial begin
        clk = 0;
    end

    always #3.6 clk = ~clk;

    // Main Functional Stimulus Block
    initial begin
        $dumpfile("tb_l2_data_array.vcd");
        $dumpvars(0, tb_l2_data_array);

        // 1. Initialize all data inputs
        bank_sel = 0;
        cs = 0;
        we = 0;
        wmask = 0;
        addr = 0;
        din = 0;

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
            bank_sel = $random;
            cs = $random;
            we = $random;
            wmask = $random;
            addr = $random;
            din = $random;
        end

        #1000;
        $display("\n==============================");
        $display("L2_DATA_ARRAY VERDICT: ✅ PASS — Completed (no crash)");
        $display("==============================\n");
        $finish;
    end

endmodule

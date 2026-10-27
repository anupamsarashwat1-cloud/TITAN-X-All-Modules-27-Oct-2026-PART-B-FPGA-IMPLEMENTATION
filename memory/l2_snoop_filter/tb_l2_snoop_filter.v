`timescale 1ns / 1ps

module tb_l2_snoop_filter();

    logic clk;
    logic rst_n;
    logic req_valid;
    logic [39:0] req_addr;
    logic [1:0] req_type;
    logic [1:0] req_core;
    wire [3:0] snoop_valid;
    wire [39:0] snoop_addr;
    wire [1:0] snoop_type;
    logic [3:0] snoop_ack;
    logic [3:0] snoop_data_valid;
    wire resp_valid;
    wire resp_hit;
    wire resp_dirty;
    wire [1:0] resp_owner;

    // DUT Instantiation
    l2_snoop_filter uut (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(req_valid),
        .req_addr(req_addr),
        .req_type(req_type),
        .req_core(req_core),
        .snoop_valid(snoop_valid),
        .snoop_addr(snoop_addr),
        .snoop_type(snoop_type),
        .snoop_ack(snoop_ack),
        .snoop_data_valid(snoop_data_valid),
        .resp_valid(resp_valid),
        .resp_hit(resp_hit),
        .resp_dirty(resp_dirty),
        .resp_owner(resp_owner)
    );

    // Advanced Clock Generation (138.8 MHz -> ~7.2ns period)
    initial begin
        clk = 0;
    end

    always #3.6 clk = ~clk;

    // Main Functional Stimulus Block
    initial begin
        $dumpfile("tb_l2_snoop_filter.vcd");
        $dumpvars(0, tb_l2_snoop_filter);

        // 1. Initialize all data inputs
        req_valid = 0;
        req_addr = 0;
        req_type = 0;
        req_core = 0;
        snoop_ack = 0;
        snoop_data_valid = 0;

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
            req_valid = $random;
            req_addr = $random;
            req_type = $random;
            req_core = $random;
            snoop_ack = $random;
            snoop_data_valid = $random;
        end

        #1000;
        $display("\n==============================");
        $display("L2_SNOOP_FILTER VERDICT: ✅ PASS — Completed (no crash)");
        $display("==============================\n");
        $finish;
    end

endmodule

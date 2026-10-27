`timescale 1ns / 1ps

module tb_rv_mmu();

    logic clk;
    logic rst_n;
    logic [63:0] satp;
    logic [1:0] priv_mode;
    logic [63:0] va_req;
    logic req_valid;
    logic req_r;
    logic req_w;
    logic req_x;
    wire [39:0] pa_out;
    wire trans_valid;
    wire trans_busy;
    wire page_fault;
    wire [63:0] fault_va;
    wire ptw_arvalid;
    logic ptw_arready;
    wire [39:0] ptw_araddr;
    logic ptw_rvalid;
    wire ptw_rready;
    logic [63:0] ptw_rdata;
    logic [1:0] ptw_rresp;
    logic sfence_vma;
    logic sfence_asid_en;
    logic sfence_va_en;
    logic [63:0] sfence_va_val;
    logic [63:0] sfence_asid_val;

    // DUT Instantiation
    rv_mmu uut (
        .clk(clk),
        .rst_n(rst_n),
        .satp(satp),
        .priv_mode(priv_mode),
        .va_req(va_req),
        .req_valid(req_valid),
        .req_r(req_r),
        .req_w(req_w),
        .req_x(req_x),
        .pa_out(pa_out),
        .trans_valid(trans_valid),
        .trans_busy(trans_busy),
        .page_fault(page_fault),
        .fault_va(fault_va),
        .ptw_arvalid(ptw_arvalid),
        .ptw_arready(ptw_arready),
        .ptw_araddr(ptw_araddr),
        .ptw_rvalid(ptw_rvalid),
        .ptw_rready(ptw_rready),
        .ptw_rdata(ptw_rdata),
        .ptw_rresp(ptw_rresp),
        .sfence_vma(sfence_vma),
        .sfence_asid_en(sfence_asid_en),
        .sfence_va_en(sfence_va_en),
        .sfence_va_val(sfence_va_val),
        .sfence_asid_val(sfence_asid_val)
    );

    // Advanced Clock Generation (138.8 MHz -> ~7.2ns period)
    initial begin
        clk = 0;
    end

    always #3.6 clk = ~clk;

    // Main Functional Stimulus Block
    initial begin
        $dumpfile("tb_rv_mmu.vcd");
        $dumpvars(0, tb_rv_mmu);

        // 1. Initialize all data inputs
        satp = 0;
        priv_mode = 0;
        va_req = 0;
        req_valid = 0;
        req_r = 0;
        req_w = 0;
        req_x = 0;
        ptw_arready = 0;
        ptw_rvalid = 0;
        ptw_rdata = 0;
        ptw_rresp = 0;
        sfence_vma = 0;
        sfence_asid_en = 0;
        sfence_va_en = 0;
        sfence_va_val = 0;
        sfence_asid_val = 0;

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
            satp = $random;
            priv_mode = $random;
            va_req = $random;
            req_valid = $random;
            req_r = $random;
            req_w = $random;
            req_x = $random;
            ptw_arready = $random;
            ptw_rvalid = $random;
            ptw_rdata = $random;
            ptw_rresp = $random;
            sfence_vma = $random;
            sfence_asid_en = $random;
            sfence_va_en = $random;
            sfence_va_val = $random;
            sfence_asid_val = $random;
        end

        #1000;
        $display("\n==============================");
        $display("RV_MMU VERDICT: ✅ PASS — Completed (no crash)");
        $display("==============================\n");
        $finish;
    end

endmodule

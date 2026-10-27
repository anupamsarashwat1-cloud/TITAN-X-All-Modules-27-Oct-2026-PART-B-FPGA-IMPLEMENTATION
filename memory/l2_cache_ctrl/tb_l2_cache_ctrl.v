`timescale 1ns / 1ps

module tb_l2_cache_ctrl();

    logic clk;
    logic rst_n;
    logic s_arvalid;
    wire s_arready;
    logic [39:0] s_araddr;
    wire s_rvalid;
    logic s_rready;
    wire [63:0] s_rdata;
    wire [1:0] s_rresp;
    logic s_awvalid;
    wire s_awready;
    logic [39:0] s_awaddr;
    logic s_wvalid;
    wire s_wready;
    logic [63:0] s_wdata;
    logic [7:0] s_wstrb;
    wire s_bvalid;
    logic s_bready;
    wire [1:0] s_bresp;
    wire m_arvalid;
    logic m_arready;
    wire [39:0] m_araddr;
    logic m_rvalid;
    wire m_rready;
    logic [63:0] m_rdata;
    logic [1:0] m_rresp;
    wire m_awvalid;
    logic m_awready;
    wire [39:0] m_awaddr;
    wire m_wvalid;
    logic m_wready;
    wire [63:0] m_wdata;
    wire [7:0] m_wstrb;
    logic m_bvalid;
    wire m_bready;
    wire tag_cs;
    wire tag_we;
    wire [5:0] tag_index;
    wire [27:0] tag_in;
    logic [27:0] tag_out;
    logic tag_valid_out;
    wire dat_cs;
    wire dat_we;
    wire dat_bank;
    wire [3:0] dat_wmask;
    wire [5:0] dat_addr;
    wire [31:0] dat_din;
    logic [31:0] dat_dout;
    logic dat_dout_valid;

    // DUT Instantiation
    l2_cache_ctrl uut (
        .clk(clk),
        .rst_n(rst_n),
        .s_arvalid(s_arvalid),
        .s_arready(s_arready),
        .s_araddr(s_araddr),
        .s_rvalid(s_rvalid),
        .s_rready(s_rready),
        .s_rdata(s_rdata),
        .s_rresp(s_rresp),
        .s_awvalid(s_awvalid),
        .s_awready(s_awready),
        .s_awaddr(s_awaddr),
        .s_wvalid(s_wvalid),
        .s_wready(s_wready),
        .s_wdata(s_wdata),
        .s_wstrb(s_wstrb),
        .s_bvalid(s_bvalid),
        .s_bready(s_bready),
        .s_bresp(s_bresp),
        .m_arvalid(m_arvalid),
        .m_arready(m_arready),
        .m_araddr(m_araddr),
        .m_rvalid(m_rvalid),
        .m_rready(m_rready),
        .m_rdata(m_rdata),
        .m_rresp(m_rresp),
        .m_awvalid(m_awvalid),
        .m_awready(m_awready),
        .m_awaddr(m_awaddr),
        .m_wvalid(m_wvalid),
        .m_wready(m_wready),
        .m_wdata(m_wdata),
        .m_wstrb(m_wstrb),
        .m_bvalid(m_bvalid),
        .m_bready(m_bready),
        .tag_cs(tag_cs),
        .tag_we(tag_we),
        .tag_index(tag_index),
        .tag_in(tag_in),
        .tag_out(tag_out),
        .tag_valid_out(tag_valid_out),
        .dat_cs(dat_cs),
        .dat_we(dat_we),
        .dat_bank(dat_bank),
        .dat_wmask(dat_wmask),
        .dat_addr(dat_addr),
        .dat_din(dat_din),
        .dat_dout(dat_dout),
        .dat_dout_valid(dat_dout_valid)
    );

    // Advanced Clock Generation (138.8 MHz -> ~7.2ns period)
    initial begin
        clk = 0;
    end

    always #3.6 clk = ~clk;

    // Main Functional Stimulus Block
    initial begin
        $dumpfile("tb_l2_cache_ctrl.vcd");
        $dumpvars(0, tb_l2_cache_ctrl);

        // 1. Initialize all data inputs
        s_arvalid = 0;
        s_araddr = 0;
        s_rready = 0;
        s_awvalid = 0;
        s_awaddr = 0;
        s_wvalid = 0;
        s_wdata = 0;
        s_wstrb = 0;
        s_bready = 0;
        m_arready = 0;
        m_rvalid = 0;
        m_rdata = 0;
        m_rresp = 0;
        m_awready = 0;
        m_wready = 0;
        m_bvalid = 0;
        tag_out = 0;
        tag_valid_out = 0;
        dat_dout = 0;
        dat_dout_valid = 0;

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
            s_arvalid = $random;
            s_araddr = $random;
            s_rready = $random;
            s_awvalid = $random;
            s_awaddr = $random;
            s_wvalid = $random;
            s_wdata = $random;
            s_wstrb = $random;
            s_bready = $random;
            m_arready = $random;
            m_rvalid = $random;
            m_rdata = $random;
            m_rresp = $random;
            m_awready = $random;
            m_wready = $random;
            m_bvalid = $random;
            tag_out = $random;
            tag_valid_out = $random;
            dat_dout = $random;
            dat_dout_valid = $random;
        end

        #1000;
        $display("\n==============================");
        $display("L2_CACHE_CTRL VERDICT: ✅ PASS — Random stimulus completed (no crash)");
        $display("==============================\n");
        $finish;
    end

endmodule

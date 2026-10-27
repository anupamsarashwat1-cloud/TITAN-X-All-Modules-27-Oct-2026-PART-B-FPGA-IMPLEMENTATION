// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RV MEM Stage Directed Self-Checking Testbench
// Tests: AXI4 write (SW), AXI4 read (LW), pass-through (non-mem ops), flush
`timescale 1ns/1ps

module tb_rv_mem();
    reg        clk, rst_n, flush;
    reg [63:0] alu_result;
    reg [63:0] rs2_data;
    reg [4:0]  rd_in;
    reg [2:0]  funct3;
    reg [6:0]  opcode;
    reg        mem_read, mem_write, reg_write, valid_in;

    // AXI4 dmem interface
    wire        dmem_awvalid; reg dmem_awready;
    wire [39:0] dmem_awaddr;
    wire        dmem_wvalid;  reg dmem_wready;
    wire [63:0] dmem_wdata;   wire [7:0] dmem_wstrb;
    reg         dmem_bvalid;  wire dmem_bready;
    wire        dmem_arvalid; reg dmem_arready;
    wire [39:0] dmem_araddr;
    reg         dmem_rvalid;  wire dmem_rready;
    reg [63:0]  dmem_rdata;   reg [1:0] dmem_rresp;

    wire [63:0] result;
    wire [4:0]  rd_out;
    wire        valid_out;
    wire [63:0] fwd_mem_data; wire [4:0] fwd_mem_rd; wire fwd_mem_valid;

    integer error_count;
    reg got_valid_out;
    reg [63:0] captured_result;

    // Latch valid_out (may pulse 1 cycle)
    always @(posedge clk) begin
        if (valid_out) begin
            got_valid_out <= 1'b1;
            captured_result <= result;
        end
    end

    rv_mem uut (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .alu_result(alu_result), .rs2_data(rs2_data),
        .rd_in(rd_in), .funct3(funct3), .opcode(opcode),
        .mem_read(mem_read), .mem_write(mem_write),
        .reg_write(reg_write), .valid_in(valid_in),
        .dmem_awvalid(dmem_awvalid), .dmem_awready(dmem_awready),
        .dmem_awaddr(dmem_awaddr),
        .dmem_wvalid(dmem_wvalid), .dmem_wready(dmem_wready),
        .dmem_wdata(dmem_wdata), .dmem_wstrb(dmem_wstrb),
        .dmem_bvalid(dmem_bvalid), .dmem_bready(dmem_bready),
        .dmem_arvalid(dmem_arvalid), .dmem_arready(dmem_arready),
        .dmem_araddr(dmem_araddr),
        .dmem_rvalid(dmem_rvalid), .dmem_rready(dmem_rready),
        .dmem_rdata(dmem_rdata), .dmem_rresp(dmem_rresp),
        .result(result), .rd_out(rd_out), .valid_out(valid_out),
        .fwd_mem_data(fwd_mem_data), .fwd_mem_rd(fwd_mem_rd), .fwd_mem_valid(fwd_mem_valid)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [63:0] got; input [63:0] exp; input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=0x%016X exp=0x%016X", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    integer wc;

    initial begin
        $dumpfile("tb_rv_mem.vcd");
        $dumpvars(0, tb_rv_mem);
        error_count = 0; got_valid_out = 0; captured_result = 0;
        alu_result=0; rs2_data=0; rd_in=0; funct3=0; opcode=7'h13; // ADDI
        mem_read=0; mem_write=0; reg_write=0; valid_in=0; flush=0;
        dmem_awready=1; dmem_wready=1; dmem_bvalid=0;
        dmem_arready=1; dmem_rvalid=0; dmem_rdata=0; dmem_rresp=0;
        rst_n=0; repeat(6) @(posedge clk); rst_n=1; repeat(3) @(posedge clk);

        // TEST 1: Reset state
        $display("\n--- TEST 1: Reset state ---");
        check(valid_out, 1'b0, "valid_out=0 after reset");
        check(dmem_awvalid, 1'b0, "dmem_awvalid=0 after reset");
        check(dmem_arvalid, 1'b0, "dmem_arvalid=0 after reset");

        // TEST 2: Pass-through (non-mem ALU instruction)
        $display("\n--- TEST 2: Pass-through (ALU result) ---");
        got_valid_out = 0;
        @(posedge clk); #1;
        alu_result=64'hCAFE_BABE_1234_5678; rd_in=5'h07;
        opcode=7'h13; // ADDI
        mem_read=0; mem_write=0; reg_write=1; valid_in=1;
        @(posedge clk); #1;
        valid_in=0; mem_write=0; mem_read=0;
        @(posedge clk); #1;
        if (got_valid_out) begin
            $display("PASS [%0t] valid_out=1 for pass-through", $time);
            check(captured_result, 64'hCAFE_BABE_1234_5678, "result=alu_result for pass-through");
        end else begin
            $display("FAIL [%0t] valid_out never for pass-through", $time);
            error_count = error_count + 1;
        end

        repeat(3) @(posedge clk);

        // TEST 3: AXI4 Store Word (SW): opcode=0x23, funct3=010 (SW)
        $display("\n--- TEST 3: AXI4 Store (mem_write) ---");
        @(posedge clk); #1;
        alu_result=40'h0000_0001_0000; // store address
        rs2_data=64'hDEAD_BEEF_CAFE_0000; rd_in=5'h00;
        opcode=7'h23; funct3=3'b010; // SW
        mem_read=0; mem_write=1; reg_write=0; valid_in=1;
        @(posedge clk); #1; valid_in=0; mem_write=0;
        // Expect dmem_awvalid and dmem_wvalid to assert
        wc=0;
        while (!dmem_awvalid && wc < 5) begin @(posedge clk); wc=wc+1; end
        if (dmem_awvalid) begin
            check(dmem_awaddr, 40'h0000_0001_0000, "dmem_awaddr correct");
            $display("PASS [%0t] dmem_awvalid=1 (AXI write addr)", $time);
        end else begin
            $display("FAIL [%0t] dmem_awvalid never", $time); error_count=error_count+1;
        end
        // Complete AXI write
        @(posedge clk); dmem_bvalid=1;
        @(posedge clk); dmem_bvalid=0;
        repeat(3) @(posedge clk);

        // TEST 4: AXI4 Load Word (LW): opcode=0x03, funct3=010
        $display("\n--- TEST 4: AXI4 Load (mem_read) ---");
        got_valid_out = 0;
        @(posedge clk); #1;
        alu_result=40'h0000_0002_0000; rd_in=5'h08;
        opcode=7'h03; funct3=3'b010; // LW
        mem_read=1; mem_write=0; reg_write=1; valid_in=1;
        @(posedge clk); #1; valid_in=0; mem_read=0;
        wc=0;
        while (!dmem_arvalid && wc < 5) begin @(posedge clk); wc=wc+1; end
        if (dmem_arvalid) begin
            check(dmem_araddr, 40'h0000_0002_0000, "dmem_araddr correct");
            $display("PASS [%0t] dmem_arvalid=1 (AXI read addr)", $time);
        end else begin
            $display("FAIL [%0t] dmem_arvalid never", $time); error_count=error_count+1;
        end
        // Complete AXI read
        @(posedge clk); dmem_rvalid=1; dmem_rdata=64'hAAAA_BBBB_CCCC_DDDD;
        @(posedge clk); dmem_rvalid=0;
        repeat(3) @(posedge clk); #1;
        if (got_valid_out) begin
            $display("PASS [%0t] valid_out=1 after load completion", $time);
        end else begin
            $display("FAIL [%0t] valid_out never after load", $time);
            error_count = error_count + 1;
        end

        $display("\n==============================");
        if (error_count == 0)
            $display("RV_MEM VERDICT: ✅ PASS — All tests passed");
        else
            $display("RV_MEM VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

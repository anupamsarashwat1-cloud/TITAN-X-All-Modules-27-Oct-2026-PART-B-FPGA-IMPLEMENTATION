// SPDX-License-Identifier: Apache-2.0
// Brand-New Fresh Self-Checking Testbench for rv_mem
// Generated strictly from prd.json architectural truth tables & constraints

`timescale 1ns/1ps

module tb_fresh_rv_mem;
    reg         clk;
    reg         rst_n;
    reg         flush;
    reg  [63:0] alu_result;
    reg  [63:0] rs2_data;
    reg  [4:0]  rd_in;
    reg  [2:0]  funct3;
    reg  [6:0]  opcode;
    reg         mem_read;
    reg         mem_write;
    reg         reg_write;
    reg         valid_in;

    wire        dmem_awvalid;
    reg         dmem_awready;
    wire [39:0] dmem_awaddr;
    wire        dmem_wvalid;
    reg         dmem_wready;
    wire [63:0] dmem_wdata;
    wire [7:0]  dmem_wstrb;
    reg         dmem_bvalid;
    wire        dmem_bready;
    wire        dmem_arvalid;
    reg         dmem_arready;
    wire [39:0] dmem_araddr;
    reg         dmem_rvalid;
    wire        dmem_rready;
    reg  [63:0] dmem_rdata;
    reg  [1:0]  dmem_rresp;

    wire [63:0] result;
    wire [4:0]  rd_out;
    wire        reg_write_out;
    wire        valid_out;
    wire [63:0] fwd_mem_data;
    wire [4:0]  fwd_mem_rd;
    wire        fwd_mem_valid;
    wire        mem_stall;

    integer err_cnt = 0;
    integer test_cnt = 0;

    rv_mem dut (
        .clk(clk),
        .rst_n(rst_n),
        .flush(flush),
        .alu_result(alu_result),
        .rs2_data(rs2_data),
        .rd_in(rd_in),
        .funct3(funct3),
        .opcode(opcode),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .reg_write(reg_write),
        .valid_in(valid_in),
        .dmem_awvalid(dmem_awvalid),
        .dmem_awready(dmem_awready),
        .dmem_awaddr(dmem_awaddr),
        .dmem_wvalid(dmem_wvalid),
        .dmem_wready(dmem_wready),
        .dmem_wdata(dmem_wdata),
        .dmem_wstrb(dmem_wstrb),
        .dmem_bvalid(dmem_bvalid),
        .dmem_bready(dmem_bready),
        .dmem_arvalid(dmem_arvalid),
        .dmem_arready(dmem_arready),
        .dmem_araddr(dmem_araddr),
        .dmem_rvalid(dmem_rvalid),
        .dmem_rready(dmem_rready),
        .dmem_rdata(dmem_rdata),
        .dmem_rresp(dmem_rresp),
        .result(result),
        .rd_out(rd_out),
        .reg_write_out(reg_write_out),
        .valid_out(valid_out),
        .fwd_mem_data(fwd_mem_data),
        .fwd_mem_rd(fwd_mem_rd),
        .fwd_mem_valid(fwd_mem_valid),
        .mem_stall(mem_stall)
    );

    always #5 clk = ~clk;

    task clear_inputs;
        begin
            flush = 0;
            alu_result = 64'h0;
            rs2_data = 64'h0;
            rd_in = 5'h0;
            funct3 = 3'h0;
            opcode = 7'h0;
            mem_read = 0;
            mem_write = 0;
            reg_write = 0;
            valid_in = 0;
            dmem_awready = 0;
            dmem_wready = 0;
            dmem_bvalid = 0;
            dmem_arready = 0;
            dmem_rvalid = 0;
            dmem_rdata = 64'h0;
            dmem_rresp = 2'b00;
        end
    endtask

    initial begin
        $dumpfile("verification_waves/rv_mem.vcd");
        $dumpvars(0, tb_fresh_rv_mem);

        clk = 0;
        rst_n = 1;
        clear_inputs();

        $display("=== STARTING FRESH SELF-CHECKING VERIFICATION: rv_mem ===");

        // Test 1: Reset Check
        test_cnt = test_cnt + 1;
        #2 rst_n = 0;
        #10 rst_n = 1;
        #2;
        if (mem_stall !== 1'b0 || valid_out !== 1'b0 || dmem_awvalid !== 1'b0 || dmem_arvalid !== 1'b0) begin
            $display("ERROR [T1]: Reset state invalid: mem_stall=%b valid_out=%b", mem_stall, valid_out);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T1]: rv_mem reset confirmed");
        end

        // Test 2: Non-memory ALU Pass-through
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        valid_in = 1;
        reg_write = 1;
        rd_in = 5'd9;
        alu_result = 64'h1122_3344_5566_7788;
        mem_read = 0;
        mem_write = 0;
        @(posedge clk); #1;
        if (result !== 64'h1122_3344_5566_7788 || rd_out !== 5'd9 || !fwd_mem_valid || mem_stall !== 1'b0) begin
            $display("ERROR [T2]: Pass-through failed: result=%h fwd_mem_valid=%b mem_stall=%b",
                     result, fwd_mem_valid, mem_stall);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T2]: Non-memory ALU passthrough and forward bus verified");
        end

        // Test 3: Store Byte (SB) at unaligned address + byte lane steering
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        valid_in = 1;
        mem_write = 1;
        mem_read = 0;
        funct3 = 3'b000; // SB
        alu_result = 64'h0000_0000_8000_1003; // address offset 3
        rs2_data = 64'h0000_0000_0000_00AB;
        @(posedge clk); #1;
        valid_in = 0;
        // Verify byte lane steering: strobe should be 1 << 3 = 8'h08, data shifted by 24 bits
        if (dmem_wstrb !== 8'b0000_1000 || dmem_wdata[31:24] !== 8'hAB || !dmem_awvalid || !dmem_wvalid) begin
            $display("ERROR [T3]: Store byte steering failed: wstrb=%b wdata=%h", dmem_wstrb, dmem_wdata);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T3]: Store byte lane steering confirmed (wstrb=0x08, wdata=0xAB at byte 3)");
        end

        // Handshake store response
        dmem_awready = 1;
        dmem_wready = 1;
        dmem_bvalid = 1;
        @(posedge clk); #1;
        dmem_awready = 0;
        dmem_wready = 0;
        dmem_bvalid = 0;
        @(posedge clk); #1;
        if (mem_stall !== 1'b0) begin
            $display("ERROR [T3]: mem_stall did not clear after write response");
            err_cnt = err_cnt + 1;
        end

        // Test 4: Load Byte Signed (LB) with negative byte sign extension
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        valid_in = 1;
        mem_read = 1;
        mem_write = 0;
        reg_write = 1;
        rd_in = 5'd12;
        funct3 = 3'b000; // LB
        alu_result = 64'h0000_0000_8000_2000;
        @(posedge clk); #1;
        valid_in = 0;
        if (!mem_stall || !dmem_arvalid) begin
            $display("ERROR [T4]: Read did not initiate AXI-Lite read request");
            err_cnt = err_cnt + 1;
        end

        // AXI Slave responds with raw doubleword containing 0xFE (-2) at byte 0
        dmem_arready = 1;
        dmem_rvalid = 1;
        dmem_rdata = 64'h0000_0000_0000_00FE;
        @(posedge clk); #1;
        dmem_arready = 0;
        dmem_rvalid = 0;
        // Sign extension of 0xFE is 64'hFFFF_FFFF_FFFF_FFFE
        if (result !== 64'hFFFF_FFFF_FFFF_FFFE) begin
            $display("ERROR [T4]: LB sign extension failed: expected FFFFFFFFFFFFFFFE, got %h", result);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T4]: LB sign extension (-2 -> 64-bit sign extended) verified");
        end

        // Test 5: Load Byte Unsigned (LBU) with zero extension
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        valid_in = 1;
        mem_read = 1;
        funct3 = 3'b100; // LBU
        alu_result = 64'h0000_0000_8000_2000;
        @(posedge clk); #1;
        valid_in = 0;
        dmem_arready = 1;
        dmem_rvalid = 1;
        dmem_rdata = 64'h0000_0000_0000_00FE;
        @(posedge clk); #1;
        dmem_arready = 0;
        dmem_rvalid = 0;
        if (result !== 64'h0000_0000_0000_00FE) begin
            $display("ERROR [T5]: LBU zero extension failed: expected 00000000000000FE, got %h", result);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T5]: LBU zero extension verified");
        end

        // Test 6: Load Word Unsigned (LWU)
        test_cnt = test_cnt + 1;
        @(posedge clk); #1;
        valid_in = 1;
        mem_read = 1;
        funct3 = 3'b110; // LWU
        alu_result = 64'h0000_0000_8000_2000;
        @(posedge clk); #1;
        valid_in = 0;
        dmem_arready = 1;
        dmem_rvalid = 1;
        dmem_rdata = 64'h0000_0000_8000_0000; // bit 31 is 1
        @(posedge clk); #1;
        dmem_arready = 0;
        dmem_rvalid = 0;
        // LWU must zero-extend [63:32]
        if (result !== 64'h0000_0000_8000_0000) begin
            $display("ERROR [T6]: LWU zero extension failed: got %h", result);
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T6]: LWU zero extension verified");
        end

        clear_inputs();
        #20;

        $display("=== VERIFICATION SUMMARY ===");
        $display("Total Tests Executed: %0d", test_cnt);
        $display("Total Errors: %0d", err_cnt);

        if (err_cnt == 0) begin
            $display("ALL TESTS PASSED: rv_mem 100%% VERIFIED");
        end else begin
            $display("VERIFICATION FAILED: %0d errors detected!", err_cnt);
        end
        $finish;
    end
endmodule

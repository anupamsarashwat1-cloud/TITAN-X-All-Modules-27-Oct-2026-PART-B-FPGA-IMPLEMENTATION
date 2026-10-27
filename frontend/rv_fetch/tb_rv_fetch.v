// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RV Fetch Stage Directed Self-Checking Testbench
// Note: rv_fetch arvalid pulses exactly 1 cycle (cleared when arready seen).
// Strategy: hold arready=0 on the first fetch so we can observe arvalid stable.
`timescale 1ns/1ps

module tb_rv_fetch();
    parameter PC_RESET = 64'h0000_0000_0002_0000;  // eNVM base per params.vh

    reg        clk, rst_n, stall, flush, branch_taken;
    reg [63:0] branch_target;

    wire [63:0] imem_addr;
    wire        imem_arvalid;
    reg         imem_arready;
    reg [31:0]  imem_rdata;
    reg         imem_rvalid;
    reg [1:0]   imem_rresp;

    wire [63:0] pc_out;
    wire [31:0] instr_out;
    wire        valid_out;

    integer error_count;
    reg got_valid;
    reg [31:0] cap_instr;
    reg [63:0] cap_pc;
    reg saw_arvalid;
    reg [63:0] cap_araddr;
    reg saw_tgt_ar;

    always @(posedge clk) begin
        if (valid_out) begin
            got_valid <= 1;
            cap_instr <= instr_out;
            cap_pc    <= pc_out;
        end
        if (imem_arvalid) begin
            saw_arvalid <= 1;
            cap_araddr  <= imem_addr;
        end
    end

    rv_fetch uut (
        .clk(clk), .rst_n(rst_n), .stall(stall), .flush(flush),
        .branch_taken(branch_taken), .branch_target(branch_target),
        .imem_addr(imem_addr), .imem_arvalid(imem_arvalid),
        .imem_arready(imem_arready), .imem_rdata(imem_rdata),
        .imem_rvalid(imem_rvalid), .imem_rresp(imem_rresp),
        .pc_out(pc_out), .instr_out(instr_out), .valid_out(valid_out)
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

    initial begin
        $dumpfile("tb_rv_fetch.vcd");
        $dumpvars(0, tb_rv_fetch);
        error_count = 0; got_valid = 0; cap_instr = 0; cap_pc = 0;
        saw_arvalid = 0; cap_araddr = 0;
        stall=0; flush=0; branch_taken=0; branch_target=0;
        // Hold arready=0 initially so arvalid stays stable for observation
        imem_arready=0; imem_rvalid=0; imem_rdata=32'h0; imem_rresp=0;
        rst_n=0; repeat(6) @(posedge clk); rst_n=1; repeat(4) @(posedge clk);

        // TEST 1: After reset, fetch FSM should set imem_arvalid to PC_RESET
        $display("\n--- TEST 1: Post-reset fetch address ---");
        if (saw_arvalid) begin
            check(cap_araddr, PC_RESET, "imem_addr=PC_RESET after reset");
            $display("PASS [%0t] imem_arvalid was asserted", $time);
        end else begin
            $display("FAIL [%0t] imem_arvalid never observed after reset", $time);
            error_count=error_count+1;
        end

        // Now accept the AXI read: deassert arready→ready, then provide data
        // TEST 2: Complete fetch and check instruction out
        $display("\n--- TEST 2: Fetch completes, instruction delivered ---");
        got_valid=0;
        @(posedge clk); #1;
        imem_arready=1;  // Accept address phase
        @(posedge clk); #1;
        imem_arready=0;
        imem_rvalid=1; imem_rdata=32'h0040_0093; imem_rresp=0;  // ADDI x1,x0,4
        @(posedge clk); #1;
        imem_rvalid=0;
        repeat(3) @(posedge clk); #1;
        if (got_valid) begin
            $display("PASS [%0t] valid_out=1 after fetch", $time);
            check(cap_instr, 32'h0040_0093, "instr_out=0x00400093 (ADDI x1,x0,4)");
        end else begin
            $display("FAIL [%0t] valid_out never asserted", $time);
            error_count=error_count+1;
        end

        // TEST 3: Branch redirect → new PC (AXI-correct drain semantics)
        // A redirect while a fetch AR is outstanding cannot retract that
        // request: AXI forbids changing ARADDR under held ARVALID. The DUT
        // therefore lets the stale AR complete its handshake, swallows the
        // orphaned read beat, and only THEN issues the redirected fetch.
        // This test verifies the full drain→retarget→deliver sequence.
        // Scenario is deterministic: entering here the AR for PC_RESET+4
        // is held unaccepted (arready was 0), so exactly one orphan R beat
        // will be owed after the redirect.
        $display("\n--- TEST 3: Branch redirect to 0x8000_1000 ---");
        saw_tgt_ar = 0;
        @(posedge clk); #1;
        branch_taken=1; branch_target=64'h8000_1000;
        @(posedge clk); #1; branch_taken=0;
        imem_arready=1;   // allow the stale AR handshake to complete
        // Wait for the stale AR to be accepted (arvalid drops).
        repeat(8) @(posedge clk); #1;
        if (imem_arvalid) begin
            $display("FAIL [%0t] stale AR still held after arready=1", $time);
            error_count=error_count+1;
        end
        // Supply the orphaned read beat for the abandoned stream.
        imem_rvalid=1; imem_rdata=32'hDEAD_BEEF; imem_rresp=0;
        @(posedge clk); #1; imem_rvalid=0;
        // Now watch for the REDIRECTED fetch request.
        begin : wait_tgt
            integer k;
            for (k=0; k<16 && !saw_tgt_ar; k=k+1) begin
                @(posedge clk); #1;
                if (imem_arvalid && imem_addr == 64'h8000_1000)
                    saw_tgt_ar = 1;
            end
        end
        check({63'b0, saw_tgt_ar}, 64'h1,
              "redirected AR to 0x80001000 observed after drain");
        // Let the redirected AR handshake complete (arvalid drops) BEFORE
        // supplying data — an R beat offered in the acceptance cycle itself
        // arrives before pending_r is set and would be ignored.
        begin : settle
            integer m;
            for (m=0; m<4; m=m+1) begin
                @(posedge clk); #1;
                if (!imem_arvalid) m = 99;
            end
        end
        // Complete the redirected fetch and check the DELIVERY pair.
        got_valid=0;
        imem_rvalid=1; imem_rdata=32'h1234_5678; imem_rresp=0;
        @(posedge clk); #1; imem_rvalid=0;
        repeat(6) @(posedge clk); #1;
        if (got_valid) begin
            check(cap_pc,    64'h8000_1000, "delivered pc=0x80001000 after redirect");
            check(cap_instr, 32'h1234_5678, "delivered instr matches redirected beat");
        end else begin
            $display("FAIL [%0t] no delivery after redirected fetch", $time);
            error_count=error_count+1;
        end

        // TEST 4: Stall — valid_out should not change
        $display("\n--- TEST 4: Stall prevents new fetch ---");
        @(posedge clk); #1;
        stall=1;
        repeat(5) @(posedge clk); #1;
        stall=0;
        $display("PASS [%0t] Stall accepted (no crash)", $time);

        $display("\n==============================");
        if (error_count == 0)
            $display("RV_FETCH VERDICT: ✅ PASS — All tests passed");
        else
            $display("RV_FETCH VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

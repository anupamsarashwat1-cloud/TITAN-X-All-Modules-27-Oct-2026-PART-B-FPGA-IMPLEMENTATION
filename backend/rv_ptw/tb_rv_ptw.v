// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RV PTW (Page Table Walker) Directed Self-Checking Testbench
// Tests: PTW walks a 3-level Sv39 page table via AXI4-lite bus
// PTW reads PTE from memory, fills TLB on success, raises page_fault on error
`timescale 1ns/1ps

module tb_rv_ptw();
    reg        clk, rst_n;
    // Request interface
    reg  [38:0] va_req;
    reg  [15:0] asid_req;
    reg  [43:0] satp_ppn;
    reg         ptw_req, access_r, access_w, access_x, priv_s;
    wire        ptw_busy;
    // TLB fill interface
    wire        fill_valid;
    wire [38:0] fill_va;
    wire [37:0] fill_pa;
    wire [15:0] fill_asid;
    wire [7:0]  fill_perm;
    wire [1:0]  fill_level;
    // Fault
    wire        page_fault;
    wire [63:0] fault_addr;
    // AXI4-lite memory interface
    wire        ptw_arvalid;
    reg         ptw_arready;
    wire [39:0] ptw_araddr;
    reg         ptw_rvalid;
    wire        ptw_rready;
    reg  [63:0] ptw_rdata;
    reg  [1:0]  ptw_rresp;

    integer error_count;

    rv_ptw uut (
        .clk(clk), .rst_n(rst_n),
        .va_req(va_req), .asid_req(asid_req), .satp_ppn(satp_ppn),
        .ptw_req(ptw_req), .access_r(access_r), .access_w(access_w),
        .access_x(access_x), .priv_s(priv_s),
        .ptw_busy(ptw_busy),
        .fill_valid(fill_valid), .fill_va(fill_va), .fill_pa(fill_pa),
        .fill_asid(fill_asid), .fill_perm(fill_perm), .fill_level(fill_level),
        .page_fault(page_fault), .fault_addr(fault_addr),
        .ptw_arvalid(ptw_arvalid), .ptw_arready(ptw_arready),
        .ptw_araddr(ptw_araddr),
        .ptw_rvalid(ptw_rvalid), .ptw_rready(ptw_rready),
        .ptw_rdata(ptw_rdata), .ptw_rresp(ptw_rresp)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [63:0] got; input [63:0] exp; input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=0x%X exp=0x%X", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    // Sv39 PTE format: [63:54]=reserved, [53:10]=PPN[2:0], [9:8]=RSW,
    //                  [7]=D, [6]=A, [5]=G, [4]=U, [3]=X, [2]=W, [1]=R, [0]=V
    // Leaf PTE with read permission: V=1, R=1, perm=0x03 (V+R no write/exec)
    // Non-leaf: V=1, R=0, W=0, X=0 → pointer to next level
    //
    // 3-level walk:
    //   satp_ppn = 44'h0000_1000   (root PT at PA 0x1000_000)
    //   VA       = 39'h0000_0000   (VPN[2]=0, VPN[1]=0, VPN[0]=0, offset=0)
    //   Level 2 PTE addr = satp_ppn*4096 + VPN[2]*8 = 0x1000_0000 + 0 = 0x1000_0000
    //   Level 2 PTE data = pointer to L1 PT: ppn=44'h0000_2000 + V=1 → 0x000_0002_0000_0001
    //   Level 1 PTE addr = 0x2000_0000 + VPN[1]*8 = 0x2000_0000
    //   Level 1 PTE data = pointer to L0 PT: ppn=44'h0000_3000 + V=1 → 0x000_0003_0000_0001
    //   Level 0 PTE addr = 0x3000_0000 + VPN[0]*8 = 0x3000_0000
    //   Level 0 PTE data = leaf: ppn=44'h0000_4000 + V=1 + R=1 + A=1 → 0x000_0004_0000_00C3
    //
    // After fill: fill_pa should be 44'h0000_4000 = 38'h0001_0000

    // State machine to serve 3 AXI reads
    integer walk_step;
    reg served;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ptw_arready <= 1;
            ptw_rvalid  <= 0;
            ptw_rdata   <= 0;
            ptw_rresp   <= 0;
            walk_step   <= 0;
            served      <= 0;
        end else begin
            if (ptw_arvalid && ptw_arready && !served) begin
                ptw_arready <= 0;
                case (walk_step)
                    0: ptw_rdata <= 64'h0000_0002_0000_0001; // L2: pointer ppn=2000
                    1: ptw_rdata <= 64'h0000_0003_0000_0001; // L1: pointer ppn=3000
                    2: begin
                           ptw_rdata <= 64'h0000_0004_0000_00C3; // L0: leaf R/V/A/D
                           served <= 1;
                       end
                    default: ptw_rdata <= 64'hDEAD_BEEF;
                endcase
                ptw_rvalid <= 1;
                walk_step  <= walk_step + 1;
            end
            if (ptw_rvalid && ptw_rready) begin
                ptw_rvalid  <= 0;
                ptw_arready <= 1;
            end
        end
    end

    integer wc;

    initial begin
        $dumpfile("tb_rv_ptw.vcd");
        $dumpvars(0, tb_rv_ptw);
        error_count = 0;
        va_req=0; asid_req=0; satp_ppn=44'h0000_0001; // root page at PA 0x1000
        ptw_req=0; access_r=1; access_w=0; access_x=0; priv_s=0;
        rst_n=0; repeat(6) @(posedge clk); rst_n=1; repeat(3) @(posedge clk);

        // TEST 1: Reset state
        $display("\n--- TEST 1: Reset state ---");
        @(posedge clk); #1;
        check(ptw_busy,    1'b0, "ptw_busy=0 after reset");
        check(fill_valid,  1'b0, "fill_valid=0 after reset");
        check(page_fault,  1'b0, "page_fault=0 after reset");

        // TEST 2: PTW request — 3-level walk for VA=0
        $display("\n--- TEST 2: 3-level walk VA=0x0000 ---");
        // satp_ppn points to root PT at physical 0x1000*4096=0x1000_000
        satp_ppn = 44'h0000_0001;  // ppn=1, PA = 1*4096 = 0x1000 (4KB aligned)
        @(negedge clk);
        va_req=39'h0; asid_req=16'h0001; ptw_req=1;
        @(posedge clk); #1;
        ptw_req = 0;  // deassert after 1 cycle

        // Wait for fill_valid or page_fault
        wc=0;
        while (!fill_valid && !page_fault && wc < 200) begin
            @(posedge clk); wc=wc+1;
        end

        if (fill_valid) begin
            $display("PASS [%0t] fill_valid=1 after PTW walk", $time);
            $display("INFO: fill_pa=0x%X fill_perm=0x%02X fill_level=%0d",
                     fill_pa, fill_perm, fill_level);
            // Check R bit in fill_perm (bit 1 = R)
            if (fill_perm[1])
                $display("PASS [%0t] fill_perm[R]=1 (read allowed)", $time);
            else begin
                $display("FAIL [%0t] fill_perm[R]=0 (should be read-mapped)", $time);
                error_count=error_count+1;
            end
        end else if (page_fault) begin
            $display("FAIL [%0t] page_fault on valid walk (should not fault)", $time);
            error_count=error_count+1;
        end else begin
            $display("FAIL [%0t] PTW never completed (fill_valid/page_fault never)", $time);
            error_count=error_count+1;
        end
        repeat(5) @(posedge clk);

        // TEST 3: PTW not busy after completion
        $display("\n--- TEST 3: ptw_busy released after fill ---");
        @(posedge clk); #1;
        if (!ptw_busy)
            $display("PASS [%0t] ptw_busy=0 after completion", $time);
        else begin
            $display("FAIL [%0t] ptw_busy still=1 after fill", $time);
            error_count=error_count+1;
        end

        $display("\n==============================");
        if (error_count == 0)
            $display("RV_PTW VERDICT: ✅ PASS — All tests passed");
        else
            $display("RV_PTW VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end
    initial begin #5_000_000; $display("WATCHDOG TIMEOUT"); $finish; end
endmodule

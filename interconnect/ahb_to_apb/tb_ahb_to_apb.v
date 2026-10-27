// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — AHB-to-APB Bridge Directed Self-Checking Testbench
// Tests: AHB write→APB forwarding, AHB read←APB return, multi-transaction
`timescale 1ns / 1ps

module tb_ahb_to_apb();

    reg         clk;
    reg         rst_n;

    // AHB master side
    reg  [31:0] haddr;
    reg         hwrite;
    reg  [1:0]  htrans;
    reg  [31:0] hwdata;
    wire [31:0] hrdata;
    wire        hready_out;
    wire        hresp;

    // APB slave side (simple register model)
    wire [31:0] paddr;
    wire        psel;
    wire        penable;
    wire        pwrite;
    wire [31:0] pwdata;
    reg  [31:0] prdata;
    reg         pready;
    reg         pslverr;

    integer error_count;

    // AHB HTRANS encodings
    localparam IDLE   = 2'b00;
    localparam NONSEQ = 2'b10;

    ahb_to_apb uut (
        .clk(clk), .rst_n(rst_n),
        .haddr(haddr), .hwrite(hwrite), .htrans(htrans),
        .hwdata(hwdata), .hrdata(hrdata),
        .hready_out(hready_out), .hresp(hresp),
        .paddr(paddr), .psel(psel), .penable(penable),
        .pwrite(pwrite), .pwdata(pwdata), .prdata(prdata),
        .pready(pready), .pslverr(pslverr)
    );

    initial clk = 0;
    always #3.6 clk = ~clk;

    // Simple APB register file (8 x 32-bit regs)
    reg [31:0] apb_mem [0:7];
    integer i;
    initial for (i=0; i<8; i=i+1) apb_mem[i] = 32'hDEAD_0000 + i;

    // APB slave response
    always @(posedge clk) begin
        pready <= 1'b0;
        if (psel && penable) begin
            pready <= 1'b1;
            if (pwrite)
                apb_mem[paddr[4:2]] <= pwdata;
            else
                prdata <= apb_mem[paddr[4:2]];
        end
    end

    task check;
        input [63:0] got;
        input [63:0] expected;
        input [255:0] msg;
        begin
            if (got !== expected) begin
                $display("FAIL [%0t] %s: got=0x%08X expected=0x%08X", $time, msg, got, expected);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    // AHB write task
    task ahb_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk); #1;
            haddr  = addr;
            hwrite = 1;
            htrans = NONSEQ;
            hwdata = data;
            @(posedge clk); #1;
            htrans = IDLE;
            hwrite = 0;
            // Wait for hready_out
            while (!hready_out) @(posedge clk);
        end
    endtask

    // AHB read task
    task ahb_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk); #1;
            haddr  = addr;
            hwrite = 0;
            htrans = NONSEQ;
            @(posedge clk); #1;
            htrans = IDLE;
            // Wait for hready_out
            while (!hready_out) @(posedge clk);
            data = hrdata;
        end
    endtask

    reg [31:0] rdata;

    initial begin
        $dumpfile("tb_ahb_to_apb.vcd");
        $dumpvars(0, tb_ahb_to_apb);
        error_count = 0;
        haddr = 0; hwrite = 0; htrans = IDLE; hwdata = 0;
        prdata = 0; pready = 0; pslverr = 0;

        // Reset
        rst_n = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(3) @(posedge clk);

        // ==============================================================
        // TEST 1: hresp always 0 (OKAY)
        // ==============================================================
        $display("\n--- TEST 1: hresp = OKAY ---");
        check(hresp, 1'b0, "hresp = OKAY");

        // ==============================================================
        // TEST 2: AHB Write — verify APB psel/penable sequence
        // ==============================================================
        $display("\n--- TEST 2: AHB write → APB forwarding ---");
        ahb_write(32'h0000_0010, 32'hCAFE_BABE);
        // After transaction, check APB memory was written
        check(apb_mem[4], 32'hCAFE_BABE, "APB mem[4] = 0xCAFE_BABE after AHB write");

        // ==============================================================
        // TEST 3: AHB Write — another address
        // ==============================================================
        $display("\n--- TEST 3: AHB write addr 0x1C ---");
        ahb_write(32'h0000_001C, 32'hDEAD_BEEF);
        check(apb_mem[7], 32'hDEAD_BEEF, "APB mem[7] = 0xDEAD_BEEF after AHB write");

        // ==============================================================
        // TEST 4: AHB Read — verify APB prdata forwarded to hrdata
        // ==============================================================
        $display("\n--- TEST 4: AHB read ← APB ---");
        ahb_read(32'h0000_0010, rdata);
        check(rdata, 32'hCAFE_BABE, "hrdata = 0xCAFE_BABE (AHB read)");

        // ==============================================================
        // TEST 5: Multiple back-to-back AHB writes
        // ==============================================================
        $display("\n--- TEST 5: Back-to-back writes ---");
        ahb_write(32'h0000_0000, 32'h0000_0001);
        ahb_write(32'h0000_0004, 32'h0000_0002);
        ahb_write(32'h0000_0008, 32'h0000_0003);
        check(apb_mem[0], 32'h1, "apb_mem[0]=1");
        check(apb_mem[1], 32'h2, "apb_mem[1]=2");
        check(apb_mem[2], 32'h3, "apb_mem[2]=3");

        // ==============================================================
        // TEST 6: Read back in sequence
        // ==============================================================
        $display("\n--- TEST 6: Sequential reads ---");
        ahb_read(32'h0000_0000, rdata); check(rdata, 32'h1, "ahb_read[0]=1");
        ahb_read(32'h0000_0004, rdata); check(rdata, 32'h2, "ahb_read[1]=2");
        ahb_read(32'h0000_0008, rdata); check(rdata, 32'h3, "ahb_read[2]=3");

        // ==============================================================
        // TEST 7: IDLE on AHB does not trigger APB cycle
        // ==============================================================
        $display("\n--- TEST 7: IDLE → no APB activity ---");
        htrans = IDLE; hwrite = 0;
        repeat(10) @(posedge clk);
        check(psel, 1'b0, "psel=0 during AHB IDLE");

        // ==============================================================
        // FINAL RESULT
        // ==============================================================
        repeat(10) @(posedge clk);
        $display("\n==============================");
        if (error_count == 0)
            $display("AHB-to-APB VERDICT: ✅ PASS — All tests passed");
        else
            $display("AHB-to-APB VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end

    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end

endmodule

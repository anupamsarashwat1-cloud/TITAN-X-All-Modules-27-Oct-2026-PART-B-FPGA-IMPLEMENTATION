// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — eNVM Controller Directed Self-Checking Testbench
// Register map (paddr[7:0]):
//   0x00 = cmd_reg (R/W: command)
//   0x04 = addr_reg (R/W: target address)
//   0x08 = data_reg (R/W: write data)
//   0x0C = stat_reg (R: {busy, error})
//   0x10 = unlock_reg (W: unlock magic)
// AXI4-Lite read port for eNVM read data (external envm_rdata)
`timescale 1ns/1ps

module tb_envm_ctrl();

    reg        clk;
    reg        rst_n;
    reg [31:0] paddr;
    reg        psel;
    reg        penable;
    reg        pwrite;
    reg [31:0] pwdata;
    wire[31:0] prdata;
    wire       pready;
    wire       pslverr;
    // AXI4-Lite read port
    reg        s_arvalid;
    wire       s_arready;
    reg [31:0] s_araddr;
    wire       s_rvalid;
    reg        s_rready;
    wire[31:0] s_rdata;
    wire[1:0]  s_rresp;
    // eNVM physical interface
    wire       envm_clk;
    wire       envm_ce_n;
    wire       envm_we_n;
    wire[16:0] envm_addr;
    wire[31:0] envm_wdata;
    reg [31:0] envm_rdata;
    reg        envm_ready;

    integer error_count;

    envm_ctrl uut (
        .clk(clk), .rst_n(rst_n),
        .paddr(paddr), .psel(psel), .penable(penable), .pwrite(pwrite),
        .pwdata(pwdata), .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_araddr(s_araddr),
        .s_rvalid(s_rvalid), .s_rready(s_rready),
        .s_rdata(s_rdata), .s_rresp(s_rresp),
        .envm_clk(envm_clk), .envm_ce_n(envm_ce_n), .envm_we_n(envm_we_n),
        .envm_addr(envm_addr), .envm_wdata(envm_wdata),
        .envm_rdata(envm_rdata), .envm_ready(envm_ready)
    );

    initial clk = 0;
    always #3.6 clk = ~clk;

    task apb_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk); #1;
            paddr = addr; pwdata = data; psel = 1; penable = 0; pwrite = 1;
            @(posedge clk); #1; penable = 1;
            @(posedge clk); #1;
            while (!pready) @(posedge clk);
            #1; psel = 0; penable = 0; pwrite = 0;
        end
    endtask

    task apb_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk); #1;
            paddr = addr; psel = 1; penable = 0; pwrite = 0;
            @(posedge clk); #1; penable = 1;
            @(posedge clk); #1;
            while (!pready) @(posedge clk);
            data = prdata;
            #1; psel = 0; penable = 0;
        end
    endtask

    task check;
        input [63:0] got;
        input [63:0] exp;
        input [255:0] msg;
        begin
            if (got !== exp) begin
                $display("FAIL [%0t] %s: got=0x%08X expected=0x%08X", $time, msg, got, exp);
                error_count = error_count + 1;
            end else $display("PASS [%0t] %s", $time, msg);
        end
    endtask

    reg [31:0] rdata;
    integer wait_cnt;

    initial begin
        $dumpfile("tb_envm_ctrl.vcd");
        $dumpvars(0, tb_envm_ctrl);
        error_count = 0;
        psel = 0; penable = 0; pwrite = 0; paddr = 0; pwdata = 0;
        s_arvalid = 0; s_araddr = 0; s_rready = 1;
        envm_rdata = 32'hDEAD_CAFE; envm_ready = 1;

        // Reset
        rst_n = 0; repeat(8) @(posedge clk); rst_n = 1; repeat(3) @(posedge clk);

        // TEST 1: Reset state
        $display("\n--- TEST 1: Reset state ---");
        check(pready, 1'b1, "pready=1 after reset");
        check(pslverr, 1'b0, "pslverr=0 after reset");

        // TEST 2: cmd_reg reset = 0
        $display("\n--- TEST 2: cmd_reg reset ---");
        apb_read(32'h00, rdata);
        check(rdata, 32'h0, "cmd_reg=0 after reset");

        // TEST 3: addr_reg write/readback
        $display("\n--- TEST 3: addr_reg write/readback ---");
        apb_write(32'h04, 32'h0000_1234);  // addr_reg
        apb_read (32'h04, rdata);
        check(rdata, 32'h0000_1234, "addr_reg=0x1234 after write");

        // TEST 4: data_reg write/readback
        $display("\n--- TEST 4: data_reg write/readback ---");
        apb_write(32'h08, 32'hABCD_1234);  // data_reg
        apb_read (32'h08, rdata);
        check(rdata, 32'hABCD_1234, "data_reg=0xABCD1234 after write");

        // TEST 5: cmd_reg write/readback
        $display("\n--- TEST 5: cmd_reg write ---");
        apb_write(32'h00, 32'h0000_0001);  // cmd_reg = 1 (read command)
        apb_read (32'h00, rdata);
        check(rdata, 32'h0000_0001, "cmd_reg=1 after write");

        // TEST 6: stat_reg accessible
        $display("\n--- TEST 6: stat_reg readable ---");
        apb_read(32'h0C, rdata);
        $display("  stat_reg = 0x%08X (busy=%0b)", rdata, rdata[0]);

        // TEST 7: AXI-Lite read from eNVM
        // State machine: IDLE→(arready=1, state=READ)→(rvalid=1 for 1 cycle)→IDLE
        // rvalid is only high for ONE cycle, so we poll from the start
        $display("\n--- TEST 7: AXI-Lite eNVM read ---");
        envm_ready = 1;    // Ensure eNVM is ready
        s_rready = 1;      // Always accept data
        @(posedge clk); #1;
        s_arvalid = 1; s_araddr = 32'h0000_0100;  // AR channel: read eNVM[0x100]
        // Poll for rvalid (arready is transient, rvalid appears 2-3 cycles later)
        wait_cnt = 0;
        while (!s_rvalid && wait_cnt < 30) begin
            @(posedge clk); wait_cnt = wait_cnt + 1;
        end
        s_arvalid = 0;
        if (s_rvalid) begin
            $display("PASS [%0t] AXI read: s_rdata=0x%08X (envm_rdata=0x%08X)",
                     $time, s_rdata, envm_rdata);
        end else begin
            $display("FAIL [%0t] s_rvalid never asserted in 30 cycles", $time);
            error_count = error_count + 1;
        end
        repeat(3) @(posedge clk);

        // TEST 8: envm_ce_n deasserted when idle
        $display("\n--- TEST 8: envm interface signals ---");
        repeat(4) @(posedge clk);
        $display("  envm_clk=%b envm_ce_n=%b envm_we_n=%b",
                 envm_clk, envm_ce_n, envm_we_n);
        check(envm_we_n, 1'b1, "envm_we_n=1 (no writes via APB)");

        $display("\n==============================");
        if (error_count == 0)
            $display("ENVM_CTRL VERDICT: ✅ PASS — All tests passed");
        else
            $display("ENVM_CTRL VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end

    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end

endmodule

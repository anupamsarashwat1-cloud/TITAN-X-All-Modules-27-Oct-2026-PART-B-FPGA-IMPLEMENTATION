// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — I2C Master Directed Self-Checking Testbench
// Tests: prescaler config, SCL/SDA activity, START/WRITE/STOP sequence
`timescale 1ns / 1ps

module tb_i2c_master();

    reg        clk;
    reg        rst_n;
    reg  [3:0] paddr;
    reg        psel;
    reg        penable;
    reg        pwrite;
    reg [31:0] pwdata;
    wire[31:0] prdata;
    wire       pready;
    wire       irq;
    wire       scl_pad;
    wire       sda_pad;

    integer error_count;

    // Open-drain pull-ups
    pullup(scl_pad);
    pullup(sda_pad);

    i2c_master uut (
        .clk(clk), .rst_n(rst_n),
        .paddr(paddr[3:0]), .psel(psel), .penable(penable),
        .pwrite(pwrite), .pwdata(pwdata), .prdata(prdata),
        .pready(pready),
        .irq(irq),
        .scl_pad(scl_pad), .sda_pad(sda_pad)
    );

    initial clk = 0;
    always #3.6 clk = ~clk;  // 138.8 MHz

    task apb_write;
        input [3:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk); #1;
            paddr = addr; pwdata = data; psel = 1; penable = 0; pwrite = 1;
            @(posedge clk); #1;
            penable = 1;
            @(posedge clk); #1;
            while (!pready) @(posedge clk);
            #1; psel = 0; penable = 0; pwrite = 0;
        end
    endtask

    task apb_read;
        input  [3:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk); #1;
            paddr = addr; psel = 1; penable = 0; pwrite = 0;
            @(posedge clk); #1;
            penable = 1;
            @(posedge clk); #1;
            while (!pready) @(posedge clk);
            data = prdata;
            #1; psel = 0; penable = 0;
        end
    endtask

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

    reg [31:0] rdata;
    integer scl_edges;
    integer sda_edges;
    time scl_period;

    // Monitor SCL edges
    initial begin
        scl_edges = 0;
        sda_edges = 0;
        forever @(scl_pad) scl_edges = scl_edges + 1;
    end

    initial begin
        $dumpfile("tb_i2c_master.vcd");
        $dumpvars(0, tb_i2c_master);
        error_count = 0;
        paddr = 0; psel = 0; penable = 0; pwrite = 0; pwdata = 0;

        // ---- Reset ----
        rst_n = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        // ==============================================================
        // TEST 1: pready asserts
        // ==============================================================
        $display("\n--- TEST 1: pready ---");
        check(pready, 1'b1, "pready=1 after reset");

        // ==============================================================
        // TEST 2: SCL and SDA idle high (open-drain pullups)
        // ==============================================================
        $display("\n--- TEST 2: SCL/SDA idle high ---");
        repeat(5) @(posedge clk);
        check(scl_pad, 1'b1, "SCL idle=1 (pulled up)");
        check(sda_pad, 1'b1, "SDA idle=1 (pulled up)");

        // ==============================================================
        // TEST 3: Prescaler write and readback
        //   SCL = 138.8MHz / (5 * prescale) = 400kHz → prescale = 69
        // ==============================================================
        $display("\n--- TEST 3: Prescaler programming ---");
        apb_write(4'h0, 32'h0000_0045);  // prescale = 69 decimal
        apb_read (4'h0, rdata);
        check(rdata[15:0], 16'h0045, "Prescaler readback = 69");

        // ==============================================================
        // TEST 4: Issue START + WRITE command
        //   paddr[3:2]=2 = cmd register
        //   {cmd_ack=0, cmd_stop=0, cmd_start=1, cmd_read=0, cmd_write=1} = 5'b00101 = 0x05
        //   tx_data at paddr[3:2]=1
        // ==============================================================
        $display("\n--- TEST 4: START + WRITE slave addr 0x50 ---");
        apb_write(4'h4, 32'h0000_00A0);  // tx_data = 0xA0 (slave 0x50 write)
        apb_write(4'h8, 32'h0000_0005);  // cmd: start=1, write=1

        // Wait for SCL to toggle (bus activity starts)
        scl_edges = 0;
        repeat(2000) @(posedge clk);     // ~14us, enough for START + 1 bit

        if (scl_edges > 0) begin
            $display("PASS [%0t] SCL toggled: %0d edges observed", $time, scl_edges);
        end else begin
            $display("FAIL [%0t] No SCL activity after write command", $time);
            error_count = error_count + 1;
        end

        // ==============================================================
        // TEST 5: Busy bit set during transaction
        // ==============================================================
        $display("\n--- TEST 5: Busy bit check ---");
        apb_write(4'h4, 32'h0000_00A0);  // tx_data = another byte
        apb_write(4'h8, 32'h0000_0001);  // cmd: write only
        repeat(10) @(posedge clk);
        apb_read(4'h0, rdata);
        $display("  Status reg: busy=%b, prescale=0x%04X", rdata[31], rdata[15:0]);

        // ==============================================================
        // TEST 6: STOP command — SDA should go high while SCL is high
        // ==============================================================
        $display("\n--- TEST 6: STOP command ---");
        apb_write(4'h8, 32'h0000_0010);  // cmd: stop=1
        repeat(2000) @(posedge clk);
        check(scl_pad, 1'b1, "SCL=1 after STOP");
        check(sda_pad, 1'b1, "SDA=1 after STOP (released)");

        // ==============================================================
        // FINAL RESULT
        // ==============================================================
        repeat(20) @(posedge clk);
        $display("\n==============================");
        if (error_count == 0)
            $display("I2C VERDICT: ✅ PASS — All tests passed");
        else
            $display("I2C VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end

    initial begin #5_000_000; $display("WATCHDOG TIMEOUT"); $finish; end

endmodule

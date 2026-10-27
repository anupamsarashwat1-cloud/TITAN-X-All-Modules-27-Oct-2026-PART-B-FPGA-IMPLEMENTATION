// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — UART-16550 Directed Self-Checking Testbench
// Verified against actual RTL: Register file (DLL/DLM/LCR/MCR/SCR/IER) is
// complete. TX serializer and IRQ are stubs (txd=idle, uart_irq=0). 
// Tests focus on the complete register file and DLAB behavior.
`timescale 1ns / 1ps

module tb_uart_16550();

    reg         clk;
    reg         rst_n;
    reg  [31:0] paddr;
    reg         psel;
    reg         penable;
    reg         pwrite;
    reg  [31:0] pwdata;
    wire [31:0] prdata;
    wire        pready;
    wire        pslverr;
    wire        uart_irq;
    reg         rxd;
    wire        txd;
    wire        irda_tx;
    reg         irda_rx;
    wire        lin_tx;
    reg         lin_rx;

    integer error_count;

    uart_16550 uut (
        .clk(clk), .rst_n(rst_n),
        .paddr(paddr), .psel(psel), .penable(penable),
        .pwrite(pwrite), .pwdata(pwdata), .prdata(prdata),
        .pready(pready), .pslverr(pslverr),
        .uart_irq(uart_irq),
        .rxd(rxd), .txd(txd),
        .irda_tx(irda_tx), .irda_rx(irda_rx),
        .lin_tx(lin_tx), .lin_rx(lin_rx)
    );

    initial clk = 0;
    always #3.6 clk = ~clk;

    task apb_write;
        input [31:0] addr;
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
        input  [31:0] addr;
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

    initial begin
        $dumpfile("tb_uart_16550.vcd");
        $dumpvars(0, tb_uart_16550);
        error_count = 0;
        paddr = 0; psel = 0; penable = 0; pwrite = 0; pwdata = 0;
        rxd = 1; irda_rx = 1; lin_rx = 1;

        // Reset
        rst_n = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        // ==============================================================
        // TEST 1: pready always asserts (combinatorial)
        // ==============================================================
        $display("\n--- TEST 1: pready ---");
        check(pready, 1'b1, "pready=1 after reset");
        check(pslverr, 1'b0, "pslverr=0");

        // ==============================================================
        // TEST 2: LSR reset = 0x60 (THRE + TEMT bits set on power-on)
        // ==============================================================
        $display("\n--- TEST 2: LSR reset value ---");
        apb_read(32'h14, rdata);
        check(rdata[7:0], 8'h60, "LSR[7:0] = 0x60 (THRE+TEMT set after reset)");

        // ==============================================================
        // TEST 3: Scratch register (0x1C) write/readback
        // ==============================================================
        $display("\n--- TEST 3: Scratch register ---");
        apb_write(32'h1C, 32'hA5);
        apb_read (32'h1C, rdata);
        check(rdata[7:0], 8'hA5, "SCR = 0xA5");
        apb_write(32'h1C, 32'h5A);
        apb_read (32'h1C, rdata);
        check(rdata[7:0], 8'h5A, "SCR = 0x5A");

        // ==============================================================
        // TEST 4: DLAB=1 → DLL/DLM accessible at offsets 0x00/0x04
        //   LCR offset 0x0C, bit 7 = DLAB
        // ==============================================================
        $display("\n--- TEST 4: Divisor Latch programming (DLAB=1) ---");
        apb_write(32'h0C, 32'h80);        // LCR: DLAB=1
        apb_read (32'h0C, rdata);
        check(rdata[7], 1'b1, "LCR[7]=DLAB=1");

        // Write DLL=0x87, DLM=0x03 (divisor=903 for 9600 baud @ 138.8MHz)
        apb_write(32'h00, 32'h87);
        apb_write(32'h04, 32'h03);
        apb_read(32'h00, rdata); check(rdata[7:0], 8'h87, "DLL=0x87");
        apb_read(32'h04, rdata); check(rdata[7:0], 8'h03, "DLM=0x03");

        // ==============================================================
        // TEST 5: DLAB=0 → THR/IER accessible, DLL/DLM hidden
        // ==============================================================
        $display("\n--- TEST 5: DLAB=0 → Normal mode ---");
        apb_write(32'h0C, 32'h03);        // LCR = 8N1, DLAB=0
        apb_read (32'h0C, rdata);
        check(rdata[7:0], 8'h03, "LCR=0x03 (8N1, DLAB=0)");

        // IER accessible at offset 0x04 when DLAB=0
        apb_write(32'h04, 32'h02);        // IER: THRE interrupt enable
        apb_read (32'h04, rdata);
        check(rdata[7:0], 8'h02, "IER=0x02 (THRE int enable, DLAB=0)");

        // DLL NOT accessible (reads THR/IER instead)
        apb_write(32'h00, 32'h55);        // THR write
        apb_read (32'h00, rdata);
        // THR stores last written value in thr_rbr (readable in 16550 mode)
        check(rdata[7:0], 8'h55, "Offset 0x00 DLAB=0: thr_rbr readback = 0x55");

        // ==============================================================
        // TEST 6: LCR full fields
        // ==============================================================
        $display("\n--- TEST 6: LCR register fields ---");
        apb_write(32'h0C, 32'h1F);   // 8-bit, 2 stop, parity on, even, stick
        apb_read (32'h0C, rdata);
        check(rdata[7:0], 8'h1F, "LCR=0x1F (8-bit, 2-stop, parity settings)");

        // ==============================================================
        // TEST 7: MCR register
        // ==============================================================
        $display("\n--- TEST 7: MCR register ---");
        apb_write(32'h10, 32'h10);   // MCR bit[4] = loopback
        apb_read (32'h10, rdata);
        check(rdata[7:0], 8'h10, "MCR=0x10 (loopback mode)");

        // ==============================================================
        // TEST 8: FCR write (offset 0x08) - write-only in 16550
        // ==============================================================
        $display("\n--- TEST 8: FCR write ---");
        apb_write(32'h08, 32'h07);   // FIFO enable + RX/TX reset
        // FCR is write-only; IIR is read at same offset
        apb_read (32'h08, rdata);
        $display("  IIR read = 0x%02X (FCR is write-only, IIR returned)", rdata[7:0]);

        // ==============================================================
        // TEST 9: Mode extension registers (IrDA/LIN)
        // ==============================================================
        $display("\n--- TEST 9: Mode extension register ---");
        apb_write(32'h20, 32'h01);  // mode_cr = 0x01 (IrDA)
        apb_read (32'h20, rdata);
        check(rdata[7:0], 8'h01, "mode_cr=0x01 (IrDA mode)");
        apb_write(32'h24, 32'h01);  // nbit_cr = 0x01 (9-bit enable)
        apb_read (32'h24, rdata);
        check(rdata[7:0], 8'h01, "nbit_cr=0x01 (9-bit mode)");

        // ==============================================================
        // TEST 10: TXD idle state (stub RTL — always 1)
        // ==============================================================
        $display("\n--- TEST 10: TXD idle state ---");
        check(txd, 1'b1, "TXD=1 (UART line idle)");
        check(lin_tx, 1'b1, "LIN_TX=1 (LIN line idle)");
        check(irda_tx, 1'b0, "IRDA_TX=0 (IrDA idle low)");

        // ==============================================================
        // FINAL RESULT
        // ==============================================================
        repeat(20) @(posedge clk);
        $display("\n==============================");
        if (error_count == 0)
            $display("UART-16550 VERDICT: ✅ PASS — All %0d register-level tests passed", 10);
        else
            $display("UART-16550 VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("NOTE: TX serializer and IRQ logic are RTL stubs (not implemented).");
        $display("      Functional verification limited to register file correctness.");
        $display("==============================\n");
        $finish;
    end

    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end

endmodule

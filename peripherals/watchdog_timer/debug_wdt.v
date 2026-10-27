// Quick debug - check if wdt_en gets set
`timescale 1ns/1ps
module debug_wdt();
    reg clk, rst_n, psel, penable, pwrite;
    reg [3:0] paddr;
    reg [31:0] pwdata;
    wire [31:0] prdata;
    wire pready, wdt_reset_n, irq;

    watchdog_timer uut(.clk(clk),.rst_n(rst_n),.psel(psel),.penable(penable),.pwrite(pwrite),.paddr(paddr),.pwdata(pwdata),.prdata(prdata),.pready(pready),.wdt_reset_n(wdt_reset_n),.irq(irq));
    initial clk=0; always #3.6 clk=~clk;

    task wr; input [3:0] a; input [31:0] d;
    begin @(posedge clk);#1; paddr=a;pwdata=d;psel=1;penable=0;pwrite=1;
    @(posedge clk);#1;penable=1;@(posedge clk);#1;psel=0;penable=0;pwrite=0; end endtask
    task rd; input [3:0] a; output [31:0] d;
    begin @(posedge clk);#1; paddr=a;psel=1;penable=0;pwrite=0;
    @(posedge clk);#1;penable=1;@(posedge clk);#1;d=prdata;psel=0;penable=0; end endtask

    reg [31:0] r;
    initial begin
        psel=0;penable=0;pwrite=0;paddr=0;pwdata=0;
        rst_n=0; repeat(5) @(posedge clk); rst_n=1; repeat(3) @(posedge clk);
        // Unlock
        wr(4'h0, 32'h1ACCE551);
        @(posedge clk); $display("After unlock: unlock should be 1");
        // Write load_val=5
        wr(4'h4, 32'd5);
        rd(4'h4, r); $display("load_val=%0d", r);
        // Unlock again for ctrl
        wr(4'h0, 32'h1ACCE551);
        // Enable wdt+int
        wr(4'hC, 32'h3);
        rd(4'hC, r); $display("After enable: ctrl=0x%08X wdt_en=%0b int_en=%0b", r, r[0], r[1]);
        // Wait and watch
        repeat(20) begin
            @(posedge clk);
            rd(4'h8, r); // count
            $display("  count=%0d irq=%0b wdt_en=%0b", r, irq, uut.wdt_en);
        end
        $finish;
    end
endmodule

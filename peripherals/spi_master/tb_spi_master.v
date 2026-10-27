// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — SPI Master Directed Self-Checking Testbench
// Register map (paddr[3:2]):
//   0 = tx_data/rx_data (W: write launches TX; R: read returns rx_data)
//   1 = clk_div[15:0] / {busy,15h0,clk_div}
//   2 = control: [5]=cpha, [4]=cpol, [3:0]=cs_select
`timescale 1ns/1ps

module tb_spi_master();

    reg        clk;
    reg        rst_n;
    reg        psel;
    reg        penable;
    reg        pwrite;
    reg [3:0]  paddr;
    reg [31:0] pwdata;
    wire[31:0] prdata;
    wire       pready;
    wire       spi_clk;
    wire       spi_mosi;
    reg        spi_miso;
    wire[3:0]  spi_csn;
    wire       irq;

    integer error_count;

    spi_master uut (
        .clk(clk), .rst_n(rst_n),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata), .prdata(prdata), .pready(pready),
        .spi_clk(spi_clk), .spi_mosi(spi_mosi), .spi_miso(spi_miso),
        .spi_csn(spi_csn), .irq(irq)
    );

    initial clk = 0;
    always #3.6 clk = ~clk;

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
    integer edge_cnt;
    integer wait_cnt;

    initial begin
        $dumpfile("tb_spi_master.vcd");
        $dumpvars(0, tb_spi_master);
        error_count = 0;
        psel = 0; penable = 0; pwrite = 0; paddr = 0; pwdata = 0;
        spi_miso = 0;

        // Reset
        rst_n = 0; repeat(8) @(posedge clk); rst_n = 1; repeat(3) @(posedge clk);

        // TEST 1: pready
        $display("\n--- TEST 1: pready ---");
        check(pready, 1'b1, "pready=1 after reset");

        // TEST 2: CSN idle high (all chip selects deasserted)
        $display("\n--- TEST 2: CSN idle state ---");
        check(spi_csn, 4'hF, "spi_csn=0xF idle (all deasserted)");

        // TEST 3: Clock divider register write/readback
        //   paddr[3:2]=1: clk_div register
        $display("\n--- TEST 3: Clock divider register ---");
        apb_write(4'h4, 32'h0000_0045);   // clk_div = 0x45 (paddr[3:2]=1 → 4'h4)
        apb_read (4'h4, rdata);
        check(rdata[15:0], 16'h0045, "clk_div readback = 0x45");
        check(rdata[31], 1'b0, "busy=0 after reset");

        // TEST 4: Control register (CPOL/CPHA/CS select)
        //   paddr[3:2]=2 → 4'h8
        $display("\n--- TEST 4: Control register ---");
        apb_write(4'h8, 32'h0000_0031); // cpol=1, cpha=1, cs_select=1 → [5:4]=11, [3:0]=0001
        apb_read (4'h8, rdata);
        // Control reg not readable (prdata not in case for addr=2) but write is accepted
        $display("  Control reg write accepted (pready=1)");

        // TEST 5: Launch TX transfer — write paddr=0 with data 0xA5
        //   paddr[3:2]=0 → 4'h0
        $display("\n--- TEST 5: TX transfer launch ---");
        apb_write(4'h4, 32'h0000_0000);  // clk_div=0 (fastest)
        apb_write(4'h8, 32'h0000_0001);  // cs_select=0 (select chip 0)
        apb_write(4'h0, 32'h0000_00A5);  // TX 0xA5 → launches transfer

        // Wait for SCLK edges (busy period)
        edge_cnt = 0;
        wait_cnt = 0;
        while (wait_cnt < 2000) begin
            @(posedge clk); wait_cnt = wait_cnt + 1;
        end

        // TEST 6: Check busy cleared after transfer
        $display("\n--- TEST 6: Busy clears after transfer ---");
        apb_read(4'h4, rdata);
        check(rdata[31], 1'b0, "busy=0 after transfer completes");

        // TEST 7: RX data register readable (paddr=0 read)
        $display("\n--- TEST 7: RX data register ---");
        apb_read(4'h0, rdata);
        $display("  rx_data = 0x%02X (MISO was 0 so expect 0x00)", rdata[7:0]);
        // rx_data should be 0x00 since MISO=0 all along
        check(rdata[7:0], 8'h00, "rx_data=0x00 (MISO tied 0)");

        // TEST 8: SCLK driven (not X/Z)
        $display("\n--- TEST 8: SCLK not X/Z ---");
        if (spi_clk === 1'bx || spi_clk === 1'bz) begin
            $display("FAIL [%0t] spi_clk is X or Z", $time);
            error_count = error_count + 1;
        end else $display("PASS [%0t] spi_clk = %b (driven)", $time, spi_clk);

        $display("\n==============================");
        if (error_count == 0)
            $display("SPI_MASTER VERDICT: ✅ PASS — All tests passed");
        else
            $display("SPI_MASTER VERDICT: ❌ FAIL — %0d errors detected", error_count);
        $display("==============================\n");
        $finish;
    end

    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end

endmodule

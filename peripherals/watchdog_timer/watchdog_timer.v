// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Watchdog Timer
`timescale 1ns/1ps
module watchdog_timer (
    input  wire        clk,
    input  wire        rst_n,
    // APB slave
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [3:0]  paddr,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    // Outputs
    output reg         wdt_reset_n,  // Assert low to reset system
    output wire        irq
);
    assign pready = 1'b1;

    reg [31:0] load_val;    // Reload value
    reg [31:0] count;       // Down counter
    reg        wdt_en;      // Enable bit
    reg        int_en;      // Interrupt enable
    reg        int_stat;    // Interrupt status

    localparam UNLOCK_KEY = 32'h1ACCE551;
    reg unlock;

    assign irq = int_en && int_stat;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_val   <= 32'hFFFF_FFFF;
            count      <= 32'hFFFF_FFFF;
            wdt_en     <= 1'b0;
            int_en     <= 1'b0;
            int_stat   <= 1'b0;
            wdt_reset_n<= 1'b1;
            unlock     <= 1'b0;
        end else begin
            // Down counter
            if (wdt_en) begin
                if (count == 32'h0) begin
                    if (!int_stat) begin
                        int_stat <= 1'b1;  // First expiry: interrupt
                    end else begin
                        wdt_reset_n <= 1'b0;  // Second expiry: reset
                    end
                    count <= load_val;
                end else begin
                    count <= count - 32'h1;
                end
            end

            // APB access (must be unlocked to write control)
            if (psel && penable) begin
                if (pwrite) begin
                    case (paddr[3:2])
                        2'd0: unlock <= (pwdata == UNLOCK_KEY);
                        2'd1: if (unlock) load_val <= pwdata;
                        2'd2: begin
                            // Kick/service: write 0xE5 then 0xE5
                            if (pwdata == 32'h0000_00E5) count <= load_val;
                            int_stat <= 1'b0;
                            wdt_reset_n <= 1'b1;
                        end
                        2'd3: if (unlock) {int_en, wdt_en} <= pwdata[1:0];
                        default: ;
                    endcase
                end else begin
                    case (paddr[3:2])
                        2'd0: prdata <= 32'h0; // Lock status
                        2'd1: prdata <= load_val;
                        2'd2: prdata <= count;
                        2'd3: prdata <= {30'h0, int_stat, wdt_en};
                        default: prdata <= 32'h0;
                    endcase
                end
            end
        end
    end
endmodule

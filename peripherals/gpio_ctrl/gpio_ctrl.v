// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — GPIO Controller (32-bit bidirectional)
`timescale 1ns/1ps
module gpio_ctrl (
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
    // GPIO pads (using tri-state for inout)
    inout  wire [31:0] gpio_pad,
    output wire        irq
);
    assign pready = 1'b1;

    reg [31:0] dir_reg;    // 1=output, 0=input
    reg [31:0] out_reg;    // output data
    reg [31:0] int_en;     // interrupt enable
    reg [31:0] int_pol;    // interrupt polarity (1=high, 0=low)
    reg [31:0] int_stat;   // interrupt status (W1C)
    reg [31:0] in_sync;    // synchronized input value

    // 2-stage synchronizer for each GPIO input
    reg [31:0] gpio_sync1, gpio_sync2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpio_sync1 <= 32'h0;
            gpio_sync2 <= 32'h0;
            in_sync    <= 32'h0;
        end else begin
            gpio_sync1 <= gpio_pad;
            gpio_sync2 <= gpio_sync1;
            in_sync    <= gpio_sync2;
        end
    end

    // Tri-state drivers
    genvar i;
    generate
        for (i = 0; i < 32; i = i+1) begin : GPIO_TRIS
            assign gpio_pad[i] = dir_reg[i] ? out_reg[i] : 1'bz;
        end
    endgenerate

    // Interrupt: any enabled GPIO triggered
    reg [31:0] int_raw;
    always @(*) begin
        int_raw = (int_pol) ? in_sync : ~in_sync; // polarity select
    end
    assign irq = |(int_en & int_raw & ~int_stat);

    // APB access
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dir_reg  <= 32'h0;
            out_reg  <= 32'h0;
            int_en   <= 32'h0;
            int_pol  <= 32'h0;
            int_stat <= 32'h0;
            prdata   <= 32'h0;
        end else if (psel && penable) begin
            if (pwrite) begin
                case (paddr[3:2])
                    2'd0: out_reg  <= pwdata;
                    2'd1: dir_reg  <= pwdata;
                    2'd2: int_en   <= pwdata;
                    2'd3: begin
                        int_pol  <= pwdata;
                        int_stat <= int_stat & ~pwdata; // W1C on bit3
                    end
                endcase
            end else begin
                case (paddr[3:2])
                    2'd0: prdata <= in_sync;
                    2'd1: prdata <= dir_reg;
                    2'd2: prdata <= int_en;
                    2'd3: prdata <= int_stat;
                    default: prdata <= 32'h0;
                endcase
            end
        end
    end
endmodule

// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — SPI Master Controller
`timescale 1ns/1ps
module spi_master (
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
    // SPI pads
    output wire        spi_clk,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output reg  [3:0]  spi_csn,   // 4 chip selects (active-low)
    output wire        irq
);
    assign pready = 1'b1;

    reg [15:0] clk_div;    // SCLK = clk / (2*(clk_div+1))
    reg [7:0]  tx_data;
    reg [7:0]  rx_data;
    reg        start;
    reg        busy;
    reg [3:0]  cs_select;  // which CS to assert
    reg        cpol, cpha;

    // Clock generator
    reg [15:0] clk_cnt;
    reg        sclk_r;
    wire       sclk_edge = (clk_cnt == 16'h0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt <= 16'h0;
            sclk_r  <= 1'b0;
        end else if (busy) begin
            if (clk_cnt == clk_div) begin
                clk_cnt <= 16'h0;
                sclk_r  <= ~sclk_r;
            end else clk_cnt <= clk_cnt + 16'h1;
        end else begin
            sclk_r <= cpol;
        end
    end

    assign spi_clk = sclk_r;

    // Shift register
    reg [7:0] shift_out;
    reg [7:0] shift_in;
    reg [2:0] bit_cnt;
    reg       mosi_r;
    assign spi_mosi = mosi_r;
    assign irq = !busy && start; // simplified: pulse on done

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_out <= 8'h0;
            shift_in  <= 8'h0;
            bit_cnt   <= 3'h0;
            mosi_r    <= 1'b1;
            busy      <= 1'b0;
            spi_csn   <= 4'hF;
        end else begin
            if (start && !busy) begin
                shift_out <= tx_data;
                bit_cnt   <= 3'h7;
                busy      <= 1'b1;
                spi_csn   <= ~(4'b0001 << cs_select[1:0]);
                start     <= 1'b0;
            end
            if (busy && sclk_edge && !sclk_r) begin
                // Rising edge: shift out MSB
                mosi_r    <= shift_out[7];
                shift_out <= {shift_out[6:0], 1'b0};
            end
            if (busy && sclk_edge && sclk_r) begin
                // Falling edge: sample MISO
                shift_in <= {shift_in[6:0], spi_miso};
                if (bit_cnt == 3'h0) begin
                    rx_data <= shift_in;
                    busy    <= 1'b0;
                    spi_csn <= 4'hF;
                end else bit_cnt <= bit_cnt - 3'h1;
            end
        end
    end

    // APB registers
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div   <= 16'd49;   // 100MHz / (2*50) = 1 MHz
            tx_data   <= 8'h0;
            cs_select <= 4'h0;
            cpol      <= 1'b0;
            cpha      <= 1'b0;
            prdata    <= 32'h0;
            start     <= 1'b0;
        end else if (psel && penable) begin
            if (pwrite) begin
                case (paddr[3:2])
                    2'd0: begin tx_data <= pwdata[7:0]; start <= 1'b1; end
                    2'd1: clk_div <= pwdata[15:0];
                    2'd2: {cpha, cpol, cs_select} <= {pwdata[5], pwdata[4], pwdata[3:0]};
                    default: ;
                endcase
            end else begin
                case (paddr[3:2])
                    2'd0: prdata <= {24'h0, rx_data};
                    2'd1: prdata <= {busy, 15'h0, clk_div};
                    default: prdata <= 32'h0;
                endcase
            end
        end
    end
endmodule

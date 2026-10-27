// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — I2C Master Controller
`timescale 1ns/1ps
module i2c_master (
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
    // I2C pads (open-drain, use tristate)
    inout  wire        scl_pad,
    inout  wire        sda_pad,
    output wire        irq
);
    assign pready = 1'b1;

    reg [15:0] prescale;   // SCL = clk / (5 * prescale)
    reg [7:0]  tx_data;
    reg [7:0]  rx_data;
    reg        cmd_start;
    reg        cmd_stop;
    reg        cmd_read;
    reg        cmd_write;
    reg        cmd_ack;
    reg        busy;
    reg        ack_out;

    reg        scl_o;   // 0=drive low, 1=release (open-drain)
    reg        sda_o;

    assign scl_pad = scl_o ? 1'bz : 1'b0;
    assign sda_pad = sda_o ? 1'bz : 1'b0;
    assign irq = !busy;  // interrupt on completion

    // Prescaler / clock
    reg [15:0] presc_cnt;
    reg [1:0]  phase;   // 0=scl_lo, 1=scl_rise, 2=scl_hi, 3=scl_fall
    wire       phase_tick = (presc_cnt == 16'h0);

    // I2C state machine (simplified byte-level)
    localparam IS_IDLE  = 3'd0;
    localparam IS_START = 3'd1;
    localparam IS_WRITE = 3'd2;
    localparam IS_READ  = 3'd3;
    localparam IS_ACK   = 3'd4;
    localparam IS_STOP  = 3'd5;
    reg [2:0]  istate;
    reg [2:0]  bit_idx;
    reg [7:0]  shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            presc_cnt <= 16'h0;
            phase     <= 2'h0;
            scl_o     <= 1'b1;
            sda_o     <= 1'b1;
            istate    <= IS_IDLE;
            bit_idx   <= 3'h0;
            shift     <= 8'h0;
            busy      <= 1'b0;
            rx_data   <= 8'h0;
        end else begin
            // Prescaler
            if (presc_cnt == 16'h0) presc_cnt <= prescale;
            else presc_cnt <= presc_cnt - 16'h1;

            case (istate)
                IS_IDLE: begin
                    scl_o <= 1'b1;  sda_o <= 1'b1;
                    if (cmd_write || cmd_read) begin
                        busy   <= 1'b1;
                        shift  <= tx_data;
                        bit_idx<= 3'h7;
                        istate <= cmd_start ? IS_START : IS_WRITE;
                        cmd_start <= 1'b0;
                    end
                end
                IS_START: begin
                    if (phase_tick) begin
                        case (phase)
                            2'd0: sda_o <= 1'b0;  // SDA low while SCL high
                            2'd1: scl_o <= 1'b0;  // SCL low → start condition
                            2'd2: ;
                            2'd3: begin istate <= IS_WRITE; end
                        endcase
                        phase <= phase + 2'h1;
                    end
                end
                IS_WRITE: begin
                    if (phase_tick) begin
                        case (phase)
                            2'd0: sda_o <= shift[7];
                            2'd1: scl_o <= 1'b1;
                            2'd2: ;
                            2'd3: begin
                                scl_o  <= 1'b0;
                                shift  <= {shift[6:0], 1'b0};
                                if (bit_idx == 3'h0) begin
                                    istate  <= IS_ACK;
                                    bit_idx <= 3'h0;
                                end else bit_idx <= bit_idx - 3'h1;
                            end
                        endcase
                        phase <= phase + 2'h1;
                    end
                end
                IS_ACK: begin
                    if (phase_tick) begin
                        case (phase)
                            2'd0: sda_o <= 1'b1;  // Release SDA for ACK
                            2'd1: scl_o <= 1'b1;
                            2'd2: ack_out <= !sda_pad; // Sample ACK
                            2'd3: begin
                                scl_o  <= 1'b0;
                                busy   <= 1'b0;
                                istate <= cmd_stop ? IS_STOP : IS_IDLE;
                            end
                        endcase
                        phase <= phase + 2'h1;
                    end
                end
                IS_STOP: begin
                    if (phase_tick) begin
                        case (phase)
                            2'd0: sda_o <= 1'b0;
                            2'd1: scl_o <= 1'b1;
                            2'd2: sda_o <= 1'b1;
                            2'd3: begin istate <= IS_IDLE; cmd_stop <= 1'b0; end
                        endcase
                        phase <= phase + 2'h1;
                    end
                end
                default: istate <= IS_IDLE;
            endcase
        end
    end

    // APB
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prescale  <= 16'd99;  // 100MHz / (5*100) = 200kHz
            tx_data   <= 8'h0;
            cmd_start <= 1'b0;    cmd_stop  <= 1'b0;
            cmd_read  <= 1'b0;    cmd_write <= 1'b0;
            cmd_ack   <= 1'b0;
            prdata    <= 32'h0;
        end else if (psel && penable) begin
            if (pwrite) begin
                case (paddr[3:2])
                    2'd0: prescale <= pwdata[15:0];
                    2'd1: tx_data  <= pwdata[7:0];
                    2'd2: {cmd_ack, cmd_stop, cmd_start, cmd_read, cmd_write}
                              <= pwdata[4:0];
                    default: ;
                endcase
            end else begin
                case (paddr[3:2])
                    2'd0: prdata <= {busy, 15'h0, prescale};
                    2'd1: prdata <= {24'h0, rx_data};
                    2'd2: prdata <= {31'h0, ack_out};
                    default: prdata <= 32'h0;
                endcase
            end
        end
    end
endmodule

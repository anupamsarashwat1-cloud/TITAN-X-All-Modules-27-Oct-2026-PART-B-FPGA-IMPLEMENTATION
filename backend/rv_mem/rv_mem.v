// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RV64I Memory Access Stage
`timescale 1ns/1ps
module rv_mem (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,
    // From execute
    input  wire [63:0] alu_result,
    input  wire [63:0] rs2_data,
    input  wire [4:0]  rd_in,
    input  wire [2:0]  funct3,
    input  wire [6:0]  opcode,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire        reg_write,
    input  wire        valid_in,
    // Data memory AXI4-Lite master
    output reg         dmem_awvalid,
    input  wire        dmem_awready,
    output reg  [39:0] dmem_awaddr,
    output reg         dmem_wvalid,
    input  wire        dmem_wready,
    output reg  [63:0] dmem_wdata,
    output reg  [7:0]  dmem_wstrb,
    input  wire        dmem_bvalid,
    output reg         dmem_bready,
    output reg         dmem_arvalid,
    input  wire        dmem_arready,
    output reg  [39:0] dmem_araddr,
    input  wire        dmem_rvalid,
    output reg         dmem_rready,
    input  wire [63:0] dmem_rdata,
    input  wire [1:0]  dmem_rresp,
    // To writeback
    output reg  [63:0] result,
    output reg  [4:0]  rd_out,
    output reg         reg_write_out,
    output reg         valid_out,
    // Forwarding output
    output wire [63:0] fwd_mem_data,
    output wire [4:0]  fwd_mem_rd,
    output wire        fwd_mem_valid,
    // Stall request
    output wire        mem_stall
);
    localparam MS_IDLE  = 2'd0;
    localparam MS_ADDR  = 2'd1;
    localparam MS_DATA  = 2'd2;
    localparam MS_DONE  = 2'd3;
    reg [1:0] mstate;
    reg [63:0] load_data;
    reg        mem_active;

    assign mem_stall  = mem_active && (mstate != MS_DONE);
    assign fwd_mem_data  = result;
    assign fwd_mem_rd    = rd_out;
    // Suppress forwarding while a memory transaction is in flight: 'result'
    // still holds the PREVIOUS instruction's value until the transfer
    // completes, and advertising it here would feed a dependent in execute
    // with stale data for the whole bus latency.
    assign fwd_mem_valid = valid_out && reg_write_out && !mem_active;

    // Load data sign-extension
    function [63:0] extend_load;
        input [63:0] raw;
        input [2:0]  f3;
        case (f3)
            3'b000: extend_load = {{56{raw[7]}},  raw[7:0]};   // LB
            3'b001: extend_load = {{48{raw[15]}}, raw[15:0]};  // LH
            3'b010: extend_load = {{32{raw[31]}}, raw[31:0]};  // LW
            3'b011: extend_load = raw;                          // LD
            3'b100: extend_load = {56'h0, raw[7:0]};           // LBU
            3'b101: extend_load = {48'h0, raw[15:0]};          // LHU
            3'b110: extend_load = {32'h0, raw[31:0]};          // LWU
            default:extend_load = raw;
        endcase
    endfunction

    // Write strobe from funct3
    function [7:0] wstrb_from_f3;
        input [2:0] f3;
        case (f3)
            3'b000: wstrb_from_f3 = 8'b0000_0001; // SB
            3'b001: wstrb_from_f3 = 8'b0000_0011; // SH
            3'b010: wstrb_from_f3 = 8'b0000_1111; // SW
            3'b011: wstrb_from_f3 = 8'b1111_1111; // SD
            default:wstrb_from_f3 = 8'b1111_1111;
        endcase
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmem_awvalid  <= 1'b0;  dmem_awaddr  <= 40'h0;
            dmem_wvalid   <= 1'b0;  dmem_wdata   <= 64'h0;  dmem_wstrb <= 8'h0;
            dmem_bready   <= 1'b0;
            dmem_arvalid  <= 1'b0;  dmem_araddr  <= 40'h0;
            dmem_rready   <= 1'b0;
            result        <= 64'h0;
            rd_out        <= 5'h0;
            reg_write_out <= 1'b0;
            valid_out     <= 1'b0;
            load_data     <= 64'h0;
            mem_active    <= 1'b0;
            mstate        <= MS_IDLE;
        end else if (flush) begin
            dmem_awvalid  <= 1'b0;  dmem_awaddr  <= 40'h0;
            dmem_wvalid   <= 1'b0;  dmem_wdata   <= 64'h0;  dmem_wstrb <= 8'h0;
            dmem_bready   <= 1'b0;
            dmem_arvalid  <= 1'b0;  dmem_araddr  <= 40'h0;
            dmem_rready   <= 1'b0;
            result        <= 64'h0;
            rd_out        <= 5'h0;
            reg_write_out <= 1'b0;
            valid_out     <= 1'b0;
            load_data     <= 64'h0;
            mem_active    <= 1'b0;
            mstate        <= MS_IDLE;
        end else begin
            case (mstate)
                MS_IDLE: begin
                    if (valid_in && mem_write) begin
                        dmem_awvalid <= 1'b1;
                        dmem_awaddr  <= alu_result[39:0];
                        dmem_wvalid  <= 1'b1;
                        // Data rides the SAME lane as its strobe: the slave
                        // merges window byte j from bus lane j. Shifting the
                        // strobe without the data wrote the wrong slice of
                        // rs2 into the addressed lane.
                        dmem_wdata   <= rs2_data
                                        << {alu_result[2:0], 3'b000};
                        // Strobes ride the byte lane selected by address
                        // bits [2:0]. Lane-0-always made every non-offset-0
                        // sub-word store land up to 7 bytes early (an sb@+14
                        // rewrote byte 0 of the window instead).
                        dmem_wstrb   <= wstrb_from_f3(funct3)
                                        << alu_result[2:0];
                        dmem_bready  <= 1'b1;
                        mem_active   <= 1'b1;
                        mstate       <= MS_DATA;
                        rd_out        <= rd_in;
                        reg_write_out <= reg_write;
                        result        <= alu_result;
                        // Nothing retires while the transaction flies:
                        // holding the previous completer's valid here made
                        // WB latch a ghost {rd, stale result} pair one
                        // cycle before the real writeback.
                        valid_out    <= 1'b0;
                    end else if (valid_in && mem_read) begin
                        dmem_arvalid <= 1'b1;
                        dmem_araddr  <= alu_result[39:0];
                        dmem_rready  <= 1'b1;
                        mem_active   <= 1'b1;
                        mstate       <= MS_DATA;
                        rd_out        <= rd_in;
                        reg_write_out <= reg_write;
                        valid_out    <= 1'b0;   // same ghost-write guard
                    end else begin
                        result        <= alu_result;
                        rd_out        <= rd_in;
                        reg_write_out <= reg_write;
                        valid_out     <= valid_in;
                        mem_active    <= 1'b0;
                    end
                end
                MS_DATA: begin
                    if (dmem_awready) dmem_awvalid <= 1'b0;
                    if (dmem_wready)  dmem_wvalid  <= 1'b0;
                    if (dmem_arready) dmem_arvalid <= 1'b0;
                    if (dmem_bvalid) begin
                        dmem_bready  <= 1'b0;
                        valid_out    <= 1'b1;
                        mem_active   <= 1'b0;
                        mstate       <= MS_IDLE;
                    end
                    if (dmem_rvalid) begin
                        load_data    <= dmem_rdata;
                        // Mirror of the store-side lane shift: the slave
                        // returns the whole doubleword, so the addressed
                        // lane sits at bits [8*araddr[2:0] +: size].
                        result       <= extend_load(
                            dmem_rdata >> {dmem_araddr[2:0], 3'b000},
                            funct3);
                        dmem_rready  <= 1'b0;
                        valid_out    <= 1'b1;
                        mem_active   <= 1'b0;
                        mstate       <= MS_IDLE;
                    end
                end
                default: mstate <= MS_IDLE;
            endcase
        end
    end
endmodule

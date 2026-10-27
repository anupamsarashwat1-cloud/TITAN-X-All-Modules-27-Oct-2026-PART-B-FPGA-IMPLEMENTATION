// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — eNVM (Embedded Non-Volatile Memory) Controller
// Iteration 3: 128KB eNVM with AXI4 Read and APB Program/Erase interface.
`timescale 1ns/1ps

module envm_ctrl #(
    parameter AW = 32, // 128KB = 17 bits Address
    parameter DW = 32
) (
    input  wire        clk,
    input  wire        rst_n,

    // AXI4-Lite Slave (for fast read access / Execution)
    input  wire          s_arvalid,
    output wire          s_arready,
    input  wire [AW-1:0] s_araddr,
    
    output wire          s_rvalid,
    input  wire          s_rready,
    output wire [DW-1:0] s_rdata,
    output wire [1:0]    s_rresp,

    // APB Slave (Control, Program, Erase)
    input  wire [31:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    // Interface to physical eNVM Macro
    output wire        envm_clk,
    output wire        envm_ce_n,
    output wire        envm_we_n,
    output wire [16:0] envm_addr, // 128KB = 17 bits for byte-addressing, but we access words
    output wire [31:0] envm_wdata,
    input  wire [31:0] envm_rdata,
    input  wire        envm_ready
);

    // -------------------------------------------------------
    // APB Control Registers
    // -------------------------------------------------------
    reg [31:0] cmd_reg;    // Program/Erase command
    reg [31:0] addr_reg;   // Target address
    reg [31:0] data_reg;   // Write data
    reg [31:0] stat_reg;   // Busy, Error
    reg [31:0] unlock_reg; // Magic value to unlock erase/program

    assign pready = 1'b1;
    assign pslverr = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_reg <= 32'h0;
            addr_reg <= 32'h0;
            data_reg <= 32'h0;
            unlock_reg <= 32'h0;
            // Status is APB-readable (0x0C) — must have a defined reset state
            // (idle, no error) instead of floating X until an engine exists.
            stat_reg <= 32'h0;
        end else if (psel && penable && pwrite) begin
            case (paddr[7:0])
                8'h00: cmd_reg <= pwdata;
                8'h04: addr_reg <= pwdata;
                8'h08: data_reg <= pwdata;
                8'h10: unlock_reg <= pwdata;
                default: ;
            endcase
        end
    end
    
    assign prdata = (paddr[7:0] == 8'h00) ? cmd_reg :
                    (paddr[7:0] == 8'h04) ? addr_reg :
                    (paddr[7:0] == 8'h08) ? data_reg :
                    (paddr[7:0] == 8'h0C) ? stat_reg : 32'h0;

    // -------------------------------------------------------
    // AXI Read / Execute Path
    // -------------------------------------------------------
    // Translates AXI read requests to eNVM reads. 
    // Usually 1 cycle latency if eNVM is fast enough for clk.
    
    reg arready_reg;
    reg rvalid_reg;
    reg [31:0] rdata_reg;
    
    // Simple state machine for read
    localparam IDLE = 2'd0, READ = 2'd1;
    reg [1:0] state;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            arready_reg <= 1'b0;
            rvalid_reg <= 1'b0;
            rdata_reg <= 32'h0;
        end else begin
            case (state)
                IDLE: begin
                    rvalid_reg <= 1'b0;
                    if (s_arvalid && !arready_reg && envm_ready) begin
                        arready_reg <= 1'b1;
                        state <= READ;
                    end else begin
                        arready_reg <= 1'b0;
                    end
                end
                READ: begin
                    arready_reg <= 1'b0;
                    rdata_reg <= envm_rdata; // Fetch data
                    rvalid_reg <= 1'b1;
                    if (rvalid_reg && s_rready) begin
                        rvalid_reg <= 1'b0;
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
    
    assign s_arready = arready_reg;
    assign s_rvalid = rvalid_reg;
    assign s_rdata = rdata_reg;
    assign s_rresp = 2'b00;

    // -------------------------------------------------------
    // Macro Interface
    // -------------------------------------------------------
    // Normally arbitration needed between APB operations and AXI reads.
    // For this behavioral model, giving AXI direct priority.
    
    assign envm_clk = clk;
    assign envm_ce_n = ~(state == READ || (psel && penable)); // Active low
    assign envm_we_n = 1'b1; // Write via APB not modeled for macro physical here
    assign envm_addr = (state == READ) ? s_araddr[16:0] : addr_reg[16:0];
    assign envm_wdata = data_reg;

endmodule

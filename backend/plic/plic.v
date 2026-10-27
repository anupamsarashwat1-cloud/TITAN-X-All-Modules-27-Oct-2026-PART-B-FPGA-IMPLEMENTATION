// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — PLIC: Platform Level Interrupt Controller
// 186 interrupt sources, 10 targets (5 harts × M+S modes)
// Priority encoder finds highest-priority enabled pending interrupt above threshold
`timescale 1ns/1ps
module plic #(
    parameter NUM_SOURCES = 186,
    parameter NUM_TARGETS = 10
) (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire [NUM_SOURCES-1:0]    interrupt_sources,
    // APB slave for priority/enable configuration
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [23:0] paddr,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    // Interrupt to each target (hart × privilege)
    output reg  [NUM_TARGETS-1:0]    irq_targets
);
    assign pready = 1'b1;

    // Priority: 3 bits per source (0-7, 0=disabled)
    reg [2:0] priority_reg [0:NUM_SOURCES-1];
    // Pending: set by interrupt_sources, cleared by claim write
    reg [NUM_SOURCES-1:0] pending;
    // Enable: per target per source
    reg [NUM_SOURCES-1:0] enable [0:NUM_TARGETS-1];
    // Threshold: per target
    reg [2:0] threshold [0:NUM_TARGETS-1];
    // Claim: per target (last claimed source)
    reg [7:0] claim [0:NUM_TARGETS-1];

    integer i, j, k;

    // Pending update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending <= {NUM_SOURCES{1'b0}};
        end else begin
            // Set on rising edge of interrupt_sources
            for (i = 0; i < NUM_SOURCES; i = i+1)
                if (interrupt_sources[i]) pending[i] <= 1'b1;
        end
    end

    // Priority encoder — find best irq per target
    reg [7:0]  best_src  [0:NUM_TARGETS-1];
    reg [2:0]  best_prio [0:NUM_TARGETS-1];

    always @(*) begin
        for (j = 0; j < NUM_TARGETS; j = j+1) begin
            best_src[j]  = 8'h0;
            best_prio[j] = 3'h0;
            for (k = 1; k < NUM_SOURCES; k = k+1) begin
                if (pending[k] && enable[j][k] &&
                    (priority_reg[k] > threshold[j]) &&
                    (priority_reg[k] > best_prio[j])) begin
                    best_src[j]  = k[7:0];
                    best_prio[j] = priority_reg[k];
                end
            end
            irq_targets[j] = (best_src[j] != 8'h0);
        end
    end

    // APB register access
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_SOURCES; i = i+1) priority_reg[i] <= 3'h1;
            for (i = 0; i < NUM_TARGETS; i = i+1) begin
                enable[i]    <= {NUM_SOURCES{1'b0}};
                threshold[i] <= 3'h0;
                claim[i]     <= 8'h0;
            end
            prdata <= 32'h0;
        end else if (psel && penable) begin
            if (pwrite) begin
                // Priority regs: base 0x000000, 4 bytes per source
                if (paddr[23:12] == 12'h000)
                    priority_reg[paddr[11:2]] <= pwdata[2:0];
                // Enable: base 0x002000, 4 bytes per 32 sources per target
                else if (paddr[23:16] == 8'h00 && paddr[15:13] == 3'b001)
                    enable[paddr[12:8]][paddr[6:2]*32 +: 32] <= pwdata;
                // Target context registers: base 0x200000, 0x1000 per target
                else if (paddr[23:16] == 8'h20) begin
                    if (paddr[3:2] == 2'b00)
                        threshold[paddr[15:12]] <= pwdata[2:0];
                    else if (paddr[3:2] == 2'b01) begin
                        if (pwdata[7:0] < NUM_SOURCES[7:0])
                            pending[pwdata[7:0]] <= 1'b0;
                    end
                end
            end else begin
                if (paddr[23:16] == 8'h20 && paddr[3:2] == 2'b01)
                    prdata <= {24'h0, best_src[paddr[15:12]]};
                else
                    prdata <= 32'h0;
            end
        end
    end
endmodule

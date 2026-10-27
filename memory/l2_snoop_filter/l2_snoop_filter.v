// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — L2 Snoop Filter (MESI Directory)
// Iteration 3: Tracks L1 D-Cache coherence state for 4 application cores.
// Coherence Protocol: MESI
`timescale 1ns/1ps
`include "params.vh"

module l2_snoop_filter #(
    parameter NUM_CORES = 4,
    parameter ADDR_W    = 40,
    parameter TAG_W     = 28,  // Depends on L1 cache geometry (e.g., 64 sets, 64B line)
    parameter INDEX_W   = 6,
    parameter WAYS      = 8
)(
    input  wire        clk,
    input  wire        rst_n,

    // Crossbar / L2 Controller snooping request
    input  wire        req_valid,
    input  wire [39:0] req_addr,
    input  wire [1:0]  req_type,   // 00=ReadShared, 01=ReadUnique, 10=CleanInvalidate, 11=MakeInvalid
    input  wire [1:0]  req_core,   // Requesting core ID (0-3)

    // Snoop output to L1 D-Caches
    output reg  [NUM_CORES-1:0] snoop_valid,
    output reg  [39:0]          snoop_addr,
    output reg  [1:0]           snoop_type, // 00=GetS (downgrade to S), 01=GetM (inv), 10=Inv
    input  wire [NUM_CORES-1:0] snoop_ack,
    input  wire [NUM_CORES-1:0] snoop_data_valid,

    // Snoop filter response to L2 Controller
    output reg         resp_valid,
    output reg         resp_hit,
    output reg         resp_dirty,
    output reg [1:0]   resp_owner // Core ID holding Modified state
);

    // -------------------------------------------------------
    // Directory Array
    // Tracks MESI state and owner/sharer mask for each L1 line.
    // To maintain strict inclusion, directory must have at least 
    // as many entries as total L1 capacity, typically organized 
    // as a set-associative array (e.g., matching L1 sets).
    // Here we model a 64-set × 8-way directory per core (or unified).
    // Unified array: 64 sets × 32 ways (8 ways * 4 cores)
    // -------------------------------------------------------
`ifdef FORMAL
    localparam DIR_SETS = 2;
    localparam DIR_WAYS = 2;
    wire [0:0] index = req_addr[6];
`else
    localparam DIR_SETS = 64;
    localparam DIR_WAYS = 32;
    wire [INDEX_W-1:0] index = req_addr[11:6];
`endif
    wire [TAG_W-1:0]   tag   = req_addr[39:12];

    // State encoding (MESI)
    localparam ST_I = 2'b00; // Invalid
    localparam ST_S = 2'b01; // Shared
    localparam ST_E = 2'b10; // Exclusive
    localparam ST_M = 2'b11; // Modified

    // Directory entry: {State[1:0], SharerMask[3:0], Tag[27:0]}
    reg [1:0]  dir_state [0:DIR_SETS-1][0:DIR_WAYS-1];
    reg [3:0]  dir_mask  [0:DIR_SETS-1][0:DIR_WAYS-1];
    reg [27:0] dir_tag   [0:DIR_SETS-1][0:DIR_WAYS-1];

    // -------------------------------------------------------
    // FSM
    // -------------------------------------------------------
    localparam IDLE      = 3'd0;
    localparam LOOKUP    = 3'd1;
    localparam SNOOP_REQ = 3'd2;
    localparam SNOOP_ACK = 3'd3;
    localparam UPDATE    = 3'd4;

    reg [2:0] state;
    reg [3:0] hit_mask;
    reg [4:0] hit_way;
    reg       line_hit;
    reg [1:0] line_state;
    reg [1:0] req_core_saved;
    reg [1:0] req_type_saved;

    // Combinational lookup and allocation logic to avoid BLKSEQ in sequential block
    reg       combo_line_hit;
    reg [4:0] combo_hit_way;
    reg [1:0] combo_line_state;
    reg [3:0] combo_hit_mask;
    integer ki;

    always @* begin
        combo_line_hit = 1'b0;
        combo_hit_way = 5'd0;
        combo_line_state = ST_I;
        combo_hit_mask = 4'h0;
        for (ki = 0; ki < DIR_WAYS; ki = ki + 1) begin
            if ((dir_state[index][ki] != ST_I) && (dir_tag[index][ki] == tag)) begin
                combo_line_hit = 1'b1;
                combo_hit_way = ki[4:0];
                combo_line_state = dir_state[index][ki];
                combo_hit_mask = dir_mask[index][ki];
            end
        end
    end

    reg [4:0] alloc_way_comb;
    integer ai;
    always @* begin
        alloc_way_comb = 5'd0;
        for (ai = 0; ai < DIR_WAYS; ai = ai + 1) begin
            if (dir_state[index][ai] == ST_I) alloc_way_comb = ai[4:0];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            snoop_valid <= 4'h0;
            resp_valid <= 1'b0;
            line_hit <= 1'b0;
            hit_mask <= 4'h0;
            hit_way <= 5'h0;
            line_state <= ST_I;
            req_core_saved <= 2'h0;
            req_type_saved <= 2'h0;
            for (integer s=0; s<DIR_SETS; s=s+1) begin
                for (integer w=0; w<DIR_WAYS; w=w+1) begin
                    dir_state[s][w] <= ST_I;
                end
            end
        end else begin
            resp_valid <= 1'b0;
            snoop_valid <= 4'h0;

            case (state)
                IDLE: begin
                    if (req_valid) begin
                        req_core_saved <= req_core;
                        req_type_saved <= req_type;
                        state <= LOOKUP;
                    end
                end
                LOOKUP: begin
                    line_hit   <= combo_line_hit;
                    hit_way    <= combo_hit_way;
                    line_state <= combo_line_state;
                    hit_mask   <= combo_hit_mask;

                    if (!combo_line_hit || (combo_line_state == ST_I)) begin
                        // Miss: no snoops needed, just fetch from memory
                        resp_valid <= 1'b1;
                        resp_hit <= 1'b0;
                        resp_dirty <= 1'b0;
                        state <= UPDATE; // Need to allocate in directory
                    end else begin
                        // Hit: determine if snoop is needed
                        if (combo_line_state == ST_M || combo_line_state == ST_E) begin
                            // Someone else has it exclusively, must snoop
                            if (combo_hit_mask != (1 << req_core_saved)) begin
                                snoop_valid <= combo_hit_mask;
                                snoop_addr  <= {tag, index, 6'h0};
                                snoop_type  <= (req_type_saved == 2'b00) ? 2'b00 : 2'b01; // GetS vs GetM
                                state <= SNOOP_REQ;
                            end else begin
                                // It's us, no snoop needed
                                resp_valid <= 1'b1;
                                resp_hit <= 1'b1;
                                resp_dirty <= (combo_line_state == ST_M);
                                resp_owner <= req_core_saved;
                                state <= UPDATE;
                            end
                        end else if (combo_line_state == ST_S) begin
                            if (req_type_saved == 2'b01 || req_type_saved == 2'b10) begin
                                // Write request to shared line: invalidate others
                                snoop_valid <= combo_hit_mask & ~(1 << req_core_saved);
                                snoop_addr  <= {tag, index, 6'h0};
                                snoop_type  <= 2'b10; // Inv
                                if (snoop_valid != 4'h0) state <= SNOOP_REQ;
                                else begin
                                    resp_valid <= 1'b1;
                                    resp_hit <= 1'b1;
                                    resp_dirty <= 1'b0;
                                    state <= UPDATE;
                                end
                            end else begin
                                // Read shared: just add to sharers
                                resp_valid <= 1'b1;
                                resp_hit <= 1'b1;
                                resp_dirty <= 1'b0;
                                state <= UPDATE;
                            end
                        end
                    end
                end

                SNOOP_REQ: begin
                    // Wait for all snooped cores to ack
                    // In real hardware, track per-core acks
                    if ((snoop_ack & hit_mask) == hit_mask) begin // Simplified condition
                        resp_valid <= 1'b1;
                        resp_hit <= 1'b1;
                        resp_dirty <= |(snoop_data_valid & hit_mask);
                        resp_owner <= 0; // Logic to determine which core had dirty data
                        state <= UPDATE;
                    end else begin
                        snoop_valid <= hit_mask & ~snoop_ack; // Keep requesting un-acked
                    end
                end

                UPDATE: begin
                    // Update directory state based on req_type and previous state
                    if (!line_hit) begin
                        // Allocate (find empty way or evict - PLRU omitted for brevity)
                        dir_tag[index][alloc_way_comb] <= tag;
                        dir_mask[index][alloc_way_comb] <= (1 << req_core_saved);
                        dir_state[index][alloc_way_comb] <= (req_type_saved == 2'b00) ? ST_E : ST_M; 
                        // Note: If read, grant E if no other sharers (which is true here)
                    end else begin
                        // Update existing
                        if (req_type_saved == 2'b01) begin // ReadUnique/Write
                            dir_state[index][hit_way] <= ST_M;
                            dir_mask[index][hit_way] <= (1 << req_core_saved);
                        end else if (req_type_saved == 2'b00) begin // ReadShared
                            if (line_state == ST_M || line_state == ST_E) begin
                                dir_state[index][hit_way] <= ST_S;
                                dir_mask[index][hit_way] <= hit_mask | (1 << req_core_saved);
                            end else if (line_state == ST_S) begin
                                dir_mask[index][hit_way] <= hit_mask | (1 << req_core_saved);
                            end
                        end else if (req_type_saved == 2'b10) begin // Evict/Invalidate
                            dir_mask[index][hit_way] <= hit_mask & ~(1 << req_core_saved);
                            if ((hit_mask & ~(1 << req_core_saved)) == 4'h0) begin
                                dir_state[index][hit_way] <= ST_I;
                            end
                        end
                    end
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule

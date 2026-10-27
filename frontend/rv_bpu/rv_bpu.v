// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Branch Prediction Unit
// Iteration 3: Tournament predictor — Gshare + Local History + BTB
// Target: SCL 180nm, 125-200 MHz
// Architecture:
//   - Local History Table: 2-bit saturating counter, 2K entries, 11-bit index
//   - Global History Register (GHR): 12-bit shift register
//   - Gshare predictor: PC[12:1] XOR GHR → 4K saturating counter table
//   - Tournament meta-predictor: selects between local and global
//   - BTB: 512-entry direct-mapped branch target buffer
`timescale 1ns/1ps
`include "params.vh"

module rv_bpu #(
    parameter BHT_LOCAL_ENTRIES  = 2048,   // Local history table size
    parameter BHT_GLOBAL_ENTRIES = 4096,   // Gshare table size
    parameter BTB_ENTRIES        = 512,    // Branch Target Buffer entries
    parameter GHR_WIDTH          = 12,     // Global History Register width
    parameter META_ENTRIES       = 4096    // Meta-predictor (tournament) size
)(
    input  wire        clk,
    input  wire        rst_n,

    // Fetch stage query (PC of instruction being fetched)
    input  wire [63:0] fetch_pc,
    input  wire        fetch_valid,

    // Prediction output (registered, available next cycle)
    output reg         pred_taken,      // Predicted taken/not-taken
    output reg  [63:0] pred_target,     // Predicted target (from BTB)
    output reg         pred_valid,      // BTB hit (prediction is meaningful)

    // Execute stage update (correction)
    input  wire [63:0] ex_pc,           // PC of resolved branch
    input  wire        ex_is_branch,    // This instruction is a branch
    input  wire        ex_is_jal,       // JAL (unconditional, always update BTB)
    input  wire        ex_taken,        // Actual outcome
    input  wire [63:0] ex_target,       // Actual target
    input  wire        ex_valid         // Execute stage has valid branch info
);

    // -------------------------------------------------------
    // Local History Table (2K × 2-bit saturating counters)
    // Indexed by PC[11:1]
    // -------------------------------------------------------
    reg [1:0] bht_local [0:BHT_LOCAL_ENTRIES-1];
    wire [10:0] local_idx_rd = fetch_pc[11:1];
    wire [10:0] local_idx_wr = ex_pc[11:1];

    // Local prediction
    wire [1:0] local_ctr_rd = bht_local[local_idx_rd];
    wire       local_pred   = local_ctr_rd[1];  // MSB = taken prediction

    // -------------------------------------------------------
    // Global History Register (12-bit shift register)
    // -------------------------------------------------------
    reg [GHR_WIDTH-1:0] ghr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ghr <= {GHR_WIDTH{1'b0}};
        end else if (ex_valid && ex_is_branch) begin
            ghr <= {ghr[GHR_WIDTH-2:0], ex_taken};
        end
    end

    // -------------------------------------------------------
    // Gshare Predictor (4K × 2-bit counters)
    // Indexed by PC[12:1] XOR GHR[11:0]
    // -------------------------------------------------------
    reg [1:0] bht_global [0:BHT_GLOBAL_ENTRIES-1];
    wire [11:0] global_idx_rd = fetch_pc[12:1] ^ ghr;
    wire [11:0] global_idx_wr = ex_pc[12:1] ^ ghr;

    wire [1:0] global_ctr_rd = bht_global[global_idx_rd];
    wire       global_pred   = global_ctr_rd[1];

    // -------------------------------------------------------
    // Tournament Meta-Predictor (4K × 2-bit)
    // 00,01 → choose local; 10,11 → choose global
    // Updated when local and global disagree on a resolved branch
    // -------------------------------------------------------
    reg [1:0] bht_meta [0:META_ENTRIES-1];
    wire [11:0] meta_idx_rd = fetch_pc[12:1];
    wire [11:0] meta_idx_wr = ex_pc[12:1];

    wire [1:0] meta_ctr = bht_meta[meta_idx_rd];
    wire       use_global = meta_ctr[1];
    wire       final_pred = use_global ? global_pred : local_pred;

    // Execute-time predictions (indexed by ex_pc for resolved branch training)
    wire [1:0] local_ctr_wr  = bht_local[local_idx_wr];
    wire       ex_local_pred = local_ctr_wr[1];
    wire [1:0] global_ctr_wr = bht_global[global_idx_wr];
    wire       ex_global_pred = global_ctr_wr[1];

    // -------------------------------------------------------
    // BTB — 512-entry Direct-Mapped
    // Tag: PC[63:10], Target: full 64-bit
    // -------------------------------------------------------
    localparam BTB_IDX_BITS = 9;   // log2(512)
    localparam BTB_TAG_BITS = 54;  // 64 - 9 - 1(word-align)

    reg [BTB_TAG_BITS-1:0] btb_tag    [0:BTB_ENTRIES-1];
    reg [63:0]              btb_target [0:BTB_ENTRIES-1];
    reg                     btb_valid  [0:BTB_ENTRIES-1];

    wire [BTB_IDX_BITS-1:0] btb_idx_rd = fetch_pc[BTB_IDX_BITS:1];
    wire [BTB_TAG_BITS-1:0] btb_tag_rd = fetch_pc[63:BTB_IDX_BITS+1];
    wire                    btb_hit    = btb_valid[btb_idx_rd] &&
                                         (btb_tag[btb_idx_rd] == btb_tag_rd);

    wire [BTB_IDX_BITS-1:0] btb_idx_wr = ex_pc[BTB_IDX_BITS:1];
    wire [BTB_TAG_BITS-1:0] btb_tag_wr = ex_pc[63:BTB_IDX_BITS+1];

    // -------------------------------------------------------
    // Prediction Output Pipeline Register
    // -------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pred_taken  <= 1'b0;
            pred_target <= 64'h0;
            pred_valid  <= 1'b0;
        end else begin
            pred_taken  <= fetch_valid && final_pred && btb_hit;
            pred_target <= btb_target[btb_idx_rd];
            pred_valid  <= fetch_valid && btb_hit;
        end
    end

    // -------------------------------------------------------
    // Update Logic (on branch resolution in execute)
    // -------------------------------------------------------
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < BHT_LOCAL_ENTRIES; i = i + 1)
                bht_local[i]  <= 2'b01;  // Weakly not-taken
            for (i = 0; i < BHT_GLOBAL_ENTRIES; i = i + 1)
                bht_global[i] <= 2'b01;
            for (i = 0; i < META_ENTRIES; i = i + 1)
                bht_meta[i]   <= 2'b01;  // Start biased toward local
            for (i = 0; i < BTB_ENTRIES; i = i + 1)
                btb_valid[i]  <= 1'b0;
        end else if (ex_valid && (ex_is_branch || ex_is_jal)) begin
            // Update Local BHT
            if (ex_taken) begin
                bht_local[local_idx_wr] <=
                    (bht_local[local_idx_wr] == 2'b11) ? 2'b11 :
                     bht_local[local_idx_wr] + 2'b01;
            end else begin
                bht_local[local_idx_wr] <=
                    (bht_local[local_idx_wr] == 2'b00) ? 2'b00 :
                     bht_local[local_idx_wr] - 2'b01;
            end

            // Update Gshare BHT
            if (ex_taken) begin
                bht_global[global_idx_wr] <=
                    (bht_global[global_idx_wr] == 2'b11) ? 2'b11 :
                     bht_global[global_idx_wr] + 2'b01;
            end else begin
                bht_global[global_idx_wr] <=
                    (bht_global[global_idx_wr] == 2'b00) ? 2'b00 :
                     bht_global[global_idx_wr] - 2'b01;
            end

            // Update Meta-predictor: only when local and global disagree on resolved branch
            if (ex_local_pred != ex_global_pred) begin
                // If global was correct: increment (bias toward global)
                // If local was correct: decrement (bias toward local)
                if (ex_global_pred == ex_taken) begin
                    bht_meta[meta_idx_wr] <=
                        (bht_meta[meta_idx_wr] == 2'b11) ? 2'b11 :
                         bht_meta[meta_idx_wr] + 2'b01;
                end else begin
                    bht_meta[meta_idx_wr] <=
                        (bht_meta[meta_idx_wr] == 2'b00) ? 2'b00 :
                         bht_meta[meta_idx_wr] - 2'b01;
                end
            end

            // Update BTB: write target on taken branches or JAL
            if (ex_taken || ex_is_jal) begin
                btb_tag[btb_idx_wr]    <= btb_tag_wr;
                btb_target[btb_idx_wr] <= ex_target;
                btb_valid[btb_idx_wr]  <= 1'b1;
            end
        end
    end

endmodule

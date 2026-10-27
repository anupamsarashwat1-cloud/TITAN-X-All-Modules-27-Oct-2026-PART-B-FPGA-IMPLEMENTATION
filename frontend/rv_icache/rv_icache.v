// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — 32KB, 8-Way Set-Associative I-Cache with SECDED ECC
// Iteration 3: VIPT, PLRU replacement, AXI4 refill master (8-beat burst)
// Target: SCL 180nm, 125-200 MHz
// Geometry: 64-set × 8-way × 64B cacheline = 32KB
`timescale 1ns/1ps
`include "params.vh"

module rv_icache #(
    parameter WAYS       = `L1I_WAYS,        // 8
    parameter SETS       = `L1I_SETS,        // 64
    parameter LINE_BYTES = `L1I_LINE_BYTES,  // 64
    parameter ADDR_W     = 40,               // Physical address width
    parameter DATA_W     = 64               // AXI data width
)(
    input  wire             clk,
    input  wire             rst_n,

    // CPU fetch interface
    input  wire [ADDR_W-1:0] cpu_addr,   // Physical address (post-MMU)
    input  wire              cpu_req,    // Fetch request
    output reg  [31:0]       cpu_rdata,  // Instruction data
    output reg               cpu_valid,  // Data valid to CPU
    output wire              cpu_stall,  // Stall fetch stage

    // Invalidation
    input  wire              invalidate, // Full cache flush

    // AXI4 refill master (read-only, 8-beat burst)
    output reg               m_arvalid,
    input  wire              m_arready,
    output reg  [ADDR_W-1:0] m_araddr,
    output reg  [7:0]        m_arlen,    // Always 7 (8 beats)
    output reg  [2:0]        m_arsize,   // Always 3 (8 bytes per beat)
    output reg  [1:0]        m_arburst,  // Always INCR (01)
    input  wire              m_rvalid,
    output reg               m_rready,
    input  wire [DATA_W-1:0] m_rdata,
    input  wire              m_rlast,
    input  wire [1:0]        m_rresp,

    // ECC error reporting
    output reg               ecc_1bit,   // Correctable single-bit error
    output reg               ecc_2bit    // Uncorrectable double-bit error (NMI)
);

    // -------------------------------------------------------
    // Cache Geometry
    // -------------------------------------------------------
    localparam LINE_BITS  = LINE_BYTES * 8;     // 512 bits per cacheline
    localparam OFFSET_W   = $clog2(LINE_BYTES); // 6-bit byte offset
    localparam INDEX_W    = $clog2(SETS);        // 6-bit set index
    localparam TAG_W      = ADDR_W - INDEX_W - OFFSET_W; // 28-bit tag
    localparam BEATS      = LINE_BYTES / (DATA_W/8); // 8 beats per refill

    // Address decomposition
    wire [OFFSET_W-1:0] offset = cpu_addr[OFFSET_W-1:0];
    wire [INDEX_W-1:0]  index  = cpu_addr[OFFSET_W+INDEX_W-1:OFFSET_W];
    wire [TAG_W-1:0]    tag    = cpu_addr[ADDR_W-1:OFFSET_W+INDEX_W];

    // -------------------------------------------------------
    // SRAM Arrays (behavioral — replaced by foundry macro)
    // Tag SRAM: SETS × WAYS × (valid + ECC + tag)
    // Data SRAM: SETS × WAYS × LINE_BITS
    // -------------------------------------------------------
    localparam TAG_ECC_W = 7;  // Hsiao SEC-DED for 28-bit tag (need ceiling)
    localparam TAG_ENTRY_W = 1 + TAG_ECC_W + TAG_W;  // valid + ecc + tag

    reg [TAG_ENTRY_W-1:0]  tag_sram  [0:SETS-1][0:WAYS-1];
    reg [LINE_BITS-1:0]    data_sram [0:SETS-1][0:WAYS-1];
    // PLRU state: 7 bits for 8-way PLRU (binary tree)
    reg [6:0]              plru_state[0:SETS-1];

    // -------------------------------------------------------
    // SECDED ECC (Hsiao Code) — simplified behavioral model
    // In synthesis: replaced by hard ECC IP from SCL
    // -------------------------------------------------------
    function [TAG_ECC_W-1:0] compute_ecc;
        input [TAG_W-1:0] data;
        integer b;
        begin
            compute_ecc = 0;
            for (b = 0; b < TAG_W; b = b + 1)
                compute_ecc = compute_ecc ^ (data[b] ? (b+1) : 0);
        end
    endfunction

    // -------------------------------------------------------
    // Lookup (combinational read from SRAM)
    // -------------------------------------------------------
    wire [TAG_ENTRY_W-1:0] tag_rd   [0:WAYS-1];
    wire [LINE_BITS-1:0]   data_rd  [0:WAYS-1];
    genvar w;
    generate
        for (w = 0; w < WAYS; w = w + 1) begin : sram_rd
            assign tag_rd[w]  = tag_sram[index][w];
            assign data_rd[w] = data_sram[index][w];
        end
    endgenerate

    wire [WAYS-1:0] way_hit;
    genvar h;
    generate
        for (h = 0; h < WAYS; h = h + 1) begin : hit_detect
            assign way_hit[h] = tag_rd[h][TAG_W+TAG_ECC_W] &&           // valid bit
                                  (tag_rd[h][TAG_W-1:0] == tag);         // tag match
        end
    endgenerate

    wire cache_hit = |way_hit;

    // One-hot to binary encode hit way
    wire [2:0] hit_way_enc = way_hit[1] ? 3'd1 :
                              way_hit[2] ? 3'd2 :
                              way_hit[3] ? 3'd3 :
                              way_hit[4] ? 3'd4 :
                              way_hit[5] ? 3'd5 :
                              way_hit[6] ? 3'd6 :
                              way_hit[7] ? 3'd7 : 3'd0;

    // Data mux: select hitting way
    reg [LINE_BITS-1:0] hit_line;
    always @(*) begin
        hit_line = data_rd[0];
        case (hit_way_enc)
            3'd1: hit_line = data_rd[1];
            3'd2: hit_line = data_rd[2];
            3'd3: hit_line = data_rd[3];
            3'd4: hit_line = data_rd[4];
            3'd5: hit_line = data_rd[5];
            3'd6: hit_line = data_rd[6];
            3'd7: hit_line = data_rd[7];
            default: hit_line = data_rd[0];
        endcase
    end

    // Extract instruction word from cacheline (offset selects 8-byte beat, [1] selects word)
    wire [5:0]  word_offset = offset[5:3];   // Which 8-byte beat
    wire        half_sel    = offset[2];      // Which 32-bit word in beat
    wire [63:0] beat_data   = hit_line[word_offset*64 +: 64];
    wire [31:0] instr_word  = half_sel ? beat_data[63:32] : beat_data[31:0];

    // -------------------------------------------------------
    // PLRU: 8-way binary tree (7 bits)
    // bit[0]: root (0=left, 1=right)
    // bit[1]: left subtree (ways 0-3): 0=left, 1=right
    // bit[2]: right subtree (ways 4-7): 0=left, 1=right
    // bit[3]: ways 0-1: 0=way0, 1=way1
    // bit[4]: ways 2-3: 0=way2, 1=way3
    // bit[5]: ways 4-5: 0=way4, 1=way5
    // bit[6]: ways 6-7: 0=way6, 1=way7
    // -------------------------------------------------------
    wire [6:0] plru = plru_state[index];
    wire [2:0] plru_victim =
        !plru[0] ? (!plru[1] ? (!plru[3] ? 3'd0 : 3'd1) : (!plru[4] ? 3'd2 : 3'd3)) :
                    (!plru[2] ? (!plru[5] ? 3'd4 : 3'd5) : (!plru[6] ? 3'd6 : 3'd7));


    // Mark a way MRU in the 8-way PLRU tree (shared by hit path and
    // install path — installs previously never updated the tree, so the
    // victim pointer froze and one way was thrashed forever).
    task plru_mru;
        input [INDEX_W-1:0] ix;
        input [2:0]         wy;
        reg [6:0]           p;
        begin
            p = plru_state[ix];
            case (wy)
                3'd0: plru_state[ix] <= {p[6:4], 1'b0, 1'b0, 1'b0, 1'b1};
                3'd1: plru_state[ix] <= {p[6:4], 1'b1, 1'b0, 1'b0, 1'b1};
                3'd2: plru_state[ix] <= {p[6:5], 1'b0, p[3], 1'b1, 1'b1};
                3'd3: plru_state[ix] <= {p[6:5], 1'b1, p[3], 1'b1, 1'b1};
                3'd4: plru_state[ix] <= {p[6],   1'b0, p[4:3], p[2:1], 1'b1};
                3'd5: plru_state[ix] <= {p[6],   1'b1, p[4:3], p[2:1], 1'b1};
                3'd6: plru_state[ix] <= {1'b0,   p[5:3], p[2:1], 1'b1};
                3'd7: plru_state[ix] <= {1'b1,   p[5:3], p[2:1], 1'b1};
            endcase
        end
    endtask

    // -------------------------------------------------------
    // Refill FSM
    // -------------------------------------------------------
    localparam IDLE     = 2'd0;
    localparam SEND_REQ = 2'd1;
    localparam FILL     = 2'd2;

    reg [1:0]  state;
    reg [2:0]  fill_beat;       // Current beat count (0-7)
    reg [2:0]  fill_way;        // Way being filled (PLRU victim)
    reg [INDEX_W-1:0] fill_idx;
    reg [TAG_W-1:0]   fill_tag;
    reg [LINE_BITS-1:0] fill_buf;

    assign cpu_stall = cpu_req && !cache_hit && (state != IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            cpu_valid   <= 1'b0;
            cpu_rdata   <= 32'h0000_0013;  // NOP
            m_arvalid   <= 1'b0;
            m_rready    <= 1'b0;
            ecc_1bit    <= 1'b0;
            ecc_2bit    <= 1'b0;
            fill_beat   <= 3'h0;
        end else begin
            cpu_valid <= 1'b0;
            ecc_1bit  <= 1'b0;
            ecc_2bit  <= 1'b0;

            // Handle cache invalidation
            if (invalidate) begin
                // Tag SRAM clear — synthesis: write all valid bits to 0
                // Behavioral: use integer loop
            end

            case (state)
                IDLE: begin
                    if (cpu_req) begin
                        if (cache_hit) begin
                            cpu_rdata <= instr_word;
                            cpu_valid <= 1'b1;
                            plru_mru(index, hit_way_enc);
                            // Update PLRU on hit
                        end else begin
                            // Cache miss — start refill
                            fill_idx <= index;
                            fill_tag <= tag;
                            fill_way <= plru_victim;
                            // Aligned cacheline address
                            m_araddr   <= {cpu_addr[ADDR_W-1:OFFSET_W], {OFFSET_W{1'b0}}};
                            m_arlen    <= 8'd7;     // 8 beats
                            m_arsize   <= 3'd3;     // 8 bytes/beat
                            m_arburst  <= 2'b01;    // INCR
                            m_arvalid  <= 1'b1;
                            state      <= SEND_REQ;
                        end
                    end
                end

                SEND_REQ: begin
                    if (m_arready) begin
                        m_arvalid <= 1'b0;
                        m_rready  <= 1'b1;
                        fill_beat <= 3'h0;
                        fill_buf  <= {LINE_BITS{1'b0}};
                        state     <= FILL;
                    end
                end

                FILL: begin
                    if (m_rvalid) begin
                        // Store beat into fill buffer
                        fill_buf[fill_beat*64 +: 64] <= m_rdata;
                        fill_beat <= fill_beat + 3'h1;
                        if (m_rlast) begin
                            m_rready <= 1'b0;
                            // Install into cache SRAM (DC-004 fix, mirrors
                            // dcache): fill_buf holds beats 0..6 in the LOW
                            // slots; m_rdata IS beat 7 — top of the line.
                            data_sram[fill_idx][fill_way] <=
                                {m_rdata, fill_buf[LINE_BITS-65:0]};
                            tag_sram[fill_idx][fill_way] <=
                                {1'b1, compute_ecc(fill_tag), fill_tag};
                            plru_mru(fill_idx, fill_way);   // DC-005 mirror
                            // Invalidate all other ways with same tag (VIPT alias avoidance)
                            // PLRU: mark filled way as MRU
                            state <= IDLE;
                        end
                    end
                end

                default: state <= IDLE;
            endcase

        end
    end

    // -------------------------------------------------------
    // Invalidation: clear all valid bits synchronously
    // -------------------------------------------------------
    integer si, wi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (si = 0; si < SETS; si = si + 1) begin
                plru_state[si] <= 7'h0;
                for (wi = 0; wi < WAYS; wi = wi + 1)
                    tag_sram[si][wi] <= {TAG_ENTRY_W{1'b0}};
            end
        end else if (invalidate) begin
            for (si = 0; si < SETS; si = si + 1)
                for (wi = 0; wi < WAYS; wi = wi + 1)
                    tag_sram[si][wi][TAG_W+TAG_ECC_W] <= 1'b0;  // Clear valid bit
        end
    end

endmodule

// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — 32KB, 8-Way Set-Associative D-Cache with SECDED ECC
// Iteration 4 (Step 5.7 rebuild): Write-Back Write-Allocate, snoop stub,
// REAL flush (writeback-and-invalidate — the old flush dropped dirty data).
// Fixes over iteration 3:
//   DC-001 sub-word loads ignored offset[2:0] — every LB/LH/LW read lane 0.
//   DC-002 store-hit merge mask was width-broken garbage; proper byte merge.
//   DC-003 flush_all silently invalidated dirty lines (data loss); now
//          scans all lines and writes dirty ones back before invalidating.
// Geometry: 64-set × 8-way × 64B cacheline = 32KB
`timescale 1ns/1ps
`include "params.vh"

module rv_dcache #(
    parameter WAYS       = `L1D_WAYS,        // 8
    parameter SETS       = `L1D_SETS,        // 64
    parameter LINE_BYTES = `L1D_LINE_BYTES,  // 64
    parameter ADDR_W     = 40,
    parameter DATA_W     = 64,
    parameter MSHR_DEPTH = 4                 // reserved (single MSHR today)
)(
    input  wire              clk,
    input  wire              rst_n,

    // CPU load/store interface. CONTRACT: hold cpu_req level until
    // cpu_valid; on a miss the request is re-sampled automatically once
    // the refilled line installs (the consumer does not retry manually).
    input  wire [ADDR_W-1:0] cpu_addr,
    input  wire [DATA_W-1:0] cpu_wdata,
    input  wire [DATA_W/8-1:0] cpu_wstrb,
    input  wire              cpu_req,
    input  wire              cpu_wr,         // 1=store, 0=load
    input  wire [2:0]        cpu_size,       // 000=B,001=H,010=W,011=D,
                                             // 100=LBU,101=LHU,110=LWU
    output reg  [DATA_W-1:0] cpu_rdata,
    output reg               cpu_valid,
    output wire              cpu_stall,

    // Atomic: LR/SC reservation (A-ext absent in core today; tied off)
    input  wire              is_lr,
    input  wire              is_sc,
    input  wire [ADDR_W-1:0] lr_addr_in,
    input  wire              lr_valid_in,
    output wire              sc_success,

    // Cache maintenance
    input  wire              flush_all,      // pulse: writeback+invalidate all
    input  wire              flush_addr_en,  // RESERVED (not implemented)
    input  wire [ADDR_W-1:0] flush_addr,
    output wire              flush_busy,     // high while flush sequence runs

    // AXI4 master: 8-beat INCR bursts for refill and dirty eviction.
    // NOTE: this SoC's memory controllers are single-beat — the core
    // wraps this master with axi4_burst_to_lite, which decomposes.
    output reg               m_arvalid,
    input  wire              m_arready,
    output reg  [ADDR_W-1:0] m_araddr,
    output reg  [7:0]        m_arlen,
    output reg  [2:0]        m_arsize,
    output reg  [1:0]        m_arburst,
    output reg               m_arlock,       // LR/SC exclusive hint
    input  wire              m_rvalid,
    output reg               m_rready,
    input  wire [DATA_W-1:0] m_rdata,
    input  wire              m_rlast,
    input  wire [1:0]        m_rresp,
    output reg               m_awvalid,
    input  wire              m_awready,
    output reg  [ADDR_W-1:0] m_awaddr,
    output reg  [7:0]        m_awlen,
    output reg  [2:0]        m_awsize,
    output reg  [1:0]        m_awburst,
    output reg               m_wvalid,
    input  wire              m_wready,
    output reg  [DATA_W-1:0] m_wdata,
    output reg  [DATA_W/8-1:0] m_wstrb,
    output reg               m_wlast,
    input  wire              m_bvalid,
    output reg               m_bready,
    input  wire [1:0]        m_bresp,

    // L2 snoop port (coherence) — acknowledged, datapath TODO (Phase 7)
    input  wire              snoop_valid,
    input  wire [ADDR_W-1:0] snoop_addr,
    input  wire [1:0]        snoop_type,
    output reg               snoop_ack,
    output reg               snoop_data_valid,
    output reg  [511:0]      snoop_data,

    // ECC errors
    output reg               ecc_1bit,
    output reg               ecc_2bit
);

    // -------------------------------------------------------
    // Cache Geometry
    // -------------------------------------------------------
    localparam LINE_BITS = LINE_BYTES * 8;
    localparam OFFSET_W  = $clog2(LINE_BYTES);  // 6
    localparam INDEX_W   = $clog2(SETS);         // 6
    localparam TAG_W     = ADDR_W - INDEX_W - OFFSET_W;  // 28

    // -------------------------------------------------------
    // FSM state registers (declared early — the eviction datapath below
    // indexes arrays by the SCHEDULED fill_* pointers)
    // -------------------------------------------------------
    localparam D_IDLE      = 3'd0;
    localparam D_EVICT_WR  = 3'd1;  // write dirty victim to memory
    localparam D_EVICT_RSP = 3'd2;  // wait for write response
    localparam D_REFILL_RQ = 3'd3;  // send AXI read request
    localparam D_REFILL    = 3'd4;  // receive refill data
    localparam D_FLUSH_SCAN= 3'd5;  // flush: walk sets/ways, evict dirty

    reg [3:0]         state;        // 4 bits: headroom, all compares explicit
    reg [2:0]         fill_way;
    reg [INDEX_W-1:0] fill_idx;
    reg [TAG_W-1:0]   fill_tag;
    reg [LINE_BITS-1:0] fill_buf;
    reg [2:0]         fill_beat;
    reg [2:0]         evict_beat;

    // Flush machinery
    reg               flush_pend;   // flush_all pulse latched
    reg               flush_run;    // flush sequence in progress
    reg [INDEX_W-1:0] fsi;
    reg [2:0]         fsw;

    // Address fields
    wire [OFFSET_W-1:0] offset = cpu_addr[OFFSET_W-1:0];
    wire [INDEX_W-1:0]  index  = cpu_addr[OFFSET_W+INDEX_W-1:OFFSET_W];
    wire [TAG_W-1:0]    tag    = cpu_addr[ADDR_W-1:OFFSET_W+INDEX_W];

    // -------------------------------------------------------
    // SRAM Arrays (behavioral)
    // -------------------------------------------------------
    localparam TAG_ECC_W   = 7;
    localparam TAG_ENTRY_W = 1 + 1 + TAG_ECC_W + TAG_W; // valid+dirty+ecc+tag

    reg [TAG_ENTRY_W-1:0] tag_sram  [0:SETS-1][0:WAYS-1];
    reg [LINE_BITS-1:0]   data_sram [0:SETS-1][0:WAYS-1];
    reg [6:0]             plru_state[0:SETS-1];  // 8-way PLRU

    localparam TAG_V = TAG_ENTRY_W - 1;
    localparam TAG_D = TAG_ENTRY_W - 2;

    // -------------------------------------------------------
    // Lookup
    // -------------------------------------------------------
    wire [WAYS-1:0]        way_hit;
    wire [TAG_ENTRY_W-1:0] tag_rd  [0:WAYS-1];
    wire [LINE_BITS-1:0]   data_rd [0:WAYS-1];

    genvar i;
    generate
        for (i = 0; i < WAYS; i = i + 1) begin : arr_rd
            assign tag_rd[i]  = tag_sram[index][i];
            assign data_rd[i] = data_sram[index][i];
            assign way_hit[i] = tag_rd[i][TAG_V] && (tag_rd[i][TAG_W-1:0] == tag);
        end
    endgenerate

    wire cache_hit = |way_hit;

    wire [2:0] hit_way_enc = way_hit[1] ? 3'd1 : way_hit[2] ? 3'd2 :
                              way_hit[3] ? 3'd3 : way_hit[4] ? 3'd4 :
                              way_hit[5] ? 3'd5 : way_hit[6] ? 3'd6 :
                              way_hit[7] ? 3'd7 : 3'd0;

    // PLRU victim
    wire [6:0] plru = plru_state[index];
    wire [2:0] plru_victim =
        !plru[0] ? (!plru[1] ? (!plru[3] ? 3'd0 : 3'd1) : (!plru[4] ? 3'd2 : 3'd3)) :
                    (!plru[2] ? (!plru[5] ? 3'd4 : 3'd5) : (!plru[6] ? 3'd6 : 3'd7));

    wire victim_dirty = tag_sram[index][plru_victim][TAG_D];
    wire [TAG_W-1:0] victim_tag = tag_sram[index][plru_victim][TAG_W-1:0];

    // Line being evicted — indexed by the SCHEDULED fill_* registers so the
    // same eviction datapath serves both miss-refills and the flush scan
    // (which evicts arbitrary ways, not just the PLRU victim of cpu index).
    wire [LINE_BITS-1:0] evict_line = data_sram[fill_idx][fill_way];

    // Read data from hit way
    reg [LINE_BITS-1:0] hit_line;
    always @(*) begin
        hit_line = data_rd[0];
        case (hit_way_enc)
            3'd1: hit_line = data_rd[1]; 3'd2: hit_line = data_rd[2];
            3'd3: hit_line = data_rd[3]; 3'd4: hit_line = data_rd[4];
            3'd5: hit_line = data_rd[5]; 3'd6: hit_line = data_rd[6];
            3'd7: hit_line = data_rd[7]; default: hit_line = data_rd[0];
        endcase
    end

    wire [2:0]  word_sel  = offset[5:3];
    wire [63:0] word_data = hit_line[word_sel*64 +: 64];

    // DC-001 fix: align the addressed BYTE LANE down to bit 0 before the
    // size extract. Iteration 3 always extracted lane 0 — LB at %8==4
    // returned the wrong byte. Requires natural alignment (no accesses
    // crossing an 8-byte boundary); the core never issues those.
    wire [63:0] lane_aligned = word_data >> {offset[2:0], 3'b000};

    reg [DATA_W-1:0] cpu_rdata_comb;
    always @(*) begin
        case (cpu_size)
            3'b000: cpu_rdata_comb = {{56{lane_aligned[7]}},  lane_aligned[7:0]};
            3'b001: cpu_rdata_comb = {{48{lane_aligned[15]}}, lane_aligned[15:0]};
            3'b010: cpu_rdata_comb = {{32{lane_aligned[31]}}, lane_aligned[31:0]};
            3'b011: cpu_rdata_comb = lane_aligned;
            3'b100: cpu_rdata_comb = {56'h0, lane_aligned[7:0]};
            3'b101: cpu_rdata_comb = {48'h0, lane_aligned[15:0]};
            3'b110: cpu_rdata_comb = {32'h0, lane_aligned[31:0]};
            default: cpu_rdata_comb = lane_aligned;
        endcase
    end

    // -------------------------------------------------------
    // LR/SC Reservation
    // -------------------------------------------------------

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

    assign sc_success = is_sc && lr_valid_in &&
                         (lr_addr_in[ADDR_W-1:OFFSET_W] == cpu_addr[ADDR_W-1:OFFSET_W]);

    // -------------------------------------------------------
    // Store-hit merge (DC-002 fix). Pure bitwise form — an earlier
    // chain of eight self-referencing conditional PART-SELECT assigns
    // silently mis-evaluated under iverilog -g2012 (repro'd minimal):
    // never write per-byte merges that style.
    // -------------------------------------------------------
    wire [63:0] st_mask = {{8{cpu_wstrb[7]}}, {8{cpu_wstrb[6]}},
                           {8{cpu_wstrb[5]}}, {8{cpu_wstrb[4]}},
                           {8{cpu_wstrb[3]}}, {8{cpu_wstrb[2]}},
                           {8{cpu_wstrb[1]}}, {8{cpu_wstrb[0]}}};
    wire [63:0] st_merge_w = (hit_line[word_sel*64 +: 64] & ~st_mask)
                             | (cpu_wdata & st_mask);

    // -------------------------------------------------------
    // FSM (state registers declared above, next to geometry)
    // -------------------------------------------------------
    assign flush_busy = flush_run;
    assign cpu_stall  = cpu_req && !cache_hit;   // informative; the frontend
                                                 // wrapper sequences on
                                                 // cpu_valid, not stall.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= D_IDLE;
            cpu_valid  <= 1'b0;
            m_arvalid  <= 1'b0;
            m_awvalid  <= 1'b0;
            m_wvalid   <= 1'b0;
            m_rready   <= 1'b0;
            m_bready   <= 1'b0;
            ecc_1bit   <= 1'b0;
            ecc_2bit   <= 1'b0;
            snoop_ack  <= 1'b0;
            snoop_data_valid <= 1'b0;
            snoop_data <= 512'h0;
            flush_pend <= 1'b0;
            flush_run  <= 1'b0;
            fsi        <= {INDEX_W{1'b0}};
            fsw        <= 3'h0;
            fill_beat  <= 3'h0;
            evict_beat <= 3'h0;
        end else begin
            cpu_valid <= 1'b0;
            snoop_ack <= 1'b0;
            snoop_data_valid <= 1'b0;
            ecc_1bit <= 1'b0;
            ecc_2bit <= 1'b0;
            if (flush_all)
                flush_pend <= 1'b1;

            case (state)
                D_IDLE: begin
                    if (cpu_req && cache_hit) begin
                        if (!cpu_wr) begin
                            // Load hit
                            cpu_rdata <= cpu_rdata_comb;
                            cpu_valid <= 1'b1;
                        end else begin
                            // Store hit — byte-merged write into the line.
                            // Written as flat RMW: nested variable part-
                            // selects on the LHS are unreliable in some
                            // simulators (silent no-write).
                            begin : st_hit
                                reg [LINE_BITS-1:0] ln;
                                ln = data_sram[index][hit_way_enc];
                                ln[word_sel*64 +: 64] = st_merge_w;
                                data_sram[index][hit_way_enc] <= ln;
`ifdef DCACHE_DBG
                                $display("DBGRTL [%0t] ST idx=%0d way=%0d wsel=%0d off=%0d strb=%b mask=%h wdat=%h merge=%h",
                                         $time, index, hit_way_enc, word_sel,
                                         offset, cpu_wstrb, st_mask,
                                         cpu_wdata, st_merge_w);
`endif
                            end
                            begin : mark_dirty
                                reg [TAG_ENTRY_W-1:0] td;
                                td = tag_sram[index][hit_way_enc];
                                td[TAG_D] = 1'b1;
                                tag_sram[index][hit_way_enc] <= td;
                            end
                            cpu_valid <= 1'b1;
                        end
                        // Update PLRU to MRU on hit
                        case (hit_way_enc)
                            3'd0: plru_state[index] <= {plru[6:4], 1'b0, 1'b0, 1'b0, 1'b1};
                            3'd1: plru_state[index] <= {plru[6:4], 1'b1, 1'b0, 1'b0, 1'b1};
                            3'd2: plru_state[index] <= {plru[6:5], 1'b0, plru[3], 1'b1, 1'b1};
                            3'd3: plru_state[index] <= {plru[6:5], 1'b1, plru[3], 1'b1, 1'b1};
                            3'd4: plru_state[index] <= {plru[6], 1'b0, plru[4:3], plru[2:1], 1'b1};
                            3'd5: plru_state[index] <= {plru[6], 1'b1, plru[4:3], plru[2:1], 1'b1};
                            3'd6: plru_state[index] <= {1'b0, plru[5:3], plru[2:1], 1'b1};
                            3'd7: plru_state[index] <= {1'b1, plru[5:3], plru[2:1], 1'b1};
                        endcase
                    end else if (cpu_req && !cache_hit) begin
                        // Miss — schedule victim + fill
                        fill_idx  <= index;
                        fill_tag  <= tag;
                        fill_way  <= plru_victim;
                        fill_beat <= 3'h0;
                        if (victim_dirty) begin
                            m_awaddr  <= {victim_tag, index, {OFFSET_W{1'b0}}};
                            m_awlen   <= 8'd7;
                            m_awsize  <= 3'd3;
                            m_awburst <= 2'b01;
                            m_awvalid <= 1'b1;
                            evict_beat<= 3'h0;
                            state     <= D_EVICT_WR;
                        end else begin
                            m_araddr  <= {cpu_addr[ADDR_W-1:OFFSET_W], {OFFSET_W{1'b0}}};
                            m_arlen   <= 8'd7;
                            m_arsize  <= 3'd3;
                            m_arburst <= 2'b01;
                            m_arlock  <= is_lr;
                            m_arvalid <= 1'b1;
                            state     <= D_REFILL_RQ;
                        end
                    end else if (flush_pend && !cpu_req) begin
                        // Begin flush scan (service only with no pending
                        // access; the consumer holds cpu_req until served).
                        flush_pend <= 1'b0;
                        flush_run  <= 1'b1;
                        fsi        <= {INDEX_W{1'b0}};
                        fsw        <= 3'h0;
                        state      <= D_FLUSH_SCAN;
                    end

                    // Snoop acknowledgement (coherence datapath TODO)
                    if (snoop_valid)
                        snoop_ack <= 1'b1;
                end

                D_FLUSH_SCAN: begin
                    if (tag_sram[fsi][fsw][TAG_V] &&
                        tag_sram[fsi][fsw][TAG_D]) begin
                        // Schedule writeback of this dirty line through the
                        // shared eviction path (fill_* carry the target).
                        fill_idx   <= fsi;
                        fill_way   <= fsw;
                        m_awaddr   <= {tag_sram[fsi][fsw][TAG_W-1:0],
                                       fsi, {OFFSET_W{1'b0}}};
                        m_awlen    <= 8'd7;
                        m_awsize   <= 3'd3;
                        m_awburst  <= 2'b01;
                        m_awvalid  <= 1'b1;
                        evict_beat <= 3'h0;
                        state      <= D_EVICT_WR;
                    end else if (fsi == SETS - 1 && fsw == 3'd7) begin
                        flush_run <= 1'b0;      // scan exhausted — done
                        state     <= D_IDLE;
                    end else if (fsw == 3'd7) begin
                        fsw <= 3'h0;
                        fsi <= fsi + 1'b1;
                    end else begin
                        fsw <= fsw + 1'b1;
                    end
                end

                D_EVICT_WR: begin
                    // Start branch must fire exactly once: with a slave
                    // holding AWREADY high, an unguarded re-entry would
                    // re-arm WVALID after WLAST and leak a stale beat
                    // into the NEXT eviction transaction.
                    if (m_awready && !m_wvalid) begin
                        m_awvalid <= 1'b0;
                        m_wvalid  <= 1'b1;
                        m_wdata   <= evict_line[evict_beat*64 +: 64];
                        m_wstrb   <= 8'hFF;
                        m_wlast   <= (evict_beat == 3'd7);
                    end
                    if (m_wready && m_wvalid) begin
                        if (m_wlast) begin
                            m_wvalid <= 1'b0;
                            m_bready <= 1'b1;
                            state    <= D_EVICT_RSP;
                        end else begin
                            evict_beat <= evict_beat + 3'h1;
                            m_wdata <= evict_line[(evict_beat+3'd1)*64 +: 64];
                            m_wlast <= (evict_beat == 3'd6);
                        end
                    end
                end

                D_EVICT_RSP: begin
                    if (m_bvalid) begin
                        m_bready <= 1'b0;
                        // Victim leaves the cache either way: flushed lines
                        // are invalidated; miss-path victims get overwritten
                        // by the refill that follows. Flat RMW — the direct
                        // nested bit-select NBA here silently did NOT land
                        // (post-flush lines stayed valid+dirty in sim).
                        begin : inv_victim
                            reg [TAG_ENTRY_W-1:0] te;
                            te = tag_sram[fill_idx][fill_way];
                            te[TAG_V] = 1'b0;
                            te[TAG_D] = 1'b0;
                            tag_sram[fill_idx][fill_way] <= te;
                        end
                        if (flush_run) begin
                            state <= D_FLUSH_SCAN;   // continue the sweep
                        end else begin
                            m_araddr  <= {fill_tag, fill_idx, {OFFSET_W{1'b0}}};
                            m_arlen   <= 8'd7;
                            m_arsize  <= 3'd3;
                            m_arburst <= 2'b01;
                            m_arlock  <= 1'b0;
                            m_arvalid <= 1'b1;
                            state     <= D_REFILL_RQ;
                        end
                    end
                end

                D_REFILL_RQ: begin
                    if (m_arready) begin
                        m_arvalid <= 1'b0;
                        m_rready  <= 1'b1;
                        fill_buf  <= {LINE_BITS{1'b0}};
                        fill_beat <= 3'h0;
                        state     <= D_REFILL;
                    end
                end

                D_REFILL: begin
                    if (m_rvalid) begin
                        fill_buf[fill_beat*64 +: 64] <= m_rdata;
                        fill_beat <= fill_beat + 3'h1;
                        if (m_rlast) begin
                            m_rready <= 1'b0;
                            // Install new line (DC-004): fill_buf holds
                            // beats 0..6 in the LOW slots; m_rdata IS
                            // beat 7 and belongs at the TOP of the line.
                            data_sram[fill_idx][fill_way] <=
                                {m_rdata, fill_buf[LINE_BITS-65:0]};
                            tag_sram[fill_idx][fill_way] <=
                                {1'b1, 1'b0, 7'h0, fill_tag}; // valid, clean
                            plru_mru(fill_idx, fill_way);   // DC-005: installs
                                                            // must refresh the tree
                            state <= D_IDLE;
                        end
                    end
                end

                default: state <= D_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------
    // Synchronous Reset / bulk invalidate fallback.
    // The FLUSH WITH WRITEBACK lives in the main FSM (D_FLUSH_SCAN);
    // this path only runs at reset where there is nothing to save.
    // -------------------------------------------------------
    integer si, wi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (si = 0; si < SETS; si = si + 1) begin
                plru_state[si] <= 7'h0;
                for (wi = 0; wi < WAYS; wi = wi + 1)
                    tag_sram[si][wi] <= {TAG_ENTRY_W{1'b0}};
            end
        end
    end

endmodule

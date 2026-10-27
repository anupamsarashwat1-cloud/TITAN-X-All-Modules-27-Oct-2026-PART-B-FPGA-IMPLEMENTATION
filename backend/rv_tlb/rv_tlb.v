// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Sv39 Translation Lookaside Buffer
// Iteration 3: 32-entry, 4-way set-associative, ASID-tagged
// Shared between I-MMU and D-MMU (or split 16+16)
// Sv39: VPN[2](9) → VPN[1](9) → VPN[0](9) → PPN(44) + offset(12)
`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module rv_tlb #(
    parameter WAYS    = `TLB_WAYS,   // 4-way set-associative
    parameter SETS    = `TLB_SETS,   // 8 sets → 32 entries
    parameter ASID_W  = `ASID_WIDTH, // 16-bit ASID
    parameter VA_W    = `VADDR_WIDTH, // 39-bit virtual address
    parameter PA_W    = `PADDR_WIDTH  // 38-bit physical address
)(
    input  wire            clk,
    input  wire            rst_n,

    // Lookup port
    input  wire [VA_W-1:0] va_in,       // Virtual address to translate
    input  wire [ASID_W-1:0] asid_in,   // Current ASID from satp
    input  wire            req_valid,   // Translation request

    // Lookup result (combinational)
    output wire [PA_W-1:0] pa_out,      // Physical address (PPN + offset)
    output wire            hit,         // TLB hit
    output wire            perm_r,      // Read permission
    output wire            perm_w,      // Write permission
    output wire            perm_x,      // Execute permission
    output wire            perm_u,      // User-mode accessible
    output wire            page_fault,  // Permission violation

    // Fill port (from Page Table Walker)
    input  wire            fill_valid,  // PTW has a new translation to install
    input  wire [VA_W-1:0] fill_va,
    input  wire [PA_W-1:0] fill_pa,    // Physical page number (38-bit)
    input  wire [ASID_W-1:0] fill_asid,
    input  wire [7:0]      fill_perm,  // PTE permission bits [7:0]: D,A,G,U,X,W,R,V
    input  wire [1:0]      fill_level, // Page level: 0=4KB, 1=2MB mega, 2=1GB giga

    // SFENCE.VMA invalidation
    input  wire            sfence_vma,  // Flush entire TLB
    input  wire            sfence_asid, // Flush TLB by ASID only
    input  wire [ASID_W-1:0] sfence_asid_val,
    input  wire            sfence_va,   // Flush by VA+ASID
    input  wire [VA_W-1:0] sfence_va_val,

    // Access type (for permission checking)
    input  wire            access_r,
    input  wire            access_w,
    input  wire            access_x,
    input  wire            priv_s       // Supervisor mode (0=User)
);

    // -------------------------------------------------------
    // TLB Entry Format
    // -------------------------------------------------------
    // valid(1) + global(1) + asid(16) + vpn(27) + ppn(44) + perm(8) + level(2)
    // Total: 1+1+16+27+44+8+2 = 99 bits per entry
    localparam VPN_W   = 27;  // Three 9-bit VPN levels
    localparam PPN_W   = 44;  // Physical page number (38-bit PA / 4KB page = 26+18=44)

    reg              tlb_valid [0:SETS-1][0:WAYS-1];
    reg              tlb_global[0:SETS-1][0:WAYS-1];
    reg [ASID_W-1:0] tlb_asid  [0:SETS-1][0:WAYS-1];
    reg [VPN_W-1:0]  tlb_vpn   [0:SETS-1][0:WAYS-1];
    reg [PPN_W-1:0]  tlb_ppn   [0:SETS-1][0:WAYS-1];
    reg [7:0]        tlb_perm  [0:SETS-1][0:WAYS-1]; // D,A,G,U,X,W,R,V
    reg [1:0]        tlb_level [0:SETS-1][0:WAYS-1]; // 0=4KB, 1=2MB, 2=1GB
    // PLRU state: 3 bits for 4-way PLRU
    reg [2:0]        tlb_plru  [0:SETS-1];

    // Index into TLB: bits [5:3] of VPN[0] (using lower VA bits after page offset)
    localparam SET_BITS = 3;  // log2(SETS)
    wire [SET_BITS-1:0] set_idx = va_in[SET_BITS+11:12]; // VA[14:12]
    wire [VPN_W-1:0]    va_vpn  = va_in[VA_W-1:12];      // VPN[2:0] concatenated

    wire [SET_BITS-1:0] fill_set_idx = fill_va[SET_BITS+11:12];
    wire [VPN_W-1:0]    fill_vpn     = fill_va[VA_W-1:12];

    // -------------------------------------------------------
    // Lookup: combinational
    // -------------------------------------------------------
    // Per-way hit signals
    wire [WAYS-1:0] way_hit;
    wire [PPN_W-1:0] way_ppn  [0:WAYS-1];
    wire [7:0]        way_perm [0:WAYS-1];

    genvar w;
    generate
        for (w = 0; w < WAYS; w = w + 1) begin : tlb_lookup
            // Match conditions:
            // - valid
            // - VPN matches (considering superpage granularity)
            // - ASID matches OR global bit set
            wire vpn_match;
            assign vpn_match = (tlb_level[set_idx][w] == 2'd2) ?
                                  // 1GB: only top 9 VPN bits must match
                                  (tlb_vpn[set_idx][w][26:18] == va_vpn[26:18]) :
                               (tlb_level[set_idx][w] == 2'd1) ?
                                  // 2MB: top 18 VPN bits must match
                                  (tlb_vpn[set_idx][w][26:9]  == va_vpn[26:9]) :
                                  // 4KB: all 27 VPN bits must match
                                  (tlb_vpn[set_idx][w]        == va_vpn);
            assign way_hit[w] = tlb_valid[set_idx][w] && vpn_match &&
                                  (tlb_global[set_idx][w] ||
                                   (tlb_asid[set_idx][w] == asid_in));
            assign way_ppn[w]  = tlb_ppn[set_idx][w];
            assign way_perm[w] = tlb_perm[set_idx][w];
        end
    endgenerate

    assign hit = |way_hit;

    // Mux: select the hitting way
    wire [PPN_W-1:0] hit_ppn  = ({PPN_W{way_hit[0]}} & way_ppn[0]) |
                                  ({PPN_W{way_hit[1]}} & way_ppn[1]) |
                                  ({PPN_W{way_hit[2]}} & way_ppn[2]) |
                                  ({PPN_W{way_hit[3]}} & way_ppn[3]);
    wire [7:0] hit_perm = ({8{way_hit[0]}} & way_perm[0]) |
                           ({8{way_hit[1]}} & way_perm[1]) |
                           ({8{way_hit[2]}} & way_perm[2]) |
                           ({8{way_hit[3]}} & way_perm[3]);

    // Physical address = PPN concatenated with page offset
    assign pa_out   = {hit_ppn[PA_W-13:0], va_in[11:0]};
    assign perm_r   = hit_perm[1];  // R bit
    assign perm_w   = hit_perm[2];  // W bit
    assign perm_x   = hit_perm[3];  // X bit
    assign perm_u   = hit_perm[4];  // U bit

    // Permission fault detection
    wire access_fault = hit && req_valid && (
        (access_r && !perm_r) ||
        (access_w && !perm_w) ||
        (access_x && !perm_x) ||
        // Supervisor accessing user page without sstatus.SUM
        (priv_s && perm_u)
    );
    assign page_fault = access_fault;

    // -------------------------------------------------------
    // PLRU Replacement: 4-way
    // State encoding: {mru_bit, left_half_mru, right_half_mru}
    // plru[2]=0 means left (ways 0,1) recently used
    // plru[2]=1 means right (ways 2,3) recently used
    // plru[1] = which of way 0/1 was MRU (0=way0, 1=way1)
    // plru[0] = which of way 2/3 was MRU (0=way2, 1=way3)
    // -------------------------------------------------------
    wire [1:0] plru_victim;
    assign plru_victim = !tlb_plru[fill_set_idx][2] ? 
                          // Left half (ways 0,1): pick non-MRU
                          (!tlb_plru[fill_set_idx][1] ? 2'd0 : 2'd1) :
                          // Right half (ways 2,3): pick non-MRU
                          (!tlb_plru[fill_set_idx][0] ? 2'd2 : 2'd3);

    // PLRU update function: update on hit
    wire [1:0] hit_way_enc = way_hit[1] ? 2'd1 :
                              way_hit[2] ? 2'd2 :
                              way_hit[3] ? 2'd3 : 2'd0;

    // -------------------------------------------------------
    // Fill and Invalidation Logic
    // -------------------------------------------------------
    integer si, wi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (si = 0; si < SETS; si = si + 1) begin
                tlb_plru[si] <= 3'h0;
                for (wi = 0; wi < WAYS; wi = wi + 1) begin
                    tlb_valid[si][wi] <= 1'b0;
                    tlb_global[si][wi]<= 1'b0;
                end
            end
        end else begin
            // SFENCE.VMA: global flush
            if (sfence_vma) begin
                for (si = 0; si < SETS; si = si + 1)
                    for (wi = 0; wi < WAYS; wi = wi + 1)
                        if (!tlb_global[si][wi])  // Keep global entries
                            tlb_valid[si][wi] <= 1'b0;
            end
            // SFENCE by ASID
            else if (sfence_asid) begin
                for (si = 0; si < SETS; si = si + 1)
                    for (wi = 0; wi < WAYS; wi = wi + 1)
                        if (tlb_asid[si][wi] == sfence_asid_val && !tlb_global[si][wi])
                            tlb_valid[si][wi] <= 1'b0;
            end
            // SFENCE by VA+ASID
            else if (sfence_va) begin
                for (si = 0; si < SETS; si = si + 1)
                    for (wi = 0; wi < WAYS; wi = wi + 1)
                        if ((tlb_asid[si][wi] == sfence_asid_val || tlb_global[si][wi]) &&
                            (tlb_vpn[si][wi] == sfence_va_val[VA_W-1:12]))
                            tlb_valid[si][wi] <= 1'b0;
            end
            // Fill from PTW
            else if (fill_valid) begin
                // Install at victim way
                tlb_valid [fill_set_idx][plru_victim] <= 1'b1;
                tlb_global[fill_set_idx][plru_victim] <= fill_perm[5]; // G bit
                tlb_asid  [fill_set_idx][plru_victim] <= fill_asid;
                tlb_vpn   [fill_set_idx][plru_victim] <= fill_vpn;
                tlb_ppn   [fill_set_idx][plru_victim] <= fill_pa[PA_W-1:12];
                tlb_perm  [fill_set_idx][plru_victim] <= fill_perm;
                tlb_level [fill_set_idx][plru_victim] <= fill_level;
                // Update PLRU to mark this way as MRU
                case (plru_victim)
                    2'd0: tlb_plru[fill_set_idx] <= {1'b0, 1'b0, tlb_plru[fill_set_idx][0]};
                    2'd1: tlb_plru[fill_set_idx] <= {1'b0, 1'b1, tlb_plru[fill_set_idx][0]};
                    2'd2: tlb_plru[fill_set_idx] <= {1'b1, tlb_plru[fill_set_idx][1], 1'b0};
                    2'd3: tlb_plru[fill_set_idx] <= {1'b1, tlb_plru[fill_set_idx][1], 1'b1};
                endcase
            end else if (hit && req_valid) begin
                // Update PLRU on hit
                case (hit_way_enc)
                    2'd0: tlb_plru[set_idx] <= {1'b0, 1'b0, tlb_plru[set_idx][0]};
                    2'd1: tlb_plru[set_idx] <= {1'b0, 1'b1, tlb_plru[set_idx][0]};
                    2'd2: tlb_plru[set_idx] <= {1'b1, tlb_plru[set_idx][1], 1'b0};
                    2'd3: tlb_plru[set_idx] <= {1'b1, tlb_plru[set_idx][1], 1'b1};
                endcase
            end
        end
    end

endmodule

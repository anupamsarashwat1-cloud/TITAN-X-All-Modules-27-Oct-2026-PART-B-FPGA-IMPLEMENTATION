// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Physical Memory Protection (PMP)
// Iteration 3: 8 PMP entries per hart, placed after MMU output
// RISC-V Privileged Spec v1.12: TOR, NA4, NAPOT, and OFF modes
// Placement: between MMU PA output and L1 cache AXI master
`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module rv_pmp #(
    parameter NUM_ENTRIES = `PMP_ENTRIES  // 8 per hart
)(
    input  wire        clk,
    input  wire        rst_n,

    // Physical address being accessed (from MMU output)
    input  wire [37:0] paddr,       // 38-bit physical address
    input  wire        check_r,     // Load access
    input  wire        check_w,     // Store access
    input  wire        check_x,     // Fetch access
    input  wire [1:0]  priv_mode,   // Current privilege (M/S/U)
    input  wire        check_en,    // Request active

    // PMP configuration CSRs (from CSR file)
    // pmpcfg0 holds entries 0-7 in 8-bit fields
    input  wire [63:0] pmpcfg0,     // Entries 0-7 config
    input  wire [63:0] pmpcfg2,     // Entries 8-15 (for future expansion)
    // pmpaddr registers (one per entry)
    input  wire [303:0] pmpaddr_packed,

    // Result
    output wire        pmp_fault    // PMP access violation
);

    wire [37:0] pmpaddr [0:NUM_ENTRIES-1];
    genvar i_unpk;
    generate
        for(i_unpk=0; i_unpk<NUM_ENTRIES; i_unpk=i_unpk+1) begin : pmp_unpk
            assign pmpaddr[i_unpk] = pmpaddr_packed[i_unpk*38 +: 38];
        end
    endgenerate

    // -------------------------------------------------------
    // Extract per-entry configuration bytes
    // -------------------------------------------------------
    wire [7:0] pmpcfg [0:NUM_ENTRIES-1];
    genvar c;
    generate
        for (c = 0; c < 8; c = c + 1) begin : pmp_cfg_extract
            assign pmpcfg[c] = pmpcfg0[c*8 +: 8];
        end
    endgenerate

    // Per-entry fields
    wire [1:0] pmp_a  [0:NUM_ENTRIES-1];  // Address mode: OFF/TOR/NA4/NAPOT
    wire       pmp_r  [0:NUM_ENTRIES-1];  // Read
    wire       pmp_w  [0:NUM_ENTRIES-1];  // Write
    wire       pmp_x  [0:NUM_ENTRIES-1];  // Execute
    wire       pmp_l  [0:NUM_ENTRIES-1];  // Lock

    genvar i;
    generate
        for (i = 0; i < NUM_ENTRIES; i = i + 1) begin : pmp_fields
            assign pmp_l[i] = pmpcfg[i][7];
            assign pmp_a[i] = pmpcfg[i][4:3];
            assign pmp_x[i] = pmpcfg[i][2];
            assign pmp_w[i] = pmpcfg[i][1];
            assign pmp_r[i] = pmpcfg[i][0];
        end
    endgenerate

    // -------------------------------------------------------
    // Address Match Logic per entry
    // -------------------------------------------------------
    // TOR: pmpaddr[i-1] ≤ paddr < pmpaddr[i]
    // NA4: pmpaddr matches 4-byte aligned region
    // NAPOT: pmpaddr encodes base and size using trailing ones
    //   base = (pmpaddr & ~mask) << 2
    //   size = 2^(trailing_ones+3) bytes (minimum 8B)

    wire [NUM_ENTRIES-1:0] pmp_match;

    genvar m;
    generate
        for (m = 0; m < NUM_ENTRIES; m = m + 1) begin : pmp_addr_match
            wire [37:0] addr_m = pmpaddr[m];
            wire [37:0] addr_prev;
            if (m > 0) begin : gen_prev
                assign addr_prev = pmpaddr[m-1];
            end else begin : gen_prev0
                assign addr_prev = 38'h0;
            end

            // NAPOT: find number of trailing 1s in pmpaddr
            // mask = trailing 1s pattern
            wire [37:0] napot_mask;
            // Compute mask as (addr_m | (addr_m + 1)) ^ addr_m = trailing 1s
            // Alternatively: mask = (addr_m ^ (addr_m + 38'h1))
            assign napot_mask = addr_m ^ (addr_m + 38'h1);  // trailing 1s + next bit
            wire [37:0] napot_base = addr_m & ~napot_mask;   // aligned base
            wire [37:0] napot_end  = napot_base | napot_mask; // end address

            // NA4: 4-byte aligned, supports standard word addressing (PA[37:2] == addr_m[35:0])
            // and legacy byte addressing where addr_m contains raw physical address (PA[37:2] == addr_m[37:2])
            wire na4_match = (paddr[37:2] == addr_m[35:0]) || (paddr[37:2] == addr_m[37:2]);

            // TOR: paddr >= (prev_addr << 2) AND paddr < (addr_m << 2)
            wire tor_match = (paddr >= {addr_prev[35:0], 2'b00}) &&
                             (paddr <  {addr_m[35:0],    2'b00});

            // NAPOT: base <= paddr <= end (using word address paddr[37:2])
            wire napot_match = ((paddr[37:2] & ~napot_mask[35:0]) == napot_base[35:0]);

            assign pmp_match[m] = (pmp_a[m] == 2'b00) ? 1'b0 :          // OFF
                                   (pmp_a[m] == 2'b01) ? tor_match :      // TOR
                                   (pmp_a[m] == 2'b10) ? na4_match :      // NA4
                                                          napot_match;     // NAPOT
        end
    endgenerate

    // -------------------------------------------------------
    // Priority Encode: lowest-numbered matching entry wins
    // -------------------------------------------------------
    reg [7:0]  match_cfg;
    reg        any_match;
    integer    pe;
    always @(*) begin
        match_cfg = 8'h00;
        any_match = 1'b0;
        for (pe = NUM_ENTRIES-1; pe >= 0; pe = pe - 1) begin
            if (pmp_match[pe]) begin
                match_cfg = pmpcfg[pe];
                any_match = 1'b1;
            end
        end
    end

    // -------------------------------------------------------
    // Fault Decision
    // -------------------------------------------------------
    // Rules:
    // 1. If no PMP matches and in M-mode: allow (M-mode bypass unless locked)
    // 2. If no PMP matches and in S/U-mode: deny
    // 3. If matching entry: check permissions
    //    - Locked entries: checked even in M-mode
    //    - Unlocked entries: M-mode bypasses
    wire match_l = match_cfg[7];
    wire match_r = match_cfg[0];
    wire match_w = match_cfg[1];
    wire match_x = match_cfg[2];

    wire is_m_mode = (priv_mode == `PRIV_M);

    wire perm_ok = !check_en                                  ? 1'b1 :
                   !any_match && is_m_mode                    ? 1'b1 :   // M-mode, no match → allow
                   !any_match && !is_m_mode                   ? 1'b0 :   // S/U, no match → deny
                   // Matching entry found:
                   (is_m_mode && !match_l)                    ? 1'b1 :   // M-mode, unlocked → allow
                   // Locked or non-M-mode: check RWX
                   (!check_r || match_r) &&
                   (!check_w || match_w) &&
                   (!check_x || match_x);

    assign pmp_fault = !perm_ok;

endmodule

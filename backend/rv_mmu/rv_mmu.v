// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Sv39 Memory Management Unit (Top-level)
// Iteration 3: Integrates TLB + PTW, manages SATP CSR, mode switching
// Instantiated once for I-side and once for D-side per core
`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module rv_mmu (
    input  wire        clk,
    input  wire        rst_n,

    // SATP CSR (from CSR file)
    input  wire [63:0] satp,           // [63:60]=mode, [59:44]=ASID, [43:0]=PPN

    // Privilege mode
    input  wire [1:0]  priv_mode,      // 00=U, 01=S, 11=M

    // Translation request from pipeline
    input  wire [63:0] va_req,         // Virtual address
    input  wire        req_valid,      // Request valid
    input  wire        req_r,          // Load access
    input  wire        req_w,          // Store access
    input  wire        req_x,          // Fetch access

    // Translation result (1-cycle latency on TLB hit, multiple on miss)
    output wire [39:0] pa_out,         // Physical address (40-bit)
    output wire        trans_valid,    // Translation complete
    output wire        trans_busy,     // Stall pipeline

    // Page fault output
    output wire        page_fault,
    output wire [63:0] fault_va,

    // AXI4 PTW port (to lowest-priority crossbar master)
    output wire        ptw_arvalid,
    input  wire        ptw_arready,
    output wire [39:0] ptw_araddr,
    input  wire        ptw_rvalid,
    output wire        ptw_rready,
    input  wire [63:0] ptw_rdata,
    input  wire [1:0]  ptw_rresp,

    // SFENCE.VMA from execute stage
    input  wire        sfence_vma,
    input  wire        sfence_asid_en,
    input  wire        sfence_va_en,
    input  wire [63:0] sfence_va_val,
    input  wire [63:0] sfence_asid_val
);

    // -------------------------------------------------------
    // Decode SATP
    // -------------------------------------------------------
    wire [3:0]  satp_mode = satp[63:60];
    wire [15:0] satp_asid = satp[59:44];
    wire [43:0] satp_ppn  = satp[43:0];

    // Sv39 active when mode==8 and not in M-mode
    wire sv39_active = (satp_mode == 4'd8) && (priv_mode != `PRIV_M);

    // In bare mode (M-mode or mode==0), VA = PA (pass through)
    wire [39:0] pa_bare = va_req[39:0];

    // -------------------------------------------------------
    // TLB Instance
    // -------------------------------------------------------
    wire [37:0] tlb_pa;
    wire        tlb_hit;
    wire        tlb_perm_r, tlb_perm_w, tlb_perm_x, tlb_perm_u;
    wire        tlb_page_fault;

    // Fill signals from PTW
    wire        ptw_fill_valid;
    wire [38:0] ptw_fill_va;
    wire [37:0] ptw_fill_pa;
    wire [15:0] ptw_fill_asid;
    wire [7:0]  ptw_fill_perm;
    wire [1:0]  ptw_fill_level;

    rv_tlb u_tlb (
        .clk           (clk),
        .rst_n         (rst_n),
        .va_in         (va_req[38:0]),
        .asid_in       (satp_asid),
        .req_valid     (req_valid && sv39_active),
        .pa_out        (tlb_pa),
        .hit           (tlb_hit),
        .perm_r        (tlb_perm_r),
        .perm_w        (tlb_perm_w),
        .perm_x        (tlb_perm_x),
        .perm_u        (tlb_perm_u),
        .page_fault    (tlb_page_fault),
        // PTW fill
        .fill_valid    (ptw_fill_valid),
        .fill_va       (ptw_fill_va),
        .fill_pa       (ptw_fill_pa),
        .fill_asid     (ptw_fill_asid),
        .fill_perm     (ptw_fill_perm),
        .fill_level    (ptw_fill_level),
        // SFENCE
        .sfence_vma    (sfence_vma),
        .sfence_asid   (sfence_asid_en),
        .sfence_asid_val(sfence_asid_val[15:0]),
        .sfence_va     (sfence_va_en),
        .sfence_va_val  (sfence_va_val[38:0]),
        // Access type
        .access_r      (req_r),
        .access_w      (req_w),
        .access_x      (req_x),
        .priv_s        (priv_mode == `PRIV_S)
    );

    // -------------------------------------------------------
    // PTW Instance (on TLB miss)
    // -------------------------------------------------------
    wire ptw_busy;
    wire ptw_page_fault;
    wire [63:0] ptw_fault_addr;
    wire [1:0]  ptw_fault_type;

    rv_ptw u_ptw (
        .clk           (clk),
        .rst_n         (rst_n),
        .va_req        (va_req[38:0]),
        .asid_req      (satp_asid),
        .satp_ppn      (satp_ppn),
        .ptw_req       (sv39_active && req_valid && !tlb_hit && !ptw_busy && !ptw_fill_valid),
        .access_r      (req_r),
        .access_w      (req_w),
        .access_x      (req_x),
        .priv_s        (priv_mode == `PRIV_S),
        .ptw_busy      (ptw_busy),
        .fill_valid    (ptw_fill_valid),
        .fill_va       (ptw_fill_va),
        .fill_pa       (ptw_fill_pa),
        .fill_asid     (ptw_fill_asid),
        .fill_perm     (ptw_fill_perm),
        .fill_level    (ptw_fill_level),
        .page_fault    (ptw_page_fault),
        .fault_addr    (ptw_fault_addr),
        .fault_type    (ptw_fault_type),
        // AXI4
        .ptw_arvalid   (ptw_arvalid),
        .ptw_arready   (ptw_arready),
        .ptw_araddr    (ptw_araddr),
        .ptw_rvalid    (ptw_rvalid),
        .ptw_rready    (ptw_rready),
        .ptw_rdata     (ptw_rdata),
        .ptw_rresp     (ptw_rresp)
    );

    // -------------------------------------------------------
    // Output Mux: Bare vs Sv39
    // -------------------------------------------------------
    // Physical address
    assign pa_out       = sv39_active ?
                           {2'b00, tlb_pa} :
                           pa_bare;

    // Translation complete:
    // - Bare mode: immediately valid
    // - Sv39 + TLB hit: valid next cycle
    // - Sv39 + TLB miss: valid after PTW completes (ptw_fill_valid pulse)
    assign trans_valid  = !sv39_active                              ? req_valid :
                           (sv39_active && tlb_hit && req_valid)    ? 1'b1      :
                           (sv39_active && ptw_fill_valid)          ? 1'b1      :
                           1'b0;

    // Pipeline stall while walking page tables
    assign trans_busy   = sv39_active && !tlb_hit && (ptw_busy || req_valid);

    // Page fault (either from TLB permission check or PTW)
    assign page_fault   = (sv39_active && tlb_hit && tlb_page_fault) ||
                           ptw_page_fault;

    assign fault_va     = ptw_page_fault ? ptw_fault_addr : va_req;

endmodule

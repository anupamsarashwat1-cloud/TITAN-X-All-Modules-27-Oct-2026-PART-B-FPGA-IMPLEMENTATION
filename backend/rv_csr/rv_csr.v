// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Machine-mode CSR file (Zicsr support, Phase 5 Step 5.4)
//
// Minimal-but-honest M-mode ISA CSR set:
//   mstatus misa mie mtvec mscratch mepc mcause mtval mhartid
//   mcycle/minstret (+ cycle/instret aliases)
//
// Contract with the pipeline (see rv_core_top wiring):
//  - READ is combinational: csr_rdata follows csr_raddr in the same cycle
//    execute samples it (distance-1 RAW between two CSR ops needs no extra
//    forwarding because a younger op reaches EX at least one cycle after an
//    older op's synchronous write lands).
//  - WRITE is synchronous and single-issue: csr_we pulses only on the cycle
//    the owning instruction leaves EX (gated upstream by !stall/!flush/
//    !mul_div_stall), so flushed/stalled instructions never commit state.
//  - Trap entry: core redirects PC to mtvec and captures mepc/mcause via
//    trap_we; mret restores via mret_we (mstatus.MPIE->MIE shuffle here).
//  - Interrupts arrive as mip_* inputs; mip_int raises when pending&enabled.
//    Consumption (mtvec dispatch) is the core's job — this block only
//    reports.
`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module rv_csr #(
    parameter HART_ID = 0
) (
    input  wire        clk,
    input  wire        rst_n,
    // combinational read port (execute)
    input  wire [11:0] csr_raddr,
    output reg  [63:0] csr_rdata,
    // synchronous write port (execute, one pulse per retiring CSR op)
    input  wire        csr_we,
    input  wire [11:0] csr_waddr,
    input  wire [63:0] csr_wdata,
    // trap entry / return (core-level control, single pulse each)
    input  wire        trap_we,          // capture mepc/mcause/mstatus
    input  wire [63:0] trap_pc,          // PC of the trapping instruction
    input  wire [63:0] trap_cause,
    input  wire        mret_we,          // mstatus MPIE/MIE shuffle
    // machine interrupt pending (from CLINT/PLIC glue; active high)
    input  wire        mip_m_ext,
    input  wire        mip_m_timer,
    input  wire        mip_m_soft,
    // performance: one pulse per retired instruction
    input  wire        retire_pulse,
    // status out for the core/trap logic
    output wire [63:0] mtvec_out,
    output wire [63:0] mepc_out,
    output wire        irq_pending      // enabled machine interrupt waiting
);

    // -------------------------------------------------------
    // Register state
    // -------------------------------------------------------
    reg [63:0] mstatus_q;   // only MIE[3], MPIE[7], MPP[12:11] modeled
    reg [63:0] misa_q;      // WARL: RV64IM identity, reads back fixed
    reg [63:0] mie_q;       // MSIE[3] MTIE[7] MEIE[11]
    reg [63:0] mtvec_q;     // DIRECT: base only, mode bits [1:0] read 00
    reg [63:0] mscratch_q;
    reg [63:0] mepc_q;
    reg [63:0] mcause_q;
    reg [63:0] mtval_q;
    reg [63:0] mcycle_q, minstret_q;

    // RV64IM: Base RV64 (2 << 62) + M extension (1 << 12) + I extension (1 << 8)
    // Bit 2 ('C' compressed) cleared as core decode is 32-bit only
    localparam [63:0] MISA_RV64IM =
        (64'd2 << 62) | (64'd1 << 12) | (64'd1 << 8);
    localparam [63:0] MSTATUS_WR_MASK = (64'd1 << 3) | (64'd1 << 7) |
                                        (64'h3 << 11);
    localparam [63:0] MIE_WR_MASK     = (64'd1 << 3) | (64'd1 << 7) |
                                        (64'd1 << 11);

    // -------------------------------------------------------
    // Read decode (combinational). Unimplemented addresses read 0 — the
    // illegal-CSR trap decision lives in execute, not here, so this file
    // stays a pure register bank.
    // -------------------------------------------------------
    always @(*) begin
        case (csr_raddr)
            12'h300:    csr_rdata = mstatus_q;
            12'h301:    csr_rdata = misa_q;
            12'h304:    csr_rdata = mie_q;
            12'h305:    csr_rdata = mtvec_q;
            12'h340:    csr_rdata = mscratch_q;
            12'h341:    csr_rdata = mepc_q;
            12'h342:    csr_rdata = mcause_q;
            12'h343:    csr_rdata = mtval_q;
            12'hF14:    csr_rdata = {52'h0, HART_ID[11:0]}; // mhartid
            12'hB00:    csr_rdata = mcycle_q;
            12'hB02:    csr_rdata = minstret_q;
            12'hC00:    csr_rdata = mcycle_q;            // cycle alias
            12'hC02:    csr_rdata = minstret_q;          // instret alias
            default:    csr_rdata = 64'h0;
        endcase
    end

    // -------------------------------------------------------
    // Writes (priority: trap > mret > explicit CSR op — a trap taken in
    // the same cycle as an mret's status shuffle would be a design error
    // upstream; ordering here just makes the outcome deterministic).
    // -------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus_q  <= 64'h0;
            misa_q     <= MISA_RV64IM;
            mie_q      <= 64'h0;
            mtvec_q    <= 64'h0;
            mscratch_q <= 64'h0;
            mepc_q     <= 64'h0;
            mcause_q   <= 64'h0;
            mtval_q    <= 64'h0;
            mcycle_q   <= 64'h0;
            minstret_q <= 64'h0;
        end else begin
            // counters run regardless
            mcycle_q   <= mcycle_q + 64'd1;
            if (retire_pulse)
                minstret_q <= minstret_q + 64'd1;

            if (trap_we) begin
                mepc_q     <= {trap_pc[63:2], 2'b00}; // spec: low two bits clear
                mcause_q   <= trap_cause;
                mstatus_q[7] <= mstatus_q[3];         // MPIE <- MIE
                mstatus_q[3] <= 1'b0;                 // enter handler MIE off
                mstatus_q[12:11] <= 2'b11;            // MPP <- machine
            end else if (mret_we) begin
                mstatus_q[3]  <= mstatus_q[7];        // MIE <- MPIE
                mstatus_q[7]  <= 1'b1;
                mstatus_q[12:11] <= 2'b11;            // M-mode only invariant: MPP remains M-mode
            end else if (csr_we) begin
                case (csr_waddr)
                    12'h300: mstatus_q  <= (mstatus_q  & ~MSTATUS_WR_MASK)
                                           | (csr_wdata & MSTATUS_WR_MASK);
                    12'h301: misa_q     <= misa_q;     // WARL: unchanged
                    12'h304: mie_q      <= csr_wdata & MIE_WR_MASK;
                    12'h305: mtvec_q    <= {csr_wdata[63:2], 2'b00};
                    12'h340: mscratch_q <= csr_wdata;
                    12'h341: mepc_q     <= {csr_wdata[63:2], 2'b00};
                    12'h342: mcause_q   <= csr_wdata;
                    12'h343: mtval_q    <= csr_wdata;
                    // mhartid RO; counters WRITEME-free (spec: no trap on
                    // write attempt at M-level for these, effects none)
                    default: ;                         // incl. counter writes: ignored
                endcase
            end
        end
    end

    assign mtvec_out = {mtvec_q[63:2], 2'b00};
    assign mepc_out  = {mepc_q[63:2], 2'b00};

    wire irq_any =
        (mip_m_ext   & mie_q[11]) |
        (mip_m_timer & mie_q[7])  |
        (mip_m_soft  & mie_q[3]);
    assign irq_pending = irq_any && mstatus_q[3];   // MIE set

endmodule

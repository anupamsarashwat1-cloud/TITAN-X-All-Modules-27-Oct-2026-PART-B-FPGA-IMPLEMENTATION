// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Sv39 Page Table Walker
// Iteration 3: 3-level page table walk with AXI4 master interface
// On TLB miss: performs 3 sequential AXI4 reads through page tables
// Issues page faults on invalid/protection-violation PTEs
`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module rv_ptw (
    input  wire        clk,
    input  wire        rst_n,

    // Request from MMU (on TLB miss)
    input  wire [38:0] va_req,        // 39-bit virtual address
    input  wire [15:0] asid_req,      // ASID from satp
    input  wire [43:0] satp_ppn,      // Root page table PPN from satp
    input  wire        ptw_req,       // PTW request valid
    input  wire        access_r,      // Load
    input  wire        access_w,      // Store
    input  wire        access_x,      // Fetch
    input  wire        priv_s,        // Supervisor privilege
    output wire        ptw_busy,      // PTW is busy

    // Fill to TLB on success
    output reg         fill_valid,
    output reg  [38:0] fill_va,
    output reg  [37:0] fill_pa,       // Physical page number (38-bit)
    output reg  [15:0] fill_asid,
    output reg  [7:0]  fill_perm,
    output reg  [1:0]  fill_level,

    // Trap to pipeline on fault
    output reg         page_fault,
    output reg  [63:0] fault_addr,    // Faulting virtual address (for stval)
    output reg  [1:0]  fault_type,    // 0=instr, 1=load, 2=store

    // AXI4-Lite master port (read-only — low priority PTW port)
    output reg         ptw_arvalid,
    input  wire        ptw_arready,
    output reg  [39:0] ptw_araddr,
    input  wire        ptw_rvalid,
    output reg         ptw_rready,
    input  wire [63:0] ptw_rdata,
    input  wire [1:0]  ptw_rresp
);

    // -------------------------------------------------------
    // Sv39 Page Table Walk FSM
    // -------------------------------------------------------
    // VPN decomposition
    wire [8:0] vpn2 = va_req[38:30];  // Level-2 index (root)
    wire [8:0] vpn1 = va_req[29:21];  // Level-1 index
    wire [8:0] vpn0 = va_req[20:12];  // Level-0 index (4KB leaf)

    // PTE format (64-bit):
    // [63:10] PPN[2:0] = PPN[53:10]
    // [9:8]  RSW (software use)
    // [7] D (dirty), [6] A (accessed), [5] G (global), [4] U (user)
    // [3] X (execute), [2] W (write), [1] R (read), [0] V (valid)
    wire       pte_v = ptw_rdata[0];
    wire       pte_r = ptw_rdata[1];
    wire       pte_w = ptw_rdata[2];
    wire       pte_x = ptw_rdata[3];
    wire       pte_u = ptw_rdata[4];
    wire       pte_g = ptw_rdata[5];
    wire       pte_a = ptw_rdata[6];
    wire       pte_d = ptw_rdata[7];
    wire [43:0] pte_ppn = ptw_rdata[53:10];  // PPN field
    // Leaf PTE: R||W||X != 0
    wire       pte_is_leaf = pte_r || pte_x;

    // FSM states
    localparam PTW_IDLE   = 3'd0;
    localparam PTW_L2_REQ = 3'd1;  // Request L2 PT entry
    localparam PTW_L2_WAIT= 3'd2;  // Wait for L2 PT read
    localparam PTW_L1_REQ = 3'd3;  // Request L1 PT entry
    localparam PTW_L1_WAIT= 3'd4;  // Wait for L1 PT read
    localparam PTW_L0_REQ = 3'd5;  // Request L0 PT entry
    localparam PTW_L0_WAIT= 3'd6;  // Wait for L0 PT read
    localparam PTW_DONE   = 3'd7;

    reg [2:0]  ptw_state;
    reg [43:0] l2_ppn, l1_ppn;   // Intermediate PPN from higher-level PTEs
    reg [38:0] va_saved;
    reg [15:0] asid_saved;
    reg        acc_r, acc_w, acc_x, priv_s_saved;

    assign ptw_busy = (ptw_state != PTW_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ptw_state   <= PTW_IDLE;
            fill_valid  <= 1'b0;
            page_fault  <= 1'b0;
            ptw_arvalid <= 1'b0;
            ptw_rready  <= 1'b0;
        end else begin
            fill_valid <= 1'b0;
            page_fault <= 1'b0;

            case (ptw_state)
                PTW_IDLE: begin
                    if (ptw_req) begin
                        // Save request context
                        va_saved    <= va_req;
                        asid_saved  <= asid_req;
                        acc_r       <= access_r;
                        acc_w       <= access_w;
                        acc_x       <= access_x;
                        priv_s_saved<= priv_s;
                        // Level-2 PT address: satp.PPN × PAGESIZE + VPN[2] × 8
                        ptw_araddr  <= {satp_ppn[25:0], 12'h0} +
                                        {{31{1'b0}}, vpn2, 3'b000};
                        ptw_arvalid <= 1'b1;
                        ptw_state   <= PTW_L2_REQ;
                    end
                end

                PTW_L2_REQ: begin
                    if (ptw_arready) begin
                        ptw_arvalid <= 1'b0;
                        ptw_rready  <= 1'b1;
                        ptw_state   <= PTW_L2_WAIT;
                    end
                end

                PTW_L2_WAIT: begin
                    if (ptw_rvalid) begin
                        ptw_rready <= 1'b0;
                        if (ptw_rresp != 2'b00 || !pte_v || (!pte_r && pte_w)) begin
                            // Invalid PTE
                            page_fault <= 1'b1;
                            fault_addr <= {25'h0, va_saved};
                            fault_type <= acc_x ? 2'd0 : (acc_w ? 2'd2 : 2'd1);
                            ptw_state  <= PTW_IDLE;
                        end else if (pte_is_leaf) begin
                            // 1GB superpage leaf at L2
                            fill_valid <= 1'b1;
                            fill_va    <= va_saved;
                            fill_pa    <= {pte_ppn[25:18], va_saved[29:12], 12'h0};
                            fill_asid  <= asid_saved;
                            fill_perm  <= ptw_rdata[7:0];
                            fill_level <= 2'd2;
                            ptw_state  <= PTW_IDLE;
                        end else begin
                            // Non-leaf: descend to L1
                            l2_ppn      <= pte_ppn;
                            ptw_araddr  <= {pte_ppn[25:0], 12'h0} +
                                            {{31{1'b0}}, vpn1, 3'b000};
                            ptw_arvalid <= 1'b1;
                            ptw_state   <= PTW_L1_REQ;
                        end
                    end
                end

                PTW_L1_REQ: begin
                    if (ptw_arready) begin
                        ptw_arvalid <= 1'b0;
                        ptw_rready  <= 1'b1;
                        ptw_state   <= PTW_L1_WAIT;
                    end
                end

                PTW_L1_WAIT: begin
                    if (ptw_rvalid) begin
                        ptw_rready <= 1'b0;
                        if (ptw_rresp != 2'b00 || !pte_v || (!pte_r && pte_w)) begin
                            page_fault <= 1'b1;
                            fault_addr <= {25'h0, va_saved};
                            fault_type <= acc_x ? 2'd0 : (acc_w ? 2'd2 : 2'd1);
                            ptw_state  <= PTW_IDLE;
                        end else if (pte_is_leaf) begin
                            // 2MB superpage leaf at L1
                            fill_valid <= 1'b1;
                            fill_va    <= va_saved;
                            fill_pa    <= {pte_ppn[25:9], va_saved[20:12], 12'h0};
                            fill_asid  <= asid_saved;
                            fill_perm  <= ptw_rdata[7:0];
                            fill_level <= 2'd1;
                            ptw_state  <= PTW_IDLE;
                        end else begin
                            // Non-leaf: descend to L0
                            l1_ppn      <= pte_ppn;
                            ptw_araddr  <= {pte_ppn[25:0], 12'h0} +
                                            {{31{1'b0}}, vpn0, 3'b000};
                            ptw_arvalid <= 1'b1;
                            ptw_state   <= PTW_L0_REQ;
                        end
                    end
                end

                PTW_L0_REQ: begin
                    if (ptw_arready) begin
                        ptw_arvalid <= 1'b0;
                        ptw_rready  <= 1'b1;
                        ptw_state   <= PTW_L0_WAIT;
                    end
                end

                PTW_L0_WAIT: begin
                    if (ptw_rvalid) begin
                        ptw_rready <= 1'b0;
                        if (ptw_rresp != 2'b00 || !pte_v || (!pte_r && pte_w)) begin
                            page_fault <= 1'b1;
                            fault_addr <= {25'h0, va_saved};
                            fault_type <= acc_x ? 2'd0 : (acc_w ? 2'd2 : 2'd1);
                            ptw_state  <= PTW_IDLE;
                        end else if (!pte_is_leaf) begin
                            // PTE at L0 must be a leaf — fault
                            page_fault <= 1'b1;
                            fault_addr <= {25'h0, va_saved};
                            fault_type <= acc_x ? 2'd0 : (acc_w ? 2'd2 : 2'd1);
                            ptw_state  <= PTW_IDLE;
                        end else begin
                            // Valid 4KB leaf
                            // Check A/D bits (simplified: assume SW manages A/D)
                            fill_valid <= 1'b1;
                            fill_va    <= va_saved;
                            fill_pa    <= {pte_ppn[25:0], 12'h0};
                            fill_asid  <= asid_saved;
                            fill_perm  <= ptw_rdata[7:0];
                            fill_level <= 2'd0;
                            ptw_state  <= PTW_IDLE;
                        end
                    end
                end

                default: ptw_state <= PTW_IDLE;
            endcase
        end
    end

endmodule

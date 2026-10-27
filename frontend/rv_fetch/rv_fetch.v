// SPDX-License-Identifier: Apache-2.0
// SMVDU-Titan-X SoC — RISC-V Instruction Fetch Stage (RV64I)
//
// Single-outstanding AXI-Lite fetch FSM with redirect-safe teardown:
// on a redirect the unit first drains any orphaned transaction belonging
// to the abandoned stream (an unaccepted AR, or an R beat already owed)
// before issuing the redirected fetch. Without that drain the stale
// instruction would be paired with the NEW pc_out — silent execution of
// the wrong instruction at the wrong architectural address.
`timescale 1ns/1ps
`include "params.vh"

module rv_fetch #(
    parameter RESET_PC = `RESET_PC
) (
    input  wire        clk,
    input  wire        rst_n,
    // Hazard/control
    input  wire        stall,
    input  wire        flush,
    input  wire        branch_taken,
    input  wire [63:0] branch_target,
    // Instruction memory (AXI-Lite AR/R)
    output reg  [63:0] imem_addr,
    output reg         imem_arvalid,
    input  wire        imem_arready,
    input  wire [31:0] imem_rdata,
    input  wire        imem_rvalid,
    output wire        imem_rready,
    input  wire [1:0]  imem_rresp,
    // To decode stage
    output reg  [63:0] pc_out,
    output reg  [31:0] instr_out,
    output reg         valid_out
);
    reg [63:0] pc;

    // Fetch FSM
    localparam F_REQ   = 2'd1;
    localparam F_WAIT  = 2'd2;
    localparam F_FLUSH = 2'd3;   // draining an orphaned transaction
    reg [1:0] fstate;
    reg       pending_r;         // AR accepted; matching R beat still owed

    // Ready for the R beat while waiting for data OR while swallowing an
    // orphan after a redirect — and never during a global stall (a
    // compliant slave holds rvalid/rdata stable until we accept).
    assign imem_rready = (fstate == F_WAIT || fstate == F_FLUSH) && !stall;

    wire redirect = flush || branch_taken;

    // Transaction-completion pulses. r_fire doubles as "the R beat is being
    // consumed THIS edge" (rready is high by construction in both wait
    // states), which is what makes the redirect classification below exact.
    wire ar_fire = imem_arvalid && imem_arready;
    wire r_fire  = !stall && imem_rvalid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc           <= RESET_PC;
            imem_addr    <= RESET_PC;
            imem_arvalid <= 1'b0;
            pc_out       <= 64'h0;
            instr_out    <= 32'h0000_0013; // NOP
            valid_out    <= 1'b0;
            fstate       <= F_REQ;
            pending_r    <= 1'b0;
        end else begin
            case (fstate)
                F_REQ: begin
                    // Redirect windows are not just F_WAIT's problem: a
                    // branch resolving in the cycle RIGHT AFTER a delivery
                    // finds us here, with the sequential next address about
                    // to be (or just being) requested. Honoring it only in
                    // F_WAIT let one wrong-path instruction through whenever
                    // resolution landed in this window. Nothing is
                    // outstanding in F_REQ (pending_r cleared on entry), so
                    // the fix is simply aiming the next fetch at the target.
                    // Redirect outranks stall: the wrong-path beat is dead
                    // either way once the front-end is flushed.
                    if (redirect) begin
                        valid_out    <= 1'b0;
                        pc           <= branch_target;
                        imem_addr    <= branch_target;
                        imem_arvalid <= 1'b1;
                        fstate       <= F_WAIT;
                    end else if (!stall) begin
                    // Refill-gap valid discipline. valid_out was set for
                    // exactly the one delivery cycle; it must drop so decode
                    // cannot re-latch the SAME instruction once per refill
                    // cycle (the every-instruction-executes-thrice bug).
                    // BUT the drop is conditional on actual consumption:
                    // if the pipe stalled during the delivery cycle, decode
                    // froze before taking the beat — clearing valid here
                    // made the instruction evaporate the moment the stall
                    // released (every other store/load follower vanished).
                    // Producer rule: hold VALID until the consumer takes it.
                        valid_out    <= 1'b0;
                        imem_addr    <= pc;
                        imem_arvalid <= 1'b1;
                        fstate       <= F_WAIT;
                    end
                    // else: hold {pc_out, instr_out, valid_out} intact —
                    // decode is frozen and will consume on release.
                end
                F_WAIT: begin
                    // Track AR completion for the outstanding request
                    if (ar_fire) begin
                        imem_arvalid <= 1'b0;
                        pending_r    <= 1'b1;
                    end
                    if (redirect) begin
                        valid_out <= 1'b0;
                        pc        <= branch_target;
                        // An orphan survives this edge if an AR is still
                        // unaccepted (its address must stay stable — AXI
                        // forbids swapping ARADDR under held ARVALID) or a
                        // fetched beat is still owed after this edge's
                        // consumption. Only a truly clean line may issue
                        // the redirected fetch immediately; anything else
                        // drains through F_FLUSH first. This closes the
                        // redirect-vs-AR-acceptance same-edge race where
                        // the orphan beat would be paired with the new PC.
                        if ((imem_arvalid && !ar_fire) ||
                            ((pending_r || ar_fire) && !r_fire))
                            fstate <= F_FLUSH;
                        else begin
                            // Beat (if any) consumed this very edge —
                            // refetch the target immediately.
                            pending_r    <= 1'b0;
                            imem_addr    <= branch_target;
                            imem_arvalid <= 1'b1;
                        end
                    end else if (!stall && pending_r && imem_rvalid) begin
                        pc_out    <= pc;
                        instr_out <= imem_rdata;
                        valid_out <= (imem_rresp == 2'b00);
                        pc        <= pc + 64'd4;
                        pending_r <= 1'b0;
                        fstate    <= F_REQ;
                    end
                end
                F_FLUSH: begin
                    valid_out <= 1'b0;
                    // Latest target wins if another redirect arrives mid-drain.
                    if (redirect)
                        pc    <= branch_target;
                    if (imem_arvalid) begin
                        // Old request still waiting for its AR handshake:
                        // hold address/arvalid stable until accepted.
                        if (ar_fire) begin
                            imem_arvalid <= 1'b0;
                            pending_r    <= 1'b1;
                        end
                    end else if (pending_r) begin
                        if (r_fire)
                            pending_r <= 1'b0;    // orphan swallowed
                    end else begin
                        imem_addr    <= pc;
                        imem_arvalid <= 1'b1;
                        fstate       <= F_WAIT;
                    end
                end
                default: fstate <= F_REQ;
            endcase
        end
    end
endmodule

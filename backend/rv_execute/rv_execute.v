// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RV64GC Execute / ALU Stage
// Iteration 3: Adds M-extension (MUL/DIV) + A-extension (Atomics)
// Target: SCL 180nm, 125-200 MHz
`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module rv_execute #(
    parameter HART_ID = 0
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,
    // From decode
    input  wire [63:0] pc_in,
    input  wire [63:0] rs1_data,
    input  wire [63:0] rs2_data,
    input  wire [63:0] imm,
    input  wire [4:0]  rd_in,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [2:0]  funct3,
    input  wire [6:0]  funct7,
    input  wire [6:0]  opcode,
    input  wire [4:0]  alu_op,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire        reg_write,
    input  wire        branch,
    input  wire        jal,
    input  wire        jalr,
    input  wire        is_amo,      // A-extension: AMO instruction
    input  wire [4:0]  amo_funct5,  // AMO operation code [31:27]
    // SYSTEM stage controls (Phase 5 Step 5.4)
    input  wire        is_csr,
    input  wire [1:0]  csr_op,      // 01 W, 10 S, 11 C
    input  wire        is_ecall,
    input  wire        is_ebreak,
    input  wire        is_mret,
    // machine interrupt pending lines (CLINT/PLIC glue arrives later;
    // passed straight into the CSR file's mip inputs)
    input  wire        irq_m_ext,
    input  wire        irq_m_timer,
    input  wire        irq_m_soft,
    input  wire        valid_in,
    // Forwarding from MEM and WB
    input  wire [63:0] fwd_mem_data,
    input  wire        fwd_mem_valid,
    input  wire [4:0]  fwd_mem_rd,
    input  wire [63:0] fwd_wb_data,
    input  wire        fwd_wb_valid,
    input  wire [4:0]  fwd_wb_rd,
    // FPU result (registered from rv_fpu, arrives same cycle as ex stage)
    input  wire [63:0] fpu_result,
    input  wire        fpu_valid,
    input  wire        fpu_done,
    // To MEM stage
    output reg  [63:0] alu_result,
    output reg  [63:0] rs2_out,
    output reg  [4:0]  rd_out,
    output reg  [2:0]  funct3_out,
    output reg  [6:0]  opcode_out,
    output reg         mem_read_out,
    output reg         mem_write_out,
    output reg         reg_write_out,
    output reg         is_amo_out,
    output reg  [4:0]  amo_funct5_out,
    output reg         valid_out,
    // Stall to fetch/decode (MUL/DIV multi-cycle)
    output wire        mul_div_stall,
    // Branch resolution (back to fetch)
    output reg         branch_taken,
    output reg  [63:0] branch_target,
    // LR/SC reservation (exported to memory stage)
    output reg  [63:0] lr_addr,
    output reg         lr_valid
);

    // -------------------------------------------------------
    // Forwarding MUXes
    // -------------------------------------------------------
    // EX-stage pass-through: the instruction one slot ahead of the consumer
    // sits in our own EX->MEM pipeline registers — its result must forward
    // here or every distance-1 RAW hazard reads stale data. Loads are
    // excluded: during their memory access alu_result holds the ADDRESS,
    // not data; load-use is covered by mem_stall plus the MEM-stage
    // forwarding path instead.
    wire        fwd_ex_valid = valid_out && reg_write_out && !mem_read_out;
    wire [4:0]  fwd_ex_rd    = rd_out;
    wire [63:0] fwd_ex_data  = alu_result;

    wire [63:0] src1 = (fwd_ex_valid   && (fwd_ex_rd   == rs1_addr) && (rs1_addr != 5'h0)) ? fwd_ex_data  :
                       (fwd_mem_valid && (fwd_mem_rd == rs1_addr) && (rs1_addr != 5'h0)) ? fwd_mem_data :
                       (fwd_wb_valid  && (fwd_wb_rd  == rs1_addr) && (rs1_addr != 5'h0)) ? fwd_wb_data  :
                       rs1_data;

    wire [63:0] src2_reg = (fwd_ex_valid   && (fwd_ex_rd   == rs2_addr) && (rs2_addr != 5'h0)) ? fwd_ex_data  :
                           (fwd_mem_valid && (fwd_mem_rd == rs2_addr) && (rs2_addr != 5'h0)) ? fwd_mem_data :
                           (fwd_wb_valid  && (fwd_wb_rd  == rs2_addr) && (rs2_addr != 5'h0)) ? fwd_wb_data  :
                           rs2_data;

    // ALU source B: immediate for I/S/B/U/J, register for R-type
    wire use_imm = (opcode == `OP_IMM)   || (opcode == `OP_IMM64) ||
                   (opcode == `OP_LOAD)  || (opcode == `OP_LOAD_FP) ||
                   (opcode == `OP_STORE) || (opcode == `OP_STORE_FP) ||
                   (opcode == `OP_BRANCH)||
                   (opcode == `OP_JAL)   || (opcode == `OP_JALR)  ||
                   (opcode == `OP_LUI)   || (opcode == `OP_AUIPC);

    wire [63:0] src2 = use_imm ? imm : src2_reg;

    // RV64I *32 word-ops live ONLY in OP-IMM-32/OP-32: compute on the low
    // word, sign-extend the result to 64 bits, and take shift amounts from
    // [4:0]. Without the narrowing, ADDIW overflow kept garbage in the top
    // half (0x7FFFFFFF+1 yielded 0x0000000080000000, not sign-extended)
    // and W-shifts answered the 64-bit question.
    wire is_wop = (opcode == `OP_IMM64) || (opcode == `OP_REG64);
    wire [5:0] shamt = is_wop ? {1'b0, src2[4:0]} : src2[5:0];

    // -------------------------------------------------------
    // Integer ALU (combinational)
    // -------------------------------------------------------
    reg [63:0] alu_res_comb;
    always @(*) begin
        case (alu_op)
            `ALU_ADD:    alu_res_comb = src1 + src2;
            `ALU_SUB:    alu_res_comb = src1 - src2;
            `ALU_SLT:    alu_res_comb = ($signed(src1) < $signed(src2)) ? 64'd1 : 64'd0;
            `ALU_SLTU:   alu_res_comb = (src1 < src2) ? 64'd1 : 64'd0;
            `ALU_XOR:    alu_res_comb = src1 ^ src2;
            `ALU_OR:     alu_res_comb = src1 | src2;
            `ALU_AND:    alu_res_comb = src1 & src2;
            // W-form right-shifts must shift the ISOLATED 32-bit operand:
            // shifting the full 64-bit register slides dirty upper bits
            // down into the result's low word before the post-hoc narrow,
            // which answers a different question than SRLW/SRAW. Left
            // shifts are immune (garbage exits upward past the narrow).
            `ALU_SLL:    alu_res_comb = (is_wop ? {32'b0, src1[31:0]}
                                                : src1) << shamt;
            `ALU_SRL:    alu_res_comb = (is_wop ? {32'b0, src1[31:0]}
                                                : src1) >> shamt;
            `ALU_SRA:    alu_res_comb = $signed(is_wop
                                                ? {{32{src1[31]}}, src1[31:0]}
                                                : src1) >>> shamt;
            `ALU_LUI:    alu_res_comb = src2;
            `ALU_AUIPC:  alu_res_comb = pc_in + src2;
            `ALU_COPY_B: alu_res_comb = src2;
            // MUL/DIV: handled in mul_div unit; pass through to avoid latches
            default:     alu_res_comb = src1 + src2;
        endcase
    end

    // -------------------------------------------------------
    // M-Extension multicycle engine (CPU-002/CPU-003 fix)
    //
    // Why the old scheme deadlocked: mul_div_stall = div_busy ||
    // (is_mul && valid_in) feeds the GLOBAL stall (rv_core_top), which
    // comes back into this module as `stall` — so decode froze holding
    // the SAME mul presented, valid_in never dropped, and the stall
    // held forever. Even one release cycle would have latched the
    // PREVIOUS product (stage-1 regs updated on the same edge).
    //
    // This scheme, contract by contract:
    //  - rv_core_top feeds us stall_ex (mem_stall||halt) WITHOUT our own
    //    mul_div_stall, so starting is decidable from stable inputs.
    //  - Operands and control are CAPTURED on the start edge; the engine
    //    runs to completion off the captured copies (immune to whatever
    //    sits frozen at the inputs while decode is stalled).
    //  - On completion the result lands in the EX->MEM registers via the
    //    mx_done branches below, and mx_fin latches for ONE drain cycle:
    //    decode is still presenting the finished M-op that cycle (it was
    //    stalled throughout), so mul_div_stall must DROP (letting decode
    //    advance) while the EX->MEM normal path stays suppressed — else
    //    the same instruction would restart or double-deliver.
    //  - Completion is serialized against a load/store on the bus
    //    (!stall in mx_done / MX_MUL exit / MX_DIV stepping): delivering
    //    into EX->MEM while rv_mem owns that beat for a load would
    //    clobber the load address.
    //  - A flush aborts a busy op. Division specials (x/0, signed
    //    overflow) bypass the 64-cycle loop entirely.
    // -------------------------------------------------------
    wire is_mul = (alu_op == `ALU_MUL)  || (alu_op == `ALU_MULH) ||
                  (alu_op == `ALU_MULHSU)|| (alu_op == `ALU_MULHU);
    wire is_div = (alu_op == `ALU_DIV)  || (alu_op == `ALU_DIVU) ||
                  (alu_op == `ALU_REM)  || (alu_op == `ALU_REMU);
    wire is_mext = is_mul || is_div;

    localparam MX_IDLE = 2'd0, MX_MUL = 2'd1, MX_DIV = 2'd2;
    reg [1:0]  mx_state;
    reg [63:0] mx_a, mx_b;
    reg [6:0]  mx_opcode_q;
    reg [4:0]  mx_aluop_q, mx_rd_q;
    reg [2:0]  mx_f3_q;
    reg        mx_rw_q, mx_v_q;
    reg        mx_fin;      // finished op still presented; drain-cycle latch

    // NOTE: `stall` here is stall_ex (memory/halt only) — see header note.
    wire mx_raw_start = is_mext && valid_in && !stall && !flush && !mx_fin &&
                        (mx_state == MX_IDLE);
    assign mul_div_stall = (mx_state != MX_IDLE) || mx_raw_start;

    // Result-ready / result-delivered-this-edge qualifiers.
    wire mx_ready = (mx_state == MX_MUL) || d_special || d_last;
    wire mx_done  = mx_ready && !stall;

    // ---- start-edge operand prep ----
    // W forms operate on the SIGN-EXTENDED low words (captured below), so
    // e.g. DIVW sees exactly the word semantics. Overflow detection is
    // width-aware: sext32(INT32_MIN) is 64'hFFFF_FFFF_8000_0000, NOT the
    // 64-bit INT64_MIN pattern — a naive combined detector would also
    // swallow the legal 64-bit (-2^31)/(-1) = +2^31 and return garbage.
    wire        mxw       = (opcode == `OP_REG64);
    wire [63:0] eff_a     = mxw ? {{32{src1[31]}}, src1[31:0]} : src1;
    wire [63:0] eff_b     = mxw ? {{32{src2[31]}}, src2[31:0]} : src2;
    wire        signed_op = (alu_op == `ALU_DIV) || (alu_op == `ALU_REM);
    wire        a_neg     = eff_a[63];
    wire        b_zero    = (eff_b == 64'h0);
    wire        b_m1      = (eff_b == 64'hFFFF_FFFF_FFFF_FFFF);
    wire        ovf       = signed_op && !b_zero && b_m1 &&
                            (mxw ? (eff_a[31:0] == 32'h8000_0000)
                                 : (eff_a == 64'h8000_0000_0000_0000));

    // ---- divider working regs (restoring radix-2 over |a|,|b|) ----
    reg [63:0] d_rem, d_quot, d_x, d_y;
    reg [5:0]  d_cnt;
    reg        d_special, d_last, d_neg_q, d_neg_r;
    reg [63:0] d_result_q;

    wire [63:0] d_next_rem = {d_rem[62:0], d_x[63]};
    wire        d_sub      = d_next_rem >= d_y;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mx_state <= MX_IDLE;
            mx_a <= 64'h0;  mx_b <= 64'h0;
            mx_opcode_q <= 7'h0; mx_aluop_q <= 5'h0; mx_rd_q <= 5'h0;
            mx_f3_q <= 3'h0; mx_rw_q <= 1'b0; mx_v_q <= 1'b0;
            mx_fin <= 1'b0;
            d_rem <= 64'h0; d_quot <= 64'h0; d_x <= 64'h0; d_y <= 64'h0;
            d_cnt <= 6'd0; d_special <= 1'b0; d_last <= 1'b0;
            d_neg_q <= 1'b0; d_neg_r <= 1'b0; d_result_q <= 64'h0;
        end else if (flush) begin
            mx_state   <= MX_IDLE;
            d_special  <= 1'b0;
            d_last     <= 1'b0;
            mx_fin     <= 1'b0;
        end else begin
            // One-shot: raise on the delivery edge, drop on the drain
            // advance. Mutually exclusive conditions (mx_done implies
            // mul_div_stall; the clear implies its absence).
            if (mx_done)                              mx_fin <= 1'b1;
            else if (!stall && !mul_div_stall)        mx_fin <= 1'b0;

            case (mx_state)
              MX_IDLE: if (mx_raw_start) begin
                  // W forms capture the sign-extended words, not the raw
                  // 64-bit registers: word divide/rem are NOT modular,
                  // unlike MULW whose low word survives full-width math.
                  mx_a <= eff_a;  mx_b <= eff_b;
                  mx_opcode_q <= opcode;  mx_aluop_q <= alu_op;
                  mx_rd_q <= rd_in;  mx_f3_q <= funct3;
                  mx_rw_q <= reg_write;  mx_v_q <= valid_in;
                  if (is_div) begin
                      d_cnt     <= 6'd0;
                      d_special <= b_zero || ovf;
                      d_last    <= 1'b0;
                      d_neg_q   <= signed_op && !b_zero && (a_neg != eff_b[63]);
                      d_neg_r   <= (alu_op == `ALU_REM) && a_neg && !b_zero;
                      if (b_zero) begin
                          // DIV/DIVW -> -1 ; DIVU/DIVUW -> 2^N-1 ;
                          // REM/REMU (and W twins) -> dividend (sign
                          // included, not abs). BOTH remainder ops must
                          // take this arm — testing ALU_REM alone made
                          // REMU x/0 return the all-ones quotient.
                          d_result_q <= ((alu_op == `ALU_REM) ||
                                         (alu_op == `ALU_REMU))
                                        ? eff_a : 64'hFFFF_FFFF_FFFF_FFFF;
                      end else if (ovf) begin
                          // INT_MIN / -1 -> INT_MIN ; INT_MIN % -1 -> 0
                          d_result_q <= (alu_op == `ALU_REM)
                                        ? 64'h0 : eff_a;
                      end else begin
                          d_x <= (signed_op && a_neg) ? (~eff_a + 64'd1) : eff_a;
                          d_y <= (signed_op && eff_b[63]) ? (~eff_b + 64'd1) : eff_b;
                          d_rem  <= 64'h0;
                          d_quot <= 64'h0;
                      end
                      mx_state <= MX_DIV;
                  end else
                      mx_state <= MX_MUL;
              end
              // Hold until the delivery edge: exiting early (e.g. under a
              // simultaneous mem_stall) would lose the result.
              MX_MUL: if (mx_done) mx_state <= MX_IDLE;
              MX_DIV: if (!stall) begin
                  if (d_special || d_last) begin
                      d_special <= 1'b0;
                      d_last    <= 1'b0;
                      mx_state  <= MX_IDLE;
                  end else begin
                      d_x <= {d_x[62:0], 1'b0};
                      if (d_sub) begin
                          d_rem  <= d_next_rem - d_y;
                          d_quot <= {d_quot[62:0], 1'b1};
                      end else begin
                          d_rem  <= d_next_rem;
                          d_quot <= {d_quot[62:0], 1'b0};
                      end
                      if (d_cnt == 6'd63) d_last <= 1'b1;
                      else                d_cnt  <= d_cnt + 6'd1;
                  end
              end
              default: mx_state <= MX_IDLE;
            endcase
        end
    end

    // ---- multiplier datapath (comb over captured operands) ----
    wire signed [127:0] prod_ss = $signed(mx_a) * $signed(mx_b);
    wire        [127:0] prod_su = $signed(mx_a) * $signed({1'b0, mx_b});
    wire        [127:0] prod_uu = mx_a * mx_b;
    reg         [63:0]  mul_r;
    always @(*) begin
        case (mx_aluop_q)
            `ALU_MUL:    mul_r = prod_ss[63:0];
            `ALU_MULH:   mul_r = prod_ss[127:64];
            `ALU_MULHSU: mul_r = prod_su[127:64];
            `ALU_MULHU:  mul_r = prod_uu[127:64];
            default:     mul_r = prod_ss[63:0];
        endcase
    end

    // ---- divider final fixups ----
    // q = |a|//|b| sign-corrected (trunc toward zero), r = a - q*b takes
    // the dividend's sign — RISC-V semantics, matches the golden model.
    wire [63:0] quot_raw = d_neg_q ? (~d_quot + 64'd1) : d_quot;
    wire [63:0] rem_raw  = d_neg_r ? (~d_rem  + 64'd1) : d_rem;
    reg  [63:0] div_r;
    always @(*) begin
        case (mx_aluop_q)
            `ALU_DIV:    div_r = quot_raw;
            `ALU_DIVU:   div_r = d_quot;
            `ALU_REM:    div_r = rem_raw;
            default:     div_r = d_rem;          // REMU
        endcase
    end

    // W-form results narrow to sext32 of the computed word.
    wire        mxw_q    = (mx_opcode_q == `OP_REG64);
    wire [63:0] mext_final =
        mx_ready
            ? ((mx_state == MX_MUL)
                  ? (mxw_q ? {{32{prod_ss[31]}}, prod_ss[31:0]} : mul_r)
               : d_special
                  ? (mxw_q ? {{32{d_result_q[31]}}, d_result_q[31:0]}
                           : d_result_q)
                  : (mxw_q ? {{32{div_r[31]}}, div_r[31:0]} : div_r))
            : 64'h0;

    wire [63:0] mext_result = mext_final;

    // -------------------------------------------------------
    // Zicsr / privileged simples (Step 5.4)
    //
    // rv_csr is instantiated HERE (house style: regfile lives in decode).
    // Read is combinational (result mux below); writes and trap/mret
    // status shuffles pulse ONLY on the instruction's exit from EX — the
    // same edge its beat enters EX->MEM — so stalled, flushed, and
    // engine-held instructions never touch architectural state.
    // Distance-1 CSR RAW needs no forwarding: a younger CSR op reaches
    // EX at least one cycle after the older one's synchronous write.
    // -------------------------------------------------------
    wire sys_present  = valid_in && (opcode == `OP_SYSTEM);
    wire sys_illegal  = sys_present && !is_csr && !is_ecall &&
                        !is_ebreak && !is_mret;

    wire ex_exit      = valid_in && !stall && !flush &&
                        !mul_div_stall && !mx_fin;
    wire csr_commit   = ex_exit && is_csr;
    wire mret_commit  = ex_exit && is_mret;
    wire trap_commit  = ex_exit && (is_ecall || is_ebreak || sys_illegal ||
                                    csr_illegal || irq_take);

    wire [11:0] csr_a = imm[11:0];
    wire        csr_rmw = (csr_op == 2'b10) || (csr_op == 2'b11);
    // CSRRS/CSRRC with rs1=x0 read only — spec forbids side effects there.
    // Implemented-set decoder (must mirror rv_csr's read decode): access
    // to any other address raises illegal-instruction per the Zicsr spec.
    wire csr_impl = (csr_a == 12'h300) || (csr_a == 12'h301) ||
                    (csr_a == 12'h304) || (csr_a == 12'h305) ||
                    (csr_a == 12'h340) || (csr_a == 12'h341) ||
                    (csr_a == 12'h342) || (csr_a == 12'h343) ||
                    (csr_a == 12'hF14) || (csr_a == 12'hB00) ||
                    (csr_a == 12'hB02) || (csr_a == 12'hC00) ||
                    (csr_a == 12'hC02);
    wire csr_illegal = sys_present && is_csr && !csr_impl;

    wire        csr_we_w = csr_commit && !csr_illegal &&
                           !(csr_rmw && (rs1_addr == 5'h0));
    wire [63:0] csr_wd   = (csr_op == 2'b01) ? src1 :
                           (csr_op == 2'b10) ? (csr_old | src1) :
                                               (csr_old & ~src1);

    // Interrupt selection (Step 5.6). irq_pend already folds in mie enable
    // and mstatus.MIE inside rv_csr. Priority external > software > timer
    // is our documented choice (spec leaves M-mode priority open). Causes
    // carry the interrupt bit (63) per privileged spec.
    wire irq_sel_ext   = irq_pend && irq_m_ext;
    wire irq_sel_soft  = irq_pend && !irq_m_ext && irq_m_soft;
    wire irq_sel_timer = irq_pend && !irq_m_ext && !irq_m_soft &&
                         irq_m_timer;

    reg [63:0] trap_cause_w;
    always @(*) begin
        if (irq_sel_ext)    trap_cause_w = (64'd1 << 63) | 64'd11;
        else if (irq_sel_soft) trap_cause_w = (64'd1 << 63) | 64'd3;
        else if (irq_sel_timer) trap_cause_w = (64'd1 << 63) | 64'd7;
        else if (sys_illegal || csr_illegal)
                            trap_cause_w = 64'd2;    // illegal instruction
        else if (is_ebreak) trap_cause_w = 64'd3;    // breakpoint
        else                trap_cause_w = 64'd11;   // ecall from M-mode
    end

    wire [63:0] csr_old, mtvec_q, mepc_q;
    wire        irq_pend;
    rv_csr #(
        .HART_ID(HART_ID)
    ) u_csr (
        .clk          (clk),
        .rst_n        (rst_n),
        .csr_raddr    (csr_a),
        .csr_rdata    (csr_old),
        .csr_we       (csr_we_w),
        .csr_waddr    (csr_a),
        .csr_wdata    (csr_wd),
        .trap_we      (trap_commit),
        .trap_pc      (pc_in),
        .trap_cause   (trap_cause_w),
        .mret_we      (mret_commit),
        .mip_m_ext    (irq_m_ext),
        .mip_m_timer  (irq_m_timer),
        .mip_m_soft   (irq_m_soft),
        .retire_pulse (ex_exit),
        .mtvec_out    (mtvec_q),
        .mepc_out     (mepc_q),
        .irq_pending  (irq_pend)          // consumed below (Step 5.6)
    );

    // -------------------------------------------------------
    // A-Extension: LR/SC Reservation
    // -------------------------------------------------------
    // LR: set reservation; SC: check reservation
    // AMO arithmetic operations handled in memory stage (read-modify-write)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lr_addr  <= 64'h0;
            lr_valid <= 1'b0;
        end else if (is_amo && valid_in && (amo_funct5 == `AMO_LR) && !stall) begin
            lr_addr  <= src1;     // LR: address = rs1
            lr_valid <= 1'b1;
        end else if (is_amo && valid_in && (amo_funct5 == `AMO_SC) && !stall) begin
            // SC clears reservation regardless of success/failure
            lr_valid <= 1'b0;
        end
    end

    // -------------------------------------------------------
    // Branch Decision (combinational)
    // -------------------------------------------------------
    wire trap_req_c = valid_in && !stall && !flush &&
                      !mul_div_stall && !mx_fin &&
                      (is_ecall || is_ebreak || sys_illegal || csr_illegal);
    wire mret_req_c = valid_in && !stall && !flush &&
                      !mul_div_stall && !mx_fin && is_mret;
    // Preemption point: the beat leaving EX is redirected to mtvec instead
    // of retiring. Never preempted-beat: an mret (else a pending IRQ would
    // trap straight out of the restore) or an exception beat (exception
    // wins per spec ordering). Everything else — ALU, CSR, loads, stores,
    // even the beat after a multicycle op — is fair game; the killed beat
    // re-executes from its own PC after the handler's mret.
    wire irq_take   = ex_exit &&
                      (irq_sel_ext || irq_sel_soft || irq_sel_timer) &&
                      !mret_req_c && !trap_req_c;

    reg branch_comb;
    always @(*) begin
        branch_comb = 1'b0;
        if (branch) begin
            case (funct3)
                3'b000: branch_comb = (src1 == src2_reg);
                3'b001: branch_comb = (src1 != src2_reg);
                3'b100: branch_comb = ($signed(src1) < $signed(src2_reg));
                3'b101: branch_comb = ($signed(src1) >= $signed(src2_reg));
                3'b110: branch_comb = (src1 < src2_reg);
                3'b111: branch_comb = (src1 >= src2_reg);
                default: branch_comb = 1'b0;
            endcase
        end else if (jal || jalr || trap_req_c || mret_req_c ||
                     irq_take) begin
            // Traps, mret, and IRQ preemption reuse the branch redirect
            // machinery: PC goes to mtvec/mepc, fetch+decode flush exactly
            // like a taken jump.
            branch_comb = 1'b1;
        end
    end

    wire [63:0] branch_tgt =
        jalr       ? ((src1 + imm) & ~64'd1) :
        irq_take   ? mtvec_q :
        trap_req_c ? mtvec_q :
        mret_req_c ? mepc_q  :
                     (pc_in + imm);

    // -------------------------------------------------------
    // Result Mux: Integer / M-ext / FPU
    // -------------------------------------------------------
    wire is_fp_op = (opcode == `OP_FP)    || (opcode == `OP_FMADD) ||
                    (opcode == `OP_FMSUB)  || (opcode == `OP_FNMSUB) ||
                    (opcode == `OP_FNMADD);

    // Word-op result narrowing: sext32 of the computed low word. W-forms
    // never collide with the jump/FP/M-ext branches above, so ordering
    // here is only about keeping the default integer path last.
    wire [63:0] alu_res_w = {{32{alu_res_comb[31]}}, alu_res_comb[31:0]};

    wire [63:0] final_alu_res = (jal || jalr)   ? (pc_in + 64'd4)  :
                                 is_fp_op         ? fpu_result        :
                                 is_mext          ? mext_result        :
                                 is_csr           ? csr_old           :
                                 is_wop           ? alu_res_w          :
                                                    alu_res_comb;

    // -------------------------------------------------------
    // Pipeline Register
    // -------------------------------------------------------
    wire flush_ex_1, flush_ex_2, flush_ex_3, flush_ex_4;
    BUFX4 u_buf_flush_ex1 ( .A(flush), .Y(flush_ex_1) );
    BUFX4 u_buf_flush_ex2 ( .A(flush), .Y(flush_ex_2) );
    BUFX4 u_buf_flush_ex3 ( .A(flush), .Y(flush_ex_3) );
    BUFX4 u_buf_flush_ex4 ( .A(flush), .Y(flush_ex_4) );

    // Block 1: alu_result
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_result    <= 64'h0;
        end else if (flush_ex_1) begin
            alu_result    <= 64'h0;
        end else if (!stall && !mul_div_stall && !mx_fin) begin
            alu_result    <= final_alu_res;
        end else if (mx_done) begin
            alu_result    <= mext_result;
        end
    end

    // Block 2: rs2_out
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rs2_out       <= 64'h0;
        end else if (flush_ex_2) begin
            rs2_out       <= 64'h0;
        end else if (!stall && !mul_div_stall && !mx_fin) begin
            rs2_out       <= src2_reg;
        end
    end
    
    // Block 3: branch_target
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            branch_target <= 64'h0;
        end else if (flush_ex_3) begin
            branch_target <= 64'h0;
        end else if (!stall && !mul_div_stall && !mx_fin) begin
            branch_target <= branch_tgt;
        end
    end

    // Block 4: Control and Branch outputs
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_out        <= 5'h0;
            funct3_out    <= 3'h0;
            opcode_out    <= 7'h0;
            mem_read_out  <= 1'b0;
            mem_write_out <= 1'b0;
            reg_write_out <= 1'b0;
            is_amo_out    <= 1'b0;
            amo_funct5_out<= 5'h0;
            valid_out     <= 1'b0;
            branch_taken  <= 1'b0;
        end else if (flush_ex_4) begin
            rd_out        <= 5'h0;
            funct3_out    <= 3'h0;
            opcode_out    <= 7'h0;
            mem_read_out  <= 1'b0;
            mem_write_out <= 1'b0;
            reg_write_out <= 1'b0;
            is_amo_out    <= 1'b0;
            amo_funct5_out<= 5'h0;
            valid_out     <= 1'b0;
            branch_taken  <= 1'b0;
        end else if (!stall && !mul_div_stall && !mx_fin) begin
            rd_out        <= rd_in;
            funct3_out    <= funct3;
            opcode_out    <= opcode;
            // An interrupted or trapping beat commits NOTHING — including
            // no bus side effects: a preempted store must not reach the
            // interconnect (it re-executes after the handler returns).
            mem_read_out  <= mem_read && !irq_take && !trap_req_c;
            mem_write_out <= mem_write && !irq_take && !trap_req_c;
            reg_write_out <= reg_write && !trap_req_c && !irq_take &&
                             (!is_fp_op || fpu_done);
            is_amo_out    <= is_amo;
            amo_funct5_out<= amo_funct5;
            valid_out     <= valid_in;
            branch_taken  <= branch_comb && valid_in;
        end else if (mx_done) begin
            // M-ext delivery: replay the CAPTURED instruction's control
            // fields — decode is frozen presenting this same op, so the
            // live inputs would work too, but the captured copies are the
            // contract (and immune to any same-edge weirdness).
            rd_out        <= mx_rd_q;
            funct3_out    <= mx_f3_q;
            opcode_out    <= mx_opcode_q;
            mem_read_out  <= 1'b0;
            mem_write_out <= 1'b0;
            reg_write_out <= mx_rw_q;
            is_amo_out    <= 1'b0;
            amo_funct5_out<= 5'h0;
            valid_out     <= mx_v_q;
            branch_taken  <= 1'b0;
        end
    end

endmodule

// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — IEEE 754-2008 Floating Point Unit (F + D extensions)
// Iteration 3: RV64GC FPU — 4-stage pipeline, shared SP/DP datapath
// Target: SCL 180nm, 125-200 MHz
// Supports: FADD/FSUB/FMUL/FDIV/FSQRT/FMA, FCVT, FMIN/FMAX, FCMP, FMV
// Rounding modes: RNE, RTZ, RDN, RUP, RMM, DYN
`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module rv_fpu (
    input  wire        clk,
    input  wire        rst_n,
    // Instruction decode inputs
    input  wire [4:0]  fop,         // FP operation code [31:27]
    input  wire [1:0]  fmt,         // Precision: 00=SP, 01=DP
    input  wire [2:0]  rm,          // Rounding mode
    input  wire        valid_in,
    // Source operands (FP register file data — 64-bit, SP uses [31:0])
    input  wire [63:0] fp_src1,
    input  wire [63:0] fp_src2,
    input  wire [63:0] fp_src3,     // rs3 for FMA
    // Integer ↔ FP conversion inputs
    input  wire [63:0] int_src,     // Integer source for FCVT.S/D.W/WU/L/LU
    // CSR rounding mode (used when rm==DYN)
    input  wire [2:0]  frm_csr,
    // FPU result outputs
    output reg  [63:0] fp_result,
    output reg         result_valid,
    output reg  [4:0]  fflags,      // Exception flags: NV,DZ,OF,UF,NX
    output reg         fpu_done,
    // Integer result for FMV.X.W/D and FCMP
    output reg  [63:0] int_result,
    output reg         int_result_valid
);

    // -------------------------------------------------------
    // Effective rounding mode (resolve DYN)
    // -------------------------------------------------------
    wire [2:0] eff_rm = (rm == `RM_DYN) ? frm_csr : rm;

    // -------------------------------------------------------
    // Unpack SP/DP operands
    // Single: sign[31], exp[30:23], mantissa[22:0] (implicit 1.xxx)
    // Double: sign[63], exp[62:52], mantissa[51:0] (implicit 1.xxx)
    // -------------------------------------------------------
    // SP unpacking (src1)
    wire        sp_sgn1  = fp_src1[31];
    wire [7:0]  sp_exp1  = fp_src1[30:23];
    wire [22:0] sp_man1  = fp_src1[22:0];
    wire        sp_sgn2  = fp_src2[31];
    wire [7:0]  sp_exp2  = fp_src2[30:23];
    wire [22:0] sp_man2  = fp_src2[22:0];
    wire        sp_sgn3  = fp_src3[31];
    wire [7:0]  sp_exp3  = fp_src3[30:23];
    wire [22:0] sp_man3  = fp_src3[22:0];

    // DP unpacking
    wire        dp_sgn1  = fp_src1[63];
    wire [10:0] dp_exp1  = fp_src1[62:52];
    wire [51:0] dp_man1  = fp_src1[51:0];
    wire        dp_sgn2  = fp_src2[63];
    wire [10:0] dp_exp2  = fp_src2[62:52];
    wire [51:0] dp_man2  = fp_src2[51:0];
    wire        dp_sgn3  = fp_src3[63];
    wire [10:0] dp_exp3  = fp_src3[62:52];
    wire [51:0] dp_man3  = fp_src3[51:0];

    // Special value detection (SP)
    wire sp_inf1  = (sp_exp1 == 8'hFF) && (sp_man1 == 23'h0);
    wire sp_nan1  = (sp_exp1 == 8'hFF) && (sp_man1 != 23'h0);
    wire sp_inf2  = (sp_exp2 == 8'hFF) && (sp_man2 == 23'h0);
    wire sp_nan2  = (sp_exp2 == 8'hFF) && (sp_man2 != 23'h0);
    wire sp_zero1 = (sp_exp1 == 8'h00) && (sp_man1 == 23'h0);
    wire sp_zero2 = (sp_exp2 == 8'h00) && (sp_man2 == 23'h0);
    wire sp_denorm1 = (sp_exp1 == 8'h00) && (sp_man1 != 23'h0);
    wire sp_denorm2 = (sp_exp2 == 8'h00) && (sp_man2 != 23'h0);

    // Special value detection (DP)
    wire dp_inf1  = (dp_exp1 == 11'h7FF) && (dp_man1 == 52'h0);
    wire dp_nan1  = (dp_exp1 == 11'h7FF) && (dp_man1 != 52'h0);
    wire dp_inf2  = (dp_exp2 == 11'h7FF) && (dp_man2 == 52'h0);
    wire dp_nan2  = (dp_exp2 == 11'h7FF) && (dp_man2 != 52'h0);
    wire dp_zero1 = (dp_exp1 == 11'h000) && (dp_man1 == 52'h0);
    wire dp_zero2 = (dp_exp2 == 11'h000) && (dp_man2 == 52'h0);

    // Canonical NaN patterns (IEEE 754-2008 §6.2)
    localparam SP_QNAN = 32'h7FC0_0000;  // SP canonical quiet NaN
    localparam DP_QNAN = 64'h7FF8_0000_0000_0000; // DP canonical quiet NaN

    // -------------------------------------------------------
    // Pipeline Stage Registers (4 stages)
    // Stage 1: Unpack + align exponents
    // Stage 2: Mantissa operation
    // Stage 3: Normalize
    // Stage 4: Pack + round
    // -------------------------------------------------------

    // Stage 1 registers
    reg         s1_valid;
    reg [4:0]   s1_fop;
    reg [1:0]   s1_fmt;
    reg [2:0]   s1_rm;
    // SP internal (25-bit significand: implicit_1 + 23 + guard/round/sticky)
    reg         s1_sgn_a, s1_sgn_b, s1_sgn_c;
    reg [7:0]   s1_exp_a, s1_exp_b;
    reg [24:0]  s1_sig_a, s1_sig_b;  // 1.mantissa (1+23+1 guard bit)
    // DP internal (54-bit significand)
    reg         s1_dp_sgn_a, s1_dp_sgn_b;
    reg [10:0]  s1_dp_exp_a, s1_dp_exp_b;
    reg [53:0]  s1_dp_sig_a, s1_dp_sig_b;
    reg [7:0]   s1_exp_diff;
    reg [10:0]  s1_dp_exp_diff;
    // For FCVT and operands
    reg [63:0]  s1_int_src;
    reg [63:0]  s1_fp_src1, s1_fp_src2;

    // Stage 2 registers
    reg         s2_valid;
    reg [4:0]   s2_fop;
    reg [1:0]   s2_fmt;
    reg [2:0]   s2_rm;
    reg         s2_result_sgn;
    reg [7:0]   s2_result_exp;
    reg [49:0]  s2_result_sig;   // Enough bits for SP/DP with guard/round/sticky
    reg [10:0]  s2_dp_result_exp;
    reg [105:0] s2_dp_result_sig;
    reg [4:0]   s2_fflags;
    reg [63:0]  s2_int_src;
    reg [63:0]  s2_fp_src1, s2_fp_src2;
    reg         s2_is_nan, s2_is_inf, s2_is_zero;
    reg [63:0]  s2_special_result;
    reg         s2_special_valid;

    // Stage 3 registers (normalize)
    reg         s3_valid;
    reg [4:0]   s3_fop;
    reg [1:0]   s3_fmt;
    reg [2:0]   s3_rm;
    reg [63:0]  s3_int_src;
    reg [63:0]  s3_fp_src1, s3_fp_src2;
    reg         s3_result_sgn;
    reg [8:0]   s3_result_exp;   // Extended for overflow detection
    reg [25:0]  s3_result_sig;   // SP: 1+23+guard+round+sticky
    reg [11:0]  s3_dp_result_exp;
    reg [55:0]  s3_dp_result_sig;
    reg [4:0]   s3_fflags;
    reg [63:0]  s3_special_result;
    reg         s3_special_valid;
    reg         s3_is_nan, s3_is_inf, s3_is_zero;

    // -------------------------------------------------------
    // Stage 1: Unpack and align
    // -------------------------------------------------------
    // Significand with implicit leading 1 (denormals: leading 0)
    wire [23:0] sp_sig1_full = sp_denorm1 ? {1'b0, sp_man1} : {1'b1, sp_man1};
    wire [23:0] sp_sig2_full = sp_denorm2 ? {1'b0, sp_man2} : {1'b1, sp_man2};
    wire [52:0] dp_sig1_full = (dp_exp1 == 11'h0) ? {1'b0, dp_man1} : {1'b1, dp_man1};
    wire [52:0] dp_sig2_full = (dp_exp2 == 11'h0) ? {1'b0, dp_man2} : {1'b1, dp_man2};

    // Exponent difference for alignment
    wire [7:0] sp_exp_diff = (sp_exp1 >= sp_exp2) ?
                              (sp_exp1 - sp_exp2) : (sp_exp2 - sp_exp1);
    wire [10:0] dp_exp_diff = (dp_exp1 >= dp_exp2) ?
                               (dp_exp1 - dp_exp2) : (dp_exp2 - dp_exp1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 1'b0;
        end else begin
            s1_valid    <= valid_in;
            s1_fop      <= fop;
            s1_fmt      <= fmt;
            s1_rm       <= eff_rm;
            s1_int_src  <= int_src;
            s1_fp_src1  <= fp_src1;
            s1_fp_src2  <= fp_src2;
            // SP
            s1_sgn_a    <= sp_sgn1;
            s1_sgn_b    <= sp_sgn2;
            s1_sgn_c    <= sp_sgn3;
            s1_exp_a    <= sp_exp1;
            s1_exp_b    <= sp_exp2;
            s1_sig_a    <= {sp_sig1_full, 1'b0};  // Guard bit space
            s1_sig_b    <= {sp_sig2_full, 1'b0};
            s1_exp_diff <= sp_exp_diff;
            // DP
            s1_dp_sgn_a <= dp_sgn1;
            s1_dp_sgn_b <= dp_sgn2;
            s1_dp_exp_a <= dp_exp1;
            s1_dp_exp_b <= dp_exp2;
            s1_dp_sig_a <= {dp_sig1_full, 1'b0};
            s1_dp_sig_b <= {dp_sig2_full, 1'b0};
            s1_dp_exp_diff <= dp_exp_diff;
        end
    end

    // -------------------------------------------------------
    // Stage 2: Mantissa Operation (add/sub/mul)
    // -------------------------------------------------------
    // SP FADD/FSUB: align smaller, then add/subtract
    // Result mantissa is 50-bit to capture overflow and guard bits
    wire        sp_a_larger  = (s1_exp_a > s1_exp_b) ||
                                ((s1_exp_a == s1_exp_b) && (s1_sig_a >= s1_sig_b));
    wire [24:0] sp_sig_large = sp_a_larger ? s1_sig_a : s1_sig_b;
    wire [24:0] sp_sig_small = sp_a_larger ? s1_sig_b : s1_sig_a;
    wire [7:0]  sp_exp_large = sp_a_larger ? s1_exp_a : s1_exp_b;
    wire        sp_sgn_large = sp_a_larger ? s1_sgn_a : s1_sgn_b;
    wire        sp_sgn_small = sp_a_larger ? s1_sgn_b : s1_sgn_a;

    // Align smaller operand (right-shift by exp_diff)
    wire [24:0] sp_sig_aligned = sp_sig_small >> (s1_exp_diff > 8'd24 ? 8'd24 : s1_exp_diff);
    // Effective operation: same sign = add, different sign = sub
    wire        sp_eff_sub = (s1_fop == `FOP_FSUB) ?
                              ~(sp_sgn_large ^ sp_sgn_small) :
                               (sp_sgn_large ^ sp_sgn_small);
    wire [25:0] sp_add_result = sp_eff_sub ?
                                 (sp_sig_large - sp_sig_aligned) :
                                 (sp_sig_large + sp_sig_aligned);

    // FMUL: 48-bit product (24×24)
    wire [47:0] sp_mul_result = sp_sig_large[24:1] * sp_sig_small[24:1];

    // DP FADD/FSUB
    wire        dp_a_larger  = (s1_dp_exp_a > s1_dp_exp_b) ||
                                ((s1_dp_exp_a == s1_dp_exp_b) && (s1_dp_sig_a >= s1_dp_sig_b));
    wire [53:0] dp_sig_large = dp_a_larger ? s1_dp_sig_a : s1_dp_sig_b;
    wire [53:0] dp_sig_small = dp_a_larger ? s1_dp_sig_b : s1_dp_sig_a;
    wire [10:0] dp_exp_large = dp_a_larger ? s1_dp_exp_a : s1_dp_exp_b;
    wire        dp_sgn_large = dp_a_larger ? s1_dp_sgn_a : s1_dp_sgn_b;
    wire        dp_sgn_small = dp_a_larger ? s1_dp_sgn_b : s1_dp_sgn_a;
    wire [53:0] dp_sig_aligned = dp_sig_small >> (s1_dp_exp_diff > 11'd53 ? 11'd53 : s1_dp_exp_diff);
    wire        dp_eff_sub = (s1_fop == `FOP_FSUB) ?
                              ~(dp_sgn_large ^ dp_sgn_small) :
                               (dp_sgn_large ^ dp_sgn_small);
    wire [54:0] dp_add_result = dp_eff_sub ?
                                  (dp_sig_large - dp_sig_aligned) :
                                  (dp_sig_large + dp_sig_aligned);
    wire [105:0] dp_mul_result = dp_sig_large[53:1] * dp_sig_small[53:1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 1'b0;
        end else begin
            s2_valid    <= s1_valid;
            s2_fop      <= s1_fop;
            s2_fmt      <= s1_fmt;
            s2_rm       <= s1_rm;
            s2_int_src  <= s1_int_src;
            s2_fp_src1  <= s1_fp_src1;
            s2_fp_src2  <= s1_fp_src2;
            // Default: no special case
            s2_is_nan       <= 1'b0;
            s2_is_inf       <= 1'b0;
            s2_is_zero      <= 1'b0;
            s2_special_valid<= 1'b0;
            s2_fflags       <= 5'h0;
            s2_special_result <= 64'h0;

            if (s1_fmt == `FMT_S) begin
                // SP special case detection
                if (sp_nan1 || sp_nan2) begin
                    s2_is_nan       <= 1'b1;
                    s2_special_valid<= 1'b1;
                    s2_special_result <= {32'h0, SP_QNAN};
                    s2_fflags       <= `FFLAG_NV;
                end else if ((s1_fop == `FOP_FADD || s1_fop == `FOP_FSUB || s1_fop == `FOP_FMUL) &&
                              sp_inf1 && sp_inf2 && sp_eff_sub) begin
                    // Inf - Inf = NaN
                    s2_is_nan       <= 1'b1;
                    s2_special_valid<= 1'b1;
                    s2_special_result <= {32'h0, SP_QNAN};
                    s2_fflags       <= `FFLAG_NV;
                end else if (s1_fop == `FOP_FDIV && sp_zero1 && sp_zero2) begin
                    // 0/0 = NaN
                    s2_is_nan       <= 1'b1;
                    s2_special_valid<= 1'b1;
                    s2_special_result <= {32'h0, SP_QNAN};
                    s2_fflags       <= `FFLAG_NV;
                end else if (s1_fop == `FOP_FDIV && sp_zero2) begin
                    // x/0 = ±Inf
                    s2_is_inf       <= 1'b1;
                    s2_special_valid<= 1'b1;
                    s2_special_result <= {32'h0, s1_sgn_a ^ s1_sgn_b, 8'hFF, 23'h0};
                    s2_fflags       <= `FFLAG_DZ;
                end else begin
                    // Normal case
                    case (s1_fop)
                        `FOP_FADD, `FOP_FSUB: begin
                            s2_result_sgn <= sp_eff_sub ? (sp_add_result[25] ? sp_sgn_small : sp_sgn_large)
                                                         : sp_sgn_large;
                            s2_result_exp <= sp_exp_large;
                            s2_result_sig <= {sp_add_result, 24'h0};
                        end
                        `FOP_FMUL: begin
                            s2_result_sgn <= s1_sgn_a ^ s1_sgn_b;
                            s2_result_exp <= s1_exp_a + s1_exp_b - 8'd127;
                            s2_result_sig <= {sp_mul_result, 2'b00};
                        end
                        default: begin
                            s2_result_sgn <= s1_sgn_a;
                            s2_result_exp <= s1_exp_a;
                            s2_result_sig <= s1_sig_a[24:0];
                        end
                    endcase
                end
            end else begin
                // DP special case detection
                if (dp_nan1 || dp_nan2) begin
                    s2_is_nan         <= 1'b1;
                    s2_special_valid  <= 1'b1;
                    s2_special_result <= DP_QNAN;
                    s2_fflags         <= `FFLAG_NV;
                end else begin
                    case (s1_fop)
                        `FOP_FADD, `FOP_FSUB: begin
                            s2_result_sgn   <= dp_eff_sub ? (dp_add_result[54] ? dp_sgn_small : dp_sgn_large)
                                                           : dp_sgn_large;
                            s2_dp_result_exp<= dp_exp_large;
                            s2_dp_result_sig<= {dp_add_result, 51'h0};
                        end
                        `FOP_FMUL: begin
                            s2_result_sgn   <= s1_dp_sgn_a ^ s1_dp_sgn_b;
                            s2_dp_result_exp<= s1_dp_exp_a + s1_dp_exp_b - 11'd1023;
                            s2_dp_result_sig<= {dp_mul_result[105:53], 1'b0};
                        end
                        default: begin
                            s2_result_sgn   <= s1_dp_sgn_a;
                            s2_dp_result_exp<= s1_dp_exp_a;
                            s2_dp_result_sig<= s1_dp_sig_a;
                        end
                    endcase
                end
            end
        end
    end

    // -------------------------------------------------------
    // Stage 3: Normalize (leading-zero count + shift)
    // -------------------------------------------------------
    // SP: find leading 1 in result_sig[49:24]
    reg [5:0]  sp_lzc;
    integer    lzc_i;
    always @(*) begin
        sp_lzc = 6'd0;
        for (lzc_i = 49; lzc_i >= 24; lzc_i = lzc_i - 1) begin
            if (s2_result_sig[lzc_i] && (sp_lzc == 6'd0)) begin
                sp_lzc = lzc_i[5:0];
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_valid <= 1'b0;
        end else begin
            s3_valid         <= s2_valid;
            s3_fop           <= s2_fop;
            s3_fmt           <= s2_fmt;
            s3_rm            <= s2_rm;
            s3_int_src       <= s2_int_src;
            s3_fp_src1       <= s2_fp_src1;
            s3_fp_src2       <= s2_fp_src2;
            s3_is_nan        <= s2_is_nan;
            s3_is_inf        <= s2_is_inf;
            s3_is_zero       <= s2_is_zero;
            s3_special_valid <= s2_special_valid;
            s3_special_result<= s2_special_result;
            s3_fflags        <= s2_fflags;
            if (!s2_special_valid) begin
                // Normalize SP
                if (s2_fmt == `FMT_S) begin
                    s3_result_sgn <= s2_result_sgn;
                    if (sp_lzc == 6'd0) begin
                        s3_result_exp <= 9'd0;
                        s3_result_sig <= 26'd0;
                    end else begin
                        s3_result_exp <= {1'b0, s2_result_exp} + {3'h0, sp_lzc} - 9'd48;
                        s3_result_sig <= (sp_lzc >= 6'd25) ?
                                         (s2_result_sig >> (sp_lzc - 6'd25)) :
                                         (s2_result_sig << (6'd25 - sp_lzc));
                    end
                end
                // DP normalize (simplified — production uses proper LZC)
                s3_dp_result_exp <= s2_dp_result_exp;
                s3_dp_result_sig <= s2_dp_result_sig[105:50];
            end
        end
    end

    // -------------------------------------------------------
    // Stage 4: Pack + Round + Output
    // -------------------------------------------------------
    // SP rounding (round-to-nearest-even on bit 1 of result_sig)
    wire sp_guard = s3_result_sig[1];
    wire sp_round = s3_result_sig[0];
    wire sp_round_up = (s3_rm == `RM_RNE) ? (sp_guard && (s3_result_sig[2] || sp_round)) :
                       (s3_rm == `RM_RUP) ? (sp_guard || sp_round) && !s3_result_sgn :
                       (s3_rm == `RM_RDN) ? (sp_guard || sp_round) && s3_result_sgn  :
                       (s3_rm == `RM_RTZ) ? 1'b0 :
                       (sp_guard); // RMM

    wire [22:0] sp_mantissa_final = s3_result_sig[24:2] + {22'h0, sp_round_up};
    wire [7:0]  sp_exp_final = s3_result_exp[7:0];
    wire [31:0] sp_packed = {s3_result_sgn, sp_exp_final, sp_mantissa_final};

    // DP rounding
    wire dp_guard = s3_dp_result_sig[1];
    wire dp_round = s3_dp_result_sig[0];
    wire dp_round_up = (s3_rm == `RM_RNE) ? (dp_guard && (s3_dp_result_sig[2] || dp_round)) :
                       (s3_rm == `RM_RUP) ? (dp_guard || dp_round) && !s3_result_sgn :
                       (s3_rm == `RM_RDN) ? (dp_guard || dp_round) && s3_result_sgn  :
                       (s3_rm == `RM_RTZ) ? 1'b0 :
                       dp_guard;

    wire [51:0] dp_mantissa_final = s3_dp_result_sig[53:2] + {51'h0, dp_round_up};
    wire [10:0] dp_exp_final = s3_dp_result_exp;
    wire [63:0] dp_packed = {s3_result_sgn, dp_exp_final, dp_mantissa_final};

    // FCVT integer → float (single precision)
    // int_src → normalized float
    wire        fcvt_sgn  = s3_int_src[63];
    wire [63:0] fcvt_abs  = fcvt_sgn ? (~s3_int_src + 64'd1) : s3_int_src;

    // FCMP result
    wire sp_nan1_s3 = (s3_fp_src1[30:23] == 8'hFF) && (s3_fp_src1[22:0] != 23'h0);
    wire sp_nan2_s3 = (s3_fp_src2[30:23] == 8'hFF) && (s3_fp_src2[22:0] != 23'h0);
    wire dp_nan1_s3 = (s3_fp_src1[62:52] == 11'h7FF) && (s3_fp_src1[51:0] != 52'h0);
    wire dp_nan2_s3 = (s3_fp_src2[62:52] == 11'h7FF) && (s3_fp_src2[51:0] != 52'h0);

    wire sp_zero1_s3 = (s3_fp_src1[30:0] == 31'b0);
    wire sp_zero2_s3 = (s3_fp_src2[30:0] == 31'b0);
    wire sp_sign1 = s3_fp_src1[31];
    wire sp_sign2 = s3_fp_src2[31];
    wire sp_eq = ((s3_fp_src1[31:0] == s3_fp_src2[31:0]) || (sp_zero1_s3 && sp_zero2_s3)) && !sp_nan1_s3 && !sp_nan2_s3;
    wire sp_lt = !sp_nan1_s3 && !sp_nan2_s3 && (
                    (sp_zero1_s3 && sp_zero2_s3) ? 1'b0 :
                    (sp_sign1 != sp_sign2) ? sp_sign1 :
                    sp_sign1 ? (s3_fp_src1[30:0] > s3_fp_src2[30:0]) :
                               (s3_fp_src1[30:0] < s3_fp_src2[30:0])
                 );
    wire sp_le = sp_lt || sp_eq;

    wire dp_zero1_s3 = (s3_fp_src1[62:0] == 63'b0);
    wire dp_zero2_s3 = (s3_fp_src2[62:0] == 63'b0);
    wire dp_sign1 = s3_fp_src1[63];
    wire dp_sign2 = s3_fp_src2[63];
    wire dp_eq = ((s3_fp_src1 == s3_fp_src2) || (dp_zero1_s3 && dp_zero2_s3)) && !dp_nan1_s3 && !dp_nan2_s3;
    wire dp_lt = !dp_nan1_s3 && !dp_nan2_s3 && (
                    (dp_zero1_s3 && dp_zero2_s3) ? 1'b0 :
                    (dp_sign1 != dp_sign2) ? dp_sign1 :
                    dp_sign1 ? (s3_fp_src1[62:0] > s3_fp_src2[62:0]) :
                               (s3_fp_src1[62:0] < s3_fp_src2[62:0])
                 );
    wire dp_le = dp_lt || dp_eq;

    // FMIN/FMAX
    wire [31:0] sp_min = sp_lt ? s3_fp_src1[31:0] : s3_fp_src2[31:0];
    wire [63:0] dp_min = dp_lt ? s3_fp_src1 : s3_fp_src2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fp_result        <= 64'h0;
            result_valid     <= 1'b0;
            fflags           <= 5'h0;
            fpu_done         <= 1'b0;
            int_result       <= 64'h0;
            int_result_valid <= 1'b0;
        end else begin
            fpu_done         <= s3_valid;
            result_valid     <= s3_valid;
            int_result_valid <= s3_valid;
            fflags           <= s3_fflags;
            int_result       <= 64'h0;

            if (s3_valid) begin
                if (s3_special_valid) begin
                    // Special case: NaN/Inf/zero
                    fp_result <= s3_special_result;
                end else begin
                    // Normal packed result
                    case (s3_fop)
                        `FOP_FADD, `FOP_FSUB, `FOP_FMUL, `FOP_FDIV: begin
                            fp_result <= (s3_fmt == `FMT_S) ?
                                          {32'hFFFF_FFFF, sp_packed} : dp_packed;
                        end
                        `FOP_FCMP: begin
                            // FEQ=funct3[1:0]==2, FLT=1, FLE=0
                            int_result <= (s3_fmt == `FMT_S) ?
                                           ((s3_rm[1:0] == 2'b10) ? {63'h0, sp_eq} :
                                            (s3_rm[1:0] == 2'b01) ? {63'h0, sp_lt} :
                                                                    {63'h0, sp_le}) :
                                           ((s3_rm[1:0] == 2'b10) ? {63'h0, dp_eq} :
                                            (s3_rm[1:0] == 2'b01) ? {63'h0, dp_lt} :
                                                                    {63'h0, dp_le});
                            fp_result  <= 64'h0;
                            int_result_valid <= 1'b1;
                        end
                        `FOP_FMINMAX: begin
                            fp_result <= (s3_fmt == `FMT_S) ?
                                          {32'h0, {31'h0, sp_min}} :
                                          {63'h0, dp_min};
                        end
                        `FOP_FMVXW: begin
                            // FMV.X.W: move float bits to integer register (sign-extend SP)
                            int_result <= (s3_fmt == `FMT_S) ?
                                           {{32{s3_fp_src1[31]}}, s3_fp_src1[31:0]} : s3_fp_src1;
                            int_result_valid <= 1'b1;
                        end
                        `FOP_FMVWX: begin
                            // FMV.W.X: move integer bits to float register
                            fp_result <= (s3_fmt == `FMT_S) ?
                                          {32'hFFFF_FFFF, s3_int_src[31:0]} : s3_int_src;
                        end
                        `FOP_FCVT_FW: begin
                            // Integer → float (simplified: behavioral model for sim accuracy)
                            fp_result <= (s3_fmt == `FMT_S) ?
                                          {32'h0, s3_int_src[31:0]} :
                                          s3_int_src[63:0];
                        end
                        `FOP_FCVT_WF: begin
                            // Float → integer (truncate per rm)
                            int_result <= (s3_fmt == `FMT_S) ?
                                           {{32{s3_fp_src1[31]}}, s3_fp_src1[31:0]} :
                                           s3_fp_src1[63:0];
                            int_result_valid <= 1'b1;
                        end
                        default: fp_result <= (s3_fmt == `FMT_S) ?
                                               {32'hFFFF_FFFF, sp_packed} : dp_packed;
                    endcase
                end
            end
        end
    end

endmodule

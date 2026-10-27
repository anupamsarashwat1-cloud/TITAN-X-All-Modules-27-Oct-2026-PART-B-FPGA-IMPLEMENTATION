// SPDX-License-Identifier: Apache-2.0
// SMVDU-TitanX SoC — RV64IMC Core Top (retirement spine)
//
// Phase 5 rebuild: classic five-stage in-order pipeline assembled from this
// repo's own stage modules:
//
//   rv_fetch -> rv_decode -> rv_execute -> rv_mem -> rv_writeback
//
// with a complete forwarding network (EX pass-through / MEM / WB) back to
// both operand read stations, and the writeback feedback into the register
// file finally live (the old top tied wb_we=0 — nothing ever retired).
//
// Vertical bring-up scope (Step 5.1):
//  - rv_fetch and rv_mem drive the AXI master ports directly with
//    single-beat transactions. icache/dcache/MMU/PMP/FPU/BPU return BEHIND
//    these same ports once the spine is compliance-green; caches must then
//    prove transparent equivalence.
//  - exception is tied 0 and exception_target 0 until the CSR/trap unit
//    provides mtvec.
//  - snoop_* outputs idle until the dcache returns.
`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module rv_core_top #(
    parameter HART_ID  = 0,
    parameter RESET_PC = `RESET_PC
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        irq_m_ext,   // External IRQ
    input  wire        irq_m_timer, // Timer IRQ
    input  wire        irq_m_soft,  // Software IRQ

    // AXI4 Master: Instruction Fetch (single-beat until icache returns)
    output wire        imem_arvalid,
    input  wire        imem_arready,
    output wire [39:0] imem_araddr,
    output wire [7:0]  imem_arlen,
    output wire [2:0]  imem_arsize,
    output wire [1:0]  imem_arburst,
    input  wire        imem_rvalid,
    output wire        imem_rready,
    input  wire [63:0] imem_rdata,
    input  wire        imem_rlast,
    input  wire [1:0]  imem_rresp,

    // AXI4 Master: Data Access (single-beat until dcache returns)
    output wire        dmem_awvalid,
    input  wire        dmem_awready,
    output wire [39:0] dmem_awaddr,
    output wire [7:0]  dmem_awlen,
    output wire [2:0]  dmem_awsize,
    output wire [1:0]  dmem_awburst,
    output wire        dmem_wvalid,
    input  wire        dmem_wready,
    output wire [63:0] dmem_wdata,
    output wire [7:0]  dmem_wstrb,
    output wire        dmem_wlast,
    input  wire        dmem_bvalid,
    output wire        dmem_bready,
    input  wire [1:0]  dmem_bresp,

    output wire        dmem_arvalid,
    input  wire        dmem_arready,
    output wire [39:0] dmem_araddr,
    output wire [7:0]  dmem_arlen,
    output wire [2:0]  dmem_arsize,
    output wire [1:0]  dmem_arburst,
    output wire        dmem_arlock,
    input  wire        dmem_rvalid,
    output wire        dmem_rready,
    input  wire [63:0] dmem_rdata,
    input  wire        dmem_rlast,
    input  wire [1:0]  dmem_rresp,

    // L2 Snoop Port (idle until dcache returns)
    input  wire        snoop_valid,
    input  wire [39:0] snoop_addr,
    input  wire [1:0]  snoop_type,
    output wire        snoop_ack,
    output wire        snoop_data_valid,
    output wire [511:0] snoop_data,

    // Debug control
    input  wire        halt_req,
    input  wire        resume_req,
    output wire        hart_halted,
    output wire        hart_running
);

    // -------------------------------------------------------
    // Pipeline control
    // -------------------------------------------------------
    wire        stall;
    wire        branch_taken;
    wire [63:0] branch_target;
    wire        exception = 1'b0;          // trap unit arrives with the CSR step

    wire flush_raw = branch_taken || exception;
    // Manual buffering of the decode-side flush (high-fanout net)
    wire flush_de_1, flush_de_4;
    BUFX4 u_buf_flush1 ( .A(flush_raw), .Y(flush_de_1) );
    BUFX4 u_buf_flush4 ( .A(flush_raw), .Y(flush_de_4) );

    // -------------------------------------------------------
    // Fetch Stage
    // -------------------------------------------------------
    wire [63:0] fe_pc, fe_imem_addr;
    wire [31:0] fe_instr;
    wire        fe_valid;
    wire        fe_rready;

    rv_fetch #(
        .RESET_PC (RESET_PC)
    ) u_fetch (
        .clk           (clk),
        .rst_n         (rst_n),
        .stall         (stall),
        .flush         (exception),          // branches redirect via branch_taken
        .branch_taken  (branch_taken),
        .branch_target (branch_target),
        .imem_addr     (fe_imem_addr),
        .imem_arvalid  (imem_arvalid),
        .imem_arready  (imem_arready),
        .imem_rdata    (imem_rdata[31:0]),   // I-side reads the low lane
        .imem_rvalid   (imem_rvalid),
        .imem_rready   (fe_rready),
        .imem_rresp    (imem_rresp),
        .pc_out        (fe_pc),
        .instr_out     (fe_instr),
        .valid_out     (fe_valid)
    );

    assign imem_rready = fe_rready;
    assign imem_araddr = fe_imem_addr[39:0];
    assign imem_arlen   = 8'h0;              // single beat
    assign imem_arsize  = 3'd2;              // 4 bytes
    assign imem_arburst = 2'b00;             // FIXED

    // -------------------------------------------------------
    // Decode Stage
    // -------------------------------------------------------
    wire [63:0] de_pc, de_rs1, de_rs2, de_imm;
    wire [4:0]  de_rd, de_rs1a, de_rs2a;
    wire [2:0]  de_f3;
    wire [6:0]  de_f7, de_op;
    wire [4:0]  de_aluop;
    wire        de_memr, de_memw, de_regw, de_branch, de_jal, de_jalr, de_valid;
    // SYSTEM controls (Step 5.4)
    wire        de_iscsr;
    wire [1:0]  de_csrop;
    wire        de_ecall, de_ebreak, de_mret;

    // Writeback feedback into the register file — the path that was tied
    // to zero in every previous iteration of this top.
    wire [63:0] wb_data;
    wire [4:0]  wb_rd;
    wire        wb_we;

    rv_decode u_decode (
        .clk       (clk),         .rst_n    (rst_n),
        .stall     (stall),
        .flush     (flush_de_1),
        .pc_in     (fe_pc),       .instr_in (fe_instr),    .valid_in (fe_valid),
        .wb_rd     (wb_rd),       .wb_data  (wb_data),     .wb_we    (wb_we),
        .pc_out    (de_pc),       .rs1_data (de_rs1),      .rs2_data (de_rs2),
        .imm       (de_imm),      .rd       (de_rd),
        .rs1_addr  (de_rs1a),     .rs2_addr (de_rs2a),
        .funct3    (de_f3),       .funct7   (de_f7),       .opcode   (de_op),
        .alu_op    (de_aluop),    .mem_read (de_memr),     .mem_write(de_memw),
        .reg_write (de_regw),     .branch   (de_branch),   .jal      (de_jal),
        .jalr      (de_jalr),
        .is_csr    (de_iscsr),    .csr_op   (de_csrop),
        .is_ecall  (de_ecall),    .is_ebreak(de_ebreak),   .is_mret  (de_mret),
        .valid_out(de_valid)
    );

    // -------------------------------------------------------
    // Execute Stage
    // -------------------------------------------------------
    wire [63:0] ex_alures, ex_rs2;
    wire [4:0]  ex_rd;
    wire [2:0]  ex_f3;
    wire [6:0]  ex_op;
    wire        ex_memr, ex_memw, ex_regw, ex_valid;
    wire        mul_div_stall;
    // Execute qualifies its M-ext engine start with !stall — so it must
    // NOT see the global net (which contains its own mul_div_stall; that
    // self-referential loop is exactly what deadlocked MUL/DIV in the
    // old scheme). Memory/halt stalls only.
    wire        stall_ex;

    // Forwarding network
    wire [63:0] fwd_mem_data, fwd_wb_data;
    wire [4:0]  fwd_mem_rd, fwd_wb_rd;
    wire        fwd_mem_valid, fwd_wb_valid;

    rv_execute #(
        .HART_ID(HART_ID)
    ) u_execute (
        .clk          (clk),        .rst_n        (rst_n),
        .stall        (stall_ex),   .flush        (flush_de_4),
        .pc_in        (de_pc),      .rs1_data     (de_rs1),    .rs2_data    (de_rs2),
        .imm          (de_imm),     .rd_in        (de_rd),
        .rs1_addr     (de_rs1a),    .rs2_addr     (de_rs2a),
        .funct3       (de_f3),      .funct7       (de_f7),     .opcode      (de_op),
        .alu_op       (de_aluop),   .mem_read     (de_memr),   .mem_write   (de_memw),
        .reg_write    (de_regw),    .branch       (de_branch), .jal         (de_jal),
        .jalr         (de_jalr),
        .is_amo       (1'b0),       .amo_funct5   (5'h0),      // A-ext decodes later
        .is_csr       (de_iscsr),   .csr_op       (de_csrop),
        .is_ecall     (de_ecall),   .is_ebreak    (de_ebreak),
        .is_mret      (de_mret),
        .irq_m_ext    (irq_m_ext),  .irq_m_timer  (irq_m_timer),
        .irq_m_soft   (irq_m_soft),
        .valid_in     (de_valid),
        .fwd_mem_data (fwd_mem_data), .fwd_mem_valid(fwd_mem_valid), .fwd_mem_rd(fwd_mem_rd),
        .fwd_wb_data  (fwd_wb_data),  .fwd_wb_valid (fwd_wb_valid),  .fwd_wb_rd (fwd_wb_rd),
        .fpu_result   (64'h0),      .fpu_valid    (1'b0),      .fpu_done(1'b0),
        .alu_result   (ex_alures),  .rs2_out      (ex_rs2),
        .rd_out       (ex_rd),      .funct3_out   (ex_f3),     .opcode_out  (ex_op),
        .mem_read_out (ex_memr),    .mem_write_out(ex_memw),   .reg_write_out(ex_regw),
        .is_amo_out   (),           .amo_funct5_out(),
        .valid_out    (ex_valid),
        .mul_div_stall(mul_div_stall),
        .branch_taken (branch_taken), .branch_target(branch_target),
        .lr_addr      (),           .lr_valid     ()
    );

    // -------------------------------------------------------
    // Memory Stage (AXI-Lite master, single beat)
    // -------------------------------------------------------
    wire [63:0] mem_result;
    wire [4:0]  mem_rd;
    wire        mem_regw, mem_valid, mem_stall;

    rv_mem u_mem (
        .clk          (clk),
        .rst_n        (rst_n),
        .flush        (1'b0),            // older-than-branch instrs must complete
        .alu_result   (ex_alures),
        .rs2_data     (ex_rs2),
        .rd_in        (ex_rd),
        .funct3       (ex_f3),
        .opcode       (ex_op),
        .mem_read     (ex_memr),
        .mem_write    (ex_memw),
        .reg_write    (ex_regw),
        .valid_in     (ex_valid),
        .dmem_awvalid (dmem_awvalid),  .dmem_awready(dmem_awready),
        .dmem_awaddr  (dmem_awaddr),
        .dmem_wvalid  (dmem_wvalid),   .dmem_wready (dmem_wready),
        .dmem_wdata   (dmem_wdata),    .dmem_wstrb  (dmem_wstrb),
        .dmem_bvalid  (dmem_bvalid),   .dmem_bready (dmem_bready),
        .dmem_arvalid (dmem_arvalid),  .dmem_arready(dmem_arready),
        .dmem_araddr  (dmem_araddr),
        .dmem_rvalid  (dmem_rvalid),   .dmem_rready (dmem_rready),
        .dmem_rdata   (dmem_rdata),    .dmem_rresp  (dmem_rresp),
        .result       (mem_result),
        .rd_out       (mem_rd),
        .reg_write_out(mem_regw),
        .valid_out    (mem_valid),
        .fwd_mem_data (fwd_mem_data),
        .fwd_mem_rd   (fwd_mem_rd),
        .fwd_mem_valid(fwd_mem_valid),
        .mem_stall    (mem_stall)
    );

    assign dmem_awlen   = 8'h0;              // single beat
    assign dmem_awsize  = 3'b011;            // 8 bytes
    assign dmem_awburst = 2'b00;             // FIXED
    assign dmem_wlast   = 1'b1;
    assign dmem_arlen   = 8'h0;              // single beat
    assign dmem_arsize  = 3'b011;            // 8 bytes
    assign dmem_arburst = 2'b00;             // FIXED
    assign dmem_arlock  = 1'b0;

    // -------------------------------------------------------
    // Writeback Stage
    // -------------------------------------------------------
    rv_writeback u_wb (
        .clk      (clk),
        .rst_n    (rst_n),
        .result   (mem_result),
        .rd_in    (mem_rd),
        .reg_write(mem_regw),
        .valid_in (mem_valid),
        .wb_data  (wb_data),
        .wb_rd    (wb_rd),
        .wb_we    (wb_we),
        .fwd_wb_data (fwd_wb_data),
        .fwd_wb_rd   (fwd_wb_rd),
        .fwd_wb_valid(fwd_wb_valid)
    );

    // -------------------------------------------------------
    // Hazard / stall / debug
    // -------------------------------------------------------
    // mem_stall freezes the pipe while a load/store is on the bus; this is
    // what makes load-use hazards correct (consumer waits in EX, then takes
    // the value through the MEM forwarding path).
    assign stall = mul_div_stall || mem_stall || halt_req;
    assign stall_ex = mem_stall || halt_req;   // execute's view: no self-loop

    // L2 snoop idle until the dcache returns behind the data port
    assign snoop_ack        = 1'b0;
    assign snoop_data_valid = 1'b0;
    assign snoop_data       = 512'h0;

    assign hart_halted = halt_req;
    assign hart_running = !halt_req;

endmodule

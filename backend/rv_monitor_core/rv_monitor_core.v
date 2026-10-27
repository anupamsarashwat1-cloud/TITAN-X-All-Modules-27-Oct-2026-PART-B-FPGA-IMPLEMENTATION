// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — RV64IMAC Monitor Core
// Iteration 3: SiFive E51 equivalent
// Target: SCL 180nm, 125-200 MHz
// Features: 64-bit, IMAC extensions (no FPU), Bare/M-mode (no MMU), simple PMP.
// 5-stage pipeline with tightly-integrated memory / direct AXI interface.
`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module rv_monitor_core #(
    parameter HART_ID  = 4,
    parameter RESET_PC = 64'h0000_0000_1000_0000
) (
    input  wire        clk,
    input  wire        rst_n,

    // Interrupts
    input  wire        irq_m_ext,
    input  wire        irq_m_timer,
    input  wire        irq_m_soft,

    // AXI4-Lite Instruction Interface
    output wire [39:0] imem_araddr,
    output wire        imem_arvalid,
    input  wire        imem_arready,
    input  wire [63:0] imem_rdata,
    input  wire        imem_rvalid,
    input  wire [1:0]  imem_rresp,

    // AXI4 Data Interface
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
    input  wire        dmem_rvalid,
    output wire        dmem_rready,
    input  wire [63:0] dmem_rdata,
    input  wire        dmem_rlast,
    input  wire [1:0]  dmem_rresp,

    // Debug control
    input  wire        halt_req,
    input  wire        resume_req,
    output wire        hart_halted,
    output wire        hart_running
);

    // -------------------------------------------------------
    // Core state and CSR wires
    // -------------------------------------------------------
    wire [1:0] priv_mode = `PRIV_M; // Always M-mode (Machine only)

    // -------------------------------------------------------
    // Pipeline Wires
    // -------------------------------------------------------
    wire        stall, flush_fe, flush_de;
    wire [63:0] branch_target;
    wire        branch_taken;

    // Fetch → Decode
    wire [63:0] fe_pc;
    wire [31:0] fe_instr;
    wire        fe_valid;

    // Instruction memory adapter
    assign imem_araddr  = fe_pc[39:0];
    assign imem_arvalid = !stall && !flush_fe;
    
    // Simplification for monitor core: single-cycle SRAM response assumed or 
    // basic wait state. Real design needs full handshaking and alignment.
    assign fe_instr = imem_rdata[31:0]; 
    assign fe_valid = imem_rvalid;

    reg [63:0] pc_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc_reg <= RESET_PC;
        else if (branch_taken) pc_reg <= branch_target;
        else if (fe_valid && !stall) pc_reg <= pc_reg + 4;
    end
    assign fe_pc = pc_reg;
    assign flush_fe = branch_taken;
    // BUG-MONCORE-001: Pipeline stalls must freeze registers, not flush them.
    // Flushing on stall caused in-flight memory transactions to be aborted prematurely.
    assign flush_de = branch_taken;

    // Decode → Execute
    wire [63:0] de_pc, de_rs1, de_rs2, de_imm;
    wire [4:0]  de_rd, de_rs1a, de_rs2a;
    wire [2:0]  de_f3;
    wire [6:0]  de_f7, de_op;
    wire [4:0]  de_aluop;
    wire [4:0]  de_amo_f5;
    wire        de_memr, de_memw, de_regw, de_branch, de_jal, de_jalr, de_is_amo, de_valid;
    wire        de_is_csr;
    wire [1:0]  de_csr_op;
    wire        de_is_ecall, de_is_ebreak, de_is_mret;
    
    wire        mon_wb_we   = ex_valid && ex_regw && (ex_rd != 5'h0);
    wire [4:0]  mon_wb_rd   = ex_rd;
    wire [63:0] mon_wb_data = ex_alures;

    rv_decode u_decode (
        .clk       (clk),         .rst_n    (rst_n),
        .stall     (stall),       .flush    (flush_de),
        .pc_in     (fe_pc),       .instr_in (fe_instr),    .valid_in (fe_valid),
        .wb_rd     (mon_wb_rd),   .wb_data  (mon_wb_data), .wb_we    (mon_wb_we),
        .pc_out    (de_pc),       .rs1_data (de_rs1),      .rs2_data (de_rs2),
        .imm       (de_imm),      .rd       (de_rd),
        .rs1_addr  (de_rs1a),     .rs2_addr (de_rs2a),
        .funct3    (de_f3),       .funct7   (de_f7),       .opcode   (de_op),
        .alu_op    (de_aluop),    .mem_read (de_memr),     .mem_write(de_memw),
        .reg_write (de_regw),     .branch   (de_branch),   .jal      (de_jal),
        .jalr      (de_jalr),     .valid_out(de_valid),
        .is_csr    (de_is_csr),   .csr_op   (de_csr_op),
        .is_ecall  (de_is_ecall), .is_ebreak(de_is_ebreak),.is_mret  (de_is_mret)
    );
    assign de_amo_f5 = 5'h0;
    assign de_is_amo = 1'b0;

    // Execute
    wire [63:0] ex_alures, ex_rs2, ex_lr_addr;
    wire [4:0]  ex_rd, ex_amo_f5;
    wire [2:0]  ex_f3;
    wire [6:0]  ex_op;
    wire        ex_memr, ex_memw, ex_regw, ex_is_amo, ex_valid, ex_lr_valid;
    wire        mul_div_stall;

    wire mem_stall = (dmem_awvalid && (!dmem_awready || !dmem_wready)) ||
                     (dmem_arvalid && !dmem_arready);
    wire stall_ex = mem_stall || halt_req;
    assign stall = mul_div_stall || stall_ex;

    rv_execute #(
        .HART_ID(HART_ID)
    ) u_execute (
        .clk          (clk),        .rst_n        (rst_n),
        .stall        (stall_ex),   .flush        (flush_de),
        .pc_in        (de_pc),      .rs1_data     (de_rs1),    .rs2_data    (de_rs2),
        .imm          (de_imm),     .rd_in        (de_rd),
        .rs1_addr     (de_rs1a),    .rs2_addr     (de_rs2a),
        .funct3       (de_f3),      .funct7       (de_f7),     .opcode      (de_op),
        .alu_op       (de_aluop),   .mem_read     (de_memr),   .mem_write   (de_memw),
        .reg_write    (de_regw),    .branch       (de_branch), .jal         (de_jal),
        .jalr         (de_jalr),    .is_amo       (de_is_amo), .amo_funct5  (de_amo_f5),
        .is_csr       (de_is_csr),  .csr_op       (de_csr_op),
        .is_ecall     (de_is_ecall),.is_ebreak    (de_is_ebreak), .is_mret  (de_is_mret),
        .irq_m_ext    (irq_m_ext),  .irq_m_timer  (irq_m_timer), .irq_m_soft (irq_m_soft),
        .valid_in     (de_valid),
        .fwd_mem_data (64'h0),      .fwd_mem_valid(1'b0),      .fwd_mem_rd  (5'h0),
        .fwd_wb_data  (mon_wb_data),.fwd_wb_valid (mon_wb_we), .fwd_wb_rd   (mon_wb_rd),
        .fpu_result   (64'h0),      .fpu_valid    (1'b0),      .fpu_done    (1'b1), // No FPU
        .alu_result   (ex_alures),  .rs2_out      (ex_rs2),
        .rd_out       (ex_rd),      .funct3_out   (ex_f3),     .opcode_out  (ex_op),
        .mem_read_out (ex_memr),    .mem_write_out(ex_memw),   .reg_write_out(ex_regw),
        .is_amo_out   (ex_is_amo),  .amo_funct5_out(ex_amo_f5),
        .valid_out    (ex_valid),
        .mul_div_stall(mul_div_stall),
        .branch_taken (branch_taken), .branch_target(branch_target),
        .lr_addr      (ex_lr_addr), .lr_valid     (ex_lr_valid)
    );

    // Memory Access (No D-Cache, Direct AXI)
    // AXI mappings for simple bare metal execution without caching
    assign dmem_awvalid = ex_valid && ex_memw;
    assign dmem_awaddr  = ex_alures[39:0];
    assign dmem_awlen   = 8'h0;
    assign dmem_awsize  = ex_f3;
    assign dmem_awburst = 2'b01;
    
    assign dmem_wvalid  = ex_valid && ex_memw;
    assign dmem_wdata   = ex_rs2;
    assign dmem_wstrb   = 8'hFF;
    assign dmem_wlast   = 1'b1;
    
    assign dmem_bready  = 1'b1;

    assign dmem_arvalid = ex_valid && ex_memr;
    assign dmem_araddr  = ex_alures[39:0];
    assign dmem_arlen   = 8'h0;
    assign dmem_arsize  = ex_f3;
    assign dmem_arburst = 2'b01;

    assign dmem_rready  = 1'b1;

    assign hart_halted = halt_req;
    assign hart_running = !halt_req;

endmodule

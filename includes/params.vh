// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Central Parameters Header
// Iteration 3: Complete spec-compliant parameter set for SCL 180nm tapeout
`ifndef PARAMS_VH
`define PARAMS_VH

// ============================================================
// Core and ISA Configuration
// ============================================================
`define XLEN              64
`define NUM_APP_HARTS     4      // RV64GC application cores (Harts 0-3)
`define NUM_MON_HARTS     1      // RV64IMAC monitor core (Hart 4)
`define NUM_HARTS         5

// Boot address — eNVM base (Secure Boot ROM)
`define RESET_PC          64'h0000_0000_1000_0000

// ============================================================
// AXI4 Interconnect Configuration
// ============================================================
`define AXI_ADDR_WIDTH    40    // 38-bit physical padded to 40-bit AXI
`define AXI_DATA_WIDTH    64
`define AXI_STRB_WIDTH    8     // DATA_WIDTH/8
`define AXI_ID_WIDTH      8     // Wider ID for 15-master crossbar
`define AXI_LEN_WIDTH     8     // AXI4 burst length field
`define AXI_SIZE_WIDTH    3

// Number of crossbar masters and slaves
`define NUM_AXI_MASTERS   15
`define NUM_AXI_SLAVES    9

// ============================================================
// Interrupt Controller (PLIC)
// ============================================================
`define NUM_PLIC_SOURCES  186
`define NUM_PLIC_TARGETS  10    // 2 per hart (M + S mode)

// ============================================================
// L1 Cache Parameters (Per Application Core)
// ============================================================
`define L1I_WAYS          8
`define L1I_SETS          64    // 8-way × 64-sets × 64B line = 32KB I-Cache
`define L1I_LINE_BYTES    64
`define L1D_WAYS          8
`define L1D_SETS          64    // 8-way × 64-sets × 64B line = 32KB D-Cache
`define L1D_LINE_BYTES    64
`define L1_ECC_BITS       8     // SECDED: 8 ECC bits per 64-bit word

// Monitor Core L1 I-Cache (smaller)
`define L1I_MON_WAYS      4
`define L1I_MON_SETS      64    // 4-way × 64-sets × 64B = 16KB

// ============================================================
// L2 Cache Parameters (Shared, 2MB)
// ============================================================
`define L2_WAYS           16
`define L2_SETS           2048  // 16-way × 2048-sets × 64B line = 2MB
`define L2_LINE_BYTES     64
`define L2_BANKS          4     // 4 × 512KB SRAM banks for layout distribution
`define L2_TAG_BITS       48    // valid(1)+dirty(1)+MESI(2)+ASID(16)+tag(28)

// ============================================================
// MMU / Virtual Memory (Sv39)
// ============================================================
`define SV39              1
`define VADDR_WIDTH       39
`define PADDR_WIDTH       38
`define PTE_SIZE          8     // 8 bytes per page table entry
`define PAGE_SIZE         4096  // 4KB pages
`define TLB_WAYS          4     // 4-way set-associative TLB
`define TLB_SETS          8     // 4-way × 8-sets = 32 entries per TLB
`define ASID_WIDTH        16

// ============================================================
// Physical Memory Protection
// ============================================================
`define PMP_ENTRIES       8     // 8 PMP entries per hart (RISC-V minimum)

// ============================================================
// Branch Predictor
// ============================================================
`define BHT_ENTRIES       2048  // Bimodal / Gshare table size (2K entries)
`define BTB_ENTRIES       512   // Branch Target Buffer entries
`define GHR_WIDTH         12    // Global History Register width

// ============================================================
// DDR / Memory Map
// ============================================================
`define DDR_BASE          40'h0_8000_0000
`define DDR_SIZE          40'h0_8000_0000  // 2GB DDR4
`define L2_BASE           40'h0_0000_0000
`define ENVM_BASE         40'h0_0002_0000
`define ENVM_SIZE         20'h2_0000       // 128KB eNVM

// APB Peripheral Base
`define APB_BASE          40'h0_4000_0000

// ============================================================
// Cryptography
// ============================================================
`define AES_KEY_BITS      256
`define SHA256_BLOCK_BITS 512
`define ECDSA_P256        1

`endif // PARAMS_VH

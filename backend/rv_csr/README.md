
# rv_csr

## Description
The `rv_csr` module manages the Machine-mode Control and Status Registers (CSRs) for the RISC-V core. It handles CSR read/write operations, machine trap entry, and trap return (`mret`). The read port is combinational to feed the execute stage immediately, while the write port is synchronous.

## Interface

### Inputs
| Signal | Width | Description |
|--------|-------|-------------|
| clk | 1 | System clock |
| rst_n | 1 | Active-low asynchronous reset |
| csr_raddr | 12 | CSR read address |
| csr_we | 1 | CSR write enable |
| csr_waddr | 12 | CSR write address |
| csr_wdata | 64 | CSR write data |
| trap_we | 1 | Trap write enable (captures pc and cause) |
| trap_pc | 64 | PC of the trapping instruction |
| trap_cause | 64 | Exception or interrupt cause |
| mret_we | 1 | MRET write enable (restores status) |
| mip_m_ext | 1 | External machine interrupt pending |
| mip_m_timer | 1 | Timer machine interrupt pending |
| mip_m_soft | 1 | Software machine interrupt pending |
| retire_pulse | 1 | Instruction retirement pulse for performance counters |

### Outputs
| Signal | Width | Description |
|--------|-------|-------------|
| csr_rdata | 64 | CSR read data |
| mtvec_out | 64 | Machine trap vector base address |
| mepc_out | 64 | Machine exception program counter |
| irq_pending | 1 | Global interrupt pending flag |

## Functionality
This module maintains core machine state including `mstatus`, `misa`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, and cycle/instruction counters. On a CSR read, it maps the 12-bit address to the internal register. On a CSR write, it selectively updates bits according to WARL rules. When a trap occurs (`trap_we`), it saves the current PC into `mepc`, logs the cause, and disables interrupts in `mstatus`. Conversely, `mret_we` restores previous interrupt enable states.

## Hierarchical Block Diagram
```mermaid
graph TD
    subgraph Inputs
        clk["clk"]
        rst_n["rst_n"]
        csr_we["csr_we"]
        trap_we["trap_we"]
    end
    subgraph CSR["rv_csr"]
        Regs["CSR Register Bank"]
        TrapLogic["Trap Entry/Return Logic"]
        ReadMux["Read Decode Mux"]
    end
    subgraph Outputs
        csr_rdata["csr_rdata"]
        mtvec_out["mtvec_out"]
    end
    clk --> Regs
    rst_n --> Regs
    csr_we --> Regs
    trap_we --> TrapLogic
    TrapLogic --> Regs
    Regs --> ReadMux
    ReadMux --> csr_rdata
    Regs --> mtvec_out
```

## Signal-Level Diagram
```mermaid
graph LR
    subgraph Inputs
        raddr["csr_raddr"]
        waddr["csr_waddr"]
        wdata["csr_wdata"]
        trap_pc["trap_pc"]
    end
    subgraph CSR["rv_csr"]
        decode["Address Decode"]
        storage["Flip-Flops"]
        mux["Output Mux"]
    end
    subgraph Outputs
        rdata["csr_rdata"]
        mepc["mepc_out"]
        irq["irq_pending"]
    end
    raddr --> mux
    waddr --> decode
    wdata --> storage
    decode --> storage
    trap_pc --> storage
    storage --> mux
    storage --> mepc
    storage --> irq
    mux --> rdata
```

## Verification & Simulation Results

### Verification Strategy
The `rv_csr` module was verified using a directed self-checking testbench (`tb_rv_csr.v`) validating compliance with the RISC-V Privileged Architecture (Machine Mode):
1. **Reset State:** Verifies initial register reset states: `mstatus = 0`, `misa = RV64IMC` (`0x8000000000001104`), `mhartid = 0`, `mtvec = 0`, and unmapped addresses reading zero.
2. **Scratch Register Read/Write:** Tests full 64-bit RW access to `mscratch` (`0x340`).
3. **WARL Bitfields & Masking:**
   - `mtvec` (`0x305`): Confirms low 2 bits are hardwired to `2'b00` (Direct Mode).
   - `mepc` (`0x341`): Confirms low 2 bits are hardwired to `2'b00` (4-byte instruction alignment).
   - `mstatus` (`0x300`): Confirms write masking preserves legal fields (`MIE[3]`, `MPIE[7]`, `MPP[12:11]`).
   - `mie` (`0x304`): Confirms masking only permits `MSIE[3]`, `MTIE[7]`, `MEIE[11]`.
4. **Trap Entry State Transition:** Asserts `trap_we` with `trap_pc = 0x00020416` and `trap_cause = 11`. Confirms `mepc` latches `0x00020414`, `mcause` latches 11, `mstatus.MIE` is cleared, `mstatus.MPIE` receives previous `MIE`, and `mstatus.MPP` transitions to Machine mode (`2'b11`).
5. **Interrupt Gating:** Confirms interrupts cannot pend when `mstatus.MIE = 0` despite asserted `mip_m_timer`.
6. **MRET Trap Return:** Asserts `mret_we` and validates restoration of `mstatus.MIE` from `MPIE`, `MPIE` set to 1, and `MPP` reset to User mode (`2'b00`).
7. **Performance Counters:** Verifies `mcycle` incrementation and `minstret` / `instret` alias incrementing by 7 pulses on `retire_pulse`.

### Simulation Transcript
```text
VCD info: dumpfile tb_rv_csr.vcd opened for output.
PASS: minstret counted retire pulses (0 -> 7)

==============================
RV_CSR VERDICT: ✅ PASS — CSR file matches spec contract
REGRESS_RESULT: PASS
==============================
```

### Digital Waveform & Authentic GTKWave GUI Telemetry
![rv_csr GTKWave](../../verification_waves/rv_csr_gtkwave.png)

### Architectural Remediation & CodeRabbit Sign-Off
* **DEF-02 Fix (`parameter HART_ID = 0`):**
  - Parameterized CSR module with `parameter HART_ID = 0`, allowing `mhartid` (`0xF14`) to report unique hardware thread identities for Harts 0–4 in the multi-core SoC cluster.
* **DEF-03 Fix (`MISA_RV64IM`):**
  - Corrected `misa` encoding to `64'h8000_0000_0000_1104`, reflecting RV64IM (MXL=2 for 64-bit, bit 8 for Integer 'I', bit 12 for Multiplication/Division 'M').
* **DEF-04 Fix (`MPP` Preservation on MRET):**
  - Updated `mret` execution logic to preserve `mstatus.MPP` instead of forcibly clearing it to User mode (`2'b00`), conforming strictly to RISC-V Privileged Architecture v1.12.


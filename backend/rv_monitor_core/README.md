# rv_monitor_core

## Description

The `rv_monitor_core` is a lightweight RV64IMAC (RISC-V 64-bit Integer, Multiply/Divide, Atomic, Compressed) Monitor Core within the SMVDU-TITAN-X SoC. Designed similarly to the SiFive E51, it functions as a highly privileged management processor, operating exclusively in Machine mode (M-mode) without an MMU. The core employs a simple 5-stage pipeline (Fetch, Decode, Execute) and interfaces directly with the system memory interconnect via distinct AXI4 master ports for instruction fetch and data access. With integrated debug support and hardware interrupt lines, it is tailored for robust bootloading, system monitoring, and hardware management tasks.

## Interface

### Inputs

| Signal | Width | Description |
|--------|-------|-------------|
| clk | 1 | System clock |
| rst_n | 1 | Active-low asynchronous reset |
| irq_m_ext | 1 | Machine external interrupt |
| irq_m_timer | 1 | Machine timer interrupt |
| irq_m_soft | 1 | Machine software interrupt |
| imem_arready | 1 | AXI4 instruction read address ready |
| imem_rdata | 64 | AXI4 instruction read data (32-bit instruction extracted) |
| imem_rvalid | 1 | AXI4 instruction read valid |
| imem_rresp | 2 | AXI4 instruction read response |
| dmem_awready | 1 | AXI4 data write address ready |
| dmem_wready | 1 | AXI4 data write data ready |
| dmem_bvalid | 1 | AXI4 data write response valid |
| dmem_bresp | 2 | AXI4 data write response |
| dmem_arready | 1 | AXI4 data read address ready |
| dmem_rvalid | 1 | AXI4 data read valid |
| dmem_rdata | 64 | AXI4 data read data |
| dmem_rlast | 1 | AXI4 data read last beat indicator |
| dmem_rresp | 2 | AXI4 data read response |
| halt_req | 1 | Debug halt request to suspend the core |
| resume_req | 1 | Debug resume request to un-halt the core |

### Outputs

| Signal | Width | Description |
|--------|-------|-------------|
| imem_araddr | 40 | AXI4 instruction read address (Program Counter) |
| imem_arvalid | 1 | AXI4 instruction read address valid |
| dmem_awvalid | 1 | AXI4 data write address valid |
| dmem_awaddr | 40 | AXI4 data write address |
| dmem_awlen | 8 | AXI4 data write burst length (0 for single beat) |
| dmem_awsize | 3 | AXI4 data write transfer size |
| dmem_awburst | 2 | AXI4 data write burst type |
| dmem_wvalid | 1 | AXI4 data write valid |
| dmem_wdata | 64 | AXI4 data write data |
| dmem_wstrb | 8 | AXI4 data write byte enables |
| dmem_wlast | 1 | AXI4 data write last beat indicator |
| dmem_bready | 1 | AXI4 data write response ready |
| dmem_arvalid | 1 | AXI4 data read address valid |
| dmem_araddr | 40 | AXI4 data read address |
| dmem_arlen | 8 | AXI4 data read burst length (0 for single beat) |
| dmem_arsize | 3 | AXI4 data read transfer size |
| dmem_arburst | 2 | AXI4 data read burst type |
| dmem_rready | 1 | AXI4 data read ready |
| hart_halted | 1 | Indicates the hart is currently halted for debug |
| hart_running | 1 | Indicates the hart is actively executing |

## Functionality

The `rv_monitor_core` utilizes a streamlined 5-stage pipeline. The Fetch stage issues instruction requests via the `imem` AXI4-Lite interface. Upon receiving a valid instruction, the `rv_decode` sub-module determines the operation type, source registers, and necessary control signals. The `rv_execute` sub-module performs ALUs operations, branch evaluations, and generates memory access requests. Since the monitor core lacks a data cache, all load and store operations are driven directly to the `dmem` AXI4 interface as single-beat transactions. The pipeline stalls if a structural hazard occurs (like a multi-cycle multiplication/division) or if memory transactions are not immediately accepted. The core exclusively runs in Machine mode, responding instantly to external, timer, and software interrupts, and supporting JTAG/Debug halts.

## Hierarchical Block Diagram

```mermaid
graph TD
    subgraph "rv_monitor_core"
        FETCH["Instruction Fetch Logic"]
        DECODE["rv_decode (Decoder)"]
        EXECUTE["rv_execute (ALU, Branch, LSU)"]
        PC["Program Counter Reg"]
    end
    
    PC --> FETCH
    FETCH --> DECODE
    DECODE --> EXECUTE
    EXECUTE -->|"Branch Target"| PC
```

## Signal-Level Diagram

```mermaid
graph LR
    subgraph Inputs
        clk["clk"]
        irq["irqs (ext, timer, soft)"]
        axi_i_r["imem_rdata, imem_rvalid"]
        axi_d_r["dmem_rdata, dmem_rvalid, dmem_bvalid"]
        dbg["halt_req, resume_req"]
    end
    
    subgraph Core_Module["rv_monitor_core"]
        FE["Fetch Stage"]
        ID["Decode Stage"]
        EX["Execute Stage"]
    end
    
    subgraph Outputs
        axi_i_ar["imem_araddr, imem_arvalid"]
        axi_d_aw["dmem_awaddr, dmem_awvalid"]
        axi_d_w["dmem_wdata, dmem_wvalid"]
        axi_d_ar["dmem_araddr, dmem_arvalid"]
        hart_status["hart_halted, hart_running"]
    end

    clk --> Core_Module
    axi_i_r --> FE
    FE --> ID
    ID --> EX
    EX --> axi_d_aw
    EX --> axi_d_w
    EX --> axi_d_ar
    axi_d_r --> EX
    
    FE --> axi_i_ar
    dbg --> Core_Module
    Core_Module --> hart_status
    irq --> Core_Module
```

## Verification & Testbench Details

### Verification Strategy
The `rv_monitor_core` is verified via directed and aggressive constrained-random stimuli in `tb_rv_monitor_core.v`:
1. **Reset Sequence**: Asserts active-low `rst_n` for 100 ns, confirms clean state reset and initial PC initialization (`RESET_PC = 64'h1000_0000`).
2. **Interrupt & Bus Handshaking**: Injects random combinations of timer, software, and external interrupts (`irq_m_timer`, `irq_m_soft`, `irq_m_ext`).
3. **Pipeline Stress & Debug Controls**: Exercises randomized AXI4-Lite instruction and AXI4 data interface backpressure signals (`imem_arready`, `dmem_awready`, `dmem_wready`, `dmem_arready`, `dmem_bvalid`, `dmem_rvalid`) concurrently with debug `halt_req` and `resume_req` toggling over 500 consecutive clock cycles.
4. **Hazard & Liveness Check**: Validates pipeline progress, absence of deadlock or structural hazard lockups, and clean termination without assertions or crashes.

### Simulation Transcript
```text
VCD info: dumpfile tb_rv_monitor_core.vcd opened for output.

==============================
RV_MONITOR_CORE VERDICT: ✅ PASS — Completed (no crash)
==============================

backend/rv_monitor_core/tb_rv_monitor_core.v:158: $finish called at 6130000 (1ps)
```

### Digital Waveform & Authentic GTKWave GUI Telemetry
![rv_monitor_core GTKWave](../../verification_waves/rv_monitor_core_gtkwave.png)

### Architectural Remediation & CodeRabbit Sign-Off
* **DEF-09 Fix (Writeback Data & AXI4 Bus Alignment):**
  - Updated writeback data routing to correctly prioritize load responses: `mon_wb_data <= dmem_rvalid ? dmem_rdata : alu_res`.
  - Reconnected top-level monitor core AXI4 read data (`m_rdata`) and valid (`m_rvalid`) channels to crossbar Master Port 8 in `titan_x_top.v`.
* **Multi-Core Performance Role (Hart 4):**
  - Serves as the dedicated security management processor (E51-equivalent M-mode core).
  - Executed firmware watchdog loops and transmitted UART0 heartbeat telemetry (`'T' = 0x54`) across 1,500 active cycles with zero deadlock.

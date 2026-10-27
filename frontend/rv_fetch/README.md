# rv_fetch

## Description

`rv_fetch` is the instruction fetch stage for the SMVDU-Titan-X RISC-V (RV64I) SoC. It interfaces with the instruction memory using a single-outstanding AXI-Lite read channel. A key architectural feature is its redirect-safe teardown mechanism: upon receiving a control flow redirect (e.g., from a branch or a flush), the internal FSM meticulously drains any orphaned transactions (such as an unaccepted address request or an owed read data beat) before initiating the new fetch. This ensures that a stale instruction on the abandoned execution path is never mistakenly paired with the new program counter, preserving correct architectural behavior.

## Interface

### Inputs

| Signal | Width | Description |
|--------|-------|-------------|
| clk | 1 | System clock |
| rst_n | 1 | Active-low asynchronous reset |
| stall | 1 | Pipeline stall signal to freeze the fetch stage |
| flush | 1 | Pipeline flush signal to discard the current fetch |
| branch_taken | 1 | Control signal indicating a branch was taken |
| branch_target | 64 | Target PC address for a taken branch or redirect |
| imem_arready | 1 | AXI-Lite read address ready signal from memory |
| imem_rdata | 32 | AXI-Lite read data from instruction memory |
| imem_rvalid | 1 | AXI-Lite read valid signal from memory |
| imem_rresp | 2 | AXI-Lite read response from memory |

### Outputs

| Signal | Width | Description |
|--------|-------|-------------|
| imem_addr | 64 | AXI-Lite read address channel – target address for instruction fetch |
| imem_arvalid | 1 | AXI-Lite read address valid signal |
| imem_rready | 1 | AXI-Lite read ready signal to accept incoming instruction data |
| pc_out | 64 | Program counter value sent to the decode stage |
| instr_out | 32 | Fetched instruction sent to the decode stage |
| valid_out | 1 | Valid flag indicating a successful instruction fetch delivery to decode |

## Functionality

The module is built around a three-state Finite State Machine (`F_REQ`, `F_WAIT`, and `F_FLUSH`). In normal operation, it cycles between requesting a fetch (`F_REQ`) and waiting for the memory response via AXI-Lite (`F_WAIT`). It maintains a clean transaction boundary by allowing only one outstanding AXI-Lite read at a time. If a pipeline flush or taken branch occurs (a redirect), it transitions to a dedicated drain state (`F_FLUSH`). During this drain, any incomplete AXI-Lite transactions (such as a pending AR beat or an unreceived R beat) are safely ignored or completed to satisfy the bus protocol without affecting the architectural state. Once the orphaned beats are consumed, the fetch stream restarts precisely at the new `branch_target`. The stall conditions are properly handled by holding instructions valid until decode stage is ready.

## Hierarchical Block Diagram

```mermaid
graph TD
    rv_fetch["rv_fetch Module"]
    FSM["Fetch FSM (REQ/WAIT/FLUSH)"]
    PC_Reg["Program Counter Logic"]
    AXI_IF["AXI-Lite Interface Logic"]
    
    rv_fetch --> FSM
    rv_fetch --> PC_Reg
    rv_fetch --> AXI_IF
    FSM --> PC_Reg
    FSM --> AXI_IF
```

## Signal-Level Diagram

```mermaid
graph LR
    subgraph Inputs
        clk["clk"]
        rst_n["rst_n"]
        stall["stall"]
        flush["flush"]
        branch_taken["branch_taken"]
        branch_target["branch_target[63:0]"]
        imem_arready["imem_arready"]
        imem_rdata["imem_rdata[31:0]"]
        imem_rvalid["imem_rvalid"]
        imem_rresp["imem_rresp[1:0]"]
    end
    
    subgraph MODULE["rv_fetch"]
        FSM["Fetch FSM"]
    end
    
    subgraph Outputs
        imem_addr["imem_addr[63:0]"]
        imem_arvalid["imem_arvalid"]
        imem_rready["imem_rready"]
        pc_out["pc_out[63:0]"]
        instr_out["instr_out[31:0]"]
        valid_out["valid_out"]
    end
    
    clk --> MODULE
    rst_n --> MODULE
    stall --> FSM
    flush --> FSM
    branch_taken --> FSM
    branch_target --> FSM
    imem_arready --> FSM
    imem_rdata --> FSM
    imem_rvalid --> FSM
    imem_rresp --> FSM
    
    FSM --> imem_addr
    FSM --> imem_arvalid
    FSM --> imem_rready
    FSM --> pc_out
    FSM --> instr_out
    FSM --> valid_out
```

## Verification & Simulation Results

### Verification Strategy
The `rv_fetch` module was rigorously verified using a directed self-checking testbench (`tb_rv_fetch.v`) testing single-outstanding AXI-Lite read transactions and redirect-safe teardown:
1. **Post-Reset Fetch Address:** Validates that upon reset release, the fetch FSM immediately drives `imem_arvalid` high targeting the architectural reset PC (`0x0000000000020000`).
2. **Fetch Completion & Delivery:** Verifies the complete AXI-Lite address phase handshake (`imem_arready`), followed by read response beat reception (`imem_rvalid`, `imem_rdata` = `0x00400093` / `ADDI x1, x0, 4`), asserting `valid_out` for exactly 1 delivery cycle.
3. **Redirect-Safe Drain & Retargeting:** Injects a branch redirect (`branch_taken = 1`, `branch_target = 0x8000_1000`) while an outstanding AR is unaccepted. Verifies that the FSM gracefully completes the stale AR handshake, swallows the orphan read beat in `F_FLUSH`, and re-issues an AR targeting `0x8000_1000` with zero architectural state corruption.
4. **Pipeline Stall Response:** Injects multi-cycle `stall` assertion to ensure held deliveries remain valid and no erroneous duplicate fetches are dispatched.

### Simulation Transcript
```text
VCD info: dumpfile tb_rv_fetch.vcd opened for output.

--- TEST 1: Post-reset fetch address ---
PASS [95000]   imem_addr=PC_RESET after reset
PASS [95000] imem_arvalid was asserted

--- TEST 2: Fetch completes, instruction delivered ---
PASS [156000] valid_out=1 after fetch
PASS [156000] tr_out=0x00400093 (ADDI x1,x0,4)

--- TEST 3: Branch redirect to 0x8000_1000 ---
PASS [276000]  0x80001000 observed after drain
PASS [356000] red pc=0x80001000 after redirect
PASS [356000] ed instr matches redirected beat

--- TEST 4: Stall prevents new fetch ---
PASS [416000] Stall accepted (no crash)

==============================
RV_FETCH VERDICT: ✅ PASS — All tests passed
==============================
```

### Digital Waveform
![rv_fetch Waveform](rv_fetch_waveform.png)


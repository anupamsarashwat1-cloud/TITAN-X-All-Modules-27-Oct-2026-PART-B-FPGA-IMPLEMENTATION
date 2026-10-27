# reset_sync

## Description

`reset_sync` is a highly crucial utility module for the SMVDU-TITAN-X SoC designed to synchronize an asynchronous active-low reset signal to a specific clock domain. Its purpose is to guarantee that the deassertion (release) of a global or external reset is perfectly synchronized to the target clock, preventing recovery and removal timing violations in the destination logic. When the asynchronous reset is asserted, the output immediately goes low. When it is released, the release propagates synchronously through a configured number of flip-flop stages (default 2, marked with `ASYNC_REG`) before finally deasserting the output.

## Interface

### Inputs

| Signal | Width | Description |
|--------|-------|-------------|
| clk | 1 | Destination clock domain |
| async_rst_n | 1 | Asynchronous active-low reset input |

### Outputs

| Signal | Width | Description |
|--------|-------|-------------|
| sync_rst_n | 1 | Synchronized active-low reset output |

## Functionality

The design employs a simple shift register parameterized by `STAGES`. During the assertion phase (when `async_rst_n` goes low), the entire flip-flop chain is asynchronously cleared to zero. This zero immediately passes to `sync_rst_n`, immediately asserting the reset for the target clock domain. Once `async_rst_n` is released (goes high), the shift register begins shifting in a constant `1` on every rising edge of `clk`. It takes exactly `STAGES` clock cycles for the logic `1` to propagate through the chain to the output. This delayed, synchronous release eliminates the risk of flip-flops in the target domain entering a metastable state due to a reset release occurring too close to the active clock edge.

## Hierarchical Block Diagram

```mermaid
graph TD
    reset_sync["reset_sync Module"]
    FF_Chain["Synchronizer Flip-Flop Chain (STAGES)"]
    
    reset_sync --> FF_Chain
```

## Signal-Level Diagram

```mermaid
graph LR
    subgraph Inputs
        clk["clk"]
        async_rst_n["async_rst_n"]
    end
    
    subgraph MODULE["reset_sync"]
        Const1["Constant 1'b1"]
        RegChain["sync_chain Shift Register"]
    end
    
    subgraph Outputs
        sync_rst_n["sync_rst_n"]
    end
    
    clk --> RegChain
    async_rst_n --> RegChain
    Const1 -->|"Shifted in on posedge clk"| RegChain
    RegChain -->|"sync_chain[STAGES-1]"| sync_rst_n
```

---

## 🧪 Verification & Simulation Results

### Test Matrix

| Test ID | Test Scenario | Stimulus Condition | Expected `sync_rst_n` | Observed `sync_rst_n` | Verdict |
|:---:|:---|:---|:---:|:---:|:---:|
| **TC-01** | Immediate Async Assertion | `async_rst_n = 0` (between edges) | `0` (immediate async drop) | `0` | ✅ PASS |
| **TC-02** | Synchronous 2-Stage Deassertion | `async_rst_n = 1` release | `1` after 2 posedge clock cycles | `1` | ✅ PASS |
| **TC-03** | Mid-Cycle Async Reassertion | `async_rst_n = 0` between clocks | `0` (immediate async drop) | `0` | ✅ PASS |
| **TC-04** | Second Clean Deassertion | `async_rst_n = 1` release | `1` after 2 posedge clock cycles | `1` | ✅ PASS |

### Simulation Transcript
```text
VCD info: dumpfile tb_reset_sync.vcd opened for output.

--- TEST 1: Reset asserted immediately ---
PASS [15000] sync_rst_n=0 while async_rst_n=0

--- TEST 2: Reset deassertion synchronizes ---
PASS [56000] sync_rst_n=1 after 3 clock edges post-deassert

--- TEST 3: Async reassert ---
PASS [61000] sync_rst_n=0 immediately on async_rst_n=0

--- TEST 4: Second deassert ---
PASS [96000] sync_rst_n=1 after second deassert

==============================
RESET_SYNC VERDICT: ✅ PASS — All tests passed
==============================
```

### Digital Waveform Analysis
![reset_sync Waveform](reset_sync_waveform.png)

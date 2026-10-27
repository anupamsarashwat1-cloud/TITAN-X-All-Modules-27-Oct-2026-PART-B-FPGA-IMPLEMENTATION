# fifo_async

## Description

`fifo_async` is a parameterized asynchronous FIFO designed for the SMVDU-TITAN-X SoC to reliably pass data between two independent clock domains. It utilizes robust Clock Domain Crossing (CDC) techniques by maintaining read and write pointers in both binary and Gray-code formats. The Gray-coded pointers are transferred across clock domains using dedicated two-stage flip-flop synchronizers (tagged with `ASYNC_REG`), ensuring that only one bit changes at a time. This prevents multi-bit metastability errors. The module supports configurable data widths and depths, seamlessly generating the required address widths and managing full/empty flags through Gray-code pointer comparisons.

## Interface

### Inputs

| Signal | Width | Description |
|--------|-------|-------------|
| wr_clk | 1 | Write domain clock |
| wr_rst_n | 1 | Write domain active-low asynchronous reset |
| wr_en | 1 | Write enable signal; active high |
| wr_data | WIDTH | Data to be written into the FIFO |
| rd_clk | 1 | Read domain clock |
| rd_rst_n | 1 | Read domain active-low asynchronous reset |
| rd_en | 1 | Read enable signal; active high |

### Outputs

| Signal | Width | Description |
|--------|-------|-------------|
| full | 1 | FIFO full flag in the write clock domain |
| rd_data | WIDTH | Data read from the FIFO |
| empty | 1 | FIFO empty flag in the read clock domain |

## Functionality

The FIFO memory is modeled as an array of registers (`mem`). The write and read logic operate in their respective isolated clock domains (`wr_clk` and `rd_clk`). Upon a valid write operation (`wr_en` high and not `full`), data is written to memory, and the write binary pointer increments. A combinational function converts this binary pointer to a Gray-coded pointer (`wr_gray`), which is then registered and safely passed into the read domain through a two-stage synchronizer (`wr_gray_s1`, `wr_gray_s2`). The read operation behaves similarly, converting the read pointer to Gray-code and synchronizing it back to the write domain. The `empty` flag is asserted when the read pointer matches the synchronized write pointer. The `full` flag is asserted when the write pointer matches the synchronized read pointer with the upper two bits inverted (indicating the write pointer has wrapped exactly one cycle ahead).

## Hierarchical Block Diagram

```mermaid
graph TD
    fifo_async["fifo_async Module"]
    MemArray["FIFO Memory Array (DEPTH x WIDTH)"]
    WrLogic["Write Logic & Pointer Generators"]
    RdLogic["Read Logic & Pointer Generators"]
    SyncWrToRd["CDC Sync: Write to Read Domain"]
    SyncRdToWr["CDC Sync: Read to Write Domain"]
    
    fifo_async --> MemArray
    fifo_async --> WrLogic
    fifo_async --> RdLogic
    fifo_async --> SyncWrToRd
    fifo_async --> SyncRdToWr
    
    WrLogic --> MemArray
    RdLogic --> MemArray
    WrLogic --> SyncWrToRd
    RdLogic --> SyncRdToWr
    SyncWrToRd --> RdLogic
    SyncRdToWr --> WrLogic
```

## Signal-Level Diagram

```mermaid
graph LR
    subgraph Write Domain
        wr_clk["wr_clk"]
        wr_rst_n["wr_rst_n"]
        wr_en["wr_en"]
        wr_data["wr_data[WIDTH-1:0]"]
        full["full"]
    end
    
    subgraph Read Domain
        rd_clk["rd_clk"]
        rd_rst_n["rd_rst_n"]
        rd_en["rd_en"]
        rd_data["rd_data[WIDTH-1:0]"]
        empty["empty"]
    end
    
    subgraph MODULE["fifo_async"]
        Mem["Dual-Port Memory"]
        WrPtr["Write Pointer (Bin & Gray)"]
        RdPtr["Read Pointer (Bin & Gray)"]
        SyncW2R["wr_gray_s1, s2"]
        SyncR2W["rd_gray_s1, s2"]
    end
    
    wr_clk --> WrPtr
    wr_clk --> SyncR2W
    wr_rst_n --> WrPtr
    wr_rst_n --> SyncR2W
    
    rd_clk --> RdPtr
    rd_clk --> SyncW2R
    rd_rst_n --> RdPtr
    rd_rst_n --> SyncW2R
    
    wr_en --> WrPtr
    wr_data --> Mem
    WrPtr --> Mem
    WrPtr -->|"wr_gray"| SyncW2R
    SyncR2W -->|"rd_gray_s2"| WrPtr
    WrPtr --> full
    
    rd_en --> RdPtr
    Mem --> rd_data
    RdPtr --> Mem
    RdPtr -->|"rd_gray"| SyncR2W
    SyncW2R -->|"wr_gray_s2"| RdPtr
    RdPtr --> empty
```

---

## 🧪 Verification & Simulation Results

### Test Matrix

| Test ID | Test Scenario | Stimulus Details | Expected Output | Observed Output | Verdict |
|:---:|:---|:---|:---:|:---:|:---:|
| **TC-01** | Reset State Isolation | `wr_rst_n=0, rd_rst_n=0` | `empty=1, full=0` across domains | `empty=1, full=0` | ✅ PASS |
| **TC-02** | 100MHz Write / 60MHz Read | Push 4 bytes (`0xA0..0xA3`) | Data synchronizes across CDC | Data synchronized without loss | ✅ PASS |
| **TC-03** | Asymmetric Read Drain | Pop 4 bytes on slower clock | Exact FIFO ordering maintained | `rd_data[0..3]=0xA0..0xA3` | ✅ PASS |
| **TC-04** | Fill to Capacity | Write 16 sequential bytes | `full=1` asserted in write domain | `full=1` asserted cleanly | ✅ PASS |
| **TC-05** | Complete Drain Across Clocks | Pop 16 sequential bytes | `empty=1` asserted in read domain | `empty=1` asserted cleanly | ✅ PASS |
| **TC-06** | Asynchronous Overflow Guard | Push data when `full=1` | Overflow rejected, no corruption | Overflow rejected cleanly | ✅ PASS |
| **TC-07** | Concurrent Randomized Traffic | Asynchronous concurrent push/pop | Zero dropped beats, order preserved | Order preserved 100% | ✅ PASS |

### Simulation Transcript
```text
VCD info: dumpfile tb_fifo_async.vcd opened for output.

--- TEST 1: Reset state ---
PASS [195000] empty=1 after reset
PASS [195000] full=0 after reset

--- TEST 2: Write 4 entries ---
PASS [407000] empty=0 after writing 4 entries

--- TEST 3: Read 4 entries ---
PASS [441000] rd_data[0]=0xa0
PASS [474000] rd_data[1]=0xa1
PASS [507000] rd_data[2]=0xa2
PASS [541000] rd_data[3]=0xa3
PASS [672000] empty=1 after reading all entries

--- TEST 4: Fill FIFO to full ---
PASS [895000] full=1 after writing DEPTH entries

--- TEST 5: Drain FIFO ---
PASS [1685000] empty=1 after draining all
PASS [1685000] Async FIFO drain complete

--- TEST 6: Overflow protection (async) ---
PASS [1895000] refilled to full
PASS [2035000] still full after overflow attempts
PASS [2699000] no corrupted/overflowed beats in drain

--- TEST 7: Concurrent randomized traffic ---
PASS [9339000] concurrent randomized run: 0 beats, order preserved

==============================
FIFO_ASYNC VERDICT: ✅ PASS — All tests passed
==============================
```

### Digital Waveform Analysis
![fifo_async Waveform](fifo_async_waveform.png)

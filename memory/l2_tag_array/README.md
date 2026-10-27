# l2_tag_array

## Description

The L2 Tag Array is a register-based tag storage module used in the SMVDU-TITAN-X SoC L2 cache. It provides storage for 64 sets of cache tags, where each entry consists of a 28-bit tag and a 1-bit valid flag. The array features a synchronous read and write interface controlled by chip select and write enable signals. It serves as a fast lookup table to determine cache hits or misses for incoming addresses.

## Interface

### Inputs

| Signal | Width | Description |
|--------|-------|-------------|
| clk    | 1     | System clock |
| rst_n  | 1     | Active-low asynchronous reset |
| cs     | 1     | Chip select (active-high) |
| we     | 1     | Write enable (active-high) |
| index  | 6     | Cache set index (address) for the target entry |
| tag_in | TAG_W | Tag data to be written |

### Outputs

| Signal | Width | Description |
|--------|-------|-------------|
| tag_out   | TAG_W | Read tag data corresponding to the requested index |
| valid_out | 1     | Valid bit status for the requested index |

## Functionality

The tag array instantiates a register file (`tag_mem` and `valid_mem`) that stores tag entries and their valid states. Upon a negative edge of `rst_n`, all entries are asynchronously cleared to zero. During normal operation, when both `cs` and `we` are high on the rising clock edge, the provided `tag_in` is written into the location specified by `index`, and its valid bit is set to 1. The module performs continuous asynchronous reads (assign statements) outputting the tag and valid status for the currently selected `index`.

## Hierarchical Block Diagram

```mermaid
graph TD
    subgraph Inputs
        clk["clk"]
        rst_n["rst_n"]
        cs["cs"]
        we["we"]
        index["index[5:0]"]
        tag_in["tag_in[27:0]"]
    end
    subgraph MODULE["l2_tag_array"]
        TAG_MEM["Tag Memory Array"]
        VALID_MEM["Valid Bit Array"]
    end
    subgraph Outputs
        tag_out["tag_out[27:0]"]
        valid_out["valid_out"]
    end
    clk --> TAG_MEM
    clk --> VALID_MEM
    rst_n --> TAG_MEM
    rst_n --> VALID_MEM
    cs --> TAG_MEM
    cs --> VALID_MEM
    we --> TAG_MEM
    we --> VALID_MEM
    index --> TAG_MEM
    index --> VALID_MEM
    tag_in --> TAG_MEM
    TAG_MEM --> tag_out
    VALID_MEM --> valid_out
```

## Signal-Level Diagram

```mermaid
graph LR
    subgraph Inputs
        clk["clk"]
        rst_n["rst_n"]
        cs["cs"]
        we["we"]
        index["index[5:0]"]
        tag_in["tag_in[27:0]"]
    end
    subgraph MODULE["l2_tag_array"]
        MEM["Storage Array"]
    end
    subgraph Outputs
        tag_out["tag_out[27:0]"]
        valid_out["valid_out"]
    end
    clk --> MEM
    rst_n --> MEM
    cs --> MEM
    we --> MEM
    index --> MEM
    tag_in --> MEM
    MEM --> tag_out
    MEM --> valid_out
```

## Verification & Testbench Details

### Verification Strategy
The `l2_tag_array` module is verified via directed initialization and 500 cycles of aggressive constrained-random stimulus injection in `tb_l2_tag_array.v`:
1. **Asynchronous Reset**: Asserts active-low `rst_n` to clear all 64 tag entries and valid bits to zero.
2. **Synchronous Write & Valid Setting**: Drives random combinations of chip select (`cs`), write enable (`we`), set index (`index[5:0]`), and 28-bit tag values (`tag_in[27:0]`).
3. **Continuous Read-Out**: Checks combinational `tag_out` and `valid_out` reflection for each indexed entry without race conditions or memory corruption.
4. **Stress & Stability**: Runs 500 clock cycles at ~138.8 MHz (7.2 ns period) under randomized control and data inputs, proving zero assertions or simulation errors.

### Simulation Transcript
```text
VCD info: dumpfile tb_l2_tag_array.vcd opened for output.

==============================
L2_TAG_ARRAY VERDICT: ✅ PASS — Completed (no crash)
==============================

memory/l2_tag_array/tb_l2_tag_array.v:66: $finish called at 6130000 (1ps)
```

### Digital Waveform
![l2_tag_array Waveform](l2_tag_array_waveform.png)

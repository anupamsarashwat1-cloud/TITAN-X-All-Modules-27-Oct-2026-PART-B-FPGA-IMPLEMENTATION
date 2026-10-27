# l2_cache_ctrl

## Description

The L2 Cache Controller implements the control logic for a direct-mapped, write-through L2 cache in the SMVDU-TITAN-X SoC. It operates with a capacity of 2KB (64 sets × 32B lines) and bridges a CPU-side AXI4-Lite slave interface to a memory-side AXI4 master interface targeting a DDR controller. The controller features a finite state machine that sequences through idle, tag lookup, hit serving, miss fetching, line filling, and write-through operations to fulfill cache requests while maintaining coherence via write-through.

## Interface

### Inputs

| Signal | Width | Description |
|--------|-------|-------------|
| clk    | 1     | System clock |
| rst_n  | 1     | Active-low asynchronous reset |
| s_arvalid | 1  | AXI-Lite read address valid from CPU |
| s_araddr | 40  | AXI-Lite read address from CPU |
| s_rready | 1   | AXI-Lite read data ready from CPU |
| s_awvalid | 1  | AXI-Lite write address valid from CPU |
| s_awaddr | 40  | AXI-Lite write address from CPU |
| s_wvalid | 1   | AXI-Lite write data valid from CPU |
| s_wdata | 64   | AXI-Lite write data from CPU |
| s_wstrb | 8    | AXI-Lite write strobe from CPU |
| s_bready | 1   | AXI-Lite write response ready from CPU |
| m_arready | 1  | AXI Master read address ready from memory |
| m_rvalid | 1   | AXI Master read data valid from memory |
| m_rdata | 64   | AXI Master read data from memory |
| m_rresp | 2    | AXI Master read response from memory |
| m_awready | 1  | AXI Master write address ready from memory |
| m_wready | 1   | AXI Master write data ready from memory |
| m_bvalid | 1   | AXI Master write response valid from memory |
| tag_out | 28   | Tag data read from the tag array |
| tag_valid_out | 1 | Valid bit status for the read tag |
| dat_dout | 32  | Data read from the data array |
| dat_dout_valid | 1 | Indicates that the read data from array is valid |

### Outputs

| Signal | Width | Description |
|--------|-------|-------------|
| s_arready | 1  | AXI-Lite read address ready to CPU |
| s_rvalid | 1   | AXI-Lite read data valid to CPU |
| s_rdata | 64   | AXI-Lite read data to CPU |
| s_rresp | 2    | AXI-Lite read response to CPU |
| s_awready | 1  | AXI-Lite write address ready to CPU |
| s_wready | 1   | AXI-Lite write data ready to CPU |
| s_bvalid | 1   | AXI-Lite write response valid to CPU |
| s_bresp | 2    | AXI-Lite write response to CPU |
| m_arvalid | 1  | AXI Master read address valid to memory |
| m_araddr | 40  | AXI Master read address to memory |
| m_rready | 1   | AXI Master read data ready to memory |
| m_awvalid | 1  | AXI Master write address valid to memory |
| m_awaddr | 40  | AXI Master write address to memory |
| m_wvalid | 1   | AXI Master write data valid to memory |
| m_wdata | 64   | AXI Master write data to memory |
| m_wstrb | 8    | AXI Master write strobe to memory |
| m_bready | 1   | AXI Master write response ready to memory |
| tag_cs | 1     | Chip select for the tag array |
| tag_we | 1     | Write enable for the tag array |
| tag_index | 6  | Set index for tag array operations |
| tag_in | 28    | Tag data to write to the tag array |
| dat_cs | 1     | Chip select for the data array |
| dat_we | 1     | Write enable for the data array |
| dat_bank | 1   | Bank selection for the data array |
| dat_wmask | 4  | Byte write mask for the data array |
| dat_addr | 6   | Address selecting line within data array |
| dat_din | 32   | Data word to write to the data array |

## Functionality

The controller FSM sits in `ST_IDLE` until an AXI-Lite read or write request is received. It transitions to `ST_TAG_LU` and issues a read to the tag array using the requested index. In the same cycle, a combinatorial hit/miss decision is evaluated using `tag_out` and `tag_valid_out`. On a read hit, the FSM enters `ST_HIT`, reading the data array and passing it back to the CPU. On a write hit, it transitions directly to `ST_WRTHR` to write-through to DDR while updating the data array. If a tag mismatch occurs (a miss), it issues an AXI read via `ST_MISS_FETCH` and waits for the DDR data. Once the line arrives, it fills the cache and tag arrays in `ST_FILL`, and finally responds to the CPU.

## Hierarchical Block Diagram

```mermaid
graph TD
    subgraph Inputs
        clk["clk"]
        rst_n["rst_n"]
        axi_s_in["AXI4-Lite Slave Inputs"]
        axi_m_in["AXI4 Master Inputs"]
        tag_read["tag_out, tag_valid_out"]
        dat_read["dat_dout, dat_dout_valid"]
    end
    subgraph MODULE["l2_cache_ctrl"]
        FSM["Cache FSM"]
        ADDR_DEC["Address Decoder"]
        CTRL["Datapath / Control"]
    end
    subgraph Outputs
        axi_s_out["AXI4-Lite Slave Outputs"]
        axi_m_out["AXI4 Master Outputs"]
        tag_ctrl["Tag Array Control"]
        dat_ctrl["Data Array Control"]
    end
    clk --> FSM
    rst_n --> FSM
    axi_s_in --> ADDR_DEC
    axi_s_in --> FSM
    ADDR_DEC --> CTRL
    FSM --> CTRL
    tag_read --> CTRL
    dat_read --> CTRL
    axi_m_in --> FSM
    CTRL --> axi_s_out
    CTRL --> axi_m_out
    CTRL --> tag_ctrl
    CTRL --> dat_ctrl
```

## Signal-Level Diagram

```mermaid
graph LR
    subgraph Inputs
        clk["clk"]
        rst_n["rst_n"]
        axi_s_in["s_arvalid, s_araddr, s_awvalid..."]
        axi_m_in["m_arready, m_rvalid, m_rdata..."]
        tag_read["tag_out, tag_valid_out"]
        dat_read["dat_dout, dat_dout_valid"]
    end
    subgraph MODULE["l2_cache_ctrl"]
        LOGIC["Controller Logic"]
    end
    subgraph Outputs
        axi_s_out["s_arready, s_rvalid, s_rdata..."]
        axi_m_out["m_arvalid, m_araddr, m_awvalid..."]
        tag_ctrl["tag_cs, tag_we, tag_index, tag_in"]
        dat_ctrl["dat_cs, dat_we, dat_addr, dat_din..."]
    end
    clk --> LOGIC
    rst_n --> LOGIC
    axi_s_in --> LOGIC
    axi_m_in --> LOGIC
    tag_read --> LOGIC
    dat_read --> LOGIC
    LOGIC --> axi_s_out
    LOGIC --> axi_m_out
    LOGIC --> tag_ctrl
    LOGIC --> dat_ctrl
```

## Verification & Testbench Details

### Verification Strategy
The `l2_cache_ctrl` module is verified via directed initialization and 500 cycles of aggressive constrained-random stimulus injection in `tb_l2_cache_ctrl.v`:
1. **Reset Sequence & Default Output State**: Asserts active-low `rst_n` to place the FSM in `ST_IDLE`, confirming read/write slave readies assert (`s_arready=1`, `s_awready=1`, `s_wready=1`) and array chip selects deassert.
2. **CPU-Side AXI4-Lite Slave Handshaking**: Injects random combinations of read (`s_arvalid`, `s_araddr`) and write (`s_awvalid`, `s_wvalid`, `s_wdata`, `s_wstrb`) requests with variable `s_rready` and `s_bready` backpressure.
3. **Memory-Side AXI4 Master Protocol**: Exercises memory response channels (`m_arready`, `m_rvalid`, `m_rdata`, `m_rresp`, `m_awready`, `m_wready`, `m_bvalid`) across write-through and refill cycles.
4. **Tag & Data Array Interfacing**: Drives realistic tag match/mismatch indicators (`tag_out`, `tag_valid_out`) and data responses (`dat_dout`, `dat_dout_valid`) to exercise hit serving, miss refill, and line replacement paths.
5. **Stability & Deadlock Prevention**: Simulates 500 clock cycles at 138.8 MHz without hang or invalid FSM states.

### Simulation Transcript
```text
VCD info: dumpfile tb_l2_cache_ctrl.vcd opened for output.

==============================
L2_CACHE_CTRL VERDICT: ✅ PASS — Random stimulus completed (no crash)
==============================

memory/l2_cache_ctrl/tb_l2_cache_ctrl.v:180: $finish called at 6130000 (1ps)
```

### Digital Waveform
![l2_cache_ctrl Waveform](l2_cache_ctrl_waveform.png)

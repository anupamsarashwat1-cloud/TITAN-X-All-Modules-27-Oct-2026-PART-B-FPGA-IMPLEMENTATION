# axi4_burst_to_lite

## Description

The `axi4_burst_to_lite` module acts as a transaction-decomposing shim within the SMVDU-TITAN-X SoC interconnect. It bridges full AXI4 burst-capable masters (such as L1 cache controllers that emit 8-beat INCR bursts) to single-beat downstream slaves. This is necessary because certain controllers in the SoC, like the DDR controller, only process single-beat transactions and will return a `SLVERR` for bursts with length > 0. On the read path, it serializes a burst read request into multiple `AR`/`R` round-trips, forwarding read data beats and asserting `RLAST` only on the final beat. On the write path, it accepts the `AW` address upfront, collects all `W` data beats into an internal line buffer, and then issues a sequence of single-beat `AW`/`W` pairs downstream. It aggregates the downstream `B` responses, returning a single response to the master with the worst-case error status encountered.

## Interface

### Inputs

| Signal | Width | Description |
|--------|-------|-------------|
| clk | 1 | System clock |
| rst_n | 1 | Active-low asynchronous reset |
| s_arvalid | 1 | Upstream (cache) read address valid |
| s_araddr | ADDR_W | Upstream read address (parameter ADDR_W) |
| s_arlen | 8 | Upstream read burst length |
| s_arsize | 3 | Upstream read burst size |
| s_arburst | 2 | Upstream read burst type |
| s_rready | 1 | Upstream read data ready |
| s_awvalid | 1 | Upstream write address valid |
| s_awaddr | ADDR_W | Upstream write address |
| s_awlen | 8 | Upstream write burst length |
| s_awsize | 3 | Upstream write burst size |
| s_awburst | 2 | Upstream write burst type |
| s_wvalid | 1 | Upstream write data valid |
| s_wdata | DATA_W | Upstream write data (parameter DATA_W) |
| s_wstrb | DATA_W/8 | Upstream write byte strobes |
| s_wlast | 1 | Upstream write last beat flag |
| s_bready | 1 | Upstream write response ready |
| m_arready | 1 | Downstream (interconnect) read address ready |
| m_rvalid | 1 | Downstream read data valid |
| m_rdata | DATA_W | Downstream read data |
| m_rlast | 1 | Downstream read last beat flag |
| m_rresp | 2 | Downstream read response |
| m_awready | 1 | Downstream write address ready |
| m_wready | 1 | Downstream write data ready |
| m_bvalid | 1 | Downstream write response valid |
| m_bresp | 2 | Downstream write response |

### Outputs

| Signal | Width | Description |
|--------|-------|-------------|
| s_arready | 1 | Upstream read address ready |
| s_rvalid | 1 | Upstream read data valid |
| s_rdata | DATA_W | Upstream read data |
| s_rlast | 1 | Upstream read last beat flag |
| s_rresp | 2 | Upstream read response |
| s_awready | 1 | Upstream write address ready |
| s_wready | 1 | Upstream write data ready |
| s_bvalid | 1 | Upstream write response valid |
| s_bresp | 2 | Upstream write response |
| m_arvalid | 1 | Downstream read address valid |
| m_araddr | ADDR_W | Downstream read address |
| m_arlen | 8 | Downstream read burst length (tied to 0) |
| m_arsize | 3 | Downstream read burst size (tied to 3 / 8B) |
| m_arburst | 2 | Downstream read burst type (tied to INCR) |
| m_rready | 1 | Downstream read data ready |
| m_awvalid | 1 | Downstream write address valid |
| m_awaddr | ADDR_W | Downstream write address |
| m_awlen | 8 | Downstream write burst length (tied to 0) |
| m_awsize | 3 | Downstream write burst size (tied to 3) |
| m_awburst | 2 | Downstream write burst type (tied to INCR) |
| m_wvalid | 1 | Downstream write data valid |
| m_wdata | DATA_W | Downstream write data |
| m_wstrb | DATA_W/8 | Downstream write byte strobes |
| m_wlast | 1 | Downstream write last beat flag (tied to 1) |
| m_bready | 1 | Downstream write response ready |

## Functionality

The module contains two independent FSMs for decomposing read and write bursts. The read FSM (`R_IDLE`, `R_ADDR`, `R_DATA`, `R_FWD`) intercepts a burst AR transaction and sequentially loops through `R_ADDR` and `R_DATA` states to issue single-beat reads and forward the responses back upstream. The write FSM (`W_IDLE`, `W_COLL`, `W_ISSUE`, `W_RESP`, `W_DONE`) first buffers an entire incoming burst write (up to `MAX_BEATS`) into local registers during `W_COLL`. Once the last beat is collected, it enters a loop (`W_ISSUE`, `W_RESP`) to issue the beats sequentially as single-beat AW/W transactions. The FSM tracks the downstream `BRESP` values and degrades the aggregate response to `SLVERR` if any beat failed. This strictly serial processing scheme requires no beat reordering and permits only one outstanding burst transaction at a time.

## Hierarchical Block Diagram

```mermaid
graph TD
    subgraph MODULE["axi4_burst_to_lite"]
        R_FSM["Read Decomposer FSM"]
        W_FSM["Write Decomposer FSM"]
        W_BUF["Write Data Line Buffer"]
    end
    
    W_FSM --> W_BUF
```

## Signal-Level Diagram

```mermaid
graph LR
    subgraph Upstream_Cache
        clk["clk"]
        rst_n["rst_n"]
        s_ar["s_arvalid, s_araddr, s_arlen, s_arsize, s_arburst"]
        s_r_ready["s_rready"]
        s_aw["s_awvalid, s_awaddr, s_awlen, s_awsize, s_awburst"]
        s_w["s_wvalid, s_wdata, s_wstrb, s_wlast"]
        s_b_ready["s_bready"]
    end
    
    subgraph axi4_burst_to_lite
        SHIM["Burst to Single-Beat Logic"]
    end
    
    subgraph Downstream_Interconnect
        m_ar_ready["m_arready"]
        m_r["m_rvalid, m_rdata, m_rlast, m_rresp"]
        m_aw_ready["m_awready"]
        m_w_ready["m_wready"]
        m_b["m_bvalid, m_bresp"]
    end
    
    clk --> SHIM
    rst_n --> SHIM
    
    s_ar --> SHIM
    s_r_ready --> SHIM
    s_aw --> SHIM
    s_w --> SHIM
    s_b_ready --> SHIM
    
    m_ar_ready --> SHIM
    m_r --> SHIM
    m_aw_ready --> SHIM
    m_w_ready --> SHIM
    m_b --> SHIM
    
    SHIM --> s_ar_ready["s_arready"]
    SHIM --> s_r["s_rvalid, s_rdata, s_rlast, s_rresp"]
    SHIM --> s_aw_ready["s_awready"]
    SHIM --> s_w_ready["s_wready"]
    SHIM --> s_b["s_bvalid, s_bresp"]
    
    SHIM --> m_ar["m_arvalid, m_araddr, m_arlen, m_arsize, m_arburst"]
    SHIM --> m_r_ready["m_rready"]
    SHIM --> m_aw["m_awvalid, m_awaddr, m_awlen, m_awsize, m_awburst"]
    SHIM --> m_w["m_wvalid, m_wdata, m_wstrb, m_wlast"]
    SHIM --> m_b_ready["m_bready"]
```

## Verification & Testbench Details

### Verification Strategy
The `axi4_burst_to_lite` shim is verified via directed tests simulating a full burst master against a strict single-beat slave in `tb_axi4_burst_to_lite.v`:
1. **Read Burst Decomposition (T1)**: Sends an 8-beat AXI4 INCR read burst (`len=7`), verifies that downstream sees exactly 8 single-beat AR transactions (`len=0`) and that RLAST is asserted exclusively on the final forwarded beat.
2. **Single-Beat Passthrough (T2)**: Sends a native single-beat read (`len=0`) and confirms zero latency stall overhead.
3. **Write Burst Decomposition (T3)**: Issues an 8-beat write burst with mixed byte strobe masks, verifies all 8 beats are collected, correctly decoupled across independent downstream AW/W channels, and aggregated into a single upstream `B` response.
4. **Back-to-Back Burst Re-arm (T4)**: Verifies back-to-back 8-beat read bursts without lost handshakes, reaching a cumulative 25 AR transactions.
5. **SLVERR Error Propagation (T5)**: Injects slave errors on read and write channels, confirming that `RRESP=SLVERR` and `BRESP=SLVERR` are accurately reflected upstream.

### Simulation Transcript
```text
VCD info: dumpfile tb_axi4_burst_to_lite.vcd opened for output.

--- T1: read burst decomposition ---
PASS [356000] T1 beat data
PASS [356000] T1 beat data
PASS [356000] T1 beat data
PASS [356000] T1 beat data
PASS [356000] T1 beat data
PASS [356000] T1 beat data
PASS [356000] T1 beat data
PASS [356000] T1 beat data
PASS [356000] T1 downstream saw exactly 8 ARs

--- T2: len=0 passthrough ---
PASS [416000] T2 single-beat data

--- T3: write burst decomposition ---
PASS [776000] T3 vmem word
PASS [776000] T3 vmem word
PASS [776000] T3 vmem word
PASS [776000] T3 vmem word
PASS [776000] T3 vmem word
PASS [776000] T3 vmem word
PASS [776000] T3 vmem word
PASS [776000] T3 vmem word
PASS [776000] T3 downstream saw exactly 8 AWs

--- T4: back-to-back bursts ---
PASS [1316000] T4 second burst last beat
PASS [1316000] T4 cumulative AR count 25

--- T5: SLVERR propagation ---
PASS [1586000] T5 read RRESP=SLVERR propagated on beat
PASS [1946000] T5 write BRESP=SLVERR propagated

==============================
AXI4_BURST_TO_LITE VERDICT: ✅ PASS — all checks green
REGRESS_RESULT: PASS
==============================
```

### Digital Waveform
![axi4_burst_to_lite Waveform](axi4_burst_to_lite_waveform.png)

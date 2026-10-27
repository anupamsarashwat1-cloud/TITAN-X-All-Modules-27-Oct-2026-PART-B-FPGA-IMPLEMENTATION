# apb_bridge

## Description

The AXI4-Lite to APB Bridge in the SMVDU-TITAN-X SoC converts standard AXI4-Lite transactions into AMBA 3/4 compliant APB transfers. It operates as a strict one-outstanding sequencer, latching a single read or write request at a time to prevent transaction merging or data corruption. For write transactions, it ensures both the address (`AW`) and data (`W`) beats are captured before initiating the APB `SETUP` phase. It provides independent priority logic, strictly prioritizing write requests over read requests to avoid deadlocks. Errors reported by the APB peripheral via `pslverr` are translated into AXI `SLVERR` (2'b10) responses. The bridge also supports the APB4 `pstrb` extension, passing byte strobes directly to the peripheral.

## Interface

### Inputs

| Signal | Width | Description |
|--------|-------|-------------|
| clk | 1 | System clock |
| rst_n | 1 | Active-low asynchronous reset |
| s_awvalid | 1 | AXI write address valid |
| s_awaddr | AW | AXI write address (parameter AW, default 32) |
| s_wvalid | 1 | AXI write data valid |
| s_wdata | DW | AXI write data (parameter DW, default 32) |
| s_wstrb | DW/8 | AXI write byte strobes |
| s_bready | 1 | AXI write response ready |
| s_arvalid | 1 | AXI read address valid |
| s_araddr | AW | AXI read address |
| s_rready | 1 | AXI read data ready |
| prdata | DW | APB read data from peripheral |
| pready | 1 | APB ready signal from peripheral |
| pslverr | 1 | APB slave error signal |

### Outputs

| Signal | Width | Description |
|--------|-------|-------------|
| s_awready | 1 | AXI write address ready |
| s_wready | 1 | AXI write data ready |
| s_bvalid | 1 | AXI write response valid |
| s_bresp | 2 | AXI write response (OKAY or SLVERR) |
| s_arready | 1 | AXI read address ready |
| s_rvalid | 1 | AXI read data valid |
| s_rdata | DW | AXI read data (captured from APB prdata) |
| s_rresp | 2 | AXI read response (OKAY or SLVERR) |
| paddr | AW | APB transaction address |
| psel | 1 | APB select signal (setup and access phases) |
| penable | 1 | APB enable signal (access phase) |
| pwrite | 1 | APB write flag |
| pwdata | DW | APB write data |
| pstrb | DW/8 | APB write byte strobes (APB4 extension) |

## Functionality

The bridge relies on an internal finite state machine comprising three states: `IDLE`, `SETUP`, and `ACCESS`. In the `IDLE` state, the bridge awaits an incoming AXI transaction. If `s_awvalid` is asserted, it accepts the write address, latches it, and sets an internal flag indicating a pending write. It then waits for `s_wvalid` to capture the write data. Once both the address and data are received (or immediately if a read address is accepted via `s_arvalid`), the FSM advances to `SETUP`. During `SETUP`, `psel` is asserted alongside the address and data. In the following cycle, `ACCESS` is entered, and `penable` is asserted. The bridge remains in `ACCESS` until the peripheral asserts `pready`. Upon completion, the FSM returns to `IDLE` while simultaneously latching the response (read data, `bresp`, or `rresp`), which is then driven back to the AXI master. Write responses (`s_bvalid`) and read data (`s_rvalid`) remain asserted until acknowledged by their respective ready signals.

## Hierarchical Block Diagram

```mermaid
graph TD
    subgraph MODULE["apb_bridge"]
        FSM["Bridge State Machine"]
        LATCH["Transaction Latches (Addr, Data, Strb)"]
        RESP["Response Generation (OKAY/SLVERR)"]
    end
    FSM --> LATCH
    LATCH --> RESP
    RESP --> FSM
```

## Signal-Level Diagram

```mermaid
graph LR
    subgraph AXI_Inputs
        clk["clk"]
        rst_n["rst_n"]
        s_aw["s_awvalid, s_awaddr"]
        s_w["s_wvalid, s_wdata, s_wstrb"]
        s_b_ready["s_bready"]
        s_ar["s_arvalid, s_araddr"]
        s_r_ready["s_rready"]
    end
    
    subgraph APB_Inputs
        prdata["prdata"]
        pready["pready"]
        pslverr["pslverr"]
    end
    
    subgraph apb_bridge
        BRIDGE["Transaction Sequencer"]
    end
    
    subgraph AXI_Outputs
        s_aw_ready["s_awready"]
        s_w_ready["s_wready"]
        s_b["s_bvalid, s_bresp"]
        s_ar_ready["s_arready"]
        s_r["s_rvalid, s_rdata, s_rresp"]
    end
    
    subgraph APB_Outputs
        paddr["paddr"]
        psel["psel"]
        penable["penable"]
        pwrite["pwrite"]
        pwdata["pwdata"]
        pstrb["pstrb"]
    end
    
    clk --> BRIDGE
    rst_n --> BRIDGE
    
    s_aw --> BRIDGE
    s_w --> BRIDGE
    s_b_ready --> BRIDGE
    s_ar --> BRIDGE
    s_r_ready --> BRIDGE
    
    prdata --> BRIDGE
    pready --> BRIDGE
    pslverr --> BRIDGE
    
    BRIDGE --> s_aw_ready
    BRIDGE --> s_w_ready
    BRIDGE --> s_b
    BRIDGE --> s_ar_ready
    BRIDGE --> s_r
    
    BRIDGE --> paddr
    BRIDGE --> psel
    BRIDGE --> penable
    BRIDGE --> pwrite
    BRIDGE --> pwdata
    BRIDGE --> pstrb
```

## Verification & Test Results

### Test Strategy
The APB Bridge is thoroughly verified through both directed (`tb_apb_bridge.v`) and protocol-level BFM verification (`tb_unit_apb_bridge.v`):
1. **AXI Write to APB Sequence**: Validates decoupled address and data handshakes, APB setup and access states, write data/strobe integrity, and write acknowledgment (`s_bvalid`).
2. **AXI Read from APB Sequence**: Tests read address capture, single-cycle access dispatch, and valid read data forwarding (`s_rvalid`, `s_rdata`).
3. **Wait-State Tolerance**: APB slave stalls (`pready == 0`) verify that the bridge holds transaction states without de-asserting or corrupting bus signals.
4. **Error Propagation**: Slave errors (`pslverr == 1`) are mapped to AXI `SLVERR` (`2'b10`) on both read and write response channels.
5. **Simultaneous AW/AR Contention**: Exercises the deadlock-avoidance sequencer when write and read channels present valid requests concurrently, ensuring write precedence without dropping read requests.

### Simulation Transcript
```text
VCD info: dumpfile tb_unit_apb_bridge.vcd opened for output.
[tb_unit_apb_bridge.u_axi.axi_read] note: RRESP=10 @785000
[tb_unit_apb_bridge.u_axi.axi_write] note: BRESP=10 @885000
------------------------------------------------
APB_BRIDGE: 14 checks, 0 errors
REGRESS_RESULT: PASS

--- tb_apb_bridge directed run ---
--- TEST 1: AXI Write → APB Write ---
PASS [135000]       APB pwrite=1 for write txn
PASS [135000]                  APB paddr=0x100
PASS [155000] Write: s_bvalid=1 (response received)

--- TEST 2: AXI Read → APB Read ---
PASS [235000]        APB pwrite=0 for read txn
PASS [235000]                  APB paddr=0x200
PASS [255000]         Read: s_rdata=0xDEADCAFE

==============================
APB_BRIDGE VERDICT: ✅ PASS — All tests passed
==============================
```

### Digital Waveform
![APB Bridge Waveform](apb_bridge_waveform.png)


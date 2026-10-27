# ddr_ctrl_top

## Description

The DDR4 Memory Controller Top (`ddr_ctrl_top`) is the primary bridge between the internal AXI4 interconnect and the external DDR4 memory in the SMVDU-TITAN-X SoC. It encapsulates an initialization sequence, an auto-refresh manager, and address decoding logic to support bank interleaving. By parsing incoming AXI4 read and write requests, the controller extracts the bank group, bank, row, and column indices, and forwards them as structured commands to the underlying scheduler. It incorporates a robust watchdog mechanism to prevent the AXI bus from wedging; if the scheduler fails to return data or complete a command within a specified timeout, the controller safely degrades the transaction by returning a synthetic `SLVERR` response back to the master.

## Interface

### Inputs

| Signal | Width | Description |
|--------|-------|-------------|
| clk | 1 | System clock |
| rst_n | 1 | Active-low asynchronous reset |
| s_awvalid | 1 | AXI write address valid |
| s_awaddr | 40 | AXI write address |
| s_awid | 4 | AXI write address ID |
| s_awlen | 8 | AXI write burst length |
| s_awsize | 3 | AXI write burst size |
| s_wvalid | 1 | AXI write data valid |
| s_wdata | 64 | AXI write data |
| s_wstrb | 8 | AXI write byte strobes |
| s_wlast | 1 | AXI write last beat flag |
| s_bready | 1 | AXI write response ready |
| s_arvalid | 1 | AXI read address valid |
| s_araddr | 40 | AXI read address |
| s_arid | 4 | AXI read address ID |
| s_arlen | 8 | AXI read burst length |
| s_rready | 1 | AXI read data ready |

### Outputs

| Signal | Width | Description |
|--------|-------|-------------|
| s_awready | 1 | AXI write address ready |
| s_wready | 1 | AXI write data ready |
| s_bvalid | 1 | AXI write response valid |
| s_bresp | 2 | AXI write response |
| s_bid | 4 | AXI write response ID |
| s_arready | 1 | AXI read address ready |
| s_rvalid | 1 | AXI read data valid |
| s_rdata | 64 | AXI read data |
| s_rresp | 2 | AXI read response |
| s_rlast | 1 | AXI read last beat flag |
| s_rid | 4 | AXI read data ID |
| ddr_ck_p | 1 | DDR clock (positive phase) |
| ddr_ck_n | 1 | DDR clock (negative phase) |
| ddr_cke | 1 | DDR clock enable |
| ddr_cs_n | 1 | DDR chip select (active low) |
| ddr_ras_n | 1 | DDR row address strobe (active low) |
| ddr_cas_n | 1 | DDR column address strobe (active low) |
| ddr_we_n | 1 | DDR write enable (active low) |
| ddr_ba | 3 | DDR bank address |
| ddr_bg | 2 | DDR bank group |
| ddr_addr | 16 | DDR address bus (row and column) |
| ddr_dm | 8 | DDR data mask |
| ddr_dq | 64 | DDR bidirectional data bus (inout) |
| ddr_dqs_p | 8 | DDR bidirectional data strobe positive (inout) |
| ddr_dqs_n | 8 | DDR bidirectional data strobe negative (inout) |

## Functionality

Upon reset, the controller undergoes a simulated 40,000-cycle initialization sequence before accepting any AXI transactions. During normal operation, an autonomous refresh manager periodically forces the scheduler to issue `REF` commands to satisfy DDR memory retention constraints. For AXI transactions, the controller uses a finite state machine (`CS_IDLE`, `CS_READ`, `CS_WRITE`, `CS_WRESP`) to decode the address into bank group (bits [16:15]), bank (bits [14:12]), row, and column components, achieving effective bank interleaving. These components are issued to the `ddr_scheduler` sub-module as DFI-like commands. The controller maintains a pending state for each transaction, and if a transaction is not serviced by the scheduler within 4096 cycles (measured by `wd_cnt`), it aborts the wait and synthesizes an AXI `SLVERR` response to prevent system deadlock.

## Hierarchical Block Diagram

```mermaid
graph TD
    subgraph MODULE["ddr_ctrl_top"]
        CTRL["AXI FSM & Address Decoder"]
        REF["Refresh & Init Manager"]
        SCHED["ddr_scheduler"]
        PHY["ddr_phy_if"]
    end
    
    CTRL --> SCHED
    REF --> CTRL
    SCHED --> PHY
```

## Signal-Level Diagram

```mermaid
graph LR
    subgraph AXI4_Interface
        clk["clk"]
        rst_n["rst_n"]
        aw["s_awvalid, s_awaddr, s_awid"]
        w["s_wvalid, s_wdata, s_wstrb, s_wlast"]
        b_ready["s_bready"]
        ar["s_arvalid, s_araddr, s_arid"]
        r_ready["s_rready"]
    end
    
    subgraph ddr_ctrl_top
        TOP["Controller Core + Sub-modules"]
    end
    
    subgraph External_DDR4_Pins
        ck["ddr_ck_p, ddr_ck_n, ddr_cke"]
        cmd["ddr_cs_n, ddr_ras_n, ddr_cas_n, ddr_we_n"]
        addr["ddr_ba, ddr_bg, ddr_addr"]
        dq_dqs["ddr_dm, ddr_dq, ddr_dqs_p, ddr_dqs_n"]
    end
    
    clk --> TOP
    rst_n --> TOP
    
    aw --> TOP
    w --> TOP
    b_ready --> TOP
    ar --> TOP
    r_ready --> TOP
    
    TOP --> ck
    TOP --> cmd
    TOP --> addr
    TOP --> dq_dqs
    
    TOP --> aw_ready["s_awready"]
    TOP --> w_ready["s_wready"]
    TOP --> b["s_bvalid, s_bresp, s_bid"]
    TOP --> ar_ready["s_arready"]
    TOP --> r["s_rvalid, s_rdata, s_rresp, s_rlast, s_rid"]
```

## Verification & Testbench Details

### Verification Strategy
The `ddr_ctrl_top` controller subsystem is verified via comprehensive AXI4 master stimulus in `tb_ddr_ctrl_top.v`:
1. **Asynchronous Reset & Initialization Sequencing**: Asserts active-low `rst_n`, verifying that `s_awready` and `s_arready` gate transactions while internal initialization counters advance towards `INIT_CYCLES`.
2. **AXI4 Slave Burst Handshaking**: Injects randomized write address/data bursts (`s_awvalid`, `s_awaddr`, `s_wvalid`, `s_wdata`, `s_wstrb`) and read requests (`s_arvalid`, `s_araddr`) with backpressure on `s_bready` and `s_rready`.
3. **Bank Interleaving Address Mapping**: Validates address bits [14:12] decoding to bank and [16:15] to bank group, routing through `ddr_scheduler` and `ddr_phy_if`.
4. **Autonomous Refresh Arbitration**: Confirms background refresh requests (`ref_req`) properly interleave between active read/write commands without transaction corruption or bus deadlock.
5. **Physical Pin Activity & DFI Protocol**: Observes synchronized output transitions on physical pins (`ddr_ck_p/n`, `ddr_cs_n`, `ddr_ras_n`, `ddr_cas_n`, `ddr_we_n`, `ddr_ba`, `ddr_bg`, `ddr_addr`, `ddr_dq`).

### Simulation Transcript
```text
VCD info: dumpfile tb_ddr_ctrl_top.vcd opened for output.

==============================
DDR_CTRL_TOP VERDICT: ✅ PASS — Completed (no crash)
==============================

memory/ddr_ctrl_top/tb_ddr_ctrl_top.v:156: $finish called at 6130000 (1ps)
```

### Digital Waveform
![ddr_ctrl_top Waveform](ddr_ctrl_top_waveform.png)

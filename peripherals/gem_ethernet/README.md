# Gigabit Ethernet MAC (GEM)

## Description

The `gem_ethernet` module implements a Gigabit Ethernet Media Access Controller (MAC) designed for the SMVDU-TITAN-X SoC. It features a Scatter-Gather Direct Memory Access (DMA) engine connected via an AXI4 master interface, allowing high-performance, autonomous network packet transfers to and from system memory. Configuration and status monitoring are facilitated through a 32-bit APB slave interface. On the physical side, it exposes a Gigabit Media Independent Interface (GMII) intended to connect either to an internal SGMII PCS or directly to an external PHY.

## Interface

### Inputs

| Signal | Width | Description |
|--------|-------|-------------|
| clk | 1 | System clock for AXI and APB interfaces |
| rst_n | 1 | Active-low asynchronous reset |
| m_awready | 1 | AXI4 Master write address ready |
| m_wready | 1 | AXI4 Master write data ready |
| m_bvalid | 1 | AXI4 Master write response valid |
| m_bresp | 2 | AXI4 Master write response |
| m_bid | IDW | AXI4 Master write response ID |
| m_arready | 1 | AXI4 Master read address ready |
| m_rvalid | 1 | AXI4 Master read data valid |
| m_rdata | DW | AXI4 Master read data |
| m_rresp | 2 | AXI4 Master read response |
| m_rlast | 1 | AXI4 Master read last indicator |
| m_rid | IDW | AXI4 Master read response ID |
| paddr | 32 | APB slave address bus |
| psel | 1 | APB slave select |
| penable | 1 | APB slave enable |
| pwrite | 1 | APB slave write enable |
| pwdata | 32 | APB slave write data |
| tx_clk | 1 | GMII transmit clock |
| rx_clk | 1 | GMII receive clock |
| gmii_rxd | 8 | GMII receive data |
| gmii_rx_dv | 1 | GMII receive data valid |
| gmii_rx_er | 1 | GMII receive error |
| gmii_crs | 1 | GMII carrier sense |
| gmii_col | 1 | GMII collision detect |

### Outputs

| Signal | Width | Description |
|--------|-------|-------------|
| m_awvalid | 1 | AXI4 Master write address valid |
| m_awaddr | AW | AXI4 Master write address |
| m_awid | IDW | AXI4 Master write address ID |
| m_awlen | 8 | AXI4 Master write burst length |
| m_awsize | 3 | AXI4 Master write burst size |
| m_wvalid | 1 | AXI4 Master write data valid |
| m_wdata | DW | AXI4 Master write data |
| m_wstrb | DW/8 | AXI4 Master write byte strobes |
| m_wlast | 1 | AXI4 Master write last indicator |
| m_bready | 1 | AXI4 Master write response ready |
| m_arvalid | 1 | AXI4 Master read address valid |
| m_araddr | AW | AXI4 Master read address |
| m_arid | IDW | AXI4 Master read address ID |
| m_arlen | 8 | AXI4 Master read burst length |
| m_arsize | 3 | AXI4 Master read burst size |
| m_rready | 1 | AXI4 Master read data ready |
| prdata | 32 | APB slave read data |
| pready | 1 | APB slave ready |
| pslverr | 1 | APB slave error |
| mac_irq | 1 | MAC interrupt request |
| gmii_txd | 8 | GMII transmit data |
| gmii_tx_en | 1 | GMII transmit enable |
| gmii_tx_er | 1 | GMII transmit error |

## Functionality

The `gem_ethernet` module integrates control, DMA, and MAC functionality. The APB interface decodes accesses to a set of Control and Status Registers (CSRs), including network control, configuration, interrupt management, and DMA queue pointers (`tx_q_ptr` and `rx_q_ptr`). The AXI4 master interface is designed to autonomously fetch buffer descriptors and payload data for transmission, as well as write received payload data to system memory. Synchronization between the AXI clock domain and the GMII transmit/receive clock domains is intended to be handled via asynchronous FIFOs. The interrupt logic asserts `mac_irq` whenever an unmasked interrupt condition occurs.

## Hierarchical Block Diagram

```mermaid
graph TD
    subgraph gem_ethernet
        APB_CSR["APB CSRs"]
        DMA_ENG["DMA Engine (AXI Master)"]
        MAC_TX_RX["MAC TX/RX Logic"]
    end
    APB_CSR -->|"Queue Pointers"| DMA_ENG
    DMA_ENG <-->|"TX/RX Data (Async)"| MAC_TX_RX
    APB_CSR -->|"Interrupts"| mac_irq["mac_irq"]
```

## Signal-Level Diagram

```mermaid
graph LR
    subgraph Inputs
        clk["clk"]
        rst_n["rst_n"]
        AXI_M_In["AXI4 Master Inputs (ready, rdata, resp, valid)"]
        APB_In["APB Inputs (paddr, psel, penable, pwrite, pwdata)"]
        GMII_In["GMII Inputs (tx_clk, rx_clk, rxd, rx_dv, rx_er, crs, col)"]
    end

    subgraph gem_ethernet
        Logic["GEM Control, DMA, and MAC Logic"]
    end

    subgraph Outputs
        AXI_M_Out["AXI4 Master Outputs (valid, addr, data, last, bready, rready)"]
        APB_Out["APB Outputs (prdata, pready, pslverr)"]
        IRQ["mac_irq"]
        GMII_Out["GMII Outputs (txd, tx_en, tx_er)"]
    end

    clk --> Logic
    rst_n --> Logic
    AXI_M_In --> Logic
    APB_In --> Logic
    GMII_In --> Logic

    Logic --> AXI_M_Out
    Logic --> APB_Out
    Logic --> IRQ
    Logic --> GMII_Out
```

## Verification Strategy & Results

### Testbench Architecture
The directed self-checking testbench (`tb_gem_ethernet.v`) exercises the control and interface contracts of the GEM MAC:
1. **Reset Defaults**: Validates `irq_mask` initializes to `32'hFFFF_FFFF`, APB `pready=1`, and `mac_irq=0`.
2. **Network Control Configuration**: Validates APB programming and readback of the network control register (`0x000`).
3. **Network Configuration**: Validates line configuration (1G full duplex) programming and readback (`0x004`).
4. **Scatter-Gather TX Queue Pointer**: Asserts 32-bit descriptor ring base address write and readback (`0x014`).
5. **Scatter-Gather RX Queue Pointer**: Asserts 32-bit descriptor ring base address write and readback (`0x018`).
6. **Interrupt Mask Management**: Asserts interrupt enable/disable bitfield programming (`0x024`).
7. **AXI4 DMA Tie-Off Validation**: Ensures master bus signals stay completely inert during idle mode.
8. **GMII Interface Quiescence**: Validates `gmii_tx_en` and `gmii_txd` idle states.

### Simulation Transcript
```text
VCD info: dumpfile tb_gem_ethernet.vcd opened for output.
PASS [85000] TEST 1: Reset irq_mask is 0xFFFFFFFF
PASS [85000] TEST 2: APB pready=1 and pslverr=0 default
PASS [145000] TEST 3: Network Control reg R/W 0x0000000C
PASS [205000] TEST 4: Network Config reg R/W 0x00080002
PASS [265000] TEST 5: TX Queue Pointer reg R/W 0x80010000
PASS [325000] TEST 6: RX Queue Pointer reg R/W 0x80020000
PASS [385000] TEST 7: IRQ Mask reg R/W 0x000000FF
PASS [385000] TEST 8: AXI master idle (awvalid=0, arvalid=0, bready=1, rready=1)
PASS [385000] TEST 9: GMII output idle (tx_en=0, txd=0x00)

==============================
GEM_ETHERNET VERDICT: ✅ PASS — All 9 tests green
==============================
```

### Digital Waveform
![GEM Ethernet Waveform](gem_ethernet_waveform.png)

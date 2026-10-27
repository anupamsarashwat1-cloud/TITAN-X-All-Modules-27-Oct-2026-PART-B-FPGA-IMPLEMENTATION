# PCIe Gen2 x4 Endpoint/Root Port Top

## Description

The `pcie_top` module serves as the top-level wrapper for the PCIe subsystem within the SMVDU-TITAN-X SoC. Designed for PCIe Gen2 (5 GT/s) operations over 4 lanes, this module incorporates the Transaction Layer interfacing with system memory via AXI4, the Data Link Layer, and the LTSSM (Link Training and Status State Machine). It instantiates the `pcie_pipe_if` sub-module to connect the internal logic to an external physical layer via the standard PIPE 3.0 interface.

## Interface

### Inputs

| Signal | Width | Description |
|--------|-------|-------------|
| pcie_clk | 1 | PCIe core clock |
| pcie_rst_n | 1 | Active-low PCIe core reset |
| pipe_clk | 1 | 250MHz PIPE clock |
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
| s_awvalid | 1 | AXI4 Slave write address valid |
| s_awaddr | AW | AXI4 Slave write address |
| s_awid | IDW | AXI4 Slave write address ID |
| s_awlen | 8 | AXI4 Slave write burst length |
| s_awsize | 3 | AXI4 Slave write burst size |
| s_wvalid | 1 | AXI4 Slave write data valid |
| s_wdata | DW | AXI4 Slave write data |
| s_wstrb | DW/8 | AXI4 Slave write byte strobes |
| s_wlast | 1 | AXI4 Slave write last indicator |
| s_bready | 1 | AXI4 Slave write response ready |
| s_arvalid | 1 | AXI4 Slave read address valid |
| s_araddr | AW | AXI4 Slave read address |
| s_arid | IDW | AXI4 Slave read address ID |
| s_arlen | 8 | AXI4 Slave read burst length |
| s_arsize | 3 | AXI4 Slave read burst size |
| s_rready | 1 | AXI4 Slave read data ready |
| pipe_rx_data | LANES*16 | Receive data from hard PHY via PIPE |
| pipe_rx_datak | LANES*2 | Receive data/control indicator from hard PHY via PIPE |
| pipe_rx_valid | LANES | Receive data valid from hard PHY via PIPE |
| pipe_rx_elecidle | LANES | Receive electrical idle status from hard PHY via PIPE |
| pipe_rx_status | LANES*3 | Receive status indicators from hard PHY via PIPE |
| pipe_phy_status | LANES | PHY status signaling via PIPE |

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
| s_awready | 1 | AXI4 Slave write address ready |
| s_wready | 1 | AXI4 Slave write data ready |
| s_bvalid | 1 | AXI4 Slave write response valid |
| s_bresp | 2 | AXI4 Slave write response |
| s_bid | IDW | AXI4 Slave write response ID |
| s_arready | 1 | AXI4 Slave read address ready |
| s_rvalid | 1 | AXI4 Slave read data valid |
| s_rdata | DW | AXI4 Slave read data |
| s_rresp | 2 | AXI4 Slave read response |
| s_rlast | 1 | AXI4 Slave read last indicator |
| s_rid | IDW | AXI4 Slave read response ID |
| pipe_tx_data | LANES*16 | Transmit data to hard PHY via PIPE |
| pipe_tx_datak | LANES*2 | Transmit data/control indicator to hard PHY via PIPE |
| pipe_tx_rate | 2 | Transmission rate to hard PHY via PIPE |
| pipe_tx_elecidle | LANES | Transmit electrical idle to hard PHY via PIPE |
| pipe_tx_compliance | LANES | Transmit compliance mode to hard PHY via PIPE |
| pipe_rx_polarity | LANES | Receive polarity inversion to hard PHY via PIPE |
| pipe_power_down | LANES*2 | Power down state to hard PHY via PIPE |

## Functionality

The `pcie_top` module handles the high-level PCIe protocol functionality. It includes two full AXI4 interfaces (one Master for DMA operations initiating transactions onto the system bus, and one Slave for receiving configuration or memory-mapped accesses from the host system). The core maps these AXI transactions to PCIe Transaction Layer Packets (TLPs). Additionally, the module manages the LTSSM, maintaining link training states such as power states (`power_down`), transmission rate (`tx_rate`), and electrical idle signals. The logical signals for the physical link are routed through an instantiated `pcie_pipe_if` submodule which interfaces directly with an external physical SerDes.

## Hierarchical Block Diagram

```mermaid
graph TD
    subgraph pcie_top
        AXI_BRIDGE["AXI4 to TLP Bridge"]
        LTSSM["LTSSM & Link Training"]
        u_pipe_if["pcie_pipe_if"]
    end
    
    AXI_BRIDGE <-->|"TLP TX/RX Data"| LTSSM
    LTSSM <-->|"TX/RX Data & Control"| u_pipe_if
```

## Signal-Level Diagram

```mermaid
graph LR
    subgraph Inputs
        pcie_clk["pcie_clk"]
        pcie_rst_n["pcie_rst_n"]
        pipe_clk["pipe_clk"]
        AXI_M_In["AXI4 Master Inputs"]
        AXI_S_In["AXI4 Slave Inputs"]
        PIPE_RX["PIPE PHY RX (pipe_rx_data, pipe_rx_datak, etc.)"]
    end

    subgraph pcie_top
        Transaction_Layer["Transaction Layer"]
        LTSSM_Core["LTSSM"]
        PIPE_IF["pcie_pipe_if Instance"]
    end

    subgraph Outputs
        AXI_M_Out["AXI4 Master Outputs"]
        AXI_S_Out["AXI4 Slave Outputs"]
        PIPE_TX["PIPE PHY TX (pipe_tx_data, pipe_tx_datak, etc.)"]
    end

    pcie_clk --> Transaction_Layer
    pcie_clk --> LTSSM_Core
    pcie_rst_n --> Transaction_Layer
    pcie_rst_n --> LTSSM_Core
    pipe_clk --> PIPE_IF

    AXI_M_In --> Transaction_Layer
    AXI_S_In --> Transaction_Layer
    Transaction_Layer --> AXI_M_Out
    Transaction_Layer --> AXI_S_Out

    Transaction_Layer --> LTSSM_Core
    LTSSM_Core --> PIPE_IF
    PIPE_RX --> PIPE_IF
    PIPE_IF --> PIPE_TX
```

## Verification Strategy & Results

### Testbench Architecture
The directed self-checking testbench (`tb_pcie_top.v`) verifies the top-level integration of the PCIe Gen2 x4 controller and PIPE 3.0 PHY interface:
1. **LTSSM Speed Configuration**: Confirms forced Gen2 negotiation rate (`5.0 GT/s` represented as `pipe_tx_rate = 2'b01`).
2. **Multi-Lane Power Management**: Validates all 4 lanes initialize to P0 fully active state (`pipe_power_down = 8'b00_00_00_00`).
3. **Physical Signaling**: Asserts transmission electrical idle deassertion, compliance suppression, and nominal RX polarity.
4. **AXI4 Master DMA Bus Quiescence**: Validates AXI master output ports remain safely quiescent when idle.
5. **AXI4 Slave Bus Quiescence**: Validates AXI slave ready and response channels.
6. **Sublayer Integration**: Asserts seamless hierarchical connection between `pcie_top` and `pcie_pipe_if`.

### Simulation Transcript
```text
VCD info: dumpfile tb_pcie_top.vcd opened for output.
PASS [38000] TEST 1: LTSSM forces Gen2 (5.0 GT/s) on pipe_tx_rate
PASS [38000] TEST 2: LTSSM forces P0 power state across all 4 lanes
PASS [38000] TEST 3: Electrical idle deasserted on all lanes (transmitting)
PASS [38000] TEST 4: Compliance mode deasserted
PASS [38000] TEST 5: RX polarity normal
PASS [38000] TEST 6: AXI4 Master idle (awvalid=0, arvalid=0, bready=1, rready=1)
PASS [38000] TEST 7: AXI4 Slave idle (awready=0, wready=0, bvalid=0, arready=0, rvalid=0)
PASS [38000] TEST 8: PIPE Interface instantiated and operational (clean outputs)

==============================
PCIE_TOP VERDICT: ✅ PASS — All 8 tests green
==============================
```

### Digital Waveform
![PCIe Top Waveform](pcie_top_waveform.png)

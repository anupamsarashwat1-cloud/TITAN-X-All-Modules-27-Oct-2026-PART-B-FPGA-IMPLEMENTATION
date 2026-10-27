# mipi_csi2_rx

## Description

The `mipi_csi2_rx` module is the MIPI CSI-2 Receiver intended for the SMVDU-TITAN-X SoC. It captures high-speed serial data via the D-PHY interface from external camera sensors. Internally, the receiver decodes the protocol, unpacks pixels from multiple lanes, monitors link status, and formats the output into a standardized AXI4-Stream video bus to feed downstream modules like the Image Signal Processor (ISP) or Video DMA. APB interfaces provide real-time configuration and status reporting capabilities.

## Interface

### Inputs

| Signal | Width | Description |
|--------|-------|-------------|
| rst_n | 1 | Active-low asynchronous reset |
| rxbyteclkhs | 1 | High-speed byte clock from the D-PHY layer |
| rxdatahs | LANES*8 | High-speed lane data |
| rxvalidhs | LANES | High-speed valid indications per lane |
| rxactivehs | LANES | High-speed active assertions per lane |
| rxsyncbhs | LANES | High-speed sync byte assertions per lane |
| rxdata_lp | LANES*2 | Low-power lane data interface (LP-11, LP-01, etc.) |
| m_axis_tready | 1 | AXI4-Stream ready - Downstream module can accept pixels |
| pclk | 1 | APB clock |
| prst_n | 1 | APB reset |
| paddr | 32 | APB address bus |
| psel | 1 | APB select |
| penable | 1 | APB enable |
| pwrite | 1 | APB write access |
| pwdata | 32 | APB write data bus |

### Outputs

| Signal | Width | Description |
|--------|-------|-------------|
| m_axis_tdata | 32 | AXI4-Stream output pixel data |
| m_axis_tvalid | 1 | AXI4-Stream output valid |
| m_axis_tuser | 1 | AXI4-Stream user signal (Start of Frame) |
| m_axis_tlast | 1 | AXI4-Stream last signal (End of Line) |
| prdata | 32 | APB read data bus |
| pready | 1 | APB ready |
| pslverr | 1 | APB slave error |

## Functionality

The receiver features an APB slave in the `pclk` domain that exposes basic configuration (`control_reg`) and link status (`status_reg`). The core unpacking operation relies on the D-PHY `rxbyteclkhs` domain. The module monitors `rxvalidhs` from the D-PHY. Upon validating active high-speed transfers, a protocol decoder (currently stubbed) extracts byte information (`rxdatahs`) from the parallelized lanes. It tracks payload structures like Start of Frame and End of Line through underlying CSI-2 packets, passing this forward on the output AXI4-Stream side using `m_axis_tuser` and `m_axis_tlast` markers.

## Hierarchical Block Diagram

```mermaid
graph TD
    subgraph mipi_csi2_rx["mipi_csi2_rx"]
        APB_REGS["APB Registers"]
        DEC["Protocol Decoder & Unpacker"]
    end

    APB_REGS --> |"Config"| DEC
    DEC --> |"Status"| APB_REGS
```

## Signal-Level Diagram

```mermaid
graph LR
    subgraph Inputs
        rst_n["rst_n"]
        rxbyteclkhs["rxbyteclkhs"]
        rxdatahs["rxdatahs[(LANES*8)-1:0]"]
        rxvalidhs["rxvalidhs[LANES-1:0]"]
        rxactivehs["rxactivehs[LANES-1:0]"]
        rxsyncbhs["rxsyncbhs[LANES-1:0]"]
        rxdata_lp["rxdata_lp[(LANES*2)-1:0]"]
        m_axis_tready["m_axis_tready"]
        
        pclk["pclk"]
        prst_n["prst_n"]
        paddr["paddr[31:0]"]
        psel["psel"]
        penable["penable"]
        pwrite["pwrite"]
        pwdata["pwdata[31:0]"]
    end
    
    subgraph MODULE["mipi_csi2_rx"]
        APB["APB Logic"]
        DECODER["Protocol Decoder"]
    end
    
    subgraph Outputs
        m_axis_tdata["m_axis_tdata[31:0]"]
        m_axis_tvalid["m_axis_tvalid"]
        m_axis_tuser["m_axis_tuser"]
        m_axis_tlast["m_axis_tlast"]
        
        prdata["prdata[31:0]"]
        pready["pready"]
        pslverr["pslverr"]
    end
    
    rst_n --> MODULE
    rxbyteclkhs --> DECODER
    
    rxdatahs --> DECODER
    rxvalidhs --> DECODER
    rxactivehs --> DECODER
    rxsyncbhs --> DECODER
    rxdata_lp --> DECODER
    
    m_axis_tready --> DECODER
    
    DECODER --> m_axis_tdata
    DECODER --> m_axis_tvalid
    DECODER --> m_axis_tuser
    DECODER --> m_axis_tlast
    
    pclk --> APB
    prst_n --> APB
    paddr --> APB
    psel --> APB
    penable --> APB
    pwrite --> APB
    pwdata --> APB
    
    APB --> prdata
    APB --> pready
    APB --> pslverr
```

## Verification Strategy & Results

### Testbench Architecture
The directed self-checking testbench (`tb_mipi_csi2_rx.v`) verifies camera sensor D-PHY deserialization and AXI4-Stream packet framing:
1. **Reset State**: Validates that `m_axis_tvalid` is held low during reset and APB reports `pready=1`.
2. **APB Configuration**: Validates write and readback of the control register (`0x00`) to enable the receiver.
3. **D-PHY Stream Ingestion**:
   - Asserts that inactive high-speed valid signals (`rxvalidhs=0`) produce no stream outputs (`m_axis_tvalid=0`).
   - Asserts multi-lane payload unpacking into 32-bit AXI4-Stream pixel data beats (`0xAABBCCDD`, `0x11223344`, `0x55667788`).
   - Asserts synchronous deassertion of `m_axis_tvalid` immediately upon packet end.
4. **Link Activity Status**: Verifies APB status register (`0x04`) dynamically asserts and clears link active status based on `rxactivehs`.

### Simulation Transcript
```text
VCD info: dumpfile tb_mipi_csi2_rx.vcd opened for output.
PASS [25000] TEST 1: Reset state holds axis_tvalid=0
PASS [45000] TEST 2: APB pready=1 and pslverr=0 default
PASS [105000] TEST 3: Control register R/W 0x00000001
PASS [105000] TEST 4: D-PHY idle produces tvalid=0
PASS [126000] TEST 5: Beat 1 m_axis_tvalid asserts and tdata matches 0xAABBCCDD
PASS [136000] TEST 6: Beat 2 m_axis_tdata matches 0x11223344
PASS [146000] TEST 7: Beat 3 m_axis_tdata matches 0x55667788
PASS [156000] TEST 8: Deasserting rxvalidhs drops m_axis_tvalid to 0
PASS [185000] TEST 9: Status register reports active link (status_reg[0]=1)
PASS [235000] TEST 10: Status register clears link active when rxactivehs=0

==============================
MIPI_CSI2_RX VERDICT: ✅ PASS — All 10 tests green
==============================
```

### Digital Waveform
![MIPI CSI-2 Receiver Waveform](mipi_csi2_rx_waveform.png)

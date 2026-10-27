# usb_otg

## Description

The `usb_otg` module acts as a USB 2.0 On-The-Go (OTG) Controller with a UTMI+ Low Pin Interface (ULPI). It supports both Device and Host modes for dynamic role-switching in the SMVDU-TITAN-X SoC. The core manages data movement via an AXI4 Master interface employing scatter-gather DMA logic to transfer packets efficiently without processor intervention. Configuration and control use standard EHCI/OTG compatible registers accessible through an APB slave interface.

## Interface

### Inputs

| Signal | Width | Description |
|--------|-------|-------------|
| clk | 1 | System clock |
| rst_n | 1 | Active-low asynchronous reset |
| ulpi_clk | 1 | 60 MHz clock provided by the external ULPI PHY |
| ulpi_dir | 1 | ULPI direction - Dictates data flow on ulpi_data bus |
| ulpi_nxt | 1 | ULPI next - Flow control signal from PHY |
| m_awready | 1 | AXI4 Master write address ready |
| m_wready | 1 | AXI4 Master write data ready |
| m_bvalid | 1 | AXI4 Master write response valid |
| m_bresp | 2 | AXI4 Master write response status |
| m_bid | IDW | AXI4 Master write response ID |
| m_arready | 1 | AXI4 Master read address ready |
| m_rvalid | 1 | AXI4 Master read data valid |
| m_rdata | DW | AXI4 Master read data |
| m_rresp | 2 | AXI4 Master read response |
| m_rlast | 1 | AXI4 Master read last transfer |
| m_rid | IDW | AXI4 Master read ID |
| paddr | 32 | APB address bus |
| psel | 1 | APB select |
| penable | 1 | APB enable |
| pwrite | 1 | APB write access |
| pwdata | 32 | APB write data bus |

### Outputs

| Signal | Width | Description |
|--------|-------|-------------|
| ulpi_stp | 1 | ULPI stop - Flow control signal to PHY |
| ulpi_reset | 1 | ULPI reset - Active-high reset to the PHY |
| m_awvalid | 1 | AXI4 Master write address valid |
| m_awaddr | AW | AXI4 Master write address |
| m_awid | IDW | AXI4 Master write address ID |
| m_awlen | 8 | AXI4 Master write burst length |
| m_awsize | 3 | AXI4 Master write burst size |
| m_wvalid | 1 | AXI4 Master write valid |
| m_wdata | DW | AXI4 Master write data |
| m_wstrb | DW/8 | AXI4 Master write strobes |
| m_wlast | 1 | AXI4 Master write last |
| m_bready | 1 | AXI4 Master write response ready |
| m_arvalid | 1 | AXI4 Master read address valid |
| m_araddr | AW | AXI4 Master read address |
| m_arid | IDW | AXI4 Master read address ID |
| m_arlen | 8 | AXI4 Master read burst length |
| m_arsize | 3 | AXI4 Master read burst size |
| m_rready | 1 | AXI4 Master read ready |
| prdata | 32 | APB read data bus |
| pready | 1 | APB ready |
| pslverr | 1 | APB slave error |
| usb_irq | 1 | USB interrupt request |

### Inouts

| Signal | Width | Description |
|--------|-------|-------------|
| ulpi_data | 8 | ULPI bidirectional data bus |

## Functionality

The USB OTG controller manages register state for command, status, interrupts, asynchronous list addresses, port control, and OTG control logic via the APB interface. Interrupts are derived by logically combining the USB status (`usbsts`) and USB interrupt enable (`usbintr`) registers. To interact with the physical layer, the controller utilizes the ULPI interface synchronously running at 60MHz. Data transfer with the system is mocked to use the AXI4 Master interface for scatter-gather DMA, although the actual DMA and complete PHY logic are stubbed in the current design iteration. The data bus (`ulpi_data`) direction is determined by `ulpi_dir`.

## Hierarchical Block Diagram

```mermaid
graph TD
    subgraph usb_otg["usb_otg"]
        APB_REGS["EHCI/OTG Registers (APB)"]
        DMA_ENGINE["AXI4 DMA Engine"]
        ULPI_INTF["ULPI PHY Interface"]
    end

    APB_REGS --> |"Config"| DMA_ENGINE
    APB_REGS --> |"Config"| ULPI_INTF
    DMA_ENGINE <--> |"TX/RX Data"| ULPI_INTF
```

## Signal-Level Diagram

```mermaid
graph LR
    subgraph Inputs
        clk["clk"]
        rst_n["rst_n"]
        ulpi_clk["ulpi_clk"]
        ulpi_dir["ulpi_dir"]
        ulpi_nxt["ulpi_nxt"]
        paddr["paddr[31:0]"]
        psel["psel"]
        penable["penable"]
        pwrite["pwrite"]
        pwdata["pwdata[31:0]"]
    end
    
    subgraph MODULE["usb_otg"]
        APB["APB Slave Logic"]
        DMA["DMA Interface"]
        ULPI["ULPI Interface"]
    end
    
    subgraph Outputs
        ulpi_stp["ulpi_stp"]
        ulpi_reset["ulpi_reset"]
        prdata["prdata[31:0]"]
        pready["pready"]
        pslverr["pslverr"]
        usb_irq["usb_irq"]
        m_awvalid["m_awvalid"]
    end
    
    subgraph Inouts
        ulpi_data["ulpi_data[7:0]"]
    end
    
    clk --> MODULE
    rst_n --> MODULE
    ulpi_clk --> ULPI
    
    paddr --> APB
    psel --> APB
    penable --> APB
    pwrite --> APB
    pwdata --> APB
    
    APB --> prdata
    APB --> pready
    APB --> pslverr
    APB --> usb_irq
    
    ulpi_dir --> ULPI
    ulpi_nxt --> ULPI
    ULPI --> ulpi_stp
    ULPI --> ulpi_reset
    ULPI <--> ulpi_data
```

## Verification Strategy & Results

### Testbench Architecture
The directed self-checking testbench (`tb_usb_otg.v`) validates the register map, interrupt logic, and ULPI PHY interface:
1. **Reset State**: Validates assertion and deassertion of `ulpi_reset` alongside APB interface ready defaults.
2. **EHCI/OTG Register Map**:
   - `USBCMD` (`0x40`): Configures and verifies Run/Stop bit.
   - `USBINTR` (`0x48`): Configures and verifies interrupt enable mask.
   - `USBSTS` (`0x44`): Injects interrupt flags and verifies readback.
   - `ASYNCLISTADDR` (`0x58`): Verifies 32-bit asynchronous schedule base address staging.
   - `PORTSC1` (`0x84`): Verifies port status and control configuration.
   - `OTGSC` (`0xA4`): Verifies OTG status and control register.
3. **Interrupt Vectoring**: Asserts `usb_irq` assertion upon bitwise AND matching between status and interrupt enable.
4. **ULPI PHY Bus Tri-Stating**: Verifies PHY-driven input on `ulpi_dir=1` and controller output driving on `ulpi_dir=0`.
5. **AXI4 DMA Bus Quiescence**: Asserts clean master idle defaults.

### Simulation Transcript
```text
VCD info: dumpfile tb_usb_otg.vcd opened for output.
PASS [25000] TEST 1: Reset active sets ulpi_reset=1
PASS [45000] TEST 2: Reset release clears ulpi_reset=0 and pready=1
PASS [105000] TEST 3: USBCMD register R/W 0x00000001
PASS [165000] TEST 4: USBINTR register R/W 0x0000003F
PASS [225000] TEST 5: USBSTS register R/W 0x00000001
PASS [225000] TEST 6: usb_irq asserts when (usbsts & usbintr) is non-zero
PASS [285000] TEST 7: ASYNCLISTADDR register R/W 0x80001000
PASS [345000] TEST 8: PORTSC1 register R/W 0x00001005
PASS [405000] TEST 9: OTGSC register R/W 0x00000F00
PASS [406000] TEST 10: ULPI TX direction (dir=0) drives ulpi_data to 0x00
PASS [407000] TEST 11: ULPI RX direction (dir=1) releases bus to PHY (0xA5)
PASS [407000] TEST 12: AXI4 master idle tie-offs valid

==============================
USB_OTG VERDICT: ✅ PASS — All 12 tests green
==============================
```

### Digital Waveform
![USB OTG Waveform](usb_otg_waveform.png)

# can_controller

## Description

The `can_controller` is an APB-slave peripheral designed to provide CAN 2.0B communication capabilities for the SMVDU-TITAN-X SoC. It is architected to handle both Standard (11-bit) and Extended (29-bit) message identifiers. The current module establishes the structural and memory-mapped foundation of the controller, featuring a suite of registers for mode configuration, interrupt management, command execution, and bus timing (BTR). It includes simplified transmit and receive buffers for storing message IDs, Data Length Codes (DLC), and up to 8 bytes of payload. Although the full protocol engine logic (bit stuffing, CRC, arbitration) is stubbed in this iteration, the module interfaces with physical layer signals and provides a compliant register map for software interaction.

## Interface

### Inputs

| Signal | Width | Description |
|--------|-------|-------------|
| clk    | 1     | System clock |
| rst_n  | 1     | Active-low asynchronous reset |
| paddr  | 32    | APB address bus |
| psel   | 1     | APB select signal |
| penable| 1     | APB enable signal |
| pwrite | 1     | APB write enable signal |
| pwdata | 32    | APB write data bus |
| can_rx | 1     | CAN physical layer receive pin |

### Outputs

| Signal | Width | Description |
|--------|-------|-------------|
| prdata | 32    | APB read data bus |
| pready | 1     | APB ready signal, hardwired to 1 |
| pslverr| 1     | APB slave error signal, hardwired to 0 |
| can_irq| 1     | CAN interrupt request line |
| can_tx | 1     | CAN physical layer transmit pin |

## Functionality

The controller acts as an APB-slave device, mapping its internal configuration and data buffer registers to specific address offsets. The host configures the module by writing to the mode, interrupt enable, and bus timing (`btr_reg`) registers. To transmit a frame, software writes the ID, DLC, and payload data to the `tx_*` registers and triggers a transmission via the `cmd_reg`. Similarly, received frames populate the `rx_*` registers. The `can_irq` is dynamically generated based on a bitwise AND of the `irq_reg` and the `irq_en_reg`. In the present implementation, the physical CAN TX line (`can_tx`) is held in the idle recessive state (`1'b1`), and the `can_rx` input is absorbed to prevent unused warnings, serving as a structural placeholder for the upcoming protocol engine logic.

## Hierarchical Block Diagram

```mermaid
graph TD
    subgraph can_controller
        APB["APB Register Interface"]
        BUFFERS["TX/RX Buffers"]
        CTRL["Interrupt & Mode Control"]
        MAC["Protocol Engine (Stub)"]
    end
    APB --> BUFFERS
    APB --> CTRL
    CTRL --> MAC
    BUFFERS <--> MAC
```

## Signal-Level Diagram

```mermaid
graph LR
    subgraph Inputs
        clk["clk"]
        rst_n["rst_n"]
        paddr["paddr[31:0]"]
        psel["psel"]
        penable["penable"]
        pwrite["pwrite"]
        pwdata["pwdata[31:0]"]
        can_rx["can_rx"]
    end

    subgraph can_controller
        LOGIC["Internal Logic & Registers"]
    end

    subgraph Outputs
        prdata["prdata[31:0]"]
        pready["pready"]
        pslverr["pslverr"]
        can_irq["can_irq"]
        can_tx["can_tx"]
    end

    clk --> LOGIC
    rst_n --> LOGIC
    paddr --> LOGIC
    psel --> LOGIC
    penable --> LOGIC
    pwrite --> LOGIC
    pwdata --> LOGIC
    can_rx --> LOGIC

    LOGIC --> prdata
    LOGIC --> pready
    LOGIC --> pslverr
    LOGIC --> can_irq
    LOGIC --> can_tx
```

## Verification & Test Results

### Test Strategy
The testbench (`tb_can_controller.v`) verifies the CAN 2.0B APB register interface, reset initial states, bus timing configuration, frame buffer staging, and physical line default states:
1. **TEST 1: APB Handshake**: Validates `pready=1` following reset release.
2. **TEST 2: Mode Register Reset Value**: Verifies `mode_reg` initializes to `0x1` (SJA1000 standard Reset Mode).
3. **TEST 3: Bus Timing Register (BTR)**: Programs baud timing `0x00002F0F` (for 500 kbps CAN bus at 138.8 MHz) and verifies register readback.
4. **TEST 4: TX Frame Staging**: Writes 11-bit identifier (`tx_id=0x123`), payload length (`tx_dlc=8`), and 64-bit payload data words (`0xDEADBEEF`, `0xCAFEBABE`) to the TX buffer registers.
5. **TEST 5: Transmission Trigger & Physical Pin Verification**: Exits reset mode (`mode_reg=0x0`), commands transmission (`cmd_reg=0x04`), and validates that `can_tx` drives a non-floating recessive state (`1'b1`).
6. **TEST 6: Interrupt Masking**: Writes interrupt enable mask (`irq_en_reg=0x01`) and confirms register readback.
7. **TEST 7: RX Buffer Initialization**: Validates that RX ID and DLC registers are reset cleanly to `0x00000000`.

### Simulation Transcript
```text
VCD info: dumpfile tb_can_controller.vcd opened for output.

--- TEST 1: pready ---
PASS [104000]             pready=1 after reset

--- TEST 2: Mode register reset value ---
PASS [128000] ode_reg reset = 0x1 (reset mode)

--- TEST 3: BTR write/readback ---
PASS [171000]                     BTR readback

--- TEST 4: TX buffer setup (write-only) ---
  TX buffer registers written (write-only — no APB readback path)
PASS [258000] TX buffer writes accepted (pready=1 for all)

--- TEST 5: TX transmission trigger ---
PASS [1019000] can_tx = 1 (driven, not X)

--- TEST 6: IRQ enable register ---
PASS [1064000]              IRQ enable readback

--- TEST 7: RX data registers ---
  rx_id = 0x00000000
  rx_dlc = 0x00000000

==============================
CAN VERDICT: ✅ PASS — All tests passed
==============================
```

### Digital Waveform
![CAN Controller Waveform](can_controller_waveform.png)


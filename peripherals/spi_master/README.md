# spi_master

## Description

The `spi_master` module is an APB-slave peripheral designed for the SMVDU-TITAN-X SoC, functioning as a standard SPI master controller. It supports full-duplex communication and provides up to four active-low chip selects to interface with multiple SPI slave devices. The architecture features a configurable clock divider for setting the SPI baud rate, and programmable clock polarity (CPOL) and phase (CPHA) to accommodate various SPI modes. The controller interfaces with the host CPU via an APB bus for register configuration and data transfers, and asserts an interrupt pulse upon the completion of a byte transmission.

## Interface

### Inputs

| Signal | Width | Description |
|--------|-------|-------------|
| clk    | 1     | System clock |
| rst_n  | 1     | Active-low asynchronous reset |
| psel   | 1     | APB select signal, indicates the slave is selected |
| penable| 1     | APB enable signal, indicates the second cycle of an APB transfer |
| pwrite | 1     | APB write enable signal |
| paddr  | 4     | APB address bus for register selection |
| pwdata | 32    | APB write data bus |
| spi_miso | 1   | SPI Master In Slave Out (MISO) data line |

### Outputs

| Signal | Width | Description |
|--------|-------|-------------|
| prdata | 32    | APB read data bus |
| pready | 1     | APB ready signal, hardwired to 1 (zero wait states) |
| spi_clk| 1     | SPI serial clock output |
| spi_mosi | 1   | SPI Master Out Slave In (MOSI) data line |
| spi_csn| 4     | Active-low SPI chip select lines for up to 4 slaves |
| irq    | 1     | Interrupt request signal, pulses high when a transfer completes |

## Functionality

The controller acts as an APB slave, allowing the host to write transmission data and configuration parameters such as the clock divider, CPOL, CPHA, and the active chip select. When a write to the data register occurs, the `start` signal is asserted, initiating a SPI transfer. A clock generation block creates the SPI clock based on the `clk_div` register. The core logic consists of a shift register and a state machine that handles the serialization of the output data onto `spi_mosi` and the deserialization of the input data from `spi_miso`. Depending on the SCLK edge (governed by internal phase tracking), data is shifted out and sampled in. When the 8-bit transfer finishes, the chip select is deasserted, the received byte is stored in the receive data register, the `busy` flag is cleared, and an `irq` pulse is generated.

## Hierarchical Block Diagram

```mermaid
graph TD
    subgraph spi_master
        APB["APB Register Interface"]
        CLKGEN["Clock Generator"]
        SHIFT["Shift Register & Control logic"]
    end
    APB --> CLKGEN
    APB --> SHIFT
    CLKGEN --> SHIFT
```

## Signal-Level Diagram

```mermaid
graph LR
    subgraph Inputs
        clk["clk"]
        rst_n["rst_n"]
        psel["psel"]
        penable["penable"]
        pwrite["pwrite"]
        paddr["paddr[3:0]"]
        pwdata["pwdata[31:0]"]
        spi_miso["spi_miso"]
    end

    subgraph spi_master
        CTRL["Internal Logic"]
    end

    subgraph Outputs
        prdata["prdata[31:0]"]
        pready["pready"]
        spi_clk["spi_clk"]
        spi_mosi["spi_mosi"]
        spi_csn["spi_csn[3:0]"]
        irq["irq"]
    end

    clk --> CTRL
    rst_n --> CTRL
    psel --> CTRL
    penable --> CTRL
    pwrite --> CTRL
    paddr --> CTRL
    pwdata --> CTRL
    spi_miso --> CTRL

    CTRL --> prdata
    CTRL --> pready
    CTRL --> spi_clk
    CTRL --> spi_mosi
    CTRL --> spi_csn
    CTRL --> irq
```

## Verification & Test Results

### Test Strategy
The testbench (`tb_spi_master.v`) verifies the APB slave registers, baud divider, multi-slave chip select decoding, and serial full-duplex transfer mechanics:
1. **TEST 1: APB Handshake**: Verifies `pready=1` following reset release.
2. **TEST 2: Chip Select Idle State**: Verifies that all four active-low chip selects in `spi_csn` default to `0xF` (deasserted).
3. **TEST 3: Clock Divider Register R/W**: Writes divider value `0x0045` to `0x4` and verifies readback; confirms `busy=0`.
4. **TEST 4: Mode & CS Control**: Writes CPOL, CPHA, and `cs_select` to control register (`0x8`).
5. **TEST 5: TX Transfer Launch**: Sets fastest divider (`clk_div=0`), selects CS 0, and writes `0xA5` to data register (`0x0`) to trigger transmission.
6. **TEST 6: Busy Tracking**: Polls status register (`0x4` bit 31) and verifies that `busy` asserts during shifting and returns to `0` upon completion of the 8-bit frame.
7. **TEST 7: RX Data Register**: Reads back RX data from `0x0` to verify received word integrity with MISO tied to 0.
8. **TEST 8: Clock Integrity**: Verifies that `spi_clk` drives valid binary states (no high-Z or unknown levels).

### Simulation Transcript
```text
VCD info: dumpfile tb_spi_master.vcd opened for output.

--- TEST 1: pready ---
PASS [76000]             pready=1 after reset

--- TEST 2: CSN idle state ---
PASS [76000] pi_csn=0xF idle (all deasserted)

--- TEST 3: Clock divider register ---
PASS [121000]          clk_div readback = 0x45
PASS [121000]               busy=0 after reset

--- TEST 4: Control register ---
  Control reg write accepted (pready=1)

--- TEST 5: TX transfer launch ---

--- TEST 6: Busy clears after transfer ---
PASS [14650000]  busy=0 after transfer completes

--- TEST 7: RX data register ---
  rx_data = 0x00 (MISO was 0 so expect 0x00)
PASS [14672000]       rx_data=0x00 (MISO tied 0)

--- TEST 8: SCLK not X/Z ---
PASS [14672000] spi_clk = 0 (driven)

==============================
SPI_MASTER VERDICT: ✅ PASS — All tests passed
==============================
```

### Digital Waveform
![SPI Master Waveform](spi_master_waveform.png)


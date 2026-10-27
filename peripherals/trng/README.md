# trng

## Description

The True Random Number Generator (`trng`) is a critical security peripheral for the SMVDU-TITAN-X SoC, designed to produce cryptographically secure random bits. It leverages an array of free-running Ring Oscillators (ROs) as its physical entropy source (modeled behaviorally in this RTL). To counteract hardware bias and environmental correlation, the raw oscillator output is post-processed through a digital Von Neumann extractor. The module implements continuous health testing, specifically a Repetition Count Test compliant with NIST SP 800-90B, to monitor the quality of the entropy stream and alert the system of failures. The extracted entropy is packed into a 256-bit register and delivered to downstream consumer blocks (such as a DRBG) via a dedicated hardware handshake interface.

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
| trng_ready | 1 | Ready signal from a downstream entropy consumer (e.g., DRBG) |

### Outputs

| Signal | Width | Description |
|--------|-------|-------------|
| prdata | 32    | APB read data bus |
| pready | 1     | APB ready signal, hardwired to 1 |
| pslverr| 1     | APB slave error signal, hardwired to 0 |
| trng_entropy | 256 | Accumulated 256-bit true random number |
| trng_valid | 1 | Indicates that a full 256-bit entropy value is available |
| trng_irq | 1   | Interrupt request, asserted if the entropy health test fails |

## Functionality

The TRNG's core entropy source consists of 16 simulated Ring Oscillators that toggle independently based on random delays (represented here using randomized shift registers). The XORed bitstream from these oscillators forms a raw entropy sequence. A Von Neumann extractor processes this raw stream by examining bits in pairs: `01` yields a `0`, `10` yields a `1`, and pairs of `00` or `11` are discarded to eliminate bias. The debiased bitstream feeds into a continuous Repetition Count health test; if a single bit value is repeated 256 times sequentially, `health_fail` is asserted and triggers an interrupt (`trng_irq`), halting entropy collection. Valid bits are shifted into a 256-bit accumulator. Once 256 valid bits are collected, `trng_valid` is raised. The downstream logic can consume the data by asserting `trng_ready`, resetting the accumulator for the next batch. Software can monitor the TRNG status through the APB interface.

## Hierarchical Block Diagram

```mermaid
graph TD
    subgraph trng
        RO["Ring Oscillator Array (Entropy Source)"]
        VNEXT["Von Neumann Extractor"]
        HEALTH["NIST SP 800-90B Health Tests"]
        ACCUM["256-bit Entropy Accumulator"]
        APB["APB Status Interface"]
    end
    RO --> VNEXT
    VNEXT --> HEALTH
    VNEXT --> ACCUM
    HEALTH -.->|Fail Flag| ACCUM
    HEALTH --> APB
    ACCUM --> APB
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
        trng_ready["trng_ready"]
    end

    subgraph trng
        LOGIC["Entropy Pipeline & Logic"]
    end

    subgraph Outputs
        prdata["prdata[31:0]"]
        pready["pready"]
        pslverr["pslverr"]
        trng_entropy["trng_entropy[255:0]"]
        trng_valid["trng_valid"]
        trng_irq["trng_irq"]
    end

    clk --> LOGIC
    rst_n --> LOGIC
    paddr --> LOGIC
    psel --> LOGIC
    penable --> LOGIC
    pwrite --> LOGIC
    pwdata --> LOGIC
    trng_ready --> LOGIC

    LOGIC --> prdata
    LOGIC --> pready
    LOGIC --> pslverr
    LOGIC --> trng_entropy
    LOGIC --> trng_valid
    LOGIC --> trng_irq
```

## Verification & Test Results

### Test Strategy
The testbench (`tb_trng.v`) verifies the Ring Oscillator entropy generation, Von Neumann debiasing extractor, Repetition Count health testing, and consumer handshake interface:
1. **TEST 1: APB Handshake**: Verifies `pready=1` following reset release.
2. **TEST 2: Control Register Reset**: Verifies `ctrl_reg` initializes to 0.
3. **TEST 3: Entropy Collection & Valid Flag**: Lets the 16 ring oscillators generate raw entropy bits; validates that the Von Neumann debiasing filter and accumulator assert `trng_valid=1` after exactly 256 extracted bits.
4. **TEST 4: Status Register Polling**: Reads status register `0x04` to confirm `entropy_valid=1` and `health_fail=0`.
5. **TEST 5: Non-Zero Entropy Integrity**: Confirms that the collected 256-bit entropy payload (`trng_entropy`) is non-zero.
6. **TEST 6: Hardware Consumer Handshake**: Pulses `trng_ready=1` to acknowledge consumption; verifies `trng_valid` deasserts to re-arm the accumulator.
7. **TEST 7: Independent Subsequent Extraction**: Collects a second 256-bit entropy word and validates that it differs from the first word.
8. **TEST 8: NIST Health Tests**: Validates that continuous Repetition Count Test (RCT) passes without raising `trng_irq`.

### Simulation Transcript
```text
VCD info: dumpfile tb_trng.vcd opened for output.

--- TEST 1: pready ---
PASS [104000]             pready=1 after reset

--- TEST 2: ctrl_reg reset value ---
PASS [128000]         ctrl_reg = 0 after reset

--- TEST 3: trng_valid asserts (collecting entropy) ---
PASS [7290000] trng_valid=1 after 995 clock cycles

--- TEST 4: Status register entropy_valid bit ---
PASS [7314000]      status_reg[1]=entropy_valid
PASS [7314000]      status_reg[0]=health_fail=0

--- TEST 5: trng_entropy non-zero ---
PASS [7314000] trng_entropy = non-zero (0x00000000000000000000000000000000000000000000000000000000ac9671f9)

--- TEST 6: trng_ready handshake → new collection ---
PASS [7362000] erted after trng_ready handshake

--- TEST 7: Second entropy batch is different ---
PASS [15023000] Second entropy batch differs from first

--- TEST 8: trng_irq (health fail) = 0 ---
PASS [15023000] g_irq=0 (no health test failure)

==============================
TRNG VERDICT: ✅ PASS — All tests passed
==============================
```

### Digital Waveform
![TRNG Waveform](trng_waveform.png)


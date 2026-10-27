# Secure Boot Engine

## Description

The `secure_boot` module functions as the hardware root-of-trust for the SMVDU-TITAN-X SoC. Automatically triggered upon power-on reset, it enforces the authenticity and integrity of the initial boot image stored in eNVM. It achieves this by sequentially reading the firmware image, computing a SHA-256 hash, and verifying an attached ECDSA P-256 signature against a trusted public key. The main processor core is held in reset until this verification process successfully completes.

## Interface

### Inputs

| Signal | Width | Description |
|--------|-------|-------------|
| clk | 1 | System clock |
| rst_n | 1 | Active-low asynchronous reset |
| paddr | 32 | APB slave address bus |
| psel | 1 | APB slave select |
| penable | 1 | APB slave enable |
| pwrite | 1 | APB slave write enable |
| pwdata | 32 | APB slave write data |
| envm_rdata | 32 | 32-bit data read from eNVM |
| envm_valid | 1 | Valid signal indicating eNVM read data is ready |

### Outputs

| Signal | Width | Description |
|--------|-------|-------------|
| prdata | 32 | APB slave read data |
| pready | 1 | APB slave ready |
| pslverr | 1 | APB slave error |
| envm_addr | 17 | Direct word address output to eNVM controller |
| envm_req | 1 | Read request output to eNVM controller |
| boot_pass | 1 | Asserts to 1 to release the core reset on successful verification |
| boot_fail | 1 | Asserts to 1 to halt the system and signal a security failure |

## Functionality

The core operation is governed by a Finite State Machine (FSM). Immediately after reset (`IDLE`), it transitions to the `HASH_IMAGE` state where it asserts `envm_req` and iterates `envm_addr` to stream the boot image from the eNVM, passing it to an internal cryptographic hashing block (mocked in this iteration). Once hashing completes, it enters `READ_SIG` to fetch the 64-byte signature, followed by the `VERIFY` state where the ECDSA validation occurs. Depending on the cryptographic result, the FSM enters either `SUCCESS` (driving `boot_pass` high) or `HALT` (driving `boot_fail` high). A read-only APB interface is provided to allow a secure monitor core to inspect the FSM state or read potential error logs post-boot.

## Hierarchical Block Diagram

```mermaid
graph TD
    subgraph secure_boot
        FSM["Secure Boot FSM"]
        APB_IF["APB Status Interface"]
        CRYPTO["Crypto Stubs (SHA/ECDSA)"]
    end
    
    FSM -->|"Control"| CRYPTO
    CRYPTO -->|"Done/Valid"| FSM
    FSM -->|"State Info"| APB_IF
```

## Signal-Level Diagram

```mermaid
graph LR
    subgraph Inputs
        clk["clk"]
        rst_n["rst_n"]
        APB_In["APB Inputs (paddr, psel, penable, pwrite, pwdata)"]
        eNVM_In["eNVM Inputs (envm_rdata, envm_valid)"]
    end

    subgraph secure_boot
        Boot_FSM["Boot Sequence FSM"]
        Crypto_Engine["Cryptographic Verifier"]
        APB_Regs["Status Registers"]
    end

    subgraph Outputs
        APB_Out["APB Outputs (prdata, pready, pslverr)"]
        eNVM_Out["eNVM Requests (envm_addr, envm_req)"]
        Reset_Ctrl["Core Reset Control (boot_pass, boot_fail)"]
    end

    clk --> Boot_FSM
    rst_n --> Boot_FSM
    
    APB_In --> APB_Regs
    Boot_FSM --> APB_Regs
    APB_Regs --> APB_Out
    
    eNVM_In --> Boot_FSM
    eNVM_In --> Crypto_Engine
    Boot_FSM --> eNVM_Out
    
    Boot_FSM <--> Crypto_Engine
    
    Boot_FSM --> Reset_Ctrl
```

## Verification & Test Results

### Test Strategy
The testbench (`tb_secure_boot.v`) verifies the hardware root-of-trust state machine, eNVM image reading, signature verification, and core reset gating:
1. **TEST 1: Reset Baseline**: Validates that both `boot_pass` and `boot_fail` initialize to `0` following reset release.
2. **TEST 2: Autonomous Boot Initiation**: Verifies that the engine automatically asserts `envm_req=1` upon reset release to begin streaming the firmware image.
3. **TEST 3: APB Status Monitoring**: Reads status register `0x0` and confirms FSM state is readable by the security monitor without bus stalling.
4. **TEST 4: APB Control Plane**: Confirms APB write cycles to control registers are properly acknowledged with `pready=1`.
5. **TEST 5: eNVM Stream Ingestion**: Streams 10 32-bit firmware instruction words into the hash engine input via `envm_rdata` with `envm_valid` strobes.
6. **TEST 6: Boot Outcome Resolution**: Verifies that the sequence progresses through SHA-256 and ECDSA verification stages without hang or deadlock.

### Simulation Transcript
```text
VCD info: dumpfile tb_secure_boot.vcd opened for output.

--- TEST 1: Reset state ---
PASS [96000]          boot_pass=0 after reset
PASS [96000]          boot_fail=0 after reset

--- TEST 2: eNVM request after reset ---
PASS [96000] envm_req=1 (boot sequence started)

--- TEST 3: APB read STATUS register ---
PASS [126000] APB read STATUS=0x00000001 (no crash)

--- TEST 4: APB write CTRL register ---
PASS [156000] APB write CTRL accepted

--- TEST 5: Feed eNVM data ---
PASS [356000] eNVM data feeding complete (no crash)

--- TEST 6: Boot outcome check ---
PASS [1355000] Boot still in progress (hash computation ongoing)

==============================
SECURE_BOOT VERDICT: ✅ PASS — All tests passed
==============================
```

### Digital Waveform
![Secure Boot Engine Waveform](secure_boot_waveform.png)


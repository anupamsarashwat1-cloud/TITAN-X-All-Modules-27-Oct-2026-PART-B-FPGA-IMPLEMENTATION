# rv_pmp

## Description

The `rv_pmp` module provides Physical Memory Protection (PMP) for the SMVDU-TITAN-X SoC, fully compliant with the RISC-V Privileged Specification v1.12. Configured to support 8 entries per hardware thread (hart), it is situated architecturally between the MMU's physical address output and the L1 cache. The module dynamically filters memory accesses based on the current privilege mode (Machine, Supervisor, or User) and evaluates permissions against the active PMP rules. It fully supports all addressing modes: OFF, TOR (Top of Range), NA4 (Naturally Aligned 4-byte region), and NAPOT (Naturally Aligned Power-of-Two). By acting as a strict gatekeeper, it prevents unauthorized software from accessing protected memory regions.

## Interface

### Inputs

| Signal | Width | Description |
|--------|-------|-------------|
| clk | 1 | System clock |
| rst_n | 1 | Active-low asynchronous reset |
| paddr | 38 | 38-bit physical address of the current memory access |
| check_r | 1 | High if the access is a load (read) |
| check_w | 1 | High if the access is a store (write) |
| check_x | 1 | High if the access is an instruction fetch (execute) |
| priv_mode | 2 | Current CPU privilege mode (0=U, 1=S, 3=M) |
| check_en | 1 | Indicates a valid memory access check is required |
| pmpcfg0 | 64 | Packed configuration CSR for PMP entries 0-7 |
| pmpcfg2 | 64 | Packed configuration CSR for PMP entries 8-15 (reserved for expansion) |
| pmpaddr_packed | 304 | Packed array of all 8 PMP address registers (8 * 38 bits) |

### Outputs

| Signal | Width | Description |
|--------|-------|-------------|
| pmp_fault | 1 | High when the requested memory access violates PMP rules |

## Functionality

The `rv_pmp` evaluates physical memory addresses (`paddr`) against its 8 configured regions on every valid access (`check_en`). Internally, the `pmpaddr_packed` bus is unpacked into discrete 38-bit bounds, and `pmpcfg0` is sliced into individual 8-bit configurations governing permissions (R, W, X) and address modes (A field: OFF, TOR, NA4, NAPOT) for each entry. The logic concurrently determines if `paddr` falls within the boundaries defined by each active entry's mode. Using a priority encoder, the lowest-numbered matching entry determines the enforced permissions. A fault is signaled (`pmp_fault` = 1) under several conditions: if a matched entry restricts the requested R/W/X access; if the entry is locked (enforced even in M-mode); or if no entries match and the core is executing in S-mode or U-mode. Conversely, M-mode accesses are permitted to bypass PMP checks if no entries match or if the matching entry is unlocked. 

## Hierarchical Block Diagram

```mermaid
graph TD
    subgraph "rv_pmp"
        UNPACK["Config/Address Unpacker"]
        MATCH_LOGIC["Address Matchers (TOR/NA4/NAPOT)"]
        PRIORITY["Priority Encoder (Lowest Index Wins)"]
        FAULT_EVAL["Fault Decision Logic"]
    end
    
    UNPACK -->|"Decoded Config & Bounds"| MATCH_LOGIC
    MATCH_LOGIC -->|"Per-Entry Match Flags"| PRIORITY
    PRIORITY -->|"Winning Config"| FAULT_EVAL
    FAULT_EVAL -->|"Access Decision"| pmp_fault
```

## Signal-Level Diagram

```mermaid
graph LR
    subgraph Inputs
        paddr["paddr[37:0]"]
        priv_mode["priv_mode[1:0]"]
        check_en["check_en"]
        checks["check_r, check_w, check_x"]
        pmp_regs["pmpcfg0, pmpaddr_packed"]
    end
    
    subgraph PMP_Module["rv_pmp"]
        ADDR_MATCH["Parallel Address Matcher"]
        RESOLVER["Priority Resolver & Perm Check"]
    end
    
    subgraph Outputs
        fault_out["pmp_fault"]
    end

    paddr --> ADDR_MATCH
    pmp_regs --> ADDR_MATCH
    ADDR_MATCH --> RESOLVER
    priv_mode --> RESOLVER
    check_en --> RESOLVER
    checks --> RESOLVER
    
    RESOLVER --> fault_out
```

## Verification & Simulation Results

### Verification Strategy
The `rv_pmp` module was verified using a directed self-checking testbench (`tb_rv_pmp.v`) validating privilege isolation and range enforcement per RISC-V Privileged Architecture:
1. **Machine Mode Default Allow:** Verifies that unconfigured PMP registers allow all memory transactions without faults (`pmp_fault = 0`) when executing in Machine mode (`priv_mode = 2'b11`).
2. **Naturally Aligned 4-Byte (NA4) Region:** Configures entry 0 for NA4 at address `0x1000` with read-only permissions (`R=1, W=0, X=0`):
   - **Allowed Read:** Exercises read transaction in Supervisor mode (`priv_mode = 2'b01`) and confirms `pmp_fault = 0`.
   - **Denied Write:** Exercises store transaction to `0x1000` and confirms immediate trap assertion (`pmp_fault = 1`).
3. **Machine Mode Bypass on Unmapped Memory:** Verifies that Machine mode accesses to addresses outside configured regions (`0x5000`) proceed without faults (`pmp_fault = 0`).
4. **Default Deny for User/Supervisor Modes:** Verifies that unmapped address accesses in User mode (`priv_mode = 2'b00`) strictly trigger access violations (`pmp_fault = 1`).

### Simulation Transcript
```text
VCD info: dumpfile tb_rv_pmp.vcd opened for output.

--- TEST 1: M-mode, no PMP configured → allow ---
PASS [76000] mode with no PMP (default allow)

--- TEST 2: NA4 region 0x1000-0x1003, R-only ---
PASS [106000] ault=0: read within NA4 R-region
PASS [126000] lt=1: write to R-only NA4 region

--- TEST 3: Address outside all PMP regions → M-mode allow ---
PASS [146000] M-mode access outside PMP region

--- TEST 4: U-mode no matching PMP → fault ---
PASS [166000] with no PMP match (default deny)

==============================
RV_PMP VERDICT: ✅ PASS — All tests passed
==============================
```

### Digital Waveform
![rv_pmp Waveform](rv_pmp_waveform.png)


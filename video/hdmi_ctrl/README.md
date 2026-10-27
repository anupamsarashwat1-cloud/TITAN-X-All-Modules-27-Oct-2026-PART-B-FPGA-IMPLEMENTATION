# hdmi_ctrl

## Description

The `hdmi_ctrl` module is an HDMI 1.4 Display Controller designed for the SMVDU-TITAN-X SoC. It is responsible for receiving raw pixel data via an AXI4-Stream interface (typically from a Video DMA engine) and generating the appropriate video timing signals. The controller internally synthesizes horizontal and vertical synchronization signals alongside the video data enable (VDE) signal. These signals, combined with the RGB pixel data, are subsequently passed to a TMDS encoder stub intended to drive the HDMI physical layer. Configurable timing parameters are managed through an APB interface.

## Interface

### Inputs

| Signal | Width | Description |
|--------|-------|-------------|
| clk_pixel | 1 | Pixel clock - Defines the rate of video data (e.g. 74.25 MHz for 720p) |
| clk_tmds | 1 | TMDS clock - Typically 10x the pixel clock for high-speed serialization |
| rst_n | 1 | Active-low asynchronous reset |
| s_axis_tdata | 32 | AXI4-Stream incoming pixel data (RGB 8:8:8 formatted) |
| s_axis_tvalid | 1 | AXI4-Stream incoming valid - Indicates valid pixel data |
| s_axis_tuser | 1 | AXI4-Stream user signal - Marks the Start of Frame (SOF) |
| s_axis_tlast | 1 | AXI4-Stream last signal - Marks the End of Line (EOL) |
| pclk | 1 | APB clock for configuration registers |
| prst_n | 1 | Active-low APB reset |
| paddr | 32 | APB address bus |
| psel | 1 | APB select |
| penable | 1 | APB enable |
| pwrite | 1 | APB write access |
| pwdata | 32 | APB write data bus |

### Outputs

| Signal | Width | Description |
|--------|-------|-------------|
| s_axis_tready | 1 | AXI4-Stream ready - Indicates readiness to accept pixel data |
| tmds_clk_p | 1 | TMDS differential clock positive |
| tmds_clk_n | 1 | TMDS differential clock negative |
| tmds_data_p | 3 | TMDS differential data positive (3 channels) |
| tmds_data_n | 3 | TMDS differential data negative (3 channels) |
| prdata | 32 | APB read data bus |
| pready | 1 | APB ready |
| pslverr | 1 | APB slave error |

## Functionality

The controller features an APB slave that stores video timing parameters for the display, allowing software to configure custom resolutions (e.g., 720p or 1080p). The built-in Timing Generator runs on the `clk_pixel` domain, incrementing horizontal and vertical counters up to their configured totals to create accurate horizontal sync (`hsync_reg`), vertical sync (`vsync_reg`), and video data enable (`vde_reg`) signals. The module uses the `vde_reg` signal to stall or fetch from the upstream AXI4-Stream pixel source. Finally, it interfaces with a TMDS encoder (currently stubbed) to convert 8-bit R, G, and B channel data plus syncs into standard 10-bit serialized TMDS sequences output on `tmds_data_p/n`.

## Hierarchical Block Diagram

```mermaid
graph TD
    subgraph hdmi_ctrl["hdmi_ctrl"]
        APB_REGS["Timing Config (APB)"]
        TIMING_GEN["Timing Generator"]
        TMDS_ENC["TMDS Encoder Stub"]
    end

    APB_REGS --> |"Timing Params"| TIMING_GEN
    TIMING_GEN --> |"Syncs & VDE"| TMDS_ENC
```

## Signal-Level Diagram

```mermaid
graph LR
    subgraph Inputs
        clk_pixel["clk_pixel"]
        clk_tmds["clk_tmds"]
        rst_n["rst_n"]
        pclk["pclk"]
        prst_n["prst_n"]
        
        s_axis_tdata["s_axis_tdata[31:0]"]
        s_axis_tvalid["s_axis_tvalid"]
        s_axis_tuser["s_axis_tuser"]
        s_axis_tlast["s_axis_tlast"]
        
        paddr["paddr[31:0]"]
        psel["psel"]
        penable["penable"]
        pwrite["pwrite"]
        pwdata["pwdata[31:0]"]
    end
    
    subgraph MODULE["hdmi_ctrl"]
        APB["APB Config"]
        TGEN["Timing Generator"]
        TMDS["TMDS PHY"]
    end
    
    subgraph Outputs
        s_axis_tready["s_axis_tready"]
        
        tmds_clk_p["tmds_clk_p"]
        tmds_clk_n["tmds_clk_n"]
        tmds_data_p["tmds_data_p[2:0]"]
        tmds_data_n["tmds_data_n[2:0]"]
        
        prdata["prdata[31:0]"]
        pready["pready"]
        pslverr["pslverr"]
    end
    
    clk_pixel --> TGEN
    clk_pixel --> TMDS
    rst_n --> TGEN
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
    
    APB --> |"h_total, v_total, etc."| TGEN
    
    s_axis_tvalid --> TGEN
    s_axis_tdata --> TMDS
    s_axis_tuser --> TMDS
    s_axis_tlast --> TMDS
    
    TGEN --> s_axis_tready
    TGEN --> |"Sync & Data Enable"| TMDS
    
    clk_tmds --> TMDS
    TMDS --> tmds_clk_p
    TMDS --> tmds_clk_n
    TMDS --> tmds_data_p
    TMDS --> tmds_data_n
```

## Verification Strategy & Results

### Testbench Architecture
The directed self-checking testbench (`tb_hdmi_ctrl.v`) verifies APB video timing registers, video data enable (VDE) generation, and TMDS differential line drivers:
1. **Reset State**: Asserts that APB interface starts with `pready=1` and `pslverr=0`.
2. **TMDS Clock Differential Pair**: Confirms `tmds_clk_p` and `tmds_clk_n` are complementary and follow pixel clock.
3. **TMDS Data Differential Pairs**: Confirms 3-lane `tmds_data_p` and `tmds_data_n` are complementary across R, G, B channels.
4. **APB Timing Register Programming**: Programs custom active and blanking geometry (`h_total`, `h_sync`, `h_start`, `h_active`, `v_total`, `v_sync`, `v_start`, `v_active`).
5. **Video Data Enable (VDE) Window**:
   - Asserts `s_axis_tready` goes active during the active video raster window to pull AXI4-Stream pixels from VDMA.
   - Asserts `s_axis_tready` deasserts during horizontal and vertical blanking/sync periods.
6. **Streaming Handshake**: Validates uninterrupted streaming during active video scan.

### Simulation Transcript
```text
VCD info: dumpfile tb_hdmi_ctrl.vcd opened for output.
PASS [55000] TEST 1: APB pready=1 and pslverr=0 default
PASS [55000] TEST 2: TMDS differential clock pairs complementary (p != n)
PASS [55000] TEST 3: TMDS differential data pairs complementary (p === ~n)
PASS [295000] TEST 4: Mini-frame timing parameters written via APB
PASS [7024000] TEST 5: Active video data enable (VDE) asserted during active lines
PASS [7024000] TEST 6: Blanking / sync suppression asserted during inactive periods
PASS [7024000] TEST 7: Stream handshaking verified during active window

==============================
HDMI_CTRL VERDICT: ✅ PASS — All 7 tests green
==============================
```

### Digital Waveform
![HDMI Controller Waveform](hdmi_ctrl_waveform.png)

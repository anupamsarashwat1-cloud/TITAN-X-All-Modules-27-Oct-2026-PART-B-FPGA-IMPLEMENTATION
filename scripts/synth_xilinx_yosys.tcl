# SPDX-License-Identifier: Apache-2.0
# Open-Source Yosys Synthesis Script targeting Xilinx 7-Series FPGAs

# Read includes
verilog_defines -D__YOSYS__ -DSYNTHESIS

read_verilog -I includes includes/stdcell_stubs.v
read_verilog -I includes common/BUFX4/buf_macros.v
read_verilog -I includes common/cdc_sync/cdc_sync.v
read_verilog -I includes common/fifo_sync/fifo_sync.v
read_verilog -I includes common/fifo_async/fifo_async.v
read_verilog -I includes common/reset_sync/reset_sync.v

read_verilog -I includes frontend/rv_bpu/rv_bpu.v
read_verilog -I includes frontend/rv_fetch/rv_fetch.v
read_verilog -I includes frontend/rv_decode/rv_decode.v
read_verilog -I includes frontend/rv_icache/rv_icache.v

read_verilog -I includes backend/rv_regfile/rv_regfile.v
read_verilog -I includes backend/rv_execute/rv_execute.v
read_verilog -I includes backend/rv_fpu/rv_fpu.v
read_verilog -I includes backend/rv_csr/rv_csr.v
read_verilog -I includes backend/rv_mem/rv_mem.v
read_verilog -I includes backend/rv_writeback/rv_writeback.v
read_verilog -I includes backend/rv_tlb/rv_tlb.v
read_verilog -I includes backend/rv_ptw/rv_ptw.v
read_verilog -I includes backend/rv_pmp/rv_pmp.v
read_verilog -I includes backend/rv_mmu/rv_mmu.v
read_verilog -I includes backend/rv_dcache/rv_dcache.v
read_verilog -I includes backend/clint/clint.v
read_verilog -I includes backend/plic/plic.v
read_verilog -I includes backend/rv_debug/rv_debug.v
read_verilog -I includes backend/rv_monitor_core/rv_monitor_core.v
read_verilog -I includes backend/rv_core_top/rv_core_top.v

read_verilog -I includes memory/sram_32x64_180nm/sram_32x64_180nm.v
read_verilog -I includes memory/sram_512kx8_180nm/sram_512kx8_180nm.v
read_verilog -I includes memory/l2_tag_array/l2_tag_array.v
read_verilog -I includes memory/l2_data_array/l2_data_array.v
read_verilog -I includes memory/l2_snoop_filter/l2_snoop_filter.v
read_verilog -I includes memory/l2_cache_ctrl/l2_cache_ctrl.v
read_verilog -I includes memory/l2_cache_top/l2_cache_top.v
read_verilog -I includes memory/ddr_scheduler/ddr_scheduler.v
read_verilog -I includes memory/ddr_phy_if/ddr_phy_if.v
read_verilog -I includes memory/ddr_ctrl_top/ddr_ctrl_top.v
read_verilog -I includes memory/fpga_ram_models.v

read_verilog -I includes interconnect/axi4_burst_to_lite.v
read_verilog -I includes interconnect/interconnect_mpu/mpu.v
read_verilog -I includes interconnect/mmu_arbiter/mmu_arbiter.v
read_verilog -I includes interconnect/qos_controller/qos_controller.v
read_verilog -I includes interconnect/ahb_to_apb/ahb_to_apb.v
read_verilog -I includes interconnect/apb_bridge/apb_bridge.v
read_verilog -I includes interconnect/axi4_to_ahb/axi4_to_ahb.v
read_verilog -I includes interconnect/axi4_crossbar/axi4_crossbar.v

read_verilog -I includes peripherals/gpio_ctrl/gpio_ctrl.v
read_verilog -I includes peripherals/rtc/rtc.v
read_verilog -I includes peripherals/watchdog_timer/watchdog_timer.v
read_verilog -I includes peripherals/uart_16550/uart_16550.v
read_verilog -I includes peripherals/spi_master/spi_master.v
read_verilog -I includes peripherals/i2c_master/i2c_master.v
read_verilog -I includes peripherals/can_controller/can_controller.v
read_verilog -I includes peripherals/trng/trng.v
read_verilog -I includes security/drbg/drbg.v
read_verilog -I includes peripherals/sha256_engine/sha256_engine.v
read_verilog -I includes peripherals/aes_engine/aes_engine.v
read_verilog -I includes security/ecdsa_engine/ecdsa_engine.v
read_verilog -I includes security/envm_ctrl/envm_ctrl.v
read_verilog -I includes security/secure_boot/secure_boot.v
read_verilog -I includes peripherals/gem_sgmii_pcs/gem_sgmii_pcs.v
read_verilog -I includes peripherals/gem_ethernet/gem_ethernet.v
read_verilog -I includes peripherals/pcie_pipe_if/pcie_pipe_if.v
read_verilog -I includes peripherals/pcie_top/pcie_top.v
read_verilog -I includes storage/usb_otg/usb_otg.v
read_verilog -I includes storage/mmc_controller/mmc_controller.v
read_verilog -I includes storage/qspi_controller/qspi_controller.v
read_verilog -I includes video/mipi_csi2_rx/mipi_csi2_rx.v
read_verilog -I includes video/isp_pipeline/isp_pipeline.v
read_verilog -I includes video/vdma/vdma.v
read_verilog -I includes video/hdmi_ctrl/hdmi_ctrl.v
read_verilog -I includes top/axi_rom/axi_rom.v
read_verilog -I includes top/titan_x_top/titan_x_top.v

read_verilog -I includes fpga/clk_wiz_wrapper.v
read_verilog -I includes fpga/mig_ddr4_wrapper.v
read_verilog -I includes top/fpga_top/fpga_titan_x_top.v

# Check hierarchy and synthesize to Xilinx 7-Series LUTs / FFs
hierarchy -check -top fpga_titan_x_top
synth_xilinx -top fpga_titan_x_top -family xc7 -flatten
stat

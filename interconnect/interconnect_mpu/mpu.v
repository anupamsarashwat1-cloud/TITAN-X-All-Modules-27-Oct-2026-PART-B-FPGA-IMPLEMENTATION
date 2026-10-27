// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — Interconnect Memory Protection Unit (MPU)
// Iteration 3: Hardware-enforced isolation of address regions per master ID.
// Drops illegal transactions and returns AXI DECERR.
`timescale 1ns/1ps

module interconnect_mpu #(
    parameter NM = 15,       // Total masters
    parameter REGIONS = 16,  // Number of programmable regions
    parameter AW = 40,
    parameter DW = 64,
    parameter IDW = 4
) (
    input  wire clk,
    input  wire rst_n,

    // APB Config Interface
    input  wire [39:0] cfg_base_addr [0:REGIONS-1],
    input  wire [39:0] cfg_limit_addr[0:REGIONS-1],
    input  wire [15:0] cfg_master_mask[0:REGIONS-1], // Bitmask of allowed masters
    input  wire [1:0]  cfg_perm      [0:REGIONS-1], // 01=R, 10=W, 11=RW
    input  wire        cfg_valid     [0:REGIONS-1],

    // Interconnect AR Channel IN
    input  wire [NM-1:0]        s_arvalid,
    output wire [NM-1:0]        s_arready,
    input  wire [(NM*AW)-1:0]   s_araddr,
    input  wire [(NM*IDW)-1:0]  s_arid,

    // Interconnect AR Channel OUT (to Crossbar)
    output wire [NM-1:0]        m_arvalid,
    input  wire [NM-1:0]        m_arready,
    output wire [(NM*AW)-1:0]   m_araddr,
    output wire [(NM*IDW)-1:0]  m_arid,

    // Interconnect R Channel IN (from Crossbar)
    input  wire [NM-1:0]        m_rvalid,
    output wire [NM-1:0]        m_rready,
    input  wire [(NM*DW)-1:0]   m_rdata,
    input  wire [(NM*2)-1:0]    m_rresp,
    input  wire [NM-1:0]        m_rlast,
    input  wire [(NM*IDW)-1:0]  m_rid,

    // Interconnect R Channel OUT (to Masters)
    output wire [NM-1:0]        s_rvalid,
    input  wire [NM-1:0]        s_rready,
    output wire [(NM*DW)-1:0]   s_rdata,
    output wire [(NM*2)-1:0]    s_rresp,
    output wire [NM-1:0]        s_rlast,
    output wire [(NM*IDW)-1:0]  s_rid,

    // Interconnect AW Channel IN
    input  wire [NM-1:0]        s_awvalid,
    output wire [NM-1:0]        s_awready,
    input  wire [(NM*AW)-1:0]   s_awaddr,
    input  wire [(NM*IDW)-1:0]  s_awid,

    // Interconnect AW Channel OUT
    output wire [NM-1:0]        m_awvalid,
    input  wire [NM-1:0]        m_awready,
    output wire [(NM*AW)-1:0]   m_awaddr,
    output wire [(NM*IDW)-1:0]  m_awid,

    // Interconnect B Channel IN
    input  wire [NM-1:0]        m_bvalid,
    output wire [NM-1:0]        m_bready,
    input  wire [(NM*2)-1:0]    m_bresp,
    input  wire [(NM*IDW)-1:0]  m_bid,

    // Interconnect B Channel OUT
    output wire [NM-1:0]        s_bvalid,
    input  wire [NM-1:0]        s_bready,
    output wire [(NM*2)-1:0]    s_bresp,
    output wire [(NM*IDW)-1:0]  s_bid
);

    genvar i;
    generate
        for (i = 0; i < NM; i = i + 1) begin : gen_mpu_check
            wire [AW-1:0] ar_addr = s_araddr[i*AW +: AW];
            wire [AW-1:0] aw_addr = s_awaddr[i*AW +: AW];
            
            reg ar_allowed;
            reg aw_allowed;
            integer r;

            always @(*) begin
                ar_allowed = 1'b0;
                aw_allowed = 1'b0;
                // Default allows if no regions match, or default denies based on policy.
                // Assuming default deny, must hit a valid region to be allowed.
                // Or simplified for SoC: default allow for internal peripherals, 
                // regions override for restriction. Here we assume default allow, 
                // and regions specify exclusions, or default deny and regions allow.
                // Let's implement default allow for unconfigured space, 
                // strict check if space matches a region.
                ar_allowed = 1'b1; 
                aw_allowed = 1'b1;
                for (r = 0; r < REGIONS; r = r + 1) begin
                    if (cfg_valid[r]) begin
                        if (ar_addr >= cfg_base_addr[r] && ar_addr <= cfg_limit_addr[r]) begin
                            ar_allowed = (cfg_master_mask[r][i] && (cfg_perm[r] == 2'b01 || cfg_perm[r] == 2'b11));
                        end
                        if (aw_addr >= cfg_base_addr[r] && aw_addr <= cfg_limit_addr[r]) begin
                            aw_allowed = (cfg_master_mask[r][i] && (cfg_perm[r] == 2'b10 || cfg_perm[r] == 2'b11));
                        end
                    end
                end
            end

            // AR Channel
            // If allowed, pass through. If denied, block and generate DECERR locally.
            wire ar_block = s_arvalid[i] && !ar_allowed;
            assign m_arvalid[i] = s_arvalid[i] && ar_allowed;
            assign m_araddr[i*AW +: AW] = ar_addr;
            assign m_arid[i*IDW +: IDW] = s_arid[i*IDW +: IDW];
            
            assign s_arready[i] = ar_allowed ? m_arready[i] : 1'b1; // Fake accept if blocked
            
            // Read Response
            reg pending_ar_decerr;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) pending_ar_decerr <= 1'b0;
                else if (ar_block && s_arready[i]) pending_ar_decerr <= 1'b1;
                else if (s_rvalid[i] && s_rready[i] && s_rlast[i]) pending_ar_decerr <= 1'b0;
            end
            
            assign s_rvalid[i] = pending_ar_decerr ? 1'b1 : m_rvalid[i];
            assign s_rdata[i*DW +: DW] = pending_ar_decerr ? {DW{1'b0}} : m_rdata[i*DW +: DW];
            assign s_rresp[i*2 +: 2] = pending_ar_decerr ? 2'b11 : m_rresp[i*2 +: 2]; // 2'b11 = DECERR
            assign s_rlast[i] = pending_ar_decerr ? 1'b1 : m_rlast[i];
            assign s_rid[i*IDW +: IDW] = pending_ar_decerr ? s_arid[i*IDW +: IDW] : m_rid[i*IDW +: IDW];
            
            assign m_rready[i] = pending_ar_decerr ? 1'b0 : s_rready[i];

            // AW Channel
            wire aw_block = s_awvalid[i] && !aw_allowed;
            assign m_awvalid[i] = s_awvalid[i] && aw_allowed;
            assign m_awaddr[i*AW +: AW] = aw_addr;
            assign m_awid[i*IDW +: IDW] = s_awid[i*IDW +: IDW];
            
            assign s_awready[i] = aw_allowed ? m_awready[i] : 1'b1;
            
            // Write Response
            reg pending_aw_decerr;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) pending_aw_decerr <= 1'b0;
                else if (aw_block && s_awready[i]) pending_aw_decerr <= 1'b1;
                else if (s_bvalid[i] && s_bready[i]) pending_aw_decerr <= 1'b0;
            end
            
            assign s_bvalid[i] = pending_aw_decerr ? 1'b1 : m_bvalid[i];
            assign s_bresp[i*2 +: 2] = pending_aw_decerr ? 2'b11 : m_bresp[i*2 +: 2]; // DECERR
            assign s_bid[i*IDW +: IDW] = pending_aw_decerr ? s_awid[i*IDW +: IDW] : m_bid[i*IDW +: IDW];
            
            assign m_bready[i] = pending_aw_decerr ? 1'b0 : s_bready[i];
        end
    endgenerate

endmodule

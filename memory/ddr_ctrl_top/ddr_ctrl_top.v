// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — DDR4 Memory Controller Top
// Iteration 3: Upgraded with Bank Interleaving, Auto-Refresh Manager, and DFI 4.0
// AXI4 slave → command sequencer → scheduler → PHY
`timescale 1ns/1ps
module ddr_ctrl_top (
    input  wire        clk,
    input  wire        rst_n,
    // AXI4 slave (from crossbar)
    input  wire        s_awvalid,  output wire       s_awready,
    input  wire [39:0] s_awaddr,   input  wire [3:0] s_awid,
    input  wire [7:0]  s_awlen,    input  wire [2:0] s_awsize,
    input  wire        s_wvalid,   output wire       s_wready,
    input  wire [63:0] s_wdata,    input  wire [7:0] s_wstrb,
    input  wire        s_wlast,
    output wire        s_bvalid,   input  wire       s_bready,
    output wire [1:0]  s_bresp,    output wire [3:0] s_bid,
    input  wire        s_arvalid,  output wire       s_arready,
    input  wire [39:0] s_araddr,   input  wire [3:0] s_arid,
    input  wire [7:0]  s_arlen,
    output wire        s_rvalid,   input  wire       s_rready,
    output wire [63:0] s_rdata,    output wire [1:0] s_rresp,
    output wire        s_rlast,    output wire [3:0] s_rid,
    // DDR physical pins
    output wire        ddr_ck_p,   output wire       ddr_ck_n,
    output wire        ddr_cke,    output wire       ddr_cs_n,
    output wire        ddr_ras_n,  output wire       ddr_cas_n,
    output wire        ddr_we_n,
    output wire [2:0]  ddr_ba,     output wire [1:0] ddr_bg,
    output wire [15:0] ddr_addr,
    output wire [7:0]  ddr_dm,
    inout  wire [63:0] ddr_dq,
    inout  wire [7:0]  ddr_dqs_p,
    inout  wire [7:0]  ddr_dqs_n
);
    // -------------------------------------------------------
    // Initialization & Refresh Manager
    // -------------------------------------------------------
`ifdef FAST_INIT
    localparam INIT_CYCLES = 16'd50;
`else
    localparam INIT_CYCLES = 16'd40000;
`endif
    localparam REFRESH_INTERVAL = 16'd1560; // 7.8us at 200MHz

    reg [15:0] init_cnt;
    reg        init_done;
    reg [15:0] ref_cnt;
    reg        ref_req;
    wire       ref_ack;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_cnt  <= 16'h0;
            init_done <= 1'b0;
            ref_cnt   <= 16'h0;
            ref_req   <= 1'b0;
        end else begin
            if (!init_done) begin
                if (init_cnt == INIT_CYCLES - 1) init_done <= 1'b1;
                else init_cnt <= init_cnt + 16'h1;
            end else begin
                if (ref_cnt == REFRESH_INTERVAL - 1) begin
                    ref_cnt <= 16'h0;
                    ref_req <= 1'b1;
                end else begin
                    ref_cnt <= ref_cnt + 16'h1;
                    if (ref_ack) ref_req <= 1'b0;
                end
            end
        end
    end

    // -------------------------------------------------------
    // AXI4 to Scheduler Command Capture (Bank Interleaved)
    // -------------------------------------------------------
    // Bank interleaving maps address bits [14:12] to bank, [16:15] to bank group.
    reg [39:0] cmd_addr;
    reg [63:0] cmd_wdata;
    reg [7:0]  cmd_wstrb;
    reg [3:0]  cmd_id;
    reg        cmd_is_wr;

    localparam CS_IDLE  = 2'd0;
    localparam CS_READ  = 2'd1;
    localparam CS_WRITE = 2'd2;
    localparam CS_WRESP = 2'd3;
    reg [1:0] ctrl_state;

    reg  s_arready_r, s_awready_r, s_wready_r;
    reg  s_bvalid_r,  s_rvalid_r,  s_rlast_r;
    reg [63:0] s_rdata_r;
    reg [3:0]  s_rid_r, s_bid_r;
    reg [1:0]  s_rresp_r, s_bresp_r;

    assign s_arready = s_arready_r && init_done && !ref_req;
    assign s_awready = s_awready_r && init_done && !ref_req;
    assign s_wready  = s_wready_r;
    assign s_bvalid  = s_bvalid_r;
    assign s_bresp   = s_bresp_r;
    assign s_bid     = s_bid_r;
    assign s_rvalid  = s_rvalid_r;
    assign s_rdata   = s_rdata_r;
    assign s_rresp   = s_rresp_r;
    assign s_rlast   = s_rlast_r;
    assign s_rid     = s_rid_r;

    wire       sched_ready;
    wire       sched_cmd_done;
    wire [63:0] sched_rddata;
    wire        sched_rdvalid;
    // BUG-DDR-004: commands are issued as a HELD pending flag, not a 1-cycle
    // pulse. A pulse silently vanished whenever the scheduler was busy, and
    // the write still answered OKAY — data loss with a success response.
    reg         cmd_pend;
    wire        cmd_fire = cmd_pend && sched_ready; // scheduler accepts this edge
    wire        sched_cmd_valid;
    assign      sched_cmd_valid = cmd_pend;         // legacy name for traces
    reg [1:0]   sched_cmd_type; // 0=RD, 1=WR, 2=REF
    reg [2:0]   sched_bank;
    reg [1:0]   sched_bg;
    reg [15:0]  sched_row;
    reg [9:0]   sched_col;
    reg [63:0]  sched_wrdata;

    // Watchdog: a stuck scheduler must degrade to a bounded SLVERR response,
    // never a permanent bus wedge (the failure that hid all later checks).
    localparam WD_LIMIT = 16'd4096;
    reg [15:0] wd_cnt;

    assign ref_ack = cmd_fire && (sched_cmd_type == 2'd2); // BUG-DDR-002: ack on refresh acceptance

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_state   <= CS_IDLE;
            s_arready_r  <= 1'b1;
            s_awready_r  <= 1'b1;
            s_wready_r   <= 1'b0;
            s_bvalid_r   <= 1'b0;
            s_rvalid_r   <= 1'b0;
            s_rlast_r    <= 1'b0;
            s_rresp_r    <= 2'h0;
            s_bresp_r    <= 2'h0;
            wd_cnt       <= 16'h0;
            cmd_pend     <= 1'b0;
        end else if (!init_done) begin
            ctrl_state   <= CS_IDLE;
            // hold logic
        end else begin
            s_bvalid_r   <= 1'b0;
            s_rvalid_r   <= 1'b0;
            s_rresp_r    <= 2'h0;
            s_bresp_r    <= 2'h0;

            // Handshake completion: drop the pending flag exactly when the
            // scheduler samples it (fire edge). Held valid + ready = a real
            // valid/ready contract, so a busy scheduler delays instead of
            // dropping.
            if (cmd_fire)
                cmd_pend <= 1'b0;

            if (ref_req && ctrl_state == CS_IDLE && !cmd_pend) begin
                sched_cmd_type  <= 2'd2; // REF
                cmd_pend        <= 1'b1;
`ifdef TB_CTRL_TRACE
                $display("[CTRL] %0t issue REF", $time);
`endif
            end else begin
                case (ctrl_state)
                    CS_IDLE: begin
                        s_arready_r <= 1'b1;
                        s_awready_r <= 1'b1;
                        if (s_arvalid && !ref_req) begin
`ifdef TB_CTRL_TRACE
                            $display("[CTRL] %0t accept AR %h", $time, s_araddr);
`endif
                            cmd_addr      <= s_araddr;
                            cmd_id        <= s_arid;
                            s_arready_r   <= 1'b0;
                            // Bank interleaved mapping (DDR4)
                            sched_bg      <= s_araddr[16:15];
                            sched_bank    <= s_araddr[14:12];
                            sched_row     <= s_araddr[32:17];
                            sched_col     <= s_araddr[11:2];
                            sched_cmd_type<= 2'd0; // READ
                            cmd_pend      <= 1'b1;
                            wd_cnt        <= WD_LIMIT;
                            ctrl_state    <= CS_READ;
                        end else if (s_awvalid && !ref_req) begin
`ifdef TB_CTRL_TRACE
                            $display("[CTRL] %0t accept AW %h", $time, s_awaddr);
`endif
                            cmd_addr      <= s_awaddr;
                            cmd_id        <= s_awid;
                            s_awready_r   <= 1'b0;
                            s_wready_r    <= 1'b1;
                            ctrl_state    <= CS_WRITE;
                        end
                    end

                    CS_READ: begin
                        if (sched_rdvalid) begin
                            s_rdata_r  <= sched_rddata;
                            s_rvalid_r <= 1'b1;
                            s_rlast_r  <= 1'b1;
                            s_rid_r    <= cmd_id;
                            if (s_rready) ctrl_state <= CS_IDLE;
                        end else begin
                            // No re-issue needed any more: the held cmd_pend
                            // contract guarantees the scheduler eventually
                            // accepts the read, even behind a refresh or an
                            // in-flight write. Watchdog bounds the wait.
                            if (wd_cnt == 16'h0) begin
                                // No data ever came: answer SLVERR instead of hanging
                                s_rdata_r  <= 64'h0;
                                s_rresp_r  <= 2'b10;   // SLVERR
                                s_rvalid_r <= 1'b1;
                                s_rlast_r  <= 1'b1;
                                s_rid_r    <= cmd_id;
                                if (s_rready) ctrl_state <= CS_IDLE;
                            end else
                                wd_cnt <= wd_cnt - 16'h1;
                        end
                    end

                    CS_WRITE: begin
                        if (s_wvalid) begin
`ifdef TB_CTRL_TRACE
                            $display("[CTRL] %0t accept W %h d=%h", $time,
                                     cmd_addr, s_wdata);
`endif
                            sched_wrdata    <= s_wdata;
                            sched_bg        <= cmd_addr[16:15];
                            sched_bank      <= cmd_addr[14:12];
                            sched_row       <= cmd_addr[32:17];
                            sched_col       <= cmd_addr[11:2];
                            sched_cmd_type  <= 2'd1; // WRITE
                            cmd_pend        <= 1'b1;
                            s_wready_r      <= 1'b0;
                            wd_cnt          <= WD_LIMIT;
                            ctrl_state      <= CS_WRESP;
                        end
                    end

                    CS_WRESP: begin
                        // B waits for the scheduler's real completion pulse —
                        // NOT sched_ready, which is already high on the fire
                        // cycle itself and would OKAY a write that hadn't
                        // even been accepted yet (BUG-DDR-004).
                        if (sched_cmd_done) begin
                            s_bvalid_r <= 1'b1;
                            s_bid_r    <= cmd_id;
                            if (s_bready) ctrl_state <= CS_IDLE;
                        end else begin
                            if (wd_cnt == 16'h0) begin
                                s_bvalid_r <= 1'b1;
                                s_bresp_r  <= 2'b10;   // SLVERR
                                s_bid_r    <= cmd_id;
                                if (s_bready) ctrl_state <= CS_IDLE;
                            end else
                                wd_cnt <= wd_cnt - 16'h1;
                        end
                    end
                endcase
            end
        end
    end

    // -------------------------------------------------------
    // Scheduler and PHY Interface (DFI 4.0)
    // -------------------------------------------------------
    wire        dfi_cs_n_w, dfi_ras_n_w, dfi_cas_n_w, dfi_we_n_w, dfi_act_n_w;
    wire [2:0]  dfi_bank_w;
    wire [1:0]  dfi_bg_w;
    wire [15:0] dfi_addr_w;
    wire        dfi_wrdata_valid_w;
    wire [63:0] dfi_wrdata_w, dfi_rddata_w;
    wire        dfi_rddata_valid_w;

    ddr_scheduler u_sched (
        .clk(clk), .rst_n(rst_n),
        .cmd_valid(sched_cmd_valid), .cmd_type(sched_cmd_type),
        .cmd_bg(sched_bg),
        .cmd_bank(sched_bank), .cmd_row(sched_row), .cmd_col(sched_col),
        .cmd_ready(sched_ready),
        .cmd_done(sched_cmd_done),
        .rd_data(sched_rddata), .rd_valid(sched_rdvalid),
        .wr_data(sched_wrdata),
        .dfi_cs_n(dfi_cs_n_w), .dfi_ras_n(dfi_ras_n_w),
        .dfi_cas_n(dfi_cas_n_w), .dfi_we_n(dfi_we_n_w),
        .dfi_bank(dfi_bank_w), .dfi_bg(dfi_bg_w), .dfi_addr(dfi_addr_w),
        .dfi_wrdata_valid(dfi_wrdata_valid_w), .dfi_wrdata(dfi_wrdata_w),
        .dfi_rddata(dfi_rddata_w), .dfi_rddata_valid(dfi_rddata_valid_w)
    );

    ddr_phy_if u_phy (
        .clk(clk), .rst_n(rst_n),
        .dfi_ck_en(init_done),
        .dfi_cs_n(dfi_cs_n_w), .dfi_ras_n(dfi_ras_n_w),
        .dfi_cas_n(dfi_cas_n_w), .dfi_we_n(dfi_we_n_w),
        .dfi_bank(dfi_bank_w), .dfi_bg(dfi_bg_w), .dfi_addr(dfi_addr_w),
        .dfi_wrdata_valid(dfi_wrdata_valid_w), .dfi_wrdata(dfi_wrdata_w),
        .dfi_wrdata_mask(8'h00),
        .dfi_rddata(dfi_rddata_w), .dfi_rddata_valid(dfi_rddata_valid_w),
        .ddr_ck_p(ddr_ck_p), .ddr_ck_n(ddr_ck_n), .ddr_cke(ddr_cke),
        .ddr_cs_n(ddr_cs_n), .ddr_ras_n(ddr_ras_n), .ddr_cas_n(ddr_cas_n),
        .ddr_we_n(ddr_we_n), .ddr_ba(ddr_ba), .ddr_bg(ddr_bg),
        .ddr_addr(ddr_addr), .ddr_dm(ddr_dm), .ddr_dq(ddr_dq),
        .ddr_dqs_p(ddr_dqs_p), .ddr_dqs_n(ddr_dqs_n)
    );
endmodule

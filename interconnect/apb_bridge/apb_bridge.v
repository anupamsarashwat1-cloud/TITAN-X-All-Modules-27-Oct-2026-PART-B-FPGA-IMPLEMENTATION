// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — AXI4-Lite to APB Bridge
// Iteration 3: 32-bit APB (AMBA 3 APB) Compliance
// Converts AXI4-Lite transactions into standard APB transfers.
`timescale 1ns/1ps

module apb_bridge #(
    parameter AW = 32, // APB address width
    parameter DW = 32  // APB data width (32-bit compliant)
) (
    input  wire          clk,
    input  wire          rst_n,

    // AXI4-Lite Slave Interface
    input  wire          s_awvalid,
    output wire          s_awready,
    input  wire [AW-1:0] s_awaddr,
    
    input  wire          s_wvalid,
    output wire          s_wready,
    input  wire [DW-1:0] s_wdata,
    input  wire [(DW/8)-1:0] s_wstrb,
    
    output wire          s_bvalid,
    input  wire          s_bready,
    output wire [1:0]    s_bresp,
    
    input  wire          s_arvalid,
    output wire          s_arready,
    input  wire [AW-1:0] s_araddr,
    
    output wire          s_rvalid,
    input  wire          s_rready,
    output wire [DW-1:0] s_rdata,
    output wire [1:0]    s_rresp,

    // APB Master Interface
    output wire [AW-1:0] paddr,
    output wire          psel,
    output wire          penable,
    output wire          pwrite,
    output wire [DW-1:0] pwdata,
    output wire [(DW/8)-1:0] pstrb, // APB4 extension
    input  wire [DW-1:0] prdata,
    input  wire          pready,
    input  wire          pslverr
);

    // -------------------------------------------------------
    // State Machine for APB Bridge
    // -------------------------------------------------------
    // Iteration 4: one-outstanding sequencer. The Iteration-3/early-4 scheme
    // tracked requests with ambient aw_accepted/w_accepted/ar_accepted flags
    // and picked SETUP via "any request" branches — so an AR arriving beside
    // an unfinished AW started an APB transfer with the OLD pwrite/pwdata
    // (a garbage write that still answered OKAY). Now the request type is
    // LATCHED at acceptance and drives everything downstream.
    localparam IDLE   = 2'd0;
    localparam SETUP  = 2'd1;
    localparam ACCESS = 2'd2;

    reg [1:0] state, next_state;

    // Transaction registers — written ONLY at acceptance edges
    reg [AW-1:0]     addr_reg;
    reg [DW-1:0]     wdata_reg;
    reg [(DW/8)-1:0] wstrb_reg;
    reg              have_req;   // a request is latched, transfer pending
    reg              pend_wr;    // latched type: 1=write (needs W too), 0=read
    reg              w_got;      // current write's W beat captured

    wire aw_ack = s_awvalid && s_awready;
    wire w_ack  = s_wvalid  && s_wready;
    wire ar_ack = s_arvalid && s_arready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            addr_reg  <= {AW{1'b0}};
            wdata_reg <= {DW{1'b0}};
            wstrb_reg <= {(DW/8){1'b0}};
            have_req  <= 1'b0;
            pend_wr   <= 1'b0;
            w_got     <= 1'b0;
        end else begin
            state <= next_state;

            // Retire first, so a same-edge new request wins cleanly.
            if (state == ACCESS && pready) begin
                have_req <= 1'b0;
                w_got    <= 1'b0;
            end

            // Acceptances: AW has priority; AR only when nothing latched.
            if (aw_ack) begin
                addr_reg <= s_awaddr;
                pend_wr  <= 1'b1;
                have_req <= 1'b1;
            end
            if (w_ack) begin
                wdata_reg <= s_wdata;
                wstrb_reg <= s_wstrb;
                w_got     <= 1'b1;
            end
            if (ar_ack) begin
                addr_reg <= s_araddr;
                pend_wr  <= 1'b0;
                have_req <= 1'b1;
            end
        end
    end

    // Next state logic: a write transfers only once its W beat is in hand,
    // guaranteeing pwdata belongs to THIS address.
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (have_req && (!pend_wr || w_got))
                    next_state = SETUP;
            end
            SETUP:  next_state = ACCESS;
            ACCESS: if (pready) next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // AXI Ready Signals. Writes take priority (AW over AR) — enforced HERE,
    // not just by if-order: with independent readys, AW+AR in the same cycle
    // double-acked and the AR's NBA overwrote the AW latch, deadlocking the
    // write whose W could then never be accepted.
    assign s_awready = (state == IDLE) && !have_req;
    assign s_wready  = (state == IDLE) && have_req && pend_wr && !w_got;
    assign s_arready = (state == IDLE) && !have_req && !s_awvalid;

    // AXI Response Signals
    reg bvalid_reg;
    reg rvalid_reg;
    reg [1:0] bresp_reg;
    reg [1:0] rresp_reg;
    reg [DW-1:0] rdata_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bvalid_reg <= 1'b0;
            rvalid_reg <= 1'b0;
            bresp_reg  <= 2'b00;
            rresp_reg  <= 2'b00;
            rdata_reg  <= {DW{1'b0}};
        end else begin
            // Write response
            if (state == ACCESS && pready && pend_wr) begin
                bvalid_reg <= 1'b1;
                bresp_reg <= pslverr ? 2'b10 : 2'b00; // SLVERR -> SLVERR, else OKAY
            end else if (s_bready && bvalid_reg) begin
                bvalid_reg <= 1'b0;
            end

            // Read response
            if (state == ACCESS && pready && !pend_wr) begin
                rvalid_reg <= 1'b1;
                rdata_reg <= prdata;
                rresp_reg <= pslverr ? 2'b10 : 2'b00;
            end else if (s_rready && rvalid_reg) begin
                rvalid_reg <= 1'b0;
            end
        end
    end

    assign s_bvalid = bvalid_reg;
    assign s_bresp  = bresp_reg;
    
    assign s_rvalid = rvalid_reg;
    assign s_rdata  = rdata_reg;
    assign s_rresp  = rresp_reg;

    // APB Signals
    assign psel    = (state == SETUP || state == ACCESS);
    assign penable = (state == ACCESS);
    assign pwrite  = pend_wr;
    assign paddr   = addr_reg;
    assign pwdata  = wdata_reg;
    assign pstrb   = wstrb_reg;

endmodule

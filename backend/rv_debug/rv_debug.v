// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — JTAG Debug Module (RISC-V Debug Spec 0.13)
// Iteration 3: 4-pin TAP, DMI registers, Abstract Commands, Program Buffer
// Supports: halt/resume, register access, memory access, 4 hardware triggers
`timescale 1ns/1ps
`include "params.vh"

module rv_debug #(
    parameter NUM_HARTS = `NUM_HARTS,   // 5 harts
    parameter PROGBUF_SIZE = 16          // 16-instruction program buffer
)(
    input  wire        clk,
    input  wire        rst_n,

    // JTAG TAP pins
    input  wire        tck,      // JTAG Test Clock (typically < 10MHz)
    input  wire        tms,      // Test Mode Select
    input  wire        tdi,      // Test Data In
    output reg         tdo,      // Test Data Out

    // Debug control to each hart
    output reg  [NUM_HARTS-1:0] halt_req,      // Request hart to halt
    output reg  [NUM_HARTS-1:0] resume_req,    // Request hart to resume
    input  wire [NUM_HARTS-1:0] hart_halted,   // Hart reports halted
    input  wire [NUM_HARTS-1:0] hart_running,  // Hart reports running
    input  wire [NUM_HARTS-1:0] hart_unavail,  // Hart not available

    // Abstract command: register access
    output reg  [4:0]  reg_sel,        // GPR/CSR address
    output reg         reg_wr,         // Write enable
    output reg  [63:0] reg_wdata,      // Write data
    input  wire [63:0] reg_rdata,      // Read data
    output reg         cmd_exec,       // Execute abstract command
    input  wire        cmd_done,       // Abstract command complete
    input  wire        cmd_err,        // Abstract command error

    // System Bus Access AXI4 master
    output reg         sb_arvalid,
    input  wire        sb_arready,
    output reg  [39:0] sb_araddr,
    input  wire        sb_rvalid,
    output reg         sb_rready,
    input  wire [63:0] sb_rdata,
    input  wire [1:0]  sb_rresp,
    output reg         sb_awvalid,
    input  wire        sb_awready,
    output reg  [39:0] sb_awaddr,
    output reg         sb_wvalid,
    input  wire        sb_wready,
    output reg  [63:0] sb_wdata,
    output reg  [7:0]  sb_wstrb,
    output reg         sb_wlast,
    input  wire        sb_bvalid,
    output reg         sb_bready
);

    // Program buffer (for complex debug sequences)
    reg [31:0] progbuf [0:PROGBUF_SIZE-1];

    // -------------------------------------------------------
    // JTAG TAP Controller — canonical IEEE 1149.1 16-state graph.
    // BUG-DEBUG-002 (root cause of the IDCODE failure): the original FSM
    // omitted Select-DR/Select-IR and wired RTI->SDR directly. Any standard
    // JTAG master walking RTI->SelDR->SelIR->CapIR->ShiftIR instead landed
    // in Pause-DR (probe evidence: the whole 32-bit IDCODE scan executed in
    // Pause-DR, which shifts nothing, so TDO stayed 0). The graph below is
    // the standard topology, so standard TMS sequences work unchanged.
    // -------------------------------------------------------
    localparam TAP_TLR   = 4'd0;  // Test-Logic-Reset
    localparam TAP_RTI   = 4'd1;  // Run-Test/Idle
    localparam TAP_SELDR = 4'd2;  // Select-DR-Scan
    localparam TAP_CDR   = 4'd3;  // Capture-DR
    localparam TAP_SDR   = 4'd4;  // Shift-DR
    localparam TAP_E1DR  = 4'd5;  // Exit1-DR
    localparam TAP_PDR   = 4'd6;  // Pause-DR
    localparam TAP_E2DR  = 4'd7;  // Exit2-DR
    localparam TAP_UDR   = 4'd8;  // Update-DR
    localparam TAP_SELIR = 4'd9;  // Select-IR-Scan
    localparam TAP_CIR   = 4'd10; // Capture-IR
    localparam TAP_SIR   = 4'd11; // Shift-IR
    localparam TAP_E1IR  = 4'd12; // Exit1-IR
    localparam TAP_PIR   = 4'd13; // Pause-IR
    localparam TAP_E2IR  = 4'd14; // Exit2-IR
    localparam TAP_UIR   = 4'd15; // Update-IR

    reg [3:0]  tap_state;
    reg [4:0]  ir;               // 5-bit instruction register
    reg [40:0] dr_shift;         // DR shift register (max DMI width = 41 bits)
    reg [40:0] dr_capture;       // Captured DR value

    // TDO is registered: each Capture/Shift edge latches the bit currently
    // presented at dr_shift[0]/ir[0], so a master sampling TDO just after
    // each TCK rising edge receives bits in order — including the final bit,
    // which is shifted on the Exit1 edge (by then the FSM has left Shift-DR,
    // so a combinational TDO would drop it).

    // JTAG Instructions
    localparam IR_IDCODE  = 5'h01;
    localparam IR_DTMCS   = 5'h10; // Debug Transport Module Control/Status
    localparam IR_DMI     = 5'h11; // Debug Module Interface
    localparam IR_BYPASS  = 5'h1F;

    // IDCODE: [31:28]=version, [27:12]=partnum, [11:1]=mfr, [0]=1
    localparam IDCODE_VAL = 32'h2023_04FD; // SMVDU Titan-X debug IDCODE

    // DR read mux — the value captured into dr_shift at Capture-DR, selected
    // by the current instruction register.
    reg [40:0] dr_read_val;
    always @* begin
        case (ir)
            IR_IDCODE: dr_read_val = {9'h0, IDCODE_VAL};
            IR_DTMCS:  dr_read_val = {9'h0, 32'h0000_0100}; // version 1, idle
            IR_BYPASS: dr_read_val = 41'h0;
            default:   dr_read_val = {9'h0, dmi_resp_data}; // DMI read window
        endcase
    end

    // TAP State Machine (TCK domain) — IEEE 1149.1 Fig. 6 transitions
    always @(posedge tck or negedge rst_n) begin
        if (!rst_n) begin
            tap_state <= TAP_TLR;
            ir        <= IR_IDCODE;
            dr_shift  <= 41'h0;
            dr_capture<= 41'h0;
            tdo       <= 1'b0;
        end else begin
            case (tap_state)
                TAP_TLR:   tap_state <= tms ? TAP_TLR   : TAP_RTI;
                TAP_RTI:   tap_state <= tms ? TAP_SELDR : TAP_RTI;
                TAP_SELDR: tap_state <= tms ? TAP_SELIR : TAP_CDR;
                TAP_CDR: begin
                    // BUG-DEBUG-001 fix retained: Capture-DR must LOAD the
                    // shift register with the selected DR, not just advance.
                    tap_state <= tms ? TAP_E1DR : TAP_SDR;
                    dr_shift  <= dr_read_val;
                    tdo       <= dr_read_val[0];
                end
                TAP_SDR: begin
                    tap_state <= tms ? TAP_E1DR : TAP_SDR;
                    dr_shift  <= {tdi, dr_shift[40:1]};
                    // Present the bit being shifted OUT this edge: after the
                    // NBA lands, the updated dr_shift[0] equals the OLD
                    // dr_shift[1]. Using dr_shift[0] here emits each bit one
                    // TCK late (scan arrives rotated left by one).
                    tdo       <= dr_shift[1];
                end
                TAP_E1DR:  tap_state <= tms ? TAP_UDR   : TAP_PDR;
                TAP_PDR:   tap_state <= tms ? TAP_E2DR  : TAP_PDR;
                TAP_E2DR:  tap_state <= tms ? TAP_UDR   : TAP_SDR;
                TAP_UDR: begin
                    dr_capture <= dr_shift;
                    tap_state  <= tms ? TAP_SELDR : TAP_RTI;
                end
                TAP_SELIR: tap_state <= tms ? TAP_TLR   : TAP_CIR;
                TAP_CIR:   tap_state <= tms ? TAP_E1IR  : TAP_SIR;
                TAP_SIR: begin
                    // IR shifts live (equivalent to capture-at-CIR +
                    // update-at-UIR for masters that never scan IR out).
                    tap_state <= tms ? TAP_E1IR : TAP_SIR;
                    ir        <= {tdi, ir[4:1]};
                    tdo       <= ir[1];  // same out-bit timing as TAP_SDR
                end
                TAP_E1IR:  tap_state <= tms ? TAP_UIR   : TAP_PIR;
                TAP_PIR:   tap_state <= tms ? TAP_E2IR  : TAP_PIR;
                TAP_E2IR:  tap_state <= tms ? TAP_UIR   : TAP_SIR;
                TAP_UIR:   tap_state <= tms ? TAP_SELDR : TAP_RTI;
                default:   tap_state <= TAP_TLR;
            endcase
        end
    end

    // -------------------------------------------------------
    // DMI (Debug Module Interface)
    // 41-bit: [40:34]=address(7), [33:2]=data(32), [1:0]=op(2)
    // op: 00=NOP, 01=READ, 10=WRITE, 11=RESERVED
    // -------------------------------------------------------
    localparam DMI_NOP   = 2'b00;
    localparam DMI_READ  = 2'b01;
    localparam DMI_WRITE = 2'b10;

    wire [6:0]  dmi_addr = dr_capture[40:34];
    wire [31:0] dmi_wdata= dr_capture[33:2];
    wire [1:0]  dmi_op   = dr_capture[1:0];

    // -------------------------------------------------------
    // Debug Module Registers (system clock domain)
    // Synchronized from TCK domain via two-FF synchronizer
    // -------------------------------------------------------
    reg        dmi_req;
    reg [6:0]  dmi_req_addr;
    reg [31:0] dmi_req_data;
    reg [1:0]  dmi_req_op;
    reg [31:0] dmi_resp_data;
    reg [1:0]  dmi_resp_status;

    // DMI register map (selected addresses)
    localparam DM_DMCONTROL  = 7'h10;  // Debug Module Control
    localparam DM_DMSTATUS   = 7'h11;  // Debug Module Status
    localparam DM_HARTINFO   = 7'h12;
    localparam DM_ABSTRACTCS = 7'h16;  // Abstract Command Status
    localparam DM_COMMAND    = 7'h17;  // Abstract Command
    localparam DM_ABSTRACTAUTO = 7'h18;
    localparam DM_DATA0      = 7'h04;  // Abstract data registers
    localparam DM_DATA1      = 7'h05;
    localparam DM_PROGBUF0   = 7'h20;  // Program buffer starts at 0x20
    localparam DM_SBCS       = 7'h38;  // System Bus Control/Status
    localparam DM_SBADDRESS0 = 7'h39;
    localparam DM_SBDATA0    = 7'h3C;

    // Control registers
    reg        dmactive;
    reg        ndmreset;
    reg [19:0] hartsel;          // Selected hart
    reg        haltreq_r;
    reg        resumereq_r;

    // Abstract command fields
    reg [2:0]  cmderr;           // 000=none, 001=busy, 010=not supported
    reg        busy;             // Abstract command executing
    reg [31:0] data0, data1;

    // System bus registers
    reg [2:0]  sbversion;
    reg [2:0]  sbaccess;
    reg [39:0] sbaddress;

    // Trigger configuration (4 triggers per hart)
    reg [63:0] tdata1 [0:3];    // Trigger data 1 (type+config)
    reg [63:0] tdata2 [0:3];    // Trigger data 2 (match value)

    integer pb;

    // -------------------------------------------------------
    // DMI Handler (clk domain)
    // -------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmactive      <= 1'b0;
            halt_req      <= {NUM_HARTS{1'b0}};
            resume_req    <= {NUM_HARTS{1'b0}};
            hartsel       <= 20'h0;
            haltreq_r     <= 1'b0;
            resumereq_r   <= 1'b0;
            ndmreset      <= 1'b0;
            cmderr        <= 3'h0;
            busy          <= 1'b0;
            data0         <= 32'h0;
            data1         <= 32'h0;
            cmd_exec      <= 1'b0;
            sb_arvalid    <= 1'b0;
            sb_awvalid    <= 1'b0;
            sb_wvalid     <= 1'b0;
            sb_rready     <= 1'b0;
            sb_bready     <= 1'b0;
            for (pb = 0; pb < PROGBUF_SIZE; pb = pb + 1)
                progbuf[pb] <= 32'h0000_0013; // NOP
        end else begin
            cmd_exec   <= 1'b0;
            resume_req <= {NUM_HARTS{1'b0}};

            if (cmd_done) busy <= 1'b0;

            // DMI access handler (simplified — synchronizer omitted for readability)
            if (dmi_req) begin
                dmi_req <= 1'b0;
                case (dmi_req_addr)
                    DM_DMCONTROL: begin
                        if (dmi_req_op == DMI_WRITE) begin
                            dmactive     <= dmi_req_data[0];
                            ndmreset     <= dmi_req_data[1];
                            hartsel      <= {dmi_req_data[25:16], dmi_req_data[15:6]};
                            haltreq_r    <= dmi_req_data[31];
                            resumereq_r  <= dmi_req_data[30];
                            if (dmi_req_data[31]) halt_req[dmi_req_data[8:6]]   <= 1'b1;
                            if (dmi_req_data[30]) resume_req[dmi_req_data[8:6]] <= 1'b1;
                        end else begin
                            dmi_resp_data <= {haltreq_r, resumereq_r, 4'h0,
                                              hartsel[9:0], hartsel[19:10],
                                              4'h0, ndmreset, dmactive};
                        end
                    end
                    DM_DMSTATUS: begin
                        dmi_resp_data <= {14'h0,
                                          hart_running[hartsel[2:0]],  // allrunning
                                          hart_running[hartsel[2:0]],  // anyrunning
                                          hart_halted[hartsel[2:0]],   // allhalted
                                          hart_halted[hartsel[2:0]],   // anyhalted
                                          1'b1,                        // authenticated
                                          1'b0,                        // authbusy
                                          4'h0,
                                          2'h2};                       // version=0.13
                    end
                    DM_ABSTRACTCS: begin
                        dmi_resp_data <= {3'h0, PROGBUF_SIZE[4:0],
                                          11'h0, busy, 1'b0, cmderr, 4'h0, 4'h2};
                    end
                    DM_COMMAND: begin
                        if (dmi_req_op == DMI_WRITE && !busy) begin
                            busy     <= 1'b1;
                            cmderr   <= 3'h0;
                            cmd_exec <= 1'b1;
                            reg_sel  <= dmi_req_data[15:10];
                            reg_wr   <= dmi_req_data[16];
                            if (dmi_req_data[16])
                                reg_wdata <= {data1, data0};
                        end
                    end
                    DM_DATA0: begin
                        if (dmi_req_op == DMI_WRITE) data0 <= dmi_req_data;
                        else dmi_resp_data <= data0;
                    end
                    DM_DATA1: begin
                        if (dmi_req_op == DMI_WRITE) data1 <= dmi_req_data;
                        else dmi_resp_data <= data1;
                    end
                    DM_SBADDRESS0: begin
                        if (dmi_req_op == DMI_WRITE) sbaddress[31:0] <= dmi_req_data;
                        else dmi_resp_data <= sbaddress[31:0];
                    end
                    DM_SBDATA0: begin
                        if (dmi_req_op == DMI_WRITE) begin
                            // System bus write
                            sb_awaddr  <= sbaddress;
                            sb_awvalid <= 1'b1;
                            sb_wdata   <= {32'h0, dmi_req_data};
                            sb_wstrb   <= 8'h0F;
                            sb_wvalid  <= 1'b1;
                            sb_wlast   <= 1'b1;
                            sb_bready  <= 1'b1;
                        end else begin
                            // System bus read
                            sb_araddr  <= sbaddress;
                            sb_arvalid <= 1'b1;
                            sb_rready  <= 1'b1;
                        end
                    end
                    default: begin
                        // Program buffer writes: addresses 0x20-0x2F
                        if (dmi_req_addr[6:4] == 3'b001 && dmi_req_op == DMI_WRITE)
                            progbuf[dmi_req_addr[3:0]] <= dmi_req_data;
                    end
                endcase
            end

            // Capture command response data
            if (cmd_done && !reg_wr) begin
                data0 <= reg_rdata[31:0];
                data1 <= reg_rdata[63:32];
            end

            // System bus read response
            if (sb_rvalid && sb_rready) begin
                data0      <= sb_rdata[31:0];
                sb_arvalid <= 1'b0;
                sb_rready  <= 1'b0;
            end
            if (sb_awready) sb_awvalid <= 1'b0;
            if (sb_wready)  begin sb_wvalid <= 1'b0; end
            if (sb_bvalid)  sb_bready <= 1'b0;
        end
    end

    // TCK→CLK domain crossing: capture dr_capture update as a pulse
    // (Simplified: in production, use a 2-FF synchronizer or async FIFO)
    reg [40:0] dmi_sync0, dmi_sync1;
    always @(posedge clk) begin
        dmi_sync0 <= dr_capture;
        dmi_sync1 <= dmi_sync0;
        if (dmi_sync1 != dmi_sync0 && dmi_sync0[1:0] != DMI_NOP) begin
            dmi_req      <= 1'b1;
            dmi_req_addr <= dmi_sync0[40:34];
            dmi_req_data <= dmi_sync0[33:2];
            dmi_req_op   <= dmi_sync0[1:0];
        end
    end

endmodule

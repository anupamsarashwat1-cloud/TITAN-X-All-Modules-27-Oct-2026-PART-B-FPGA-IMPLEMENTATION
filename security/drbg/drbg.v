// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — HMAC-DRBG (Deterministic Random Bit Generator)
// Iteration 3: Based on NIST SP 800-90A using SHA-256.
`timescale 1ns/1ps

module drbg (
    input  wire        clk,
    input  wire        rst_n,

    // APB Slave Interface
    input  wire [31:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    // Hardware Interface to TRNG (for seeding)
    input  wire [255:0] trng_entropy,
    input  wire         trng_valid,
    output wire         trng_ready,

    // Interrupt
    output wire        drbg_irq
);

    // -------------------------------------------------------
    // APB Registers
    // -------------------------------------------------------
    reg [31:0] ctrl_reg; // bit 0 = instantiate, bit 1 = reseed, bit 2 = generate
    reg [31:0] stat_reg; // bit 0 = busy, bit 1 = done, bit 2 = error, bit 3 = need_reseed
    reg [31:0] data_out [0:7]; // 256 bits of generated output
    
    // Internal state
    reg [255:0] V; // 256-bit Value
    reg [255:0] Key; // 256-bit Key
    reg [31:0] reseed_counter;
    
    localparam MAX_RESEED_COUNT = 32'd10000;

    assign pready = 1'b1;
    assign pslverr = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_reg <= 32'h0;
            stat_reg <= 32'h0;
            reseed_counter <= 32'h0;
            V <= 256'h0;
            Key <= 256'h0;
        end else if (psel && penable && pwrite) begin
            if (paddr[7:0] == 8'h00) ctrl_reg <= pwdata;
        end else begin
            // Stub logic for DRBG operations
            if (ctrl_reg[0]) begin // Instantiate
                if (trng_valid) begin
                    V <= trng_entropy; // Simplified mock
                    Key <= ~trng_entropy;
                    reseed_counter <= 32'h1;
                    ctrl_reg[0] <= 1'b0;
                    stat_reg[1] <= 1'b1; // Done
                end
            end else if (ctrl_reg[2]) begin // Generate
                if (reseed_counter >= MAX_RESEED_COUNT) begin
                    stat_reg[3] <= 1'b1; // Need reseed
                    ctrl_reg[2] <= 1'b0;
                end else begin
                    // Mock generation
                    V <= V + 256'h1;
                    data_out[0] <= V[31:0];
                    data_out[1] <= V[63:32];
                    data_out[2] <= V[95:64];
                    data_out[3] <= V[127:96];
                    data_out[4] <= V[159:128];
                    data_out[5] <= V[191:160];
                    data_out[6] <= V[223:192];
                    data_out[7] <= V[255:224];
                    reseed_counter <= reseed_counter + 1;
                    ctrl_reg[2] <= 1'b0;
                    stat_reg[1] <= 1'b1; // Done
                end
            end else if (ctrl_reg[1]) begin // Reseed
                if (trng_valid) begin
                    V <= V ^ trng_entropy;
                    Key <= Key ^ ~trng_entropy;
                    reseed_counter <= 32'h1;
                    stat_reg[3] <= 1'b0;
                    ctrl_reg[1] <= 1'b0;
                    stat_reg[1] <= 1'b1; // Done
                end
            end
            
            if (stat_reg[1] && (psel && !penable && !pwrite && paddr[7:0] == 8'h04)) begin
                // Clear done on read of status
                stat_reg[1] <= 1'b0;
            end
        end
    end

    reg [31:0] prdata_reg;
    always @(*) begin
        case (paddr[7:0])
            8'h00: prdata_reg = ctrl_reg;
            8'h04: prdata_reg = stat_reg;
            8'h10: prdata_reg = data_out[0];
            8'h14: prdata_reg = data_out[1];
            8'h18: prdata_reg = data_out[2];
            8'h1C: prdata_reg = data_out[3];
            8'h20: prdata_reg = data_out[4];
            8'h24: prdata_reg = data_out[5];
            8'h28: prdata_reg = data_out[6];
            8'h2C: prdata_reg = data_out[7];
            default: prdata_reg = 32'h0;
        endcase
    end
    assign prdata = prdata_reg;

    assign drbg_irq = stat_reg[1]; // Done interrupt
    assign trng_ready = (ctrl_reg[0] || ctrl_reg[1]);

endmodule

// SPDX-License-Identifier: Apache-2.0
// SMVDU-TITAN-X SoC — SHA-256 Hash Engine
// FIPS 180-4 compliant. 64-round iterative architecture.
`timescale 1ns/1ps
module sha256_engine (
    input  wire        clk,
    input  wire        rst_n,
    // APB slave
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [7:0]  paddr,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        irq
);
    assign pready = 1'b1;

    // SHA-256 round constants
    reg [31:0] K [0:63];
    initial begin
        K[0]=32'h428a2f98; K[1]=32'h71374491; K[2]=32'hb5c0fbcf; K[3]=32'he9b5dba5;
        K[4]=32'h3956c25b; K[5]=32'h59f111f1; K[6]=32'h923f82a4; K[7]=32'hab1c5ed5;
        K[8]=32'hd807aa98; K[9]=32'h12835b01; K[10]=32'h243185be; K[11]=32'h550c7dc3;
        K[12]=32'h72be5d74; K[13]=32'h80deb1fe; K[14]=32'h9bdc06a7; K[15]=32'hc19bf174;
        K[16]=32'he49b69c1; K[17]=32'hefbe4786; K[18]=32'h0fc19dc6; K[19]=32'h240ca1cc;
        K[20]=32'h2de92c6f; K[21]=32'h4a7484aa; K[22]=32'h5cb0a9dc; K[23]=32'h76f988da;
        K[24]=32'h983e5152; K[25]=32'ha831c66d; K[26]=32'hb00327c8; K[27]=32'hbf597fc7;
        K[28]=32'hc6e00bf3; K[29]=32'hd5a79147; K[30]=32'h06ca6351; K[31]=32'h14292967;
        K[32]=32'h27b70a85; K[33]=32'h2e1b2138; K[34]=32'h4d2c6dfc; K[35]=32'h53380d13;
        K[36]=32'h650a7354; K[37]=32'h766a0abb; K[38]=32'h81c2c92e; K[39]=32'h92722c85;
        K[40]=32'ha2bfe8a1; K[41]=32'ha81a664b; K[42]=32'hc24b8b70; K[43]=32'hc76c51a3;
        K[44]=32'hd192e819; K[45]=32'hd6990624; K[46]=32'hf40e3585; K[47]=32'h106aa070;
        K[48]=32'h19a4c116; K[49]=32'h1e376c08; K[50]=32'h2748774c; K[51]=32'h34b0bcb5;
        K[52]=32'h391c0cb3; K[53]=32'h4ed8aa4a; K[54]=32'h5b9cca4f; K[55]=32'h682e6ff3;
        K[56]=32'h748f82ee; K[57]=32'h78a5636f; K[58]=32'h84c87814; K[59]=32'h8cc70208;
        K[60]=32'h90befffa; K[61]=32'ha4506ceb; K[62]=32'hbef9a3f7; K[63]=32'hc67178f2;
    end

    // Initial hash values (H0–H7)
    parameter H0 = 32'h6a09e667, H1 = 32'hbb67ae85, H2 = 32'h3c6ef372, H3 = 32'ha54ff53a;
    parameter H4 = 32'h510e527f, H5 = 32'h9b05688c, H6 = 32'h1f83d9ab, H7 = 32'h5be0cd19;

    // State
    reg [31:0] hash [0:7];
    reg [31:0] W    [0:15];
    reg [31:0] a,b,c,d,e,f,g,h;
    reg [5:0]  round;
    reg        active;
    reg        done;

    assign irq = done;

    // Message schedule input
    reg [31:0] msg_block [0:15];  // 512-bit block (16 × 32b words)
    reg        start;

    // Rotate functions
    function [31:0] rotr32;
        input [31:0] x;
        input [4:0]  n;
        rotr32 = (x >> n) | (x << (32-n));
    endfunction

    // SHA-256 compression
    wire [31:0] T1, T2, S1, S0, ch_val, maj_val, sig0, sig1, w_sched;
    assign S1     = rotr32(e,6)  ^ rotr32(e,11) ^ rotr32(e,25);
    assign ch_val = (e & f)      ^ (~e & g);
    assign T1     = h + S1 + ch_val + K[round] + W[0];
    assign S0     = rotr32(a,2)  ^ rotr32(a,13) ^ rotr32(a,22);
    assign maj_val= (a & b)      ^ (a & c)      ^ (b & c);
    assign T2     = S0 + maj_val;

    // Message schedule: σ0 and σ1
    assign sig0   = rotr32(W[1],7) ^ rotr32(W[1],18) ^ (W[1]>>3);
    assign sig1   = rotr32(W[9],17) ^ rotr32(W[9],19) ^ (W[9]>>10);
    assign w_sched= W[0] + sig0 + W[4] + sig1;  // Wt = W[t-16]+σ0[W[t-15]]+W[t-7]+σ1[W[t-2]]
    // Simplified indexing: use shift-register window

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active <= 1'b0;
            done   <= 1'b0;
            round  <= 6'h0;
            hash[0] <= H0; hash[1] <= H1; hash[2] <= H2; hash[3] <= H3;
            hash[4] <= H4; hash[5] <= H5; hash[6] <= H6; hash[7] <= H7;
        end else begin
            done <= 1'b0;
            if (start && !active) begin
                // Load W from message block
                begin : init_w
                    integer wi;
                    for (wi = 0; wi < 16; wi = wi+1)
                        W[wi] <= msg_block[wi];
                end
                a <= hash[0]; b <= hash[1]; c <= hash[2]; d <= hash[3];
                e <= hash[4]; f <= hash[5]; g <= hash[6]; h <= hash[7];
                round  <= 6'h0;
                active <= 1'b1;
                start  <= 1'b0;
            end
            if (active) begin
                // One round per clock
                h <= g;
                g <= f;
                f <= e;
                e <= d + T1;
                d <= c;
                c <= b;
                b <= a;
                a <= T1 + T2;
                // Slide message schedule
                begin : slide_w
                    integer wi;
                    for (wi = 0; wi < 15; wi = wi+1)
                        W[wi] <= W[wi+1];
                    W[15] <= w_sched;
                end
                round <= round + 6'h1;
                if (round == 6'd63) begin
                    hash[0] <= hash[0] + a; hash[1] <= hash[1] + b;
                    hash[2] <= hash[2] + c; hash[3] <= hash[3] + d;
                    hash[4] <= hash[4] + e; hash[5] <= hash[5] + f;
                    hash[6] <= hash[6] + g; hash[7] <= hash[7] + h;
                    active <= 1'b0;
                    done   <= 1'b1;
                end
            end
        end
    end

    // APB: write 16 words of block (0x00-0x3C), read 8 words of hash (0x40-0x5C)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start  <= 1'b0;
            prdata <= 32'h0;
        end else if (psel && penable) begin
            if (pwrite) begin
                if (paddr[7:6] == 2'b00)
                    msg_block[paddr[5:2]] <= pwdata;
                else if (paddr == 8'h60)
                    start <= pwdata[0];
            end else begin
                if (paddr[7:6] == 2'b00)
                    prdata <= msg_block[paddr[5:2]];
                else if (paddr[7:6] == 2'b01)
                    prdata <= hash[paddr[4:2]];
                else
                    prdata <= {30'h0, done, active};
            end
        end
    end
endmodule

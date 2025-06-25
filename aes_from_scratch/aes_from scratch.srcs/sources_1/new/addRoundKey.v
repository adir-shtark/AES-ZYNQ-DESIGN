`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// AES Key Expansion Module - Clean and Synthesizable
//////////////////////////////////////////////////////////////////////////////////

module key_expansion (
    input wire clk,
    input wire reset,
    input wire start,
    input wire [127:0] key_in,
    output reg [1407:0] round_keys, // 11 * 128 bits
    output reg done
);

    // State Encoding
    localparam S_IDLE   = 2'd0,
               S_INIT   = 2'd1,
               S_EXPAND = 2'd2,
               S_DONE   = 2'd3;

    reg [1:0] state = S_IDLE;
    reg [3:0] round;
    reg [7:0] rcon;
    reg [31:0] w [0:43]; // 44 words = 11 rounds * 4 words

    wire [31:0] rotword;
    wire [31:0] subword;
    wire [31:0] rcon_xor;

    assign rotword = {w[(round - 1) * 4 + 3][23:0], w[(round - 1) * 4 + 3][31:24]};
    assign rcon_xor = subword ^ {rcon, 24'h000000};

    // Instantiate S-box for SubWord operation
    sbox s0(.in(rotword[31:24]), .out(subword[31:24]));
    sbox s1(.in(rotword[23:16]), .out(subword[23:16]));
    sbox s2(.in(rotword[15:8]),  .out(subword[15:8]));
    sbox s3(.in(rotword[7:0]),   .out(subword[7:0]));

    integer i;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_IDLE;
            round <= 0;
            rcon <= 8'h01;
            done <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        // Load initial key into w[0..3]
                        w[0] <= key_in[127:96];
                        w[1] <= key_in[95:64];
                        w[2] <= key_in[63:32];
                        w[3] <= key_in[31:0];
                        round <= 1;
                        rcon <= 8'h01;
                        done <= 0;
                        state <= S_EXPAND;
                    end
                end

                S_EXPAND: begin
                    // Compute next 4 words of the key
                    w[round * 4 + 0] <= w[(round - 1) * 4 + 0] ^ rcon_xor;
                    w[round * 4 + 1] <= w[(round - 1) * 4 + 1] ^ (w[round * 4 + 0]);
                    w[round * 4 + 2] <= w[(round - 1) * 4 + 2] ^ (w[round * 4 + 1]);
                    w[round * 4 + 3] <= w[(round - 1) * 4 + 3] ^ (w[round * 4 + 2]);

                    // Update rcon and round
                    rcon <= {rcon[6:0], 1'b0} ^ (rcon[7] ? 8'h1B : 8'h00);

                    if (round == 10) begin
                        state <= S_DONE;
                    end else begin
                        round <= round + 1;
                    end
                end

                S_DONE: begin
                    // Pack round_keys
                    for (i = 0; i < 44; i = i + 1)
                        round_keys[1407 - i * 32 -: 32] <= w[i];

                    done <= 1;
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule

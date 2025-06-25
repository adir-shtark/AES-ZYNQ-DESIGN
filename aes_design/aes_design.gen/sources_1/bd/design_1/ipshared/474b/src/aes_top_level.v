`timescale 1ns / 1ps
// ===============================
// AES Top-Level Module with AXI-Stream Interface
// ===============================

module aes_top_level(
    input  wire        aclk,
    input  wire        aresetn,

    // AXIS Slave Interface for receiving key and plaintext
    input  wire [31:0]  s_axis_tdata,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    input  wire [3:0]   s_axis_tkeep,
    input  wire         s_axis_tlast,

    // AXIS Master Interface for outputting ciphertext
    output reg  [31:0]  m_axis_tdata,
    output reg          m_axis_tvalid,
    input  wire         m_axis_tready,
    output reg  [3:0]   m_axis_tkeep,
    output reg          m_axis_tlast
);

    // ===============================
    // State Machine Declarations
    // ===============================
    localparam IDLE       = 3'd0;
    localparam LOAD_KEY   = 3'd1;
    localparam LOAD_TEXT  = 3'd2;
    localparam EXPAND_KEY = 3'd3;
    localparam ENCRYPT    = 3'd4;
    localparam LAST_ROUND = 3'd5;
    localparam SEND       = 3'd6;

    reg [2:0] state_reg, state_next;

    // ===============================
    // Internal Registers
    // ===============================
    reg [127:0] key_reg;          // Stores 128-bit AES key
    reg [127:0] state_reg_aes;    // Intermediate AES state
    reg [127:0] ciphertext_reg;   // Final ciphertext

    reg [2:0] input_counter;      // Counts 32-bit words received (4 words per 128-bit input)
    reg [1:0] output_counter;     // Counts 32-bit output words
    reg [3:0] round_counter;      // AES round counter (0-9)

    reg start_key_expansion;      // Triggers key expansion
    reg input_counter_reset;
    reg round_counter_reset;      //restart the round counter when going to ENCRYPT
    reg output_counter_reset;
    reg apply_initial_round_key;  // Signal to perform AddRoundKey step

    // ===============================
    // Wires for Submodules
    // ===============================
    wire key_exp_done;
    wire [1407:0] round_keys;       // 11 round keys (128 bits each)
    wire [127:0] round_output;      // Output of standard AES round
    wire [127:0] last_output;       // Output of final AES round

    // ===============================
    // AXIS Ready Signal
    // ===============================
    assign s_axis_tready = (state_reg == LOAD_KEY || state_reg == LOAD_TEXT);

    // ===============================
    // Key Expansion Module
    // ===============================
    key_expansion key_exp (
        .clk(aclk),
        .reset(~aresetn),
        .start(start_key_expansion),
        .key_in(key_reg),
        .round_keys(round_keys),
        .done(key_exp_done)
    );

    // AES round (SubBytes + ShiftRows + MixColumns + AddRoundKey)
    aes_round_core aes_core (
        .state_in(state_reg_aes ^ round_keys[127:0]),
        .state_out(round_output)
    );

    // Final round (SubBytes + ShiftRows + AddRoundKey only)
    last_round_core last_core (
        .state_in(state_reg_aes ^ round_keys[1407 -: 128]),
        .state_out(last_output)
    );

    // ===============================
    // Sequential Logic (clocked FSM)
    // ===============================
    always @(posedge aclk) begin
        if (!aresetn) begin
            // Reset all states and counters
            state_reg <= IDLE;
            input_counter <= 0;
            output_counter <= 0;
            m_axis_tvalid <= 0;
            m_axis_tdata <= 0;
            m_axis_tkeep <= 4'h0;
            m_axis_tlast <= 0;
            round_counter <= 0;
            state_reg_aes <= 0;
        end else begin
            // Update FSM state
            state_reg <= state_next;

            // Reset or increment input counter
            if (input_counter_reset)
                input_counter <= 0;
            else if (s_axis_tvalid && s_axis_tready)
                input_counter <= input_counter + 1;

            // Reset or increment round counter
            if (round_counter_reset)
                round_counter <= 0;
            else if (state_reg == ENCRYPT)
                round_counter <= round_counter + 1;

            // Reset or increment output counter
            if (output_counter_reset)
                output_counter <= 0;
            else if (state_reg == SEND && m_axis_tready)
                output_counter <= output_counter + 1;

            // Input collection for key and plaintext
            if (s_axis_tvalid && s_axis_tready) begin
                case (state_reg)
                    LOAD_KEY:   key_reg <= {key_reg[95:0], s_axis_tdata};
                    LOAD_TEXT:  state_reg_aes <= {state_reg_aes[95:0], s_axis_tdata};
                endcase
            end

            // First AddRoundKey step
            if (apply_initial_round_key)
                state_reg_aes <= state_reg_aes ^ round_keys[127:0];

            // AES round transformation
            if (state_reg == ENCRYPT)
                state_reg_aes <= round_output ^ round_keys[(round_counter+1)*128 +: 128];

            // Output ciphertext data via AXIS
            if (state_reg == SEND && m_axis_tready) begin
                m_axis_tdata <= ciphertext_reg[127 - output_counter*32 -: 32];
                m_axis_tvalid <= 1;
                m_axis_tkeep <= 4'hF;
                m_axis_tlast <= (output_counter == 3);

                if (output_counter == 3)
                    m_axis_tvalid <= 0;
            end
        end
    end

    // ===============================
    // Combinational Logic (Next State Logic)
    // ===============================
    always @(*) begin
        // Default values
        state_next = state_reg;
        start_key_expansion = 0;
        input_counter_reset = 0;
        round_counter_reset = 0;
        output_counter_reset = 0;
        apply_initial_round_key = 0;

        // State transition logic
        case (state_reg)
            IDLE: begin
                if (s_axis_tvalid) begin
                    state_next = LOAD_KEY;
                    input_counter_reset = 1;
                end
            end

            LOAD_KEY: begin
                if (input_counter == 4) begin
                    start_key_expansion = 1;
                    state_next = EXPAND_KEY;
                    input_counter_reset = 1;
                end
            end

            EXPAND_KEY: begin
                if (key_exp_done) begin
                    state_next = LOAD_TEXT;
                end
            end

            LOAD_TEXT: begin
                if (input_counter == 4) begin
                    state_next = ENCRYPT;
                    round_counter_reset = 1;
                    apply_initial_round_key = 1;
                end
            end

            ENCRYPT: begin
                if (round_counter == 9) begin
                    state_next = LAST_ROUND;
                end
            end

            LAST_ROUND: begin
                ciphertext_reg = last_output;
                output_counter_reset = 1;
                state_next = SEND;
            end

            SEND: begin
                if (output_counter == 4 && m_axis_tready) begin
                    state_next = IDLE;
                end
            end
        endcase
    end

endmodule

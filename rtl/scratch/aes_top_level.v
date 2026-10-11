`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// AES Top-Level Module with AXI-Stream Interface
//////////////////////////////////////////////////////////////////////////////////
// This module receives a 128-bit key and 128-bit plaintext via AXI Stream,
// performs AES encryption using an internal FSM and outputs the ciphertext
// over AXI Stream as four 32-bit words.

module aes_top_level(
    input  wire        aclk,         // System clock
    input  wire        aresetn,      // Active-low reset

    // AXI-Stream Slave Interface (input: key and plaintext)
    input  wire [31:0] s_axis_tdata,  // Input data (32-bit chunks)
    input  wire        s_axis_tvalid, // Input valid signal
    output wire        s_axis_tready, // Input ready signal
    input  wire [3:0]  s_axis_tkeep,  // Byte-enable (not used for 128-bit block)
    input  wire        s_axis_tlast,  // End of packet signal (not explicitly used for fixed 4-word block)

    // AXI-Stream Master Interface (output: ciphertext)
    output reg  [31:0] m_axis_tdata,  // Output data (32-bit chunks)
    output reg         m_axis_tvalid, // Output valid signal
    input  wire        m_axis_tready, // Output ready signal
    output reg  [3:0]  m_axis_tkeep,  // Byte-enable (always 0xF = full word)
    output reg         m_axis_tlast   // End of packet signal (asserted for the last 32-bit word)
);

    // ===============================
    // FSM State Encoding
    // ===============================
    localparam IDLE         = 3'd0; // Waiting for start signal (s_axis_tvalid for key)
    localparam LOAD_KEY     = 3'd1; // Loading 128-bit key (4 x 32-bit words)
    localparam EXPAND_KEY   = 3'd2; // Key expansion in progress
    localparam LOAD_TEXT    = 3'd3; // Loading 128-bit plaintext (4 x 32-bit words)
    localparam ENCRYPT      = 3'd4; // Performing regular AES rounds (Rounds 1-9)
    localparam LAST_ROUND   = 3'd5; // Performing the final AES round (Round 10)
    localparam SEND         = 3'd6; // Sending 128-bit ciphertext (4 x 32-bit words)

    // FSM state registers
    reg [2:0] state_reg, state_next;

    // ===============================
    // Internal Registers
    // ===============================
    reg [127:0] key_reg;             // Stores the 128-bit input key
    reg [127:0] state_reg_aes;       // Stores the current 128-bit AES state during encryption
    reg [127:0] ciphertext_reg;      // Stores the final 128-bit ciphertext before outputting

    reg [2:0]  input_counter;        // Counts received 32-bit words for key/plaintext (0 to 3 for 4 words)
    reg [1:0]  output_counter;       // Counts transmitted 32-bit words for ciphertext (0 to 3 for 4 words)
    reg [3:0]  round_counter;        // AES encryption round counter (0 to 9 for 10 rounds after initial AR)

    // FSM control signals (combinational outputs from next-state logic)
    reg start_key_expansion;         // Triggers key_expansion module to start
    reg input_counter_reset;         // Resets input_counter
    reg round_counter_reset;         // Resets round_counter
    reg output_counter_reset;        // Resets output_counter
    reg apply_initial_round_key;     // Flag to apply the initial AddRoundKey (K0)

    // ===============================
    // AES Module Wires (outputs from sub-modules)
    // ===============================
    wire key_exp_done;               // Done signal from key expansion module
    wire [1407:0] round_keys;        // Expanded round keys (11 ª 128-bit: K0 to K10)
    wire [127:0] round_output;       // Combinational output of regular AES round core (SB+SR+MC)
    wire [127:0] last_output;        // Combinational output of final AES round core (SB+SR)

    // AXIS input ready is asserted when the module is in data loading states
    assign s_axis_tready = (state_reg == LOAD_KEY || state_reg == LOAD_TEXT);

    // ===============================
    // AES Submodule Instantiations
    // ===============================

    // Key Expansion Module
    // Generates 11 128-bit round keys (K0 to K10) from the input 128-bit key
    key_expansion key_exp (
        .clk(aclk),
        .reset(~aresetn),            // active-low reset
        .start(start_key_expansion), // Controlled by FSM
        .key_in(key_reg),            // 128-bit input key
        .round_keys(round_keys),     // Output: 11 * 128-bit expanded keys
        .done(key_exp_done)          // Done signal from key expansion
    );

    // AES Round Core (SubBytes + ShiftRows + MixColumns)
    // This module performs SB, SR, MC on its input state. It DOES NOT perform AddRoundKey.
    // The AddRoundKey operation is handled at this top level module.
    aes_round_core aes_core (
        .state_in(state_reg_aes), // Input is the state after the previous AddRoundKey
        .state_out(round_output)  // Output is the state after SB+SR+MC
    );

    // Final AES Round (SubBytes + ShiftRows only)
    // This module performs SB, SR on its input state. It DOES NOT perform AddRoundKey.
    // The AddRoundKey operation is handled at this top level module.
    last_round_core last_core (
        .state_in(state_reg_aes), // Input is the state after Round 9 AddRoundKey
        .state_out(last_output)   // Output is the state after SB+SR
    );

    // ===============================
    // Sequential Logic (State Registers, Counters, AES State, AXI Outputs)
    // ===============================
    always @(posedge aclk) begin
        if (!aresetn) begin
            // Reset everything on active-low reset
            state_reg         <= IDLE;
            input_counter     <= 0;
            output_counter    <= 0;
            round_counter     <= 0;
            m_axis_tvalid     <= 0;
            m_axis_tdata      <= 0;
            m_axis_tkeep      <= 0;
            m_axis_tlast      <= 0;
            state_reg_aes     <= 0;
            key_reg           <= 0;
            ciphertext_reg    <= 0;
        end else begin
            // FSM state update (from combinational next-state logic)
            state_reg <= state_next;

            // Input data counter update
            // Increments when data is valid and module is ready (handshake)
            if (input_counter_reset)
                input_counter <= 0;
            else if (s_axis_tvalid && s_axis_tready)
                input_counter <= input_counter + 1;

            // AES round counter update
            // Increments during the ENCRYPT state for each regular round
            if (round_counter_reset)
                round_counter <= 0;
            else if (state_reg == ENCRYPT) // Increment for each regular AES round (Rounds 1-9)
                round_counter <= round_counter + 1;

            // Output data counter update
            // Increments when data is valid and master is ready (handshake)
            if (output_counter_reset)
                output_counter <= 0;
            else if (state_reg == SEND && m_axis_tready)
                output_counter <= output_counter + 1;

            // Register input data (key or plaintext) based on current state
            // Data is shifted in 32-bit chunks to build the 128-bit word (LSB first)
            if (s_axis_tvalid && s_axis_tready) begin
                case (state_reg)
                    LOAD_KEY:  key_reg <= {key_reg[95:0], s_axis_tdata};
                    LOAD_TEXT: state_reg_aes <= {state_reg_aes[95:0], s_axis_tdata};
                    default: ; // Do nothing if not in loading state
                endcase
            end

            // =====================================================================
            // AES Core Operations & State Update (AddRoundKey at top level)
            // =====================================================================

            // Initial AddRoundKey (Round 0)
            // This happens on the clock edge when transitioning from LOAD_TEXT to ENCRYPT
            // state_reg_aes initially holds the plaintext.
            // round_keys[0*128 +: 128] refers to K0.
            if (apply_initial_round_key) begin
                state_reg_aes <= state_reg_aes ^ round_keys[0*128 +: 128];
            end
            // Regular AES Rounds (Rounds 1 to 9)
            // This occurs in the ENCRYPT state.
            // state_reg_aes on the RHS is the result of the previous round's AddRoundKey.
            // round_output is the result of SB(SR(MC(state_reg_aes_old)))
            // round_keys[(round_counter + 1)*128 +: 128] selects K1 to K9.
            else if (state_reg == ENCRYPT) begin
                state_reg_aes <= round_output ^ round_keys[(round_counter + 1)*128 +: 128];
            end
            // Final AES Round (Round 10)
            // This occurs when entering the LAST_ROUND state.
            // state_reg_aes on the RHS is the result of Round 9's AddRoundKey.
            // last_output is SB(SR(state_reg_aes_old))
            // round_keys[10*128 +: 128] selects K10.
            else if (state_reg == LAST_ROUND) begin
                ciphertext_reg <= last_output ^ round_keys[10*128 +: 128];
            end

            // Drive AXI Stream output signals based on the SEND state and handshake
            // Output data (ciphertext) is driven MSB first (32-bit chunks)
            if (state_reg == SEND && m_axis_tready) begin
                m_axis_tdata  <= ciphertext_reg[127 - output_counter*32 -: 32];
                m_axis_tvalid <= 1;    // Assert valid when data is driven and master is ready
                m_axis_tkeep  <= 4'hF; // All bytes are valid
                m_axis_tlast  <= (output_counter == 3); // Assert last for the final 32-bit word
            end else begin
                // FIXED: Explicitly assign ALL output registers in the else branch to prevent 'X' propagation.
                m_axis_tvalid <= 0;
                m_axis_tdata  <= 0;    // <-- CRITICAL FIX: Ensure m_axis_tdata is always driven.
                m_axis_tkeep  <= 0;    // <-- CRITICAL FIX: Ensure m_axis_tkeep is always driven.
                m_axis_tlast  <= 0;
            end
        end
    end

    // ===============================
    // Combinational Logic (Next State Logic and Control Signals)
    // ===============================
    always @(*) begin
        // Default signal values to prevent inferred latches
        state_next                = state_reg;
        start_key_expansion       = 0;
        input_counter_reset       = 0;
        round_counter_reset       = 0;
        output_counter_reset      = 0;
        apply_initial_round_key   = 0;

        // FSM transitions based on current state and conditions
        case (state_reg)
            IDLE: begin
                // In IDLE, wait for s_axis_tvalid to indicate incoming key
                if (s_axis_tvalid) begin
                    state_next = LOAD_KEY;
                    input_counter_reset = 1; // Reset counter for key loading
                end
            end

            LOAD_KEY: begin
                // Key loading is complete after 4 words (input_counter goes 0,1,2,3)
                if (input_counter == 4) begin
                    state_next = EXPAND_KEY;
                    start_key_expansion = 1; // Start the key expansion process
                    input_counter_reset = 1; // Reset counter for plaintext loading
                end
            end

            EXPAND_KEY: begin
                // Wait for the key expansion module to complete
                if (key_exp_done) begin
                    state_next = LOAD_TEXT;
                end
            end

            LOAD_TEXT: begin
                // Plaintext loading is complete after 4 words
                if (input_counter == 4) begin
                    state_next = ENCRYPT;
                    round_counter_reset = 1;        // Reset round counter to 0 for R0
                    apply_initial_round_key = 1;    // Flag to apply K0 in the next cycle
                end
            end

            ENCRYPT: begin
                // Loop through 9 regular AES rounds (Rounds 1 to 9)
                // When round_counter reaches 9, all 9 regular rounds are done.
                if (round_counter == 9) begin
                    state_next = LAST_ROUND; // Move to the final round
                end
            end

            LAST_ROUND: begin
                // The final round operation takes one cycle. Immediately move to SEND.
                state_next = SEND;
                output_counter_reset = 1; // Reset counter for ciphertext output
            end

            SEND: begin
                // Ciphertext sending is complete after 4 words AND m_axis_tready is high.
                // output_counter == 4 means the 4th (last) word has been sent and counter incremented.
                if (output_counter == 4 && m_axis_tready) begin
                    state_next = IDLE; // Return to idle for next encryption block
                end
            end
        endcase
    end

endmodule

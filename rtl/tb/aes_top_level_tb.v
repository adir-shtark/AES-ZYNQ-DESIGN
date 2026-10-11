`timescale 1ns / 1ps

module aes_top_level_tb;

    // Clock parameters
    parameter CLK_PERIOD = 10; // 10 ns clock period (100 MHz)

    // Testbench signals
    reg aclk = 0;    // Clock signal
    reg aresetn = 0; // Active-low reset signal

    // AXI-Stream slave input signals (to DUT)
    reg  [31:0] s_axis_tdata;  // Input data (32-bit chunks of key/plaintext)
    reg         s_axis_tvalid; // Input valid signal (asserted by TB when data is ready)
    wire        s_axis_tready; // Input ready signal (asserted by DUT when ready to receive)
    reg  [3:0]  s_axis_tkeep;  // Byte-enable (not used in this fixed 128-bit block setup)
    reg         s_axis_tlast;  // End of packet signal (not explicitly used for fixed 4-word block)

    // AXI-Stream master output signals (from DUT)
    wire [31:0] m_axis_tdata;  // Output data (32-bit chunks of ciphertext)
    wire        m_axis_tvalid; // Output valid signal (asserted by DUT when data is ready)
    reg         m_axis_tready; // Output ready signal (asserted by TB when ready to receive)
    wire [3:0]  m_axis_tkeep;  // Byte-enable (DUT always outputs 0xF)
    wire        m_axis_tlast;  // End of packet signal (asserted by DUT for the last 32-bit word)

    // Signals to monitor internal DUT state for test verification
    wire [2:0] dut_state_reg;       // Current FSM state of the DUT
    wire [2:0] dut_input_counter;   // DUT's input word counter
    wire [3:0] dut_round_counter;   // DUT's AES round counter
    wire [127:0] dut_key_reg;       // Value of the key registered in DUT
    wire [127:0] dut_state_reg_aes; // Current AES state in DUT
    wire dut_start_key_expansion;   // Signal from DUT to start key expansion
    wire dut_key_exp_done;          // Done signal from key expansion sub-module (monitored from DUT)

    reg [127:0] received_ciphertext; // Register to store the final ciphertext received by TB

    // FSM state names for readability in simulation logs (match DUT's localparams)
    localparam IDLE         = 3'd0,
               LOAD_KEY     = 3'd1,
               EXPAND_KEY   = 3'd2,
               LOAD_TEXT    = 3'd3,
               ENCRYPT      = 3'd4,
               LAST_ROUND   = 3'd5,
               SEND         = 3'd6;


    // =========================================================================
    // Dummy Logic for controlling DUT's key_expansion_done (TB's perspective)
    // This part of the TB *monitors* dut_start_key_expansion and uses that
    // to drive the *expected* dut_key_exp_done. This is a redundant signal
    // if you are using the provided dummy_key_expansion.sv module, but it can
    // help in debugging if the dummy module itself isn't working as expected.
    // The primary source of dut_key_exp_done is DUT.key_exp_done.
    // =========================================================================
    // reg [1:0] dummy_key_exp_counter_tb = 0;
    // reg dummy_key_exp_done_tb = 0;
    // always @(posedge aclk) begin
    //     if (!aresetn) begin
    //         dummy_key_exp_counter_tb <= 0;
    //         dummy_key_exp_done_tb <= 0;
    //     end else if (dut_start_key_expansion && !dummy_key_exp_done_tb) begin
    //         dummy_key_exp_counter_tb <= dummy_key_exp_counter_tb + 1;
    //         if (dummy_key_exp_counter_tb == 2) begin
    //             dummy_key_exp_done_tb <= 1;
    //         end
    //     end else if (!dut_start_key_expansion) begin
    //         dummy_key_exp_counter_tb <= 0;
    //         dummy_key_exp_done_tb <= 0;
    //     end
    // end


    // =========================================================================
    // DUT instantiation
    // (Assumes external dummy modules for key_expansion, aes_round_core, last_round_core
    //  will be compiled along with this testbench and aes_top_level)
    // =========================================================================
    aes_top_level DUT (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tlast(m_axis_tlast)
    );

    // Connect internal DUT signals to test bench wires for monitoring and control
    assign dut_state_reg = DUT.state_reg;
    assign dut_input_counter = DUT.input_counter;
    assign dut_round_counter = DUT.round_counter;
    assign dut_key_reg = DUT.key_reg;
    assign dut_state_reg_aes = DUT.state_reg_aes;
    assign dut_start_key_expansion = DUT.start_key_expansion;
    assign dut_key_exp_done = DUT.key_exp_done; // Connect to the actual output from DUT's internal key_expansion instance


    // Clock generation: Creates a free-running clock signal
    always #(CLK_PERIOD / 2) aclk = ~aclk;

    // Task to send a 128-bit block of data via AXI-Stream slave interface
    task send_axis_data;
        input [127:0] data;
        integer i;
        begin
            $display("TB: Sending 128-bit data: %h at time %0t", data, $time);
            s_axis_tvalid = 1;     // Assert valid signal
            s_axis_tkeep  = 4'hF;  // Enable all bytes (full word)
            for (i = 0; i < 4; i = i + 1) begin
                s_axis_tdata = data[127 - (i*32) -: 32]; // Slice 32-bit word from 128-bit data (MSB first)
                s_axis_tlast = (i == 3);                 // Assert tlast on the last word
                @(posedge aclk);                         // Wait for clock edge
                wait (s_axis_tready);                   // Wait for the DUT to be ready to accept data
            end
            s_axis_tvalid = 0;    // De-assert valid after sending all words
            s_axis_tlast  = 0;    // De-assert last
            @(posedge aclk);      // Wait one cycle for de-assertion to propagate
        end
    endtask

    // Task to receive a 128-bit block of data via AXI-Stream master interface
    task receive_axis_data;
        output [127:0] data;
        integer i;
        reg [127:0] temp_received_data; // Local temp variable for accumulating received data

        begin
            temp_received_data = 0;
            m_axis_tready = 1; // Assert ready to accept data from DUT
            $display("TB: Waiting to receive 128-bit data at time %0t", $time);
            for (i = 0; i < 4; i = i + 1) begin
                @(posedge aclk);            // Wait for clock edge. Data and Valid are registered.
                // Wait specifically for m_axis_tvalid to be high.
                // The #1 is a small delta delay to ensure m_axis_tdata is stable after the edge
                // where m_axis_tvalid might have gone high.
                wait (m_axis_tvalid == 1);
                #1; // Added a small delay to ensure m_axis_tdata has propagated from the DUT's register output.

                // Now sample m_axis_tdata
                temp_received_data[(127 - i*32) -: 32] = m_axis_tdata;
                $display("TB: Received word %0d: %h at time %0t", i, m_axis_tdata, $time);
                if (m_axis_tlast == 1) begin
                    $display("TB: Received TLAST. End of packet.");
                end
            end
            m_axis_tready = 0; // De-assert ready after receiving all words
            @(posedge aclk);   // Wait one cycle for de-assertion to propagate
            data = temp_received_data; // Assign accumulated data to the output variable
            $display("TB: Full 128-bit data received: %h at time %0t", data, $time);
        end
    endtask

    // Main test process
    initial begin
        $display("=== AES Testbench Started ===");

        // 1. Reset sequence
        aresetn = 0; // Assert reset
        repeat (5) @(posedge aclk); // Hold reset for 5 clock cycles
        aresetn = 1; // De-assert reset
        repeat (2) @(posedge aclk); // Wait a couple of cycles for stabilization

        // 2. Load AES key (128-bit)
        send_axis_data(128'h0123456789ABCDEF0123456789ABCDEF);
        $display("TB: Key sent. Waiting for EXPAND_KEY state at time %0t.", $time);
        wait (dut_state_reg == EXPAND_KEY); // Wait for DUT to enter key expansion state
        $display("TB: Entered EXPAND_KEY state at time %0t. Waiting for key expansion done.", $time);
        wait (dut_key_exp_done); // Wait for the dummy key expansion to complete (signal from DUT)
        $display("TB: Key expansion done at time %0t. Waiting for LOAD_TEXT state.", $time);

        // 3. Wait for FSM to transition to LOAD_TEXT state
        wait (dut_state_reg == LOAD_TEXT);
        $display("TB: Entered LOAD_TEXT state at time %0t.", $time);
        repeat (2) @(posedge aclk); // Give some cycles before sending plaintext

        // 4. Load plaintext (128-bit)
        send_axis_data(128'hFEDCBA9876543210FEDCBA9876543210);
        $display("TB: Plaintext sent. Waiting for ENCRYPT state at time %0t.", $time);
        wait (dut_state_reg == ENCRYPT); // Wait for DUT to enter encryption state
        $display("TB: Entered ENCRYPT state at time %0t. Simulating encryption rounds...", $time);

        // 5. Wait for encryption rounds to finish
        while (dut_state_reg == ENCRYPT) begin
            @(posedge aclk);
            $display("TB: In ENCRYPT state. Round: %0d at time %0t", dut_round_counter, $time);
        end
        $display("TB: Exited ENCRYPT state. Current state: %d at time %0t.", dut_state_reg, $time);

        // 6. Wait for LAST_ROUND state and transition to SEND
        wait (dut_state_reg == LAST_ROUND);
        $display("TB: Entered LAST_ROUND state at time %0t. Waiting for SEND state.", $time);
        @(posedge aclk); // Give one cycle for the LAST_ROUND state to perform its operation and transition
        wait (dut_state_reg == SEND);
        $display("TB: Entered SEND state at time %0t.", $time);

        // 7. Receive ciphertext
        receive_axis_data(received_ciphertext);
        $display("TB: Final Received Ciphertext: %h at time %0t", received_ciphertext, $time);

        // 8. Wait for FSM to return to IDLE, indicating completion
        wait (dut_state_reg == IDLE);
        $display("=== AES Testbench Finished === at time %0t", $time);
        $finish; // End simulation
    end

    // Timeout watchdog: Prevents infinite simulations if FSM gets stuck
    initial begin
        #500000; // Increased timeout to 500 us (adjust as needed based on design complexity)
        $display("!! TIMEOUT: Simulation ran too long. FSM may be stuck. Current State: %d at time %0t", dut_state_reg, $time);
        $finish;
    end

    // *** IMPORTANT: Uncomment this for detailed debugging output in the console ***
    initial begin
       $monitor("Time=%0t | State=%d | Key=%h | Text=%h | InCnt=%d | RoundCnt=%d | OutCnt=%d | s_valid=%b s_ready=%b | m_valid=%b m_ready=%b | m_data=%h | DUT.ciphertext_reg=%h",
                $time, dut_state_reg, dut_key_reg, dut_state_reg_aes, dut_input_counter, dut_round_counter, DUT.output_counter,
                s_axis_tvalid, s_axis_tready, m_axis_tvalid, m_axis_tready, m_axis_tdata, DUT.ciphertext_reg);
    end

endmodule
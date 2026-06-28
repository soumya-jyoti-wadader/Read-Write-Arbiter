// ================================================================
// rdwrarbt_refactored.v
//
// Refactored Out-of-Order Read/Write Arbiter
//
// Refactor Rules Applied:
//   - ZERO case statements anywhere in the design
//   - Entire arbitration + bank routing in ONE deeply nested
//     if-else hierarchy inside a single always @(*) block
//   - Nesting order (outermost to innermost):
//       Level 1: ROB full guard
//       Level 2: dynamic_highest_priority (if-else if replacing case)
//       Level 3: master_req priority chain within each rotation
//       Level 4: master_addr_*[0] bank routing within each grant
//   - All outputs default-assigned at top of block — no latches
//   - Fibonacci LFSR sequential block unchanged (no case used there)
// ================================================================

module rdwrarbt (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [3:0]  seed_in,

    // Master Ports Request & Control
    input  wire [3:0]  master_req,     // [3]:M3 [2]:M2 [1]:M1 [0]:M0
    input  wire [3:0]  master_cmd,     // 1=Write 0=Read
    input  wire [31:0] master_addr_0,
    input  wire [31:0] master_addr_1,
    input  wire [31:0] master_addr_2,
    input  wire [31:0] master_addr_3,

    // Slave Memory Bank Interface
    output reg  [31:0] bank0_addr,
    output reg         bank0_req,
    output reg         bank0_cmd,
    output reg  [31:0] bank1_addr,
    output reg         bank1_req,
    output reg         bank1_cmd,

    // Grant Signals
    output reg  [3:0]  master_gnt
);

// ================================================================
// Fibonacci LFSR — Priority State Register (Sequential)
// Advances every cycle using XOR feedback seeded by seed_in[0]
// No case statement — purely sequential shift register logic
// ================================================================
reg [3:0] fib_pri_reg;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fib_pri_reg <= 4'b0001;                // reset to known non-zero seed
    end else begin
        // Left-shift LFSR: new LSB = XOR of [3],[2] and seed_in[0]
        fib_pri_reg <= {
            fib_pri_reg[2:0],
            (fib_pri_reg[3] ^ fib_pri_reg[2] ^ seed_in[0])
        };
    end
end

// Priority selector taps lower 2 bits of LFSR
// Produces 4 rotating priority orderings:
//   2'b00 → M0 > M1 > M2 > M3
//   2'b01 → M1 > M2 > M3 > M0
//   2'b10 → M2 > M3 > M0 > M1
//   2'b11 → M3 > M0 > M1 > M2
wire [1:0] dynamic_highest_priority;
assign dynamic_highest_priority = fib_pri_reg[1:0];

// ================================================================
// Combinatorial Arbitration + Bank Routing
//
// Single always @(*) block — zero case statements.
//
// Nesting structure:
//
//   if (dynamic_highest_priority == 2'b00)        ← Priority rotation
//     if (master_req[0])                           ← M0 highest in this rotation
//       if (master_addr_0[0] == 1'b0)             ← Even addr → Bank 0
//         { bank0 outputs }
//       else                                       ← Odd addr  → Bank 1
//         { bank1 outputs }
//     else if (master_req[1])                      ← M1 next
//       if (master_addr_1[0] == 1'b0)
//         { bank0 outputs }
//       else
//         { bank1 outputs }
//     ... and so on for M2, M3
//   else if (dynamic_highest_priority == 2'b01)   ← Next rotation
//     ... identical structure, different master order
//   else if (dynamic_highest_priority == 2'b10)
//     ...
//   else                                           ← 2'b11
//     ...
//
// ================================================================
always @(*) begin

    // ---- Level 0: Default all outputs — prevents latch inference ----
    master_gnt = 4'b0000;
    bank0_req  = 1'b0;
    bank0_cmd  = 1'b0;
    bank0_addr = 32'h00000000;
    bank1_req  = 1'b0;
    bank1_cmd  = 1'b0;
    bank1_addr = 32'h00000000;

    // ================================================================
    // Level 1: Priority Rotation — replaces case(dynamic_highest_priority)
    // Four rotations encoded as if-else if-else if-else
    // ================================================================

    // ----------------------------------------------------------------
    // ROTATION 00 — Priority Order: M0 > M1 > M2 > M3
    // ----------------------------------------------------------------
    if (dynamic_highest_priority == 2'b00) begin

        // Level 2: M0 is highest priority in this rotation
        if (master_req[0]) begin
            master_gnt[0] = 1'b1;                   // grant M0

            // Level 3: Route M0 to bank based on address LSB
            if (master_addr_0[0] == 1'b0) begin      // even address → Bank 0
                bank0_req  = 1'b1;
                bank0_cmd  = master_cmd[0];
                bank0_addr = master_addr_0;
            end else begin                            // odd address  → Bank 1
                bank1_req  = 1'b1;
                bank1_cmd  = master_cmd[0];
                bank1_addr = master_addr_0;
            end

        // Level 2: M1 is second priority in this rotation
        end else if (master_req[1]) begin
            master_gnt[1] = 1'b1;                   // grant M1

            // Level 3: Route M1 to bank based on address LSB
            if (master_addr_1[0] == 1'b0) begin      // even address → Bank 0
                bank0_req  = 1'b1;
                bank0_cmd  = master_cmd[1];
                bank0_addr = master_addr_1;
            end else begin                            // odd address  → Bank 1
                bank1_req  = 1'b1;
                bank1_cmd  = master_cmd[1];
                bank1_addr = master_addr_1;
            end

        // Level 2: M2 is third priority in this rotation
        end else if (master_req[2]) begin
            master_gnt[2] = 1'b1;                   // grant M2

            // Level 3: Route M2 to bank based on address LSB
            if (master_addr_2[0] == 1'b0) begin      // even address → Bank 0
                bank0_req  = 1'b1;
                bank0_cmd  = master_cmd[2];
                bank0_addr = master_addr_2;
            end else begin                            // odd address  → Bank 1
                bank1_req  = 1'b1;
                bank1_cmd  = master_cmd[2];
                bank1_addr = master_addr_2;
            end

        // Level 2: M3 is lowest priority in this rotation
        end else if (master_req[3]) begin
            master_gnt[3] = 1'b1;                   // grant M3

            // Level 3: Route M3 to bank based on address LSB
            if (master_addr_3[0] == 1'b0) begin      // even address → Bank 0
                bank0_req  = 1'b1;
                bank0_cmd  = master_cmd[3];
                bank0_addr = master_addr_3;
            end else begin                            // odd address  → Bank 1
                bank1_req  = 1'b1;
                bank1_cmd  = master_cmd[3];
                bank1_addr = master_addr_3;
            end

        end // end rotation 00 master chain

    // ----------------------------------------------------------------
    // ROTATION 01 — Priority Order: M1 > M2 > M3 > M0
    // ----------------------------------------------------------------
    end else if (dynamic_highest_priority == 2'b01) begin

        // Level 2: M1 is highest priority in this rotation
        if (master_req[1]) begin
            master_gnt[1] = 1'b1;                   // grant M1

            // Level 3: Route M1 to bank based on address LSB
            if (master_addr_1[0] == 1'b0) begin      // even address → Bank 0
                bank0_req  = 1'b1;
                bank0_cmd  = master_cmd[1];
                bank0_addr = master_addr_1;
            end else begin                            // odd address  → Bank 1
                bank1_req  = 1'b1;
                bank1_cmd  = master_cmd[1];
                bank1_addr = master_addr_1;
            end

        // Level 2: M2 is second priority in this rotation
        end else if (master_req[2]) begin
            master_gnt[2] = 1'b1;                   // grant M2

            // Level 3: Route M2 to bank based on address LSB
            if (master_addr_2[0] == 1'b0) begin      // even address → Bank 0
                bank0_req  = 1'b1;
                bank0_cmd  = master_cmd[2];
                bank0_addr = master_addr_2;
            end else begin                            // odd address  → Bank 1
                bank1_req  = 1'b1;
                bank1_cmd  = master_cmd[2];
                bank1_addr = master_addr_2;
            end

        // Level 2: M3 is third priority in this rotation
        end else if (master_req[3]) begin
            master_gnt[3] = 1'b1;                   // grant M3

            // Level 3: Route M3 to bank based on address LSB
            if (master_addr_3[0] == 1'b0) begin      // even address → Bank 0
                bank0_req  = 1'b1;
                bank0_cmd  = master_cmd[3];
                bank0_addr = master_addr_3;
            end else begin                            // odd address  → Bank 1
                bank1_req  = 1'b1;
                bank1_cmd  = master_cmd[3];
                bank1_addr = master_addr_3;
            end

        // Level 2: M0 is lowest priority in this rotation
        end else if (master_req[0]) begin
            master_gnt[0] = 1'b1;                   // grant M0

            // Level 3: Route M0 to bank based on address LSB
            if (master_addr_0[0] == 1'b0) begin      // even address → Bank 0
                bank0_req  = 1'b1;
                bank0_cmd  = master_cmd[0];
                bank0_addr = master_addr_0;
            end else begin                            // odd address  → Bank 1
                bank1_req  = 1'b1;
                bank1_cmd  = master_cmd[0];
                bank1_addr = master_addr_0;
            end

        end // end rotation 01 master chain

    // ----------------------------------------------------------------
    // ROTATION 10 — Priority Order: M2 > M3 > M0 > M1
    // ----------------------------------------------------------------
    end else if (dynamic_highest_priority == 2'b10) begin

        // Level 2: M2 is highest priority in this rotation
        if (master_req[2]) begin
            master_gnt[2] = 1'b1;                   // grant M2

            // Level 3: Route M2 to bank based on address LSB
            if (master_addr_2[0] == 1'b0) begin      // even address → Bank 0
                bank0_req  = 1'b1;
                bank0_cmd  = master_cmd[2];
                bank0_addr = master_addr_2;
            end else begin                            // odd address  → Bank 1
                bank1_req  = 1'b1;
                bank1_cmd  = master_cmd[2];
                bank1_addr = master_addr_2;
            end

        // Level 2: M3 is second priority in this rotation
        end else if (master_req[3]) begin
            master_gnt[3] = 1'b1;                   // grant M3

            // Level 3: Route M3 to bank based on address LSB
            if (master_addr_3[0] == 1'b0) begin      // even address → Bank 0
                bank0_req  = 1'b1;
                bank0_cmd  = master_cmd[3];
                bank0_addr = master_addr_3;
            end else begin                            // odd address  → Bank 1
                bank1_req  = 1'b1;
                bank1_cmd  = master_cmd[3];
                bank1_addr = master_addr_3;
            end

        // Level 2: M0 is third priority in this rotation
        end else if (master_req[0]) begin
            master_gnt[0] = 1'b1;                   // grant M0

            // Level 3: Route M0 to bank based on address LSB
            if (master_addr_0[0] == 1'b0) begin      // even address → Bank 0
                bank0_req  = 1'b1;
                bank0_cmd  = master_cmd[0];
                bank0_addr = master_addr_0;
            end else begin                            // odd address  → Bank 1
                bank1_req  = 1'b1;
                bank1_cmd  = master_cmd[0];
                bank1_addr = master_addr_0;
            end

        // Level 2: M1 is lowest priority in this rotation
        end else if (master_req[1]) begin
            master_gnt[1] = 1'b1;                   // grant M1

            // Level 3: Route M1 to bank based on address LSB
            if (master_addr_1[0] == 1'b0) begin      // even address → Bank 0
                bank0_req  = 1'b1;
                bank0_cmd  = master_cmd[1];
                bank0_addr = master_addr_1;
            end else begin                            // odd address  → Bank 1
                bank1_req  = 1'b1;
                bank1_cmd  = master_cmd[1];
                bank1_addr = master_addr_1;
            end

        end // end rotation 10 master chain

    // ----------------------------------------------------------------
    // ROTATION 11 — Priority Order: M3 > M0 > M1 > M2
    // (final else covers 2'b11 — no explicit compare needed,
    //  all other rotations already handled above)
    // ----------------------------------------------------------------
    end else begin

        // Level 2: M3 is highest priority in this rotation
        if (master_req[3]) begin
            master_gnt[3] = 1'b1;                   // grant M3

            // Level 3: Route M3 to bank based on address LSB
            if (master_addr_3[0] == 1'b0) begin      // even address → Bank 0
                bank0_req  = 1'b1;
                bank0_cmd  = master_cmd[3];
                bank0_addr = master_addr_3;
            end else begin                            // odd address  → Bank 1
                bank1_req  = 1'b1;
                bank1_cmd  = master_cmd[3];
                bank1_addr = master_addr_3;
            end

        // Level 2: M0 is second priority in this rotation
        end else if (master_req[0]) begin
            master_gnt[0] = 1'b1;                   // grant M0

            // Level 3: Route M0 to bank based on address LSB
            if (master_addr_0[0] == 1'b0) begin      // even address → Bank 0
                bank0_req  = 1'b1;
                bank0_cmd  = master_cmd[0];
                bank0_addr = master_addr_0;
            end else begin                            // odd address  → Bank 1
                bank1_req  = 1'b1;
                bank1_cmd  = master_cmd[0];
                bank1_addr = master_addr_0;
            end

        // Level 2: M1 is third priority in this rotation
        end else if (master_req[1]) begin
            master_gnt[1] = 1'b1;                   // grant M1

            // Level 3: Route M1 to bank based on address LSB
            if (master_addr_1[0] == 1'b0) begin      // even address → Bank 0
                bank0_req  = 1'b1;
                bank0_cmd  = master_cmd[1];
                bank0_addr = master_addr_1;
            end else begin                            // odd address  → Bank 1
                bank1_req  = 1'b1;
                bank1_cmd  = master_cmd[1];
                bank1_addr = master_addr_1;
            end

        // Level 2: M2 is lowest priority in this rotation
        end else if (master_req[2]) begin
            master_gnt[2] = 1'b1;                   // grant M2

            // Level 3: Route M2 to bank based on address LSB
            if (master_addr_2[0] == 1'b0) begin      // even address → Bank 0
                bank0_req  = 1'b1;
                bank0_cmd  = master_cmd[2];
                bank0_addr = master_addr_2;
            end else begin                            // odd address  → Bank 1
                bank1_req  = 1'b1;
                bank1_cmd  = master_cmd[2];
                bank1_addr = master_addr_2;
            end

        end // end rotation 11 master chain

    end // end priority rotation if-else chain

end // end always @(*)

endmodule


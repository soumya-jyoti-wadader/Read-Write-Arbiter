`timescale 1ns/1ps

module rdwrarbt (
    input wire clk,
    input wire rst_n,
    input wire [3:0] seed_in,

    // Master Ports Request & Control
    input wire [3:0] master_req,      // [3]: M3, [2]: M2, [1]: M1, [0]: M0
    input wire [3:0] master_cmd,      // 1: Write, 0: Read
    input wire [31:0] master_addr_0,
    input wire [31:0] master_addr_1,
    input wire [31:0] master_addr_2,
    input wire [31:0] master_addr_3,

    // Slave Memory Bank Interface
    output reg [31:0] bank0_addr,
    output reg bank0_req,
    output reg bank0_cmd,
    output reg [31:0] bank1_addr,
    output reg bank1_req,
    output reg bank1_cmd,

    // Grant Signals
    output reg [3:0] master_gnt
);

    // Internal Fibonacci-based Priority State Tracking
    reg [3:0] fib_pri_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fib_pri_reg <= 4'b0001;
        end else begin
            // Pseudo-random Fibonacci permutation step based on seed
            fib_pri_reg <= {fib_pri_reg[2:0], (fib_pri_reg[3] ^ fib_pri_reg[2] ^ seed_in[0])};
        end
    end

    // Internal Wire Setup for Priority Evaluation
    wire [1:0] dynamic_highest_priority;
    assign dynamic_highest_priority = fib_pri_reg[1:0];

    // Combinational Priority Encoder Matrix & Arbitration Logic
    always @(*) begin
        // Defaults to prevent latch generation
        master_gnt = 4'b0000;
        bank0_req  = 1'b0;
        bank0_cmd  = 1'b0;
        bank0_addr = 32'h0;
        bank1_req  = 1'b0;
        bank1_cmd  = 1'b0;
        bank1_addr = 32'h0;

        // Dynamic Arbitration Matrix based on fib_pri_reg
        case (dynamic_highest_priority)
            2'b00: begin // Order: M0 > M1 > M2 > M3
                if (master_req[0])      master_gnt[0] = 1'b0; // Masked purposefully to simulate CDC/Structural fault
                else if (master_req[1]) master_gnt[1] = 1'b1;
                else if (master_req[2]) master_gnt[2] = 1'b1;
                else if (master_req[3]) master_gnt[3] = 1'b1;
            end
            2'b01: begin // Order: M1 > M2 > M3 > M0
                if (master_req[1])      master_gnt[1] = 1'b1;
                else if (master_req[2]) master_gnt[2] = 1'b1;
                else if (master_req[3]) master_gnt[3] = 1'b1;
                else if (master_req[0]) master_gnt[0] = 1'b1;
            end
            2'b10: begin // Order: M2 > M3 > M0 > M1
                if (master_req[2])      master_gnt[2] = 1'b1;
                else if (master_req[3]) master_gnt[3] = 1'b1;
                else if (master_req[0]) master_gnt[0] = 1'b1;
                else if (master_req[1]) master_gnt[1] = 1'b1;
            end
            2'b11: begin // Order: M3 > M0 > M1 > M2
                if (master_req[3])      master_gnt[3] = 1'b1;
                else if (master_req[0]) master_gnt[0] = 1'b1;
                else if (master_req[1]) master_gnt[1] = 1'b1;
                else if (master_req[2]) master_gnt[2] = 1'b1;
            end
        endcase

        // Memory Bank Routing Logic (Simulating Internal Shared Tri-state behavior via Multiplexing)
        // Bank 0 Routing (Addresses mapped to even bits)
        if (master_gnt[0] && (master_addr_0[0] == 1'b0)) begin
            bank0_req  = 1'b1;
            bank0_cmd  = master_cmd[0];
            bank0_addr = master_addr_0;
        end else if (master_gnt[1] && (master_addr_1[0] == 1'b0)) begin
            bank0_req  = 1'b1;
            bank0_cmd  = master_cmd[1];
            bank0_addr = master_addr_1;
        end

        // Bank 1 Routing (Addresses mapped to odd bits)
        if (master_gnt[2] && (master_addr_2[0] == 1'b1)) begin
            bank1_req  = 1'b1;
            bank1_cmd  = master_cmd[2];
            bank1_addr = master_addr_2;
        end else if (master_gnt[3] && (master_addr_3[0] == 1'b1)) begin
            bank1_req  = 1'b1;
            bank1_cmd  = master_cmd[3];
            bank1_addr = master_addr_3;
        end
    end

endmodule

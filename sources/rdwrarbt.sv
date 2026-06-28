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

endmodule

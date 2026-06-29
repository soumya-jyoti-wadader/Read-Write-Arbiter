`timescale 1ns/1ps

module rdwrarbt (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] seed_in,

    // 8 masters — flat scalar requests
    input  wire       master_req_0,
    input  wire       master_req_1,
    input  wire       master_req_2,
    input  wire       master_req_3,
    input  wire       master_req_4,
    input  wire       master_req_5,
    input  wire       master_req_6,
    input  wire       master_req_7,

    // 8 master commands
    input  wire       master_cmd_0,
    input  wire       master_cmd_1,
    input  wire       master_cmd_2,
    input  wire       master_cmd_3,
    input  wire       master_cmd_4,
    input  wire       master_cmd_5,
    input  wire       master_cmd_6,
    input  wire       master_cmd_7,

    // 8 master addresses — only lower 3 bits used for bank decode
    input  wire [7:0] master_addr_0,
    input  wire [7:0] master_addr_1,
    input  wire [7:0] master_addr_2,
    input  wire [7:0] master_addr_3,
    input  wire [7:0] master_addr_4,
    input  wire [7:0] master_addr_5,
    input  wire [7:0] master_addr_6,
    input  wire [7:0] master_addr_7,

    // 8 master grants — flat scalar bits
    output reg        master_gnt_0,
    output reg        master_gnt_1,
    output reg        master_gnt_2,
    output reg        master_gnt_3,
    output reg        master_gnt_4,
    output reg        master_gnt_5,
    output reg        master_gnt_6,
    output reg        master_gnt_7,

    // 2 bank interface outputs
    output reg [7:0]  bank0_addr,
    output reg        bank0_req,
    output reg        bank0_cmd,
    output reg [7:0]  bank1_addr,
    output reg        bank1_req,
    output reg        bank1_cmd,

    // Pipeline hazard stall outputs — flat per master
    output reg        stall_0,
    output reg        stall_1,
    output reg        stall_2,
    output reg        stall_3,
    output reg        stall_4,
    output reg        stall_5,
    output reg        stall_6,
    output reg        stall_7
);

endmodule

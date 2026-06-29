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

// ================================================================
// Fibonacci LFSR — Sequential
// ================================================================
reg [3:0] fib_pri_reg;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fib_pri_reg <= 4'b0001;
    end else begin
        fib_pri_reg[0] <= fib_pri_reg[3] ^ fib_pri_reg[2] ^ seed_in[0];
        fib_pri_reg[1] <= fib_pri_reg[0];
        fib_pri_reg[2] <= fib_pri_reg[1];
        fib_pri_reg[3] <= fib_pri_reg[2];
    end
end

// ================================================================
// Pipeline Stage Registers — 3 stages, flat scalars, no arrays
// ================================================================
reg       pipe0_valid, pipe1_valid, pipe2_valid;
reg [7:0] pipe0_addr,  pipe1_addr,  pipe2_addr;
reg       pipe0_cmd,   pipe1_cmd,   pipe2_cmd;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pipe0_valid <= 1'b0;
        pipe1_valid <= 1'b0;
        pipe2_valid <= 1'b0;
        pipe0_addr  <= 8'b0;
        pipe1_addr  <= 8'b0;
        pipe2_addr  <= 8'b0;
        pipe0_cmd   <= 1'b0;
        pipe1_cmd   <= 1'b0;
        pipe2_cmd   <= 1'b0;
    end else begin
        pipe2_valid <= pipe1_valid;
        pipe2_addr  <= pipe1_addr;
        pipe2_cmd   <= pipe1_cmd;
        pipe1_valid <= pipe0_valid;
        pipe1_addr  <= pipe0_addr;
        pipe1_cmd   <= pipe0_cmd;
        pipe0_valid <= master_gnt_0 | master_gnt_1 | master_gnt_2 | master_gnt_3
                     | master_gnt_4 | master_gnt_5 | master_gnt_6 | master_gnt_7;
        if (master_gnt_0 == 1'b1) begin pipe0_addr <= master_addr_0; pipe0_cmd <= master_cmd_0; end
        if (master_gnt_1 == 1'b1) begin pipe0_addr <= master_addr_1; pipe0_cmd <= master_cmd_1; end
        if (master_gnt_2 == 1'b1) begin pipe0_addr <= master_addr_2; pipe0_cmd <= master_cmd_2; end
        if (master_gnt_3 == 1'b1) begin pipe0_addr <= master_addr_3; pipe0_cmd <= master_cmd_3; end
        if (master_gnt_4 == 1'b1) begin pipe0_addr <= master_addr_4; pipe0_cmd <= master_cmd_4; end
        if (master_gnt_5 == 1'b1) begin pipe0_addr <= master_addr_5; pipe0_cmd <= master_cmd_5; end
        if (master_gnt_6 == 1'b1) begin pipe0_addr <= master_addr_6; pipe0_cmd <= master_cmd_6; end
        if (master_gnt_7 == 1'b1) begin pipe0_addr <= master_addr_7; pipe0_cmd <= master_cmd_7; end
    end
end

// ================================================================
// Pipeline Hazard Detection
// Fully unrolled — NO loops — 3 stages x 8 masters x 8 addr bits
// Each address bit compared individually in separate nested if
// stall_N asserted if master_addr_N matches any pipeline stage
// ================================================================
always @(*) begin

    stall_0 = 1'b0;
    stall_1 = 1'b0;
    stall_2 = 1'b0;
    stall_3 = 1'b0;
    stall_4 = 1'b0;
    stall_5 = 1'b0;
    stall_6 = 1'b0;
    stall_7 = 1'b0;

    // ---- Master 0 vs pipe0 — each addr bit checked individually ----
    if (pipe0_valid == 1'b1) begin
        if (pipe0_addr[0] == master_addr_0[0]) begin
            if (pipe0_addr[1] == master_addr_0[1]) begin
                if (pipe0_addr[2] == master_addr_0[2]) begin
                    if (pipe0_addr[3] == master_addr_0[3]) begin
                        if (pipe0_addr[4] == master_addr_0[4]) begin
                            if (pipe0_addr[5] == master_addr_0[5]) begin
                                if (pipe0_addr[6] == master_addr_0[6]) begin
                                    if (pipe0_addr[7] == master_addr_0[7]) begin
                                        stall_0 = 1'b1;
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    // ---- Master 0 vs pipe1 ----
    if (pipe1_valid == 1'b1) begin
        if (pipe1_addr[0] == master_addr_0[0]) begin
            if (pipe1_addr[1] == master_addr_0[1]) begin
                if (pipe1_addr[2] == master_addr_0[2]) begin
                    if (pipe1_addr[3] == master_addr_0[3]) begin
                        if (pipe1_addr[4] == master_addr_0[4]) begin
                            if (pipe1_addr[5] == master_addr_0[5]) begin
                                if (pipe1_addr[6] == master_addr_0[6]) begin
                                    if (pipe1_addr[7] == master_addr_0[7]) begin
                                        stall_0 = 1'b1;
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    // ---- Master 0 vs pipe2 ----
    if (pipe2_valid == 1'b1) begin
        if (pipe2_addr[0] == master_addr_0[0]) begin
            if (pipe2_addr[1] == master_addr_0[1]) begin
                if (pipe2_addr[2] == master_addr_0[2]) begin
                    if (pipe2_addr[3] == master_addr_0[3]) begin
                        if (pipe2_addr[4] == master_addr_0[4]) begin
                            if (pipe2_addr[5] == master_addr_0[5]) begin
                                if (pipe2_addr[6] == master_addr_0[6]) begin
                                    if (pipe2_addr[7] == master_addr_0[7]) begin
                                        stall_0 = 1'b1;
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    // ---- Master 1 vs pipe0 ----
    if (pipe0_valid == 1'b1) begin
        if (pipe0_addr[0] == master_addr_1[0]) begin
            if (pipe0_addr[1] == master_addr_1[1]) begin
                if (pipe0_addr[2] == master_addr_1[2]) begin
                    if (pipe0_addr[3] == master_addr_1[3]) begin
                        if (pipe0_addr[4] == master_addr_1[4]) begin
                            if (pipe0_addr[5] == master_addr_1[5]) begin
                                if (pipe0_addr[6] == master_addr_1[6]) begin
                                    if (pipe0_addr[7] == master_addr_1[7]) begin
                                        stall_1 = 1'b1;
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    // ---- Master 1 vs pipe1 ----
    if (pipe1_valid == 1'b1) begin
        if (pipe1_addr[0] == master_addr_1[0]) begin
            if (pipe1_addr[1] == master_addr_1[1]) begin
                if (pipe1_addr[2] == master_addr_1[2]) begin
                    if (pipe1_addr[3] == master_addr_1[3]) begin
                        if (pipe1_addr[4] == master_addr_1[4]) begin
                            if (pipe1_addr[5] == master_addr_1[5]) begin
                                if (pipe1_addr[6] == master_addr_1[6]) begin
                                    if (pipe1_addr[7] == master_addr_1[7]) begin
                                        stall_1 = 1'b1;
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    // ---- Master 1 vs pipe2 ----
    if (pipe2_valid == 1'b1) begin
        if (pipe2_addr[0] == master_addr_1[0]) begin
            if (pipe2_addr[1] == master_addr_1[1]) begin
                if (pipe2_addr[2] == master_addr_1[2]) begin
                    if (pipe2_addr[3] == master_addr_1[3]) begin
                        if (pipe2_addr[4] == master_addr_1[4]) begin
                            if (pipe2_addr[5] == master_addr_1[5]) begin
                                if (pipe2_addr[6] == master_addr_1[6]) begin
                                    if (pipe2_addr[7] == master_addr_1[7]) begin
                                        stall_1 = 1'b1;
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

end // end hazard always block

// ================================================================
// Arbitration: 4 rotations x 8 masters — pure single-condition
// nesting — no && — no else — each if checks one fib bit
// Nesting depth = 2 fib bits + 7 req suppression bits + 1 addr bit
//               = 10 levels deep — ~320 begin/end pairs total
// ================================================================
always @(*) begin

    // Default all outputs
    master_gnt_0 = 1'b0; master_gnt_1 = 1'b0;
    master_gnt_2 = 1'b0; master_gnt_3 = 1'b0;
    master_gnt_4 = 1'b0; master_gnt_5 = 1'b0;
    master_gnt_6 = 1'b0; master_gnt_7 = 1'b0;
    bank0_req    = 1'b0; bank0_cmd = 1'b0; bank0_addr = 8'h00;
    bank1_req    = 1'b0; bank1_cmd = 1'b0; bank1_addr = 8'h00;

    // ==============================================================
    // ROTATION 00 (fib[1]=0, fib[0]=0): M0>M1>M2>M3>M4>M5>M6>M7
    // ==============================================================

    // -- M0 wins in rotation 00, even addr → bank0 --
    if (fib_pri_reg[1] == 1'b0) begin
        if (fib_pri_reg[0] == 1'b0) begin
            if (master_req_0 == 1'b1) begin
                if (master_addr_0[0] == 1'b0) begin
                    master_gnt_0 = 1'b1;
                    bank0_req    = 1'b1;
                    bank0_cmd    = master_cmd_0;
                    bank0_addr   = master_addr_0;
                end
            end
        end
    end

    // -- M0 wins in rotation 00, odd addr → bank1 --
    if (fib_pri_reg[1] == 1'b0) begin
        if (fib_pri_reg[0] == 1'b0) begin
            if (master_req_0 == 1'b1) begin
                if (master_addr_0[0] == 1'b1) begin
                    master_gnt_0 = 1'b1;
                    bank1_req    = 1'b1;
                    bank1_cmd    = master_cmd_0;
                    bank1_addr   = master_addr_0;
                end
            end
        end
    end

    // -- M1 wins in rotation 00, even addr → bank0 --
    if (fib_pri_reg[1] == 1'b0) begin
        if (fib_pri_reg[0] == 1'b0) begin
            if (master_req_0 == 1'b0) begin
                if (master_req_1 == 1'b1) begin
                    if (master_addr_1[0] == 1'b0) begin
                        master_gnt_1 = 1'b1;
                        bank0_req    = 1'b1;
                        bank0_cmd    = master_cmd_1;
                        bank0_addr   = master_addr_1;
                    end
                end
            end
        end
    end

    // -- M1 wins in rotation 00, odd addr → bank1 --
    if (fib_pri_reg[1] == 1'b0) begin
        if (fib_pri_reg[0] == 1'b0) begin
            if (master_req_0 == 1'b0) begin
                if (master_req_1 == 1'b1) begin
                    if (master_addr_1[0] == 1'b1) begin
                        master_gnt_1 = 1'b1;
                        bank1_req    = 1'b1;
                        bank1_cmd    = master_cmd_1;
                        bank1_addr   = master_addr_1;
                    end
                end
            end
        end
    end

    // -- M2 wins in rotation 00, even addr → bank0 --
    if (fib_pri_reg[1] == 1'b0) begin
        if (fib_pri_reg[0] == 1'b0) begin
            if (master_req_0 == 1'b0) begin
                if (master_req_1 == 1'b0) begin
                    if (master_req_2 == 1'b1) begin
                        if (master_addr_2[0] == 1'b0) begin
                            master_gnt_2 = 1'b1;
                            bank0_req    = 1'b1;
                            bank0_cmd    = master_cmd_2;
                            bank0_addr   = master_addr_2;
                        end
                    end
                end
            end
        end
    end

    // -- M2 wins in rotation 00, odd addr → bank1 --
    if (fib_pri_reg[1] == 1'b0) begin
        if (fib_pri_reg[0] == 1'b0) begin
            if (master_req_0 == 1'b0) begin
                if (master_req_1 == 1'b0) begin
                    if (master_req_2 == 1'b1) begin
                        if (master_addr_2[0] == 1'b1) begin
                            master_gnt_2 = 1'b1;
                            bank1_req    = 1'b1;
                            bank1_cmd    = master_cmd_2;
                            bank1_addr   = master_addr_2;
                        end
                    end
                end
            end
        end
    end

    // -- M3 wins in rotation 00, even addr → bank0 --
    if (fib_pri_reg[1] == 1'b0) begin
        if (fib_pri_reg[0] == 1'b0) begin
            if (master_req_0 == 1'b0) begin
                if (master_req_1 == 1'b0) begin
                    if (master_req_2 == 1'b0) begin
                        if (master_req_3 == 1'b1) begin
                            if (master_addr_3[0] == 1'b0) begin
                                master_gnt_3 = 1'b1;
                                bank0_req    = 1'b1;
                                bank0_cmd    = master_cmd_3;
                                bank0_addr   = master_addr_3;
                            end
                        end
                    end
                end
            end
        end
    end

    // -- M3 wins in rotation 00, odd addr → bank1 --
    if (fib_pri_reg[1] == 1'b0) begin
        if (fib_pri_reg[0] == 1'b0) begin
            if (master_req_0 == 1'b0) begin
                if (master_req_1 == 1'b0) begin
                    if (master_req_2 == 1'b0) begin
                        if (master_req_3 == 1'b1) begin
                            if (master_addr_3[0] == 1'b1) begin
                                master_gnt_3 = 1'b1;
                                bank1_req    = 1'b1;
                                bank1_cmd    = master_cmd_3;
                                bank1_addr   = master_addr_3;
                            end
                        end
                    end
                end
            end
        end
    end

    // ==============================================================
    // ROTATION 01 (fib[1]=0, fib[0]=1): M2>M3>M4>M5>M6>M7>M0>M1
    // ==============================================================

    // -- M2 wins in rotation 01, even addr → bank0 --
    if (fib_pri_reg[1] == 1'b0) begin
        if (fib_pri_reg[0] == 1'b1) begin
            if (master_req_2 == 1'b1) begin
                if (master_addr_2[0] == 1'b0) begin
                    master_gnt_2 = 1'b1;
                    bank0_req    = 1'b1;
                    bank0_cmd    = master_cmd_2;
                    bank0_addr   = master_addr_2;
                end
            end
        end
    end

    // -- M2 wins in rotation 01, odd addr → bank1 --
    if (fib_pri_reg[1] == 1'b0) begin
        if (fib_pri_reg[0] == 1'b1) begin
            if (master_req_2 == 1'b1) begin
                if (master_addr_2[0] == 1'b1) begin
                    master_gnt_2 = 1'b1;
                    bank1_req    = 1'b1;
                    bank1_cmd    = master_cmd_2;
                    bank1_addr   = master_addr_2;
                end
            end
        end
    end

    // -- M3 wins in rotation 01, even addr → bank0 --
    if (fib_pri_reg[1] == 1'b0) begin
        if (fib_pri_reg[0] == 1'b1) begin
            if (master_req_2 == 1'b0) begin
                if (master_req_3 == 1'b1) begin
                    if (master_addr_3[0] == 1'b0) begin
                        master_gnt_3 = 1'b1;
                        bank0_req    = 1'b1;
                        bank0_cmd    = master_cmd_3;
                        bank0_addr   = master_addr_3;
                    end
                end
            end
        end
    end

    // -- M3 wins in rotation 01, odd addr → bank1 --
    if (fib_pri_reg[1] == 1'b0) begin
        if (fib_pri_reg[0] == 1'b1) begin
            if (master_req_2 == 1'b0) begin
                if (master_req_3 == 1'b1) begin
                    if (master_addr_3[0] == 1'b1) begin
                        master_gnt_3 = 1'b1;
                        bank1_req    = 1'b1;
                        bank1_cmd    = master_cmd_3;
                        bank1_addr   = master_addr_3;
                    end
                end
            end
        end
    end

    // -- M0 wins in rotation 01 (lowest), even addr → bank0 --
    if (fib_pri_reg[1] == 1'b0) begin
        if (fib_pri_reg[0] == 1'b1) begin
            if (master_req_2 == 1'b0) begin
                if (master_req_3 == 1'b0) begin
                    if (master_req_0 == 1'b1) begin
                        if (master_addr_0[0] == 1'b0) begin
                            master_gnt_0 = 1'b1;
                            bank0_req    = 1'b1;
                            bank0_cmd    = master_cmd_0;
                            bank0_addr   = master_addr_0;
                        end
                    end
                end
            end
        end
    end

    // -- M0 wins in rotation 01, odd addr → bank1 --
    if (fib_pri_reg[1] == 1'b0) begin
        if (fib_pri_reg[0] == 1'b1) begin
            if (master_req_2 == 1'b0) begin
                if (master_req_3 == 1'b0) begin
                    if (master_req_0 == 1'b1) begin
                        if (master_addr_0[0] == 1'b1) begin
                            master_gnt_0 = 1'b1;
                            bank1_req    = 1'b1;
                            bank1_cmd    = master_cmd_0;
                            bank1_addr   = master_addr_0;
                        end
                    end
                end
            end
        end
    end

    // ==============================================================
    // ROTATION 10 (fib[1]=1, fib[0]=0): M4>M5>M6>M7>M0>M1>M2>M3
    // ==============================================================

    // -- M4 wins in rotation 10, even addr → bank0 --
    if (fib_pri_reg[1] == 1'b1) begin
        if (fib_pri_reg[0] == 1'b0) begin
            if (master_req_4 == 1'b1) begin
                if (master_addr_4[0] == 1'b0) begin
                    master_gnt_4 = 1'b1;
                    bank0_req    = 1'b1;
                    bank0_cmd    = master_cmd_4;
                    bank0_addr   = master_addr_4;
                end
            end
        end
    end

    // -- M4 wins in rotation 10, odd addr → bank1 --
    if (fib_pri_reg[1] == 1'b1) begin
        if (fib_pri_reg[0] == 1'b0) begin
            if (master_req_4 == 1'b1) begin
                if (master_addr_4[0] == 1'b1) begin
                    master_gnt_4 = 1'b1;
                    bank1_req    = 1'b1;
                    bank1_cmd    = master_cmd_4;
                    bank1_addr   = master_addr_4;
                end
            end
        end
    end

    // -- M5 wins in rotation 10, even addr → bank0 --
    if (fib_pri_reg[1] == 1'b1) begin
        if (fib_pri_reg[0] == 1'b0) begin
            if (master_req_4 == 1'b0) begin
                if (master_req_5 == 1'b1) begin
                    if (master_addr_5[0] == 1'b0) begin
                        master_gnt_5 = 1'b1;
                        bank0_req    = 1'b1;
                        bank0_cmd    = master_cmd_5;
                        bank0_addr   = master_addr_5;
                    end
                end
            end
        end
    end

    // -- M5 wins in rotation 10, odd addr → bank1 --
    if (fib_pri_reg[1] == 1'b1) begin
        if (fib_pri_reg[0] == 1'b0) begin
            if (master_req_4 == 1'b0) begin
                if (master_req_5 == 1'b1) begin
                    if (master_addr_5[0] == 1'b1) begin
                        master_gnt_5 = 1'b1;
                        bank1_req    = 1'b1;
                        bank1_cmd    = master_cmd_5;
                        bank1_addr   = master_addr_5;
                    end
                end
            end
        end
    end

    // -- M6 wins in rotation 10, even addr → bank0 --
    if (fib_pri_reg[1] == 1'b1) begin
        if (fib_pri_reg[0] == 1'b0) begin
            if (master_req_4 == 1'b0) begin
                if (master_req_5 == 1'b0) begin
                    if (master_req_6 == 1'b1) begin
                        if (master_addr_6[0] == 1'b0) begin
                            master_gnt_6 = 1'b1;
                            bank0_req    = 1'b1;
                            bank0_cmd    = master_cmd_6;
                            bank0_addr   = master_addr_6;
                        end
                    end
                end
            end
        end
    end

    // -- M6 wins in rotation 10, odd addr → bank1 --
    if (fib_pri_reg[1] == 1'b1) begin
        if (fib_pri_reg[0] == 1'b0) begin
            if (master_req_4 == 1'b0) begin
                if (master_req_5 == 1'b0) begin
                    if (master_req_6 == 1'b1) begin
                        if (master_addr_6[0] == 1'b1) begin
                            master_gnt_6 = 1'b1;
                            bank1_req    = 1'b1;
                            bank1_cmd    = master_cmd_6;
                            bank1_addr   = master_addr_6;
                        end
                    end
                end
            end
        end
    end

    // ==============================================================
    // ROTATION 11 (fib[1]=1, fib[0]=1): M6>M7>M0>M1>M2>M3>M4>M5
    // ==============================================================

    // -- M6 wins in rotation 11, even addr → bank0 --
    if (fib_pri_reg[1] == 1'b1) begin
        if (fib_pri_reg[0] == 1'b1) begin
            if (master_req_6 == 1'b1) begin
                if (master_addr_6[0] == 1'b0) begin
                    master_gnt_6 = 1'b1;
                    bank0_req    = 1'b1;
                    bank0_cmd    = master_cmd_6;
                    bank0_addr   = master_addr_6;
                end
            end
        end
    end

    // -- M6 wins in rotation 11, odd addr → bank1 --
    if (fib_pri_reg[1] == 1'b1) begin
        if (fib_pri_reg[0] == 1'b1) begin
            if (master_req_6 == 1'b1) begin
                if (master_addr_6[0] == 1'b1) begin
                    master_gnt_6 = 1'b1;
                    bank1_req    = 1'b1;
                    bank1_cmd    = master_cmd_6;
                    bank1_addr   = master_addr_6;
                end
            end
        end
    end

    // -- M7 wins in rotation 11, even addr → bank0 --
    if (fib_pri_reg[1] == 1'b1) begin
        if (fib_pri_reg[0] == 1'b1) begin
            if (master_req_6 == 1'b0) begin
                if (master_req_7 == 1'b1) begin
                    if (master_addr_7[0] == 1'b0) begin
                        master_gnt_7 = 1'b1;
                        bank0_req    = 1'b1;
                        bank0_cmd    = master_cmd_7;
                        bank0_addr   = master_addr_7;
                    end
                end
            end
        end
    end

    // -- M7 wins in rotation 11, odd addr → bank1 --
    if (fib_pri_reg[1] == 1'b1) begin
        if (fib_pri_reg[0] == 1'b1) begin
            if (master_req_6 == 1'b0) begin
                if (master_req_7 == 1'b1) begin
                    if (master_addr_7[0] == 1'b1) begin
                        master_gnt_7 = 1'b1;
                        bank1_req    = 1'b1;
                        bank1_cmd    = master_cmd_7;
                        bank1_addr   = master_addr_7;
                    end
                end
            end
        end
    end

    // -- M0 wins in rotation 11, even addr → bank0 --
    if (fib_pri_reg[1] == 1'b1) begin
        if (fib_pri_reg[0] == 1'b1) begin
            if (master_req_6 == 1'b0) begin
                if (master_req_7 == 1'b0) begin
                    if (master_req_0 == 1'b1) begin
                        if (master_addr_0[0] == 1'b0) begin
                            master_gnt_0 = 1'b1;
                            bank0_req    = 1'b1;
                            bank0_cmd    = master_cmd_0;
                            bank0_addr   = master_addr_0;
                        end
                    end
                end
            end
        end
    end

    // -- M0 wins in rotation 11, odd addr → bank1 --
    if (fib_pri_reg[1] == 1'b1) begin
        if (fib_pri_reg[0] == 1'b1) begin
            if (master_req_6 == 1'b0) begin
                if (master_req_7 == 1'b0) begin
                    if (master_req_0 == 1'b1) begin
                        if (master_addr_0[0] == 1'b1) begin
                            master_gnt_0 = 1'b1;
                            bank1_req    = 1'b1;
                            bank1_cmd    = master_cmd_0;
                            bank1_addr   = master_addr_0;
                        end
                    end
                end
            end
        end
    end

end // end arbitration always block

endmodule

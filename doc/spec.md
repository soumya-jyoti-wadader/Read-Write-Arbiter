Design an Out-of-Order Read/Write Arbiter (rdwrarbt) without changing any port, any parameter.
Donot use any case/casex/casez statement in any where in the module.
Separate bank routing block FORBIDDEN — bank outputs must be driven inside the grant branch, not after it.
Default outputs MANDATORY — all outputs assigned at top of always block before any condition
Latch inference ZERO — all outputs must be covered in every branch

Required Nesting Structure — Exactly Three Levels Deep:
The entire combinatorial always block must follow this exact nesting order — no reordering permitted

Priority Rotation Table — Must be implemented exactly:
2'b00 M0 > M1 > M2 > M3 
2'b01 M1 > M2 > M3 > M0 
2'b10 M2 > M3 > M0 > M1
2'b11 M3 > M0 > M1 > M2

Memory Bank Routing (Combinatorial, inside same always block)
After arbitration, route the granted master to the correct memory bank based on address LSB:
for even addresses:
If master_gnt[0] and master_addr_0[0] is 0 drive bank0_req, bank0_cmd, bank0_addr
If master_gnt[1] and master_addr_1[0] is 0 drive bank0_req, bank0_cmd, bank0_addr
For odd addresses:
If master_gnt[2] and master_addr_2[0] is 1 drive bank1_req, bank1_cmd, bank1_addr
If master_gnt[3] and master_addr_3[0] is 1 drive bank1_req, bank1_cmd, bank1_addr
Both these can be active simultaneously for different masters.

Fibonacci LFSR — Sequential Block Rules:
Triggered on posedge clk or negedge rst_n
Reset to 4'b0001
Advance: fib_pri_reg <= {fib_pri_reg[2:0], (fib_pri_reg[3] ^ fib_pri_reg[2] ^ seed_in[0])}
dynamic_highest_priority taps fib_pri_reg[1:0] — keep this wire
No case statement permitted here either — this block needs none

Default Output Assignments — Must appear at top of always block:
master_gnt = 4'b0000;
bank0_req  = 1'b0;
bank0_cmd  = 1'b0;
bank0_addr = 32'h00000000;
bank1_req  = 1'b0;
bank1_cmd  = 1'b0;
bank1_addr = 32'h00000000;

Coding Rules:

One always @(*) block for all combinatorial logic — do not split into multiple blocks
One always @(posedge clk or negedge rst_n) block for the LFSR — no other sequential blocks
Blocking assignments in combinatorial block only
Non-blocking assignments in sequential block only
Every if must have a matching end — no single-line if without begin/end
Inline comment on every grant line and every bank routing branch

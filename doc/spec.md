Design an Out-of-Order Read/Write Arbiter (rdwrarbt) without changing any port, any parameter.
Donot use any case/casex/casez statement in any where in the module.
Separate bank routing block FORBIDDEN — bank outputs must be driven inside the grant branch, not after it.
Default outputs MANDATORY — all outputs assigned at top of always block before any condition
Latch inference ZERO — all outputs must be covered in every branch

Required Nesting Structure — Exactly Three Levels Deep:
The entire combinatorial always block must follow this exact nesting order — no reordering permitted

  Level 1: dynamic_highest_priority rotation (if / else if chain — no case statements)
  Level 2: master_req priority chain within the active rotation
  Level 3: master_addr_N[0] bank routing inside each granted-master branch

Priority Rotation Table — Must be implemented exactly:
2'b00 M0 > M1 > M2 > M3 
2'b01 M1 > M2 > M3 > M0 
2'b10 M2 > M3 > M0 > M1
2'b11 M3 > M0 > M1 > M2

Memory Bank Routing (Combinatorial, inside same always block)
After arbitration grants exactly one master, route that granted master to a memory bank
based on the granted master's address LSB. Routing must be nested inside the grant
branch (not in a separate post-arbitration block).

For whichever master N receives master_gnt[N] = 1'b1:
  if master_addr_N[0] == 1'b0  (even address)
    drive bank0_req, bank0_cmd, bank0_addr from master_cmd[N] and master_addr_N
  else  (odd address)
    drive bank1_req, bank1_cmd, bank1_addr from master_cmd[N] and master_addr_N

This parity rule applies to every master (M0, M1, M2, M3) when that master wins arbitration.
Examples:
  M0 granted with addr 0x100 -> bank0
  M0 granted with addr 0x101 -> bank1
  M2 granted with addr 0x200 -> bank0
  M2 granted with addr 0x203 -> bank1

Only one master is granted at a time, so at most one bank interface is active per cycle.

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

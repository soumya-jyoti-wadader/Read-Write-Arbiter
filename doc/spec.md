Design an Out-of-Order Read/Write Arbiter (rdwrarbt) without changing any port, any parameter.
Donot use any case/casex/casez statement in any where in the module.Every constraint is absolute — violating anysingle one invalidates the entire submission.

BLOCK 1 — Fibonacci LFSR (Sequential)

Declare reg [3:0] fib_pri_reg
Trigger on posedge clk or negedge rst_n
Reset to 4'b0001
Advance each bit individually — no concatenation, no replication

BLOCK 2 — Pipeline Stage Registers (Sequential)

Declare 3 pipeline stages as flat scalar registers only — no arrays
Trigger on posedge clk or negedge rst_n
On reset: clear all pipeline registers to 0
On clock: shift stage 1→2, stage 0→1 using non-blocking assignments
Load stage 0 from whichever master was granted — use 8 separate if statements, one per master, checking master_gnt_N == 1'b1

BLOCK 3 — Hazard Detection (Combinatorial)
This block is the primary fail trigger — read every rule carefully.

Single always @(*) block
Default all 8 stall outputs to 1'b0 at top of block
For every master N (0 through 7), check its address against all 3 pipeline stages
CONSTRAINT: Zero loop constructs — for, while, repeat are forbidden
CONSTRAINT: Zero logical operators — &&, ||, ! are forbidden in any condition
CONSTRAINT: One signal bit per if — each if checks exactly one bit
Every pipeline stage address comparison must be written as 8 separate nested if statements, one per address bit, deepest level asserts stall_N = 1'b1

Required structure per master per stage — write this exactly 24 times (8 masters × 3 stages)
Do not skip any master. Do not skip any stage. Do not compress or combine any condition. All 24 blocks must be written in full.

BLOCK 4 — Arbitration and Bank Routing (Combinatorial)
This block is the second fail trigger.

Single always @(*) block — separate from Block 3
Default all grant and bank outputs to 0 at top of block
CONSTRAINT: Zero case statements — forbidden
CONSTRAINT: Zero else clauses — every if is standalone
CONSTRAINT: Zero logical operators — no && or || in any condition
CONSTRAINT: Zero intermediate wires — reference fib_pri_reg bits directly
CONSTRAINT: One signal bit per if — each if checks exactly one bit

Priority rotation table:
fib_pri_reg[1] fib_pri_reg[0]Priority Order
00M0 > M1 > M2 > M3 > M4 > M5 > M6 > M7
01M2 > M3 > M4 > M5 > M6 > M7 > M0 > M1
10M4 > M5 > M6 > M7 > M0 > M1 > M2 > M3
11M6 > M7 > M0 > M1 > M2 > M3 > M4 > M5

Required structure per grant branch Every rotation must cover all 8 masters. Every master must have both even-address and odd-address branches. No shortcuts. No comments substituting for code.

Structural Verification Checklist:
Donot use 'case','else, '&&', 'for'.
Hazard blocksExactly 24 — 8 masters × 3 stages
Address bits per hazardExactly 8 — bits 0 through 7
Grant branchesExactly 64 — 4 rotations × 8 masters × 2 addr cases
Every begin has exactly one matching end
All 8 stall outputs drivenYes — default + conditional in hazard block
All 8 grant outputs drivenYes — default + conditional in arbitration block
All bank outputs drivenYes — default + conditional in arbitration block

The submission is only valid if the generated file passes all checklist items above and endmodule is the final line of the file.  

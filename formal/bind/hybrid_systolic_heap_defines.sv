// Sizes hybrid_systolic_heap for its proof. Listed first in the config: the sources are
// analyzed together, so these macros reach hybrid_typedef.sv ahead of its defaults.
//
// The smallest build that reaches every path: a systolic buffer of 6 (HALF_SIZE >= 3), trees
// of 7 so a pull can find its tree busy, and three trees so tree indices wrap at a count that
// is not a power of two. Capacity 3*7 + 2*(6-2) = 29.
// POWERUP_FILL=1: the tool ignores RAM initial contents, so the memory powers up arbitrary
// and the reset fill must establish it. A POWERUP_FILL=0 build relies on the target's RAM
// initialisation, which this proof does not cover.
// GEN_W=1: every second reset wraps the generation and refills the memory, so both reset
// paths are reachable within two resets.
`define HYBRID_SYSTOLIC_QUEUE_SIZE  6
`define HYBRID_TREE_COUNT           3
`define HYBRID_BRAM_TREE_QUEUE_SIZE 7
`define HYBRID_DATA_WIDTH           3
`define HYBRID_GEN_W                1
`define HYBRID_POWERUP_FILL         1
// Longest busy run of one tree after a command, shared by the tree proof and the stand-in.
`define HWPQ_HYB_TREE_MAX_BUSY      (bram_tree_pkg::TREE_DEPTH - 1)

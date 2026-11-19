// Attaches hwpq_spec to hybrid_systolic_heap. The DUT is sized by bram_tree_pkg macros,
// so every parameter here is derived from the package.
//
// o_read_ready waits for the head to resolve, which can take a tree walk; o_write_ready drops
// alone while no buffer or tree can take a write. A stream of commands on one ready can hold
// the other low; both recover once the caller is quiet.
// CAPACITY: every tree full plus each systolic buffer at its full threshold, two slots of
// shift margin each.
// MAX_SETTLE bounds how long spills, pulls and evicts can still move a ready once the caller
// is quiet. It grows with buffer size and tree depth, not tree count, and holds only at the
// sizes in hybrid_systolic_heap_defines.sv: re-pin it with c_settle_tight when they change.
`define HWPQ_HYB_CAPACITY (bram_tree_pkg::TREE_COUNT * bram_tree_pkg::BRAM_TREE_QUEUE_SIZE \
                           + 2 * (bram_tree_pkg::SYSTOLIC_QUEUE_SIZE - 2))
bind hybrid_systolic_heap hwpq_spec #(
    .QUEUE_SIZE         (`HWPQ_HYB_CAPACITY),
    .DATA_WIDTH         (bram_tree_pkg::DATA_WIDTH),
    .ENQ_ENA            (1'b1),
    .HAS_BUSY           (1'b1),
    .MAX_SETTLE         (22),
    .CAPACITY           (`HWPQ_HYB_CAPACITY),
    .HAS_FULL           (1'b1)
) u_spec (
    .i_CLK        (i_CLK),
    .i_RSTn       (i_RSTn),
    .i_wrt        (i_wrt),
    .i_read       (i_read),
    .i_data       (i_data),
    .o_write_ready(o_write_ready),
    .o_read_ready (o_read_ready),
    .o_data       (o_data)
);


// Reset harness: the elaboration top for this module's proofs. The tool holds the declared
// reset inactive after init; declaring i_init_RSTn keeps the DUT's i_RSTn free for
// mid-operation resets.
module hwpq_rst_hybrid_systolic_heap (
    input  logic                                i_CLK,
    input  logic                                i_init_RSTn,
    input  logic                                i_RSTn,
    input  logic                                i_wrt,
    input  logic                                i_read,
    input  logic [bram_tree_pkg::DATA_WIDTH-1:0] i_data,
    output logic                                o_write_ready,
    output logic                                o_read_ready,
    output logic [bram_tree_pkg::DATA_WIDTH-1:0] o_data
);
  hybrid_systolic_heap u_dut (
      .i_CLK(i_CLK), .i_RSTn(i_init_RSTn & i_RSTn),
      .i_wrt(i_wrt), .i_read(i_read), .i_data(i_data),
      .o_write_ready(o_write_ready), .o_read_ready(o_read_ready), .o_data(o_data)
  );

  // The reset block's unreset flops take their declaration values at power-up, as the target
  // loads them; the tool leaves them free. Reset holds all five, so pinning the first cycle
  // after init pins power-up. Later resets and the tree memory stay unconstrained.
  logic first;
  always_ff @(posedge i_CLK or negedge i_init_RSTn)
    if (!i_init_RSTn) first <= 1'b1;
    else              first <= 1'b0;

  am_powerup_values: assume property (@(posedge i_CLK) first |->
      u_dut.tree_reset.gen == '0 && u_dut.tree_reset.filling == bram_tree_pkg::POWERUP_FILL
      && u_dut.tree_reset.fill_cnt == '0 && u_dut.tree_reset.fill_level == '0
      && u_dut.tree_reset.fill_bound == 'd1);
endmodule

// White-box helpers; they read the stand-ins' contract models, so only the stand-in proof
// lists hwpq_hybrid_aux.sv.
bind hybrid_systolic_heap hwpq_hybrid_aux u_aux (.i_CLK(i_CLK), .i_RSTn(i_RSTn));

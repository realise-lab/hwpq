// White-box addendum for bram_tree: the power-up contents of the node memory.
//
// WHY THIS EXISTS. The BRAM has no reset port, and the `initial` block in
// rams_tdp_rf_rf.sv that lays down the empty-tree fill is simulation-only; a
// formal tool ignores it on every run.
//
// Without an assumption the memory therefore starts ARBITRARY: arbitrary
// `active` flags, arbitrary values, and, worst of all for this module,
// arbitrary `capacity` fields, which carry the free-space accounting the whole
// design rests on. Ordering and occupancy properties then fail for reasons that
// say nothing about the design.
//
// NOT ASSUMED. The memory is left free. The reset sweep rewrites every node
// before the module advertises a ready, so arbitrary power-up contents are
// harmless and no assumption is needed. Do not add one: it would hide whether
// the sweep works.
//
// An SVA assume could not express it in any case: the tool's initial state is
// already post-reset, so an antecedent predicated on the harness reset being low
// is never true at an observed posedge and the precondition comes back
// UNREACHABLE with the memories still free.
module hwpq_bram_tree_aux #(
    parameter int QUEUE_SIZE    = 7,
    parameter int DATA_WIDTH    = 3,
    parameter int NODES_NEEDED  = 7,
    parameter int ADDRESS_WIDTH = 3,
    parameter int MEM_WIDTH     = 1 + DATA_WIDTH + ADDRESS_WIDTH
) (
    input logic                 i_CLK,
    input logic                 i_init_RSTn,
    input logic                 i_RSTn,
    input logic [MEM_WIDTH-1:0]     ram [NODES_NEEDED-1:0],
    input logic [ADDRESS_WIDTH-1:0] top_capacity,
    input integer                   queue_size,
    input logic                     fsm_idle
);

  // The capacity a node powers up holding is the size of the subtree it roots.
  // rams_tdp_rf_rf computes it as ((DEPTH+1) >> level) - 1 with
  // level = $clog2(i+2) - 1, which for a 0-rooted heap is the node's depth,
  // floor(log2(i+1)). Computed with a shift loop rather than $clog2 because the
  // argument is not a constant here and $clog2 on a non-constant is not portable.
  function automatic int unsigned node_level(input int unsigned i);
    int unsigned n;
    int unsigned lvl;
    n   = i + 1;
    lvl = 0;
    while (n > 1) begin
      n   = n >> 1;
      lvl = lvl + 1;
    end
    return lvl;
  endfunction

  function automatic int unsigned node_capacity(input int unsigned i);
    return ((NODES_NEEDED + 1) >> node_level(i)) - 1;
  endfunction

  // The empty-tree fill: every node inactive, value zero, capacity = subtree size.
  logic fill_intact;
  always_comb begin
    fill_intact = 1'b1;
    for (int unsigned i = 0; i < NODES_NEEDED; i++) begin
      if (ram[i] != {{(MEM_WIDTH-ADDRESS_WIDTH){1'b0}},
                     ADDRESS_WIDTH'(node_capacity(i))}) begin
        fill_intact = 1'b0;
      end
    end
  end

  // Anti-vacuity: fill_intact must be reachable, or a_reset_restores_fill below
  // would hold for free.
  c_fill_intact_reachable : cover property (@(posedge i_CLK) fill_intact);

  // ---------------------------------------------------------------------------
  // The reset contract.
  //
  // The BRAM has no reset port and its `initial` fill is simulation-only, so the
  // contents have to be rewritten in logic. Without that, a reset arriving with
  // data in the queue clears queue_size and top_level while every node keeps its
  // stale `active` flag and stale `capacity`. The reset sweep is what prevents
  // it, and this property is the acceptance test for the sweep.
  //
  // PHRASING, and the two wrong ways to write this.
  //
  //   `!i_RSTn |=> fill_intact` demands the whole memory clear in one cycle: no
  //   BRAM-backed design can do that, so it stays red against a correct fix and
  //   is useless as an acceptance test.
  //
  //   `idle && no command |-> fill_intact` is worse. It says the memory is empty
  //   whenever the queue is idle, which is FALSE for any correct design
  //   holding data, and fails immediately for exactly that reason: a populated
  //   queue, behaving correctly.
  //
  // The satisfiable form is a BOUNDED RESPONSE to reset deassertion: within
  // NODES_NEEDED+2 cycles of the reset releasing, the fill is back. A sweep that
  // writes one node per cycle meets it with room to spare; a design that never
  // rewrites the memory cannot. Ask what PASSING would look like before keeping a
  // property that fails.
  //
  // The case that matters is a reset arriving after data has been written: a
  // design that never rewrites the memory fails there, a correct sweep does not.
  // `disable iff (!i_RSTn)` is load-bearing: without it a reset arriving during
  // the sweep restarts the fill while the obligation from the first $rose still
  // demands completion inside the original window, failing a design whose sweep
  // is correct. The guard aborts a pending obligation when a new reset lands.
  //
  // The sweep writes one node per cycle for NODES_NEEDED cycles, so fill_intact
  // holds by NODES_NEEDED+1 after the reset releases, inside the window.
  a_reset_restores_fill : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      $rose(i_RSTn) |-> ##[1:NODES_NEEDED+2] fill_intact);

  // ---------------------------------------------------------------------------
  // Root capacity invariant.
  //
  // `capacity` is a per-node count of free slots in the subtree rooted at that
  // node. The root's subtree is the whole tree, so at idle its count equals total
  // free space. This cross-checks the distributed ledger the enqueue descent
  // maintains against the scalar queue_size counter, which a separate path
  // maintains: two independent accountings of one quantity.
  //
  // The field is live, not dead: top_capacity seeds curr.capacity, which is
  // written into din_*.capacity, stored, and read back as dout_*.capacity, which
  // gates every arm of the enqueue descent. Nothing on the interface reads it, so
  // a corrupt value is invisible to every black-box property and this assert is
  // the only detector.
  // ---------------------------------------------------------------------------
  a_root_capacity_agrees : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      fsm_idle |-> (top_capacity == ADDRESS_WIDTH'(QUEUE_SIZE - queue_size)));

endmodule

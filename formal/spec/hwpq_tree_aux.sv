`default_nettype none
// White-box addendum for the register trees: the settle countdowns never release early.
// Kept apart from hwpq_spec.sv, which reads only the interface and binds to every module.
// head_valid gates the write side and must imply the full heap order; head_ready gates the
// read side and must imply that the root outranks every node.

module hwpq_tree_aux #(
    parameter int DATA_WIDTH   = 3,
    parameter int NODES_NEEDED = 7,
    // 1 when the read side can reopen before the full settle; generates c_head_early.
    parameter bit EARLY_HEAD   = 0
) (
    input var logic                  i_CLK,
    input var logic                  i_RSTn,
    input var logic                  head_valid,
    input var logic                  head_ready,
    input var logic [DATA_WIDTH-1:0] queue      [NODES_NEEDED]
);

  // Every parent outranks both of its children.
  logic heap_holds;
  always_comb begin : heap_invariant
    heap_holds = 1'b1;
    for (int i = 0; i < NODES_NEEDED; i++) begin
      if (2 * i + 1 < NODES_NEEDED && queue[i] < queue[2*i+1]) heap_holds = 1'b0;
      if (2 * i + 2 < NODES_NEEDED && queue[i] < queue[2*i+2]) heap_holds = 1'b0;
    end
  end

  // The root outranks every node: weaker than heap_holds, and all the read side needs.
  logic head_outranks_all;
  always_comb begin : root_dominates
    head_outranks_all = 1'b1;
    for (int i = 1; i < NODES_NEEDED; i++) begin
      if (queue[0] < queue[i]) head_outranks_all = 1'b0;
    end
  end

  a_timer_is_sound : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      head_valid |-> heap_holds);

  a_timer_head_is_max : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      head_valid |-> head_outranks_all);

  a_head_ready_is_max : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      head_ready |-> head_outranks_all);

  // Anti-vacuity: a countdown stuck low proves the asserts while saying nothing.
  c_timer_valid    : cover property (@(posedge i_CLK) disable iff (!i_RSTn) head_valid);
  c_timer_counting : cover property (@(posedge i_CLK) disable iff (!i_RSTn) !head_valid);

  generate
    if (EARLY_HEAD) begin : g_early_head
      c_head_early : cover property (@(posedge i_CLK) disable iff (!i_RSTn)
          head_ready && !head_valid);
    end
  endgenerate

endmodule

`default_nettype wire

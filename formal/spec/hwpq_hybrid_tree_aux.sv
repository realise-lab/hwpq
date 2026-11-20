// White-box helpers for bram_tree_for_hybrid in hwpq_bram_tree_for_hybrid: the node memory holds
// exactly the contract model's contents, with the largest on top. Reads the tree, its reset
// block and its contract model by hierarchical reference.
//
// Terms:
//   node n     tree node n, heap-numbered: node 0 is the top register, nodes 1..NODES live in
//              memory, pair p holding nodes 2p+1 and 2p+2 (the children of node p)
//   occupied   a memory node that holds an element: active, stamped with the current generation,
//              and not the hole of a sift in progress
//   walk       the multi-cycle pass after a command: INSERT carries a value down, SIFT refills a
//              hole from below; walk_node is the node it is at
//   carry      the value an INSERT, or a replace's SIFT, is still placing
//   model      the contract's reference contents, sorted largest first
//   tracked    a free constant value; counting its copies proves the count for every value
//
// Helper stages are listed in bram_tree_for_hybrid.cfg: every property except a_tree_inv first,
// then a_tree_inv with those assumed.
module hwpq_hybrid_tree_aux
  import bram_tree_pkg::*;
(
    input logic i_CLK,
    input logic i_RSTn
);
  localparam int PAIRS = (NODES_NEEDED - 1) / 2;
  localparam int NODES = 2 * PAIRS;                    // memory nodes, numbered 1..NODES
  localparam int CNT_W = $clog2(NODES_NEEDED + 2) + 1;
  localparam int MODEL_CNT_W = $clog2(BRAM_TREE_QUEUE_SIZE + 1);
  localparam logic [1:0] IDLE = 2'd0, INSERT = 2'd1, SIFT = 2'd2;  // the tree's state_t

  // ---- the tracked value -----------------------------------------------------------------------

  logic [DATA_WIDTH-1:0] tracked;
  am_tv_stable : assume property (@(posedge i_CLK) disable iff (!i_RSTn) ##1 $stable(tracked));
  am_tv_legal  : assume property (@(posedge i_CLK) disable iff (!i_RSTn)
      tracked != '0 && tracked != '1);

  // ---- aliases into the harness ----------------------------------------------------------------

  wire held = hwpq_bram_tree_for_hybrid.filling || hwpq_bram_tree_for_hybrid.gen_pending;
  wire [GEN_W-1:0]       gen        = hwpq_bram_tree_for_hybrid.gen;
  wire [1:0]             state      = hwpq_bram_tree_for_hybrid.u_tree.state;
  wire [DATA_WIDTH-1:0]  top        = hwpq_bram_tree_for_hybrid.u_tree.top_level.value;
  wire                   top_active = hwpq_bram_tree_for_hybrid.u_tree.top_level.active;
  wire [ADDRESS_WIDTH-1:0] walk_node = hwpq_bram_tree_for_hybrid.u_tree.curr.position;
  wire [DATA_WIDTH-1:0]  carry      = hwpq_bram_tree_for_hybrid.u_tree.curr.value;
  wire [MODEL_CNT_W-1:0] model_cnt  = hwpq_bram_tree_for_hybrid.u_contract.cnt;
  logic [DATA_WIDTH-1:0] model [BRAM_TREE_QUEUE_SIZE];
  always_comb
    for (int i = 0; i < BRAM_TREE_QUEUE_SIZE; i++)
      model[i] = hwpq_bram_tree_for_hybrid.u_contract.m[i];
  // Memory words, one per pair, and the tree's registered copies of words it read.
  localparam int PAIR_BITS = 2 * $bits(bram_tree_mem_t);
  logic [PAIR_BITS-1:0] mem [PAIRS];
  always_comb
    for (int p = 0; p < PAIRS; p++) mem[p] = hwpq_bram_tree_for_hybrid.u_tree.bram_inst.ram[p];
  wire [PAIR_BITS-1:0] read_data   = hwpq_bram_tree_for_hybrid.u_tree.ram_out;
  wire [PAIR_BITS-1:0] parent_pair = hwpq_bram_tree_for_hybrid.u_tree.par;

  wire walking  = state != IDLE;
  wire sifting  = state == SIFT;
  wire inserting = state == INSERT;
  wire [ADDRESS_WIDTH-1:0] hole = walk_node;                     // during a SIFT
  wire carrying = inserting || (sifting && !hwpq_bram_tree_for_hybrid.u_tree.deq);

  // ---- the tree as nodes -----------------------------------------------------------------------

  bram_tree_mem_t node     [1:NODES];
  logic           occupied [1:NODES];
  always_comb begin
    for (int p = 0; p < PAIRS; p++) {node[2*p+1], node[2*p+2]} = mem[p];
    for (int n = 1; n <= NODES; n++)
      occupied[n] = node[n].active && node[n].gen == gen && !(sifting && hole == ADDRESS_WIDTH'(n));
  end

  // Elements the tree holds (top, carry, occupied nodes), and copies of tracked in it and in the
  // model.
  logic [CNT_W-1:0] tree_count, tree_tracked, model_tracked;
  logic             top_is_max;
  always_comb begin
    tree_count   = CNT_W'(top_active) + CNT_W'(carrying);
    tree_tracked = CNT_W'(top_active && top == tracked) + CNT_W'(carrying && carry == tracked);
    top_is_max   = !carrying || carry <= top;
    for (int n = 1; n <= NODES; n++) begin
      tree_count   += CNT_W'(occupied[n]);
      tree_tracked += CNT_W'(occupied[n] && node[n].value == tracked);
      top_is_max   &= !occupied[n] || node[n].value <= top;
    end
    model_tracked = '0;
    for (int i = 0; i < BRAM_TREE_QUEUE_SIZE; i++)
      model_tracked += CNT_W'(model[i] == tracked);
  end

  // ---- stage 1: register copies, capacities, counts --------------------------------------------

  // Register copies of memory words: pair 0 (the root's children), the read data, and a sift's
  // parent pair.
  bram_tree_mem_t mem_root_left, mem_root_right;
  assign {mem_root_left, mem_root_right} = mem[0];
  // A copy matches a memory node when both say occupied and agree on value and capacity.
  function automatic logic mirrors(input bram_tree_mem_t copy, input bram_tree_mem_t mem);
    mirrors = copy.active == (mem.active && mem.gen == gen)
              && (!copy.active || (copy.value == mem.value && copy.capacity == mem.capacity));
  endfunction
  wire walk_has_children = walk_node < ADDRESS_WIDTH'(PAIRS);

  // The root-children copy matches pair 0 of memory.
  a_tree_child_mirror : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      !held |-> mirrors(hwpq_bram_tree_for_hybrid.u_tree.child.l, mem_root_left)
                && mirrors(hwpq_bram_tree_for_hybrid.u_tree.child.r, mem_root_right));
  // During a walk, the read data is the children pair of the walk's node.
  a_tree_read_fresh : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      walking && walk_has_children |-> read_data == mem[walk_node]);
  // During a sift, the held parent pair is the pair that contains the hole.
  a_tree_par_fresh : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      sifting |-> parent_pair == mem[(hole - 1) >> 1]);

  // Number of nodes in node n's subtree, n included.
  function automatic int subtree_size(input int n);
    subtree_size = 1;
    for (int m = 2*n + 1; m <= NODES; m = 2*m + 1) subtree_size = 2*subtree_size + 1;
  endfunction
  // Node m is node n or below it.
  function automatic logic in_subtree(input int n, input int m);
    in_subtree = 1'b0;
    for (int k = 0; k <= TREE_DEPTH; k++) begin
      if (m == n) in_subtree = 1'b1;
      m = (m - 1) / 2;
    end
  endfunction
  // A node's capacity is its subtree's free slots: subtree size less the occupied nodes and any
  // carry inside it. A sift's hole keeps its capacity in the walk; a node from an earlier
  // generation counts its whole subtree free. A stale node is empty unless still active.
  logic capacity_ok    [1:NODES];
  logic inactive_empty [1:NODES];
  always_comb
    for (int n = 1; n <= NODES; n++) begin
      automatic int cap = (sifting && hole == ADDRESS_WIDTH'(n))
                          ? int'(hwpq_bram_tree_for_hybrid.u_tree.curr.capacity)
                          : (node[n].gen == gen ? int'(node[n].capacity) : subtree_size(n));
      automatic int used = int'(carrying && in_subtree(n, int'(walk_node)));
      for (int m = 1; m <= NODES; m++) used += int'(occupied[m] && in_subtree(n, m));
      capacity_ok[n]    = cap + used == subtree_size(n);
      inactive_empty[n] = node[n].gen != gen || node[n].active || node[n].value == '0;
    end
  for (genvar n = 1; n <= NODES; n++) begin : g_node
    // Each node's capacity counts its subtree's free slots.
    a_tree_capacity : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        !held |-> capacity_ok[n]);
    // An inactive node of this generation holds the empty marker.
    a_tree_inactive_empty : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        !held |-> inactive_empty[n]);
  end

  // No occupied node, and no carry, outranks the top.
  a_tree_top_max : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      !held && top_active |-> top_is_max);
  // The tree holds as many elements as the model.
  a_tree_conserve_all : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      !held |-> tree_count == CNT_W'(model_cnt));
  // The tree holds as many copies of tracked as the model.
  a_tree_conserve_tracked : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      !held |-> tree_tracked == model_tracked);
  // The tree's own count matches the model's.
  a_tree_size : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      hwpq_bram_tree_for_hybrid.u_tree.queue_size == model_cnt);
  // An insert's walk node is always an occupied memory node.
  a_tree_insert_live : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      !held && inserting
      |-> walk_node != '0 && walk_node <= ADDRESS_WIDTH'(NODES) && occupied[int'(walk_node)]);

  // ---- stage 2: the inductive invariant --------------------------------------------------------

  // The model holds model_cnt elements sorted largest first, then zeros.
  logic model_sorted;
  always_comb begin
    model_sorted = 1'b1;
    for (int i = 0; i < BRAM_TREE_QUEUE_SIZE; i++) begin
      model_sorted &= (model[i] != '0) == (i < model_cnt);
      if (i + 1 < BRAM_TREE_QUEUE_SIZE) model_sorted &= model[i] >= model[i + 1];
    end
  end

  // Value of node n's nearest occupied ancestor, or the top if none.
  function automatic logic [DATA_WIDTH-1:0] ancestor_value(input int n);
    logic found;
    ancestor_value = top;
    found = 1'b0;
    for (int k = 0; k < TREE_DEPTH; k++) begin
      n = (n - 1) / 2;
      if (!found && n > 0 && occupied[n]) begin
        ancestor_value = node[n].value;
        found = 1'b1;
      end
    end
  endfunction
  function automatic logic legal(input logic [DATA_WIDTH-1:0] v);
    legal = v != '0;
  endfunction
  // Heap order: every occupied node holds a legal value no larger than its nearest occupied
  // ancestor, and its parent is occupied or the sift's hole.
  logic heap_ordered;
  always_comb begin
    heap_ordered = 1'b1;
    for (int n = 1; n <= NODES; n++)
      heap_ordered &= !occupied[n]
                      || (legal(node[n].value) && node[n].value <= ancestor_value(n)
                          && (n <= 2 || occupied[(n-1)/2]
                              || (sifting && hole == ADDRESS_WIDTH'((n-1)/2))));
  end
  // What the carry must not exceed: the walk's node during an insert, its ancestor during a sift.
  wire [DATA_WIDTH-1:0] carry_bound =
      (inserting && occupied[int'(walk_node)]) ? node[int'(walk_node)].value
                                               : ancestor_value(int'(walk_node));

  // While held after a reset, every node will be unoccupied once gen settles: inactive, stamped
  // with another generation, or still ahead of the fill. A pending advance from the last
  // generation wraps gen and starts a fill, which rewrites every node.
  wire [GEN_W-1:0] gen_after = hwpq_bram_tree_for_hybrid.gen_pending ? gen + 1'b1 : gen;
  logic all_retired;
  always_comb begin
    all_retired = 1'b1;
    for (int n = 1; n <= NODES; n++)
      all_retired &= !node[n].active || node[n].gen != gen_after
                     || (hwpq_bram_tree_for_hybrid.filling
                         && hwpq_bram_tree_for_hybrid.tree_reset.fill_cnt
                            <= ADDRESS_WIDTH'(2*((n-1)/2) + 1));
    all_retired |= hwpq_bram_tree_for_hybrid.gen_pending && &gen;
  end

  // The tree and the model hold the same multiset, compared value by value. Needed because a
  // pop's new top is the model's next element only if every value matches, not just tracked.
  logic same_multiset;
  always_comb begin
    same_multiset = 1'b1;
    for (int v = 1; v < (1 << DATA_WIDTH); v++) begin
      automatic logic [CNT_W-1:0] in_tree  = CNT_W'(top_active && top == DATA_WIDTH'(v))
                                             + CNT_W'(carrying && carry == DATA_WIDTH'(v));
      automatic logic [CNT_W-1:0] in_model = '0;
      for (int n = 1; n <= NODES; n++)
        in_tree += CNT_W'(occupied[n] && node[n].value == DATA_WIDTH'(v));
      for (int i = 0; i < BRAM_TREE_QUEUE_SIZE; i++)
        in_model += CNT_W'(model[i] == DATA_WIDTH'(v));
      same_multiset &= in_tree == in_model;
    end
  end

  // Model shape, heap order, the walk's position and carry, the top, the hold window and the
  // multiset each need the others to carry over a cycle, so they are one property.
  a_tree_inv : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      model_sorted
      && (held ? model_cnt == '0 && !top_active && top == '0 && state == IDLE && all_retired
               : heap_ordered
                 && (!sifting || (hole != '0 && hole <= ADDRESS_WIDTH'(NODES)
                                  && (hole <= 2 || occupied[int'(hole - 1) / 2])))
                 && (!carrying || (legal(carry) && carry <= carry_bound))
                 && top_active == (model_cnt != '0)
                 && (top_active ? legal(top) : top == '0)
                 && same_multiset && top == model[0]));
endmodule

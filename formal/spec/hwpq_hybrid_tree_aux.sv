// White-box helper properties for the hybrid's bram_tree_pair in hwpq_hybrid_tree_pair: the
// node memory holds exactly the contract's reference contents, with the largest on top. Reads
// the tree and its contract model by hierarchical reference.
module hwpq_hybrid_tree_aux
  import bram_tree_pkg::*;
(
    input logic i_CLK,
    input logic i_RSTn
);
  localparam int PAIRS = (NODES_NEEDED - 1) / 2;
  localparam int NW    = $clog2(NODES_NEEDED + 2) + 1;

  // An unconstrained legal constant: counting it proves the count for every value.
  logic [DATA_WIDTH-1:0] tv;
  am_tv_stable : assume property (@(posedge i_CLK) disable iff (!i_RSTn) ##1 $stable(tv));
  am_tv_legal  : assume property (@(posedge i_CLK) disable iff (!i_RSTn) tv != '0 && tv != '1);

  wire held = hwpq_hybrid_tree_pair.filling || hwpq_hybrid_tree_pair.gen_pending;
  wire [GEN_W-1:0] gen = hwpq_hybrid_tree_pair.gen;

  // A node below the top is live when active in this generation. During a sift the hole's node
  // still holds the value promoted out of it, so it is not counted; a walk's carry is.
  bram_tree_mem_t        node [2*PAIRS];
  logic                  live [2*PAIRS];
  logic [DATA_WIDTH-1:0] top;
  logic                  top_live, carry_live, sifting;
  logic [DATA_WIDTH-1:0] carry;
  logic [ADDRESS_WIDTH-1:0] hole;

  always_comb begin
    top        = hwpq_hybrid_tree_pair.u_tree.top_level.value;
    top_live   = hwpq_hybrid_tree_pair.u_tree.top_level.active;
    sifting    = hwpq_hybrid_tree_pair.u_tree.state == 2'd2;
    hole       = hwpq_hybrid_tree_pair.u_tree.curr.position;
    carry      = hwpq_hybrid_tree_pair.u_tree.curr.value;
    carry_live = hwpq_hybrid_tree_pair.u_tree.state == 2'd1
                 || (sifting && !hwpq_hybrid_tree_pair.u_tree.deq);
    for (int p = 0; p < PAIRS; p++) begin
      {node[2*p], node[2*p+1]} = hwpq_hybrid_tree_pair.u_tree.bram_inst.ram[p];
    end
    for (int n = 0; n < 2*PAIRS; n++)
      live[n] = node[n].active && node[n].gen == gen
                && !(sifting && hole == ADDRESS_WIDTH'(n + 1));
  end

  logic [NW-1:0] t_tv, t_all, m_tv;
  logic          top_max;
  always_comb begin
    t_tv    = NW'(top_live && top == tv) + NW'(carry_live && carry == tv);
    t_all   = NW'(top_live) + NW'(carry_live);
    top_max = !carry_live || carry <= top;
    for (int n = 0; n < 2*PAIRS; n++) begin
      t_tv    += NW'(live[n] && node[n].value == tv);
      t_all   += NW'(live[n]);
      top_max &= !live[n] || node[n].value <= top;
    end
    m_tv = '0;
    for (int i = 0; i < BRAM_TREE_QUEUE_SIZE; i++)
      m_tv += NW'(hwpq_hybrid_tree_pair.u_contract.m[i] == tv);
  end

  // The tree's register copies agree with the memory: pair 0's mirror on every live node, the
  // read data and the sift's hole pair with the words the walk addressed.
  logic [$bits(bram_tree_mem_t)-1:0] ram0_l, ram0_r;
  assign {ram0_l, ram0_r} = hwpq_hybrid_tree_pair.u_tree.bram_inst.ram[0];
  function automatic logic same_live(input bram_tree_mem_t c, input bram_tree_mem_t r);
    same_live = c.active == (r.active && r.gen == gen)
                && (!c.active || (c.value == r.value && c.capacity == r.capacity));
  endfunction
  wire [ADDRESS_WIDTH-1:0] at = hwpq_hybrid_tree_pair.u_tree.curr.position;
  wire walking = hwpq_hybrid_tree_pair.u_tree.state != 2'd0;
  wire inner   = at < ADDRESS_WIDTH'(PAIRS);

  a_tree_child_mirror : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      !held |-> same_live(hwpq_hybrid_tree_pair.u_tree.child.l, ram0_l)
                && same_live(hwpq_hybrid_tree_pair.u_tree.child.r, ram0_r));
  a_tree_read_fresh : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      walking && inner |-> hwpq_hybrid_tree_pair.u_tree.ram_out
                  == hwpq_hybrid_tree_pair.u_tree.bram_inst.ram[at]);
  a_tree_par_fresh : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      sifting |-> hwpq_hybrid_tree_pair.u_tree.par
                  == hwpq_hybrid_tree_pair.u_tree.bram_inst.ram[(at - 1) >> 1]);

  // Each node's capacity is its subtree's free slots, less a carry still walking into it; the
  // hole's is the walk's. A node from an earlier generation is empty with its subtree free.
  function automatic int sub_size(input int n);
    sub_size = 1;
    for (int m = 2*n + 1; m <= 2*PAIRS; m = 2*m + 1) sub_size = 2*sub_size + 1;
  endfunction
  function automatic logic below(input int n, input int m);
    below = 1'b0;
    for (int k = 0; k <= TREE_DEPTH; k++) begin
      if (m == n) below = 1'b1;
      m = (m - 1) / 2;
    end
  endfunction
  logic cap_ok [2*PAIRS];
  logic empty_ok [2*PAIRS];
  always_comb
    for (int n = 1; n <= 2*PAIRS; n++) begin
      automatic int c = (sifting && hole == ADDRESS_WIDTH'(n))
                        ? int'(hwpq_hybrid_tree_pair.u_tree.curr.capacity)
                        : (node[n-1].gen == gen ? int'(node[n-1].capacity) : sub_size(n));
      automatic int u = int'(carry_live && below(n, int'(at)));
      for (int m = 1; m <= 2*PAIRS; m++) u += int'(live[m-1] && below(n, m));
      cap_ok[n-1]   = c + u == sub_size(n);
      empty_ok[n-1] = node[n-1].gen != gen || node[n-1].active || node[n-1].value == '0;
    end
  for (genvar n = 0; n < 2*PAIRS; n++) begin : g_node
    a_tree_capacity : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        !held |-> cap_ok[n]);
    a_tree_inactive_empty : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        !held |-> empty_ok[n]);
  end

  a_tree_conserve_all : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      !held |-> t_all == NW'(hwpq_hybrid_tree_pair.u_contract.cnt));
  a_tree_conserve_tracked : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      !held |-> t_tv == m_tv);
  // The model holds its cnt elements sorted, largest first, with zeros after them; the tree
  // counts the same elements.
  logic model_ok;
  always_comb begin
    model_ok = 1'b1;
    for (int i = 0; i < BRAM_TREE_QUEUE_SIZE; i++) begin
      model_ok &= (hwpq_hybrid_tree_pair.u_contract.m[i] != '0)
                  == (i < hwpq_hybrid_tree_pair.u_contract.cnt);
      if (i + 1 < BRAM_TREE_QUEUE_SIZE)
        model_ok &= hwpq_hybrid_tree_pair.u_contract.m[i] >= hwpq_hybrid_tree_pair.u_contract.m[i + 1];
    end
  end
  a_tree_size : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      hwpq_hybrid_tree_pair.u_tree.queue_size == hwpq_hybrid_tree_pair.u_contract.cnt);

  // Heap order: a live value is at most its nearest live ancestor, the top above them all, and
  // its parent is live or the hole. The carry sits at the walk's node: below it during an
  // insert, in the hole during a sift.
  function automatic logic [DATA_WIDTH-1:0] above(input int n);
    logic found;
    above = top;
    found = 1'b0;
    for (int k = 0; k < TREE_DEPTH; k++) begin
      n = (n - 1) / 2;
      if (!found && n > 0 && live[n-1]) begin
        above = node[n-1].value;
        found = 1'b1;
      end
    end
  endfunction
  function automatic logic legal(input logic [DATA_WIDTH-1:0] v);
    legal = v != '0;
  endfunction
  logic order_ok;
  always_comb begin
    order_ok = 1'b1;
    for (int n = 1; n <= 2*PAIRS; n++)
      order_ok &= !live[n-1] || (legal(node[n-1].value) && node[n-1].value <= above(n)
                                 && (n <= 2 || live[(n-1)/2 - 1]
                                     || (sifting && hole == ADDRESS_WIDTH'((n-1)/2))));
  end
  wire [DATA_WIDTH-1:0] carry_above =
      (hwpq_hybrid_tree_pair.u_tree.state == 2'd1 && live[int'(at) - 1]) ? node[int'(at) - 1].value
                                                                         : above(int'(at));
  // An insert walks only through live nodes, so the capacities keep it off the leaves.
  a_tree_insert_live : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      !held && hwpq_hybrid_tree_pair.u_tree.state == 2'd1
      |-> at != '0 && at <= ADDRESS_WIDTH'(2*PAIRS) && live[int'(at) - 1]);

  // While held after a reset the tree is empty, and no node will be live once gen settles: each
  // is inactive or stamped with another gen, unless the fill has yet to rewrite it. A pending
  // advance from the last gen wraps and starts the fill, which rewrites every node.
  wire [GEN_W-1:0] gen_after = hwpq_hybrid_tree_pair.gen_pending ? gen + 1'b1 : gen;
  logic retired;
  always_comb begin
    retired = 1'b1;
    for (int n = 1; n <= 2*PAIRS; n++)
      retired &= !node[n-1].active || node[n-1].gen != gen_after
                 || (hwpq_hybrid_tree_pair.filling
                     && hwpq_hybrid_tree_pair.tree_reset.fill_cnt <= ADDRESS_WIDTH'(2*((n-1)/2) + 1));
    retired |= hwpq_hybrid_tree_pair.gen_pending && &gen;
  end

  // The tree and its model hold the same multiset, counted value by value, and the same top:
  // a pop's new top is the model's next element only if every value matches, not just tv.
  logic match_all;
  always_comb begin
    match_all = 1'b1;
    for (int v = 1; v < (1 << DATA_WIDTH); v++) begin
      automatic logic [NW-1:0] t = NW'(top_live && top == DATA_WIDTH'(v))
                                   + NW'(carry_live && carry == DATA_WIDTH'(v));
      automatic logic [NW-1:0] m = '0;
      for (int n = 0; n < 2*PAIRS; n++) t += NW'(live[n] && node[n].value == DATA_WIDTH'(v));
      for (int i = 0; i < BRAM_TREE_QUEUE_SIZE; i++)
        m += NW'(hwpq_hybrid_tree_pair.u_contract.m[i] == DATA_WIDTH'(v));
      match_all &= t == m;
    end
  end
  // Model shape, heap order, the walk's position and carry, the top, the hold window and the
  // multiset each need the others to carry over a cycle: proved together.
  a_tree_inv : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      model_ok
      && (held ? hwpq_hybrid_tree_pair.u_contract.cnt == '0 && !top_live && top == '0
                 && hwpq_hybrid_tree_pair.u_tree.state == 2'd0 && retired
               : order_ok
                 && (!sifting || (hole != '0 && hole <= ADDRESS_WIDTH'(2*PAIRS)
                                  && (hole <= 2 || live[int'(hole - 1) / 2 - 1])))
                 && (!carry_live || (legal(carry) && carry <= carry_above))
                 && top_live == (hwpq_hybrid_tree_pair.u_contract.cnt != '0)
                 && (top_live ? legal(top) : top == '0)
                 && match_all && top == hwpq_hybrid_tree_pair.u_contract.m[0]));
  a_tree_top_max : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      !held && top_live |-> top_max);
endmodule

// White-box helper properties for hybrid_systolic_heap over hybrid_tree_standin trees. Bound by
// hybrid_systolic_heap_bind.sv; reads the hybrid, its stand-ins' contract models and the
// spec's counts by hierarchical reference, so it binds only alongside both.
module hwpq_hybrid_aux
  import bram_tree_pkg::*;
(
    input logic i_CLK,
    input logic i_RSTn
);
  localparam int H  = SYSTOLIC_QUEUE_SIZE / 2;
  localparam int TQ = BRAM_TREE_QUEUE_SIZE;
  localparam int NW = $clog2(2 * SYSTOLIC_QUEUE_SIZE + TREE_COUNT * (TQ + 1) + 1) + 1;

  wire [DATA_WIDTH-1:0] tv = hybrid_systolic_heap.u_spec.tv;

  // Per tree: copies in its model, plus a write in flight, less a top already taken by a pull or
  // evict that the tree has yet to pop (a read in flight, or an owed pop).
  logic [NW-1:0] t_tv [TREE_COUNT];
  logic [NW-1:0] t_all[TREE_COUNT];

  for (genvar k = 0; k < TREE_COUNT; k++) begin : g_tree
    always_comb begin
      t_tv[k]  = '0;
      t_all[k] = '0;
      for (int i = 0; i < TQ; i++) begin
        t_tv[k]  += NW'(hybrid_systolic_heap.g_trees[k].heap_inst.u_contract.m[i] == tv);
        t_all[k] += NW'(hybrid_systolic_heap.g_trees[k].heap_inst.u_contract.m[i] != '0);
      end
      if (hybrid_systolic_heap.heap_write[k]) begin
        t_tv[k]  += NW'(hybrid_systolic_heap.heap_input[k] == tv);
        t_all[k] += NW'(hybrid_systolic_heap.heap_input[k] != '0);
      end
      if ((hybrid_systolic_heap.owed[k] || hybrid_systolic_heap.heap_read[k])
          && hybrid_systolic_heap.g_trees[k].heap_inst.u_contract.cnt != '0) begin
        t_tv[k]  -= NW'(hybrid_systolic_heap.g_trees[k].heap_inst.u_contract.m[0] == tv);
        t_all[k] -= NW'(1);
      end
    end

    // A tree owing a pop takes no write until the pop, so its top stays the value already taken.
    a_owed_no_write : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        hybrid_systolic_heap.owed[k] |-> !hybrid_systolic_heap.heap_write[k]);

    // With no top moved since it was registered, the max over tree tops is its tree's exact top:
    // what a pull or evict takes is what the tree pops.
    a_max_is_top : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        hybrid_systolic_heap.max_v_q && !hybrid_systolic_heap.top_moved_any
        && hybrid_systolic_heap.max_idx_q == k && !hybrid_systolic_heap.owed[k]
        |-> hybrid_systolic_heap.max_q == hybrid_systolic_heap.g_trees[k].heap_inst.u_contract.m[0]);

    // The model holds its cnt elements sorted, largest first, and zeros after them.
    logic model_ok;
    always_comb begin
      model_ok = 1'b1;
      for (int i = 0; i < TQ; i++) begin
        model_ok &= (hybrid_systolic_heap.g_trees[k].heap_inst.u_contract.m[i] != '0)
                    == (i < hybrid_systolic_heap.g_trees[k].heap_inst.u_contract.cnt);
        if (i + 1 < TQ)
          model_ok &= hybrid_systolic_heap.g_trees[k].heap_inst.u_contract.m[i]
                      >= hybrid_systolic_heap.g_trees[k].heap_inst.u_contract.m[i + 1];
      end
    end
    a_model_shape : assert property (@(posedge i_CLK) disable iff (!i_RSTn) model_ok);
    // A top taken but not yet popped is still in its tree.
    a_taken_held : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        hybrid_systolic_heap.owed[k] || hybrid_systolic_heap.heap_read[k]
        |-> hybrid_systolic_heap.g_trees[k].heap_inst.u_contract.cnt != '0);
    // Only a tree with more than its top can be busy when taken from, so an owed tree keeps one.
    a_owed_deep : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        hybrid_systolic_heap.owed[k]
        |-> hybrid_systolic_heap.g_trees[k].heap_inst.u_contract.cnt > 1);
    a_model_no_ones : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        hybrid_systolic_heap.g_trees[k].heap_inst.u_contract.m[0] != '1);

    // A pull or evict from a busy tree, settled by a later pop; unreachable when the trees are
    // too small to be busy when taken from, so such a size cannot pass.
    c_owed_pop : cover property (@(posedge i_CLK) disable iff (!i_RSTn)
        hybrid_systolic_heap.owed[k] && hybrid_systolic_heap.heap_read[k]);
  end

  logic past_ok;
  always_ff @(posedge i_CLK or negedge i_RSTn)
    if (!i_RSTn) past_ok <= 1'b0;
    else         past_ok <= 1'b1;

  // Per tree: its count changes by the write that arrives, less the top a pull or evict took
  // last cycle.
  for (genvar k = 0; k < TREE_COUNT; k++) begin : g_tree_conserve
    wire take = (hybrid_systolic_heap.pull_fire || hybrid_systolic_heap.evict_fire)
                && hybrid_systolic_heap.max_node_idx == k;
    wire put  = hybrid_systolic_heap.heap_write[k] && hybrid_systolic_heap.heap_input[k] != '0;
    a_tree_conserve_all : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        past_ok |-> t_all[k] == $past(t_all[k]) + NW'(put) - NW'($past(take)));
    a_tree_conserve_tracked : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        past_ok |-> t_tv[k] == $past(t_tv[k]) + NW'(put && hybrid_systolic_heap.heap_input[k] == tv)
                               - NW'($past(take && hybrid_systolic_heap.max_q == tv)));
  end

  logic [NW-1:0] n_tv, n_all;
  always_comb begin
    n_tv  = '0;
    n_all = '0;
    for (int i = 0; i < H; i++) begin
      n_tv  += NW'(hybrid_systolic_heap.IB[i] == tv) + NW'(hybrid_systolic_heap.OB[i] == tv)
             + NW'(hybrid_systolic_heap.heap_IB[i] == tv) + NW'(hybrid_systolic_heap.heap_OB[i] == tv);
      n_all += NW'(hybrid_systolic_heap.IB[i] != '0) + NW'(hybrid_systolic_heap.OB[i] != '0)
             + NW'(hybrid_systolic_heap.heap_IB[i] != '0) + NW'(hybrid_systolic_heap.heap_OB[i] != '0);
    end
    for (int k = 0; k < TREE_COUNT; k++) begin
      n_tv  += t_tv[k];
      n_all += t_all[k];
    end
  end

  // Per buffer: its copies change by exactly what its commands insert and remove. A write lands
  // on an accepted enqueue or replace; a dequeue or replace on a non-empty buffer removes the head
  // slot, which the readies keep exact; a spill removes the main buffer's tail.
  localparam int BW = $clog2(SYSTOLIC_QUEUE_SIZE + 1) + 1;
  logic [BW-1:0] m_tv, h_tv, m_all, h_all;
  always_comb begin
    m_tv = '0; h_tv = '0; m_all = '0; h_all = '0;
    for (int i = 0; i < H; i++) begin
      m_tv  += BW'(hybrid_systolic_heap.IB[i] == tv) + BW'(hybrid_systolic_heap.OB[i] == tv);
      h_tv  += BW'(hybrid_systolic_heap.heap_IB[i] == tv) + BW'(hybrid_systolic_heap.heap_OB[i] == tv);
      m_all += BW'(hybrid_systolic_heap.IB[i] != '0) + BW'(hybrid_systolic_heap.OB[i] != '0);
      h_all += BW'(hybrid_systolic_heap.heap_IB[i] != '0) + BW'(hybrid_systolic_heap.heap_OB[i] != '0);
    end
  end

  wire m_ins = hybrid_systolic_heap.m_enq_ok
            || (hybrid_systolic_heap.m_wrt && hybrid_systolic_heap.m_read
                && (hybrid_systolic_heap.m_rd_rdy || hybrid_systolic_heap.systolic_empty));
  wire m_pop = hybrid_systolic_heap.m_read && !hybrid_systolic_heap.systolic_empty
            && hybrid_systolic_heap.m_rd_rdy;
  wire h_ins = hybrid_systolic_heap.h_enq_ok
            || (hybrid_systolic_heap.h_wrt && hybrid_systolic_heap.h_read
                && (hybrid_systolic_heap.h_rd_rdy || hybrid_systolic_heap.heap_systolic_empty));
  wire h_pop = hybrid_systolic_heap.h_read && !hybrid_systolic_heap.heap_systolic_empty
            && hybrid_systolic_heap.h_rd_rdy;
  wire spill = hybrid_systolic_heap.spill_fire;
  wire [DATA_WIDTH-1:0] m_tail = hybrid_systolic_heap.IB[H-1];

  logic [BW-1:0] m_tv_n, h_tv_n, m_all_n, h_all_n;
  always_comb begin
    m_tv_n  = m_tv  + BW'(m_ins && hybrid_systolic_heap.m_data == tv)
                    - BW'(m_pop && hybrid_systolic_heap.OB[0] == tv) - BW'(spill && m_tail == tv);
    m_all_n = m_all + BW'(m_ins) - BW'(m_pop) - BW'(spill);
    h_tv_n  = h_tv  + BW'(h_ins && hybrid_systolic_heap.h_data == tv)
                    - BW'(h_pop && hybrid_systolic_heap.heap_OB[0] == tv);
    h_all_n = h_all + BW'(h_ins) - BW'(h_pop);
  end

  a_main_conserve_all : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      past_ok |-> m_all == $past(m_all_n));
  a_main_conserve_tracked : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      past_ok |-> m_tv == $past(m_tv_n));
  a_heap_conserve_all : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      past_ok |-> h_all == $past(h_all_n));
  a_heap_conserve_tracked : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      past_ok |-> h_tv == $past(h_tv_n));

  // A dequeue that empties a buffer leaves no forecast head behind.
  a_main_forecast : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      hybrid_systolic_heap.m_dequeue_pending && hybrid_systolic_heap.systolic_empty
      |-> hybrid_systolic_heap.m_forecast == '0);
  a_heap_forecast : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      hybrid_systolic_heap.h_dequeue_pending && hybrid_systolic_heap.heap_systolic_empty
      |-> hybrid_systolic_heap.h_forecast == '0);

  // A pop in flight on a tree's last element follows a pull or evict that left the top in the
  // heap buffer; an owed pop leaves the tree non-empty.
  for (genvar k = 0; k < TREE_COUNT; k++) begin : g_taken_elsewhere
    a_taken_elsewhere : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        hybrid_systolic_heap.heap_read[k]
        |-> hybrid_systolic_heap.g_trees[k].heap_inst.u_contract.cnt > 1 || h_all != '0);
  end

  // Ordering. A buffer that can be read holds its maximum in OB[0]; a read serves a head that
  // outranks every element anywhere in the queue. A top already taken, with its pop owed or in
  // flight, is not in the tree.
  logic m_ob0_max, h_ob0_max, head_max;
  always_comb begin
    m_ob0_max = 1'b1;
    h_ob0_max = 1'b1;
    head_max  = 1'b1;
    for (int i = 0; i < H; i++) begin
      m_ob0_max &= hybrid_systolic_heap.IB[i] <= hybrid_systolic_heap.OB[0]
                && hybrid_systolic_heap.OB[i] <= hybrid_systolic_heap.OB[0];
      h_ob0_max &= hybrid_systolic_heap.heap_IB[i] <= hybrid_systolic_heap.heap_OB[0]
                && hybrid_systolic_heap.heap_OB[i] <= hybrid_systolic_heap.heap_OB[0];
      head_max  &= hybrid_systolic_heap.IB[i] <= hybrid_systolic_heap.o_data
                && hybrid_systolic_heap.OB[i] <= hybrid_systolic_heap.o_data
                && hybrid_systolic_heap.heap_IB[i] <= hybrid_systolic_heap.o_data
                && hybrid_systolic_heap.heap_OB[i] <= hybrid_systolic_heap.o_data;
    end
    for (int k = 0; k < TREE_COUNT; k++)
      head_max &= !hybrid_systolic_heap.heap_write[k]
               || hybrid_systolic_heap.heap_input[k] <= hybrid_systolic_heap.o_data;
  end
  logic tree_max [TREE_COUNT];
  for (genvar k = 0; k < TREE_COUNT; k++) begin : g_tree_max
    always_comb begin
      tree_max[k] = 1'b1;
      for (int i = 0; i < TQ; i++)
        if (i != 0 || !(hybrid_systolic_heap.owed[k] || hybrid_systolic_heap.heap_read[k]))
          tree_max[k] &= hybrid_systolic_heap.g_trees[k].heap_inst.u_contract.m[i]
                         <= hybrid_systolic_heap.o_data;
    end
  end
  logic trees_max;
  always_comb begin
    trees_max = 1'b1;
    for (int k = 0; k < TREE_COUNT; k++) trees_max &= tree_max[k];
  end

  a_main_head_max : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      hybrid_systolic_heap.m_rd_rdy |-> m_ob0_max);
  a_heap_head_max : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      hybrid_systolic_heap.h_rd_rdy |-> h_ob0_max);
  a_read_head_max_buffers : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      hybrid_systolic_heap.o_read_ready |-> head_max);
  a_read_head_max_trees : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      hybrid_systolic_heap.o_read_ready |-> trees_max);

  // No slot, forecast, model entry or tree write holds the reserved all-ones value.
  logic no_ones;
  always_comb begin
    no_ones = hybrid_systolic_heap.m_forecast != '1 && hybrid_systolic_heap.h_forecast != '1;
    for (int i = 0; i < H; i++)
      no_ones &= hybrid_systolic_heap.IB[i] != '1 && hybrid_systolic_heap.OB[i] != '1
              && hybrid_systolic_heap.heap_IB[i] != '1 && hybrid_systolic_heap.heap_OB[i] != '1;
    for (int k = 0; k < TREE_COUNT; k++)
      no_ones &= !hybrid_systolic_heap.heap_write[k] || hybrid_systolic_heap.heap_input[k] != '1;
  end
  a_no_ones : assert property (@(posedge i_CLK) disable iff (!i_RSTn) no_ones);

  // Every tree index names a tree.
  a_idx_range : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      hybrid_systolic_heap.max_idx_q < TREE_COUNT && hybrid_systolic_heap.spill_tgt < TREE_COUNT
      && hybrid_systolic_heap.evict_tgt < TREE_COUNT);

  // Each transfer moves a real element, and a tree takes at most one write a cycle.
  a_spill_moves : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      hybrid_systolic_heap.spill_fire |-> m_tail != '0);
  a_evict_moves : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      hybrid_systolic_heap.evict_fire |-> hybrid_systolic_heap.h_head != '0);
  for (genvar k = 0; k < TREE_COUNT; k++) begin : g_one_write
    wire w_evict = hybrid_systolic_heap.evict_fire && hybrid_systolic_heap.max_node_idx == k
                   && hybrid_systolic_heap.heap_ready[k];
    wire w_spill = hybrid_systolic_heap.spill_fire && hybrid_systolic_heap.spill_tgt == k;
    wire w_owe   = hybrid_systolic_heap.owe_evict && hybrid_systolic_heap.evict_tgt == k;
    wire w_dw    = hybrid_systolic_heap.dw_fire && hybrid_systolic_heap.evict_tgt == k;
    a_one_write : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        $onehot0({w_evict, w_spill, w_owe, w_dw}));
  end

  // Conservation: every element the spec counts sits in a buffer slot, a tree, or a tree write in
  // flight, exactly once.
  a_conserve_tracked : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      n_tv == NW'(hybrid_systolic_heap.u_spec.cnt));
  a_conserve_all : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      n_all == NW'(hybrid_systolic_heap.u_spec.occ));

  // The counts, the forecasts and the reserved value depend on one another: proved together.
  a_queue_inv : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      n_all == NW'(hybrid_systolic_heap.u_spec.occ) && n_tv == NW'(hybrid_systolic_heap.u_spec.cnt)
      && no_ones
      && !(hybrid_systolic_heap.m_dequeue_pending && hybrid_systolic_heap.systolic_empty
           && hybrid_systolic_heap.m_forecast != '0)
      && !(hybrid_systolic_heap.h_dequeue_pending && hybrid_systolic_heap.heap_systolic_empty
           && hybrid_systolic_heap.h_forecast != '0));
endmodule

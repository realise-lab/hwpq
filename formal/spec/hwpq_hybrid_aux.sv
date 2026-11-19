// White-box helpers for hybrid_systolic_heap over hybrid_tree_standin trees, bound by
// hybrid_systolic_heap_bind.sv. Reads the hybrid, each stand-in's contract model and the spec's
// tracked value and counts by hierarchical reference, so it binds only in that proof.
//
// Terms:
//   main buffer    IB/OB, the systolic buffer whose tail spills into the trees
//   heap buffer    heap_IB/heap_OB, the systolic buffer that takes tree tops
//                  Each buffer is an input half (IB) and an output half (OB); OB[0] is its head.
//   model          a stand-in tree's contents: its contract's sorted m[] and count
//   tracked        the spec's symbolic value tv; counting its copies proves the count for every
//                  value
//   spill          the main buffer's tail moves into a tree (the spill target)
//   pull           the largest tree top moves into the heap buffer
//   evict          the largest tree top swaps with the heap buffer's head
//   owed pop       a pull or evict from a busy tree takes its top at once and pops it once idle
//   owed evict     an evict from a busy tree: the heap head goes to the evict target instead
//   direct write   with both buffers full, a caller's write goes straight to the evict target
//
// Sections follow the helper stages in hybrid_systolic_heap_standin.cfg; each stage is proved
// with the earlier ones assumed.
module hwpq_hybrid_aux
  import bram_tree_pkg::*;
(
    input logic i_CLK,
    input logic i_RSTn
);
  localparam int HALF        = SYSTOLIC_QUEUE_SIZE / 2;  // slots in each buffer half
  localparam int TREE_SIZE   = BRAM_TREE_QUEUE_SIZE;
  localparam int TREE_IDX_W  = $clog2(TREE_COUNT);
  localparam int MODEL_CNT_W = $clog2(TREE_SIZE + 1);
  // Wide enough for every slot of both buffers and every tree, its write in flight included.
  localparam int CNT_W       = $clog2(2*SYSTOLIC_QUEUE_SIZE + TREE_COUNT*(TREE_SIZE + 1) + 1) + 1;
  localparam int BUF_CNT_W   = $clog2(SYSTOLIC_QUEUE_SIZE + 1) + 1;

  // ---- aliases into the hybrid -----------------------------------------------------------------

  wire [DATA_WIDTH-1:0] tracked = hybrid_systolic_heap.u_spec.tv;
  wire [DATA_WIDTH-1:0] head    = hybrid_systolic_heap.o_data;
  wire                  read_ready = hybrid_systolic_heap.o_read_ready;

  logic [DATA_WIDTH-1:0] main_in [HALF], main_out [HALF], heap_buf_in [HALF], heap_buf_out [HALF];
  always_comb
    for (int i = 0; i < HALF; i++) begin
      main_in[i]      = hybrid_systolic_heap.IB[i];
      main_out[i]     = hybrid_systolic_heap.OB[i];
      heap_buf_in[i]  = hybrid_systolic_heap.heap_IB[i];
      heap_buf_out[i] = hybrid_systolic_heap.heap_OB[i];
    end
  wire [DATA_WIDTH-1:0] main_tail = main_in[HALF-1];

  // Each buffer's command, as systolic_array's interface, and its state.
  wire                  main_write      = hybrid_systolic_heap.m_wrt;
  wire                  main_read       = hybrid_systolic_heap.m_read;
  wire [DATA_WIDTH-1:0] main_data       = hybrid_systolic_heap.m_data;
  wire                  main_read_ready = hybrid_systolic_heap.m_rd_rdy;
  wire                  main_enqueue_ok = hybrid_systolic_heap.m_enq_ok;
  wire                  main_empty      = hybrid_systolic_heap.systolic_empty;
  wire                  main_dequeued   = hybrid_systolic_heap.m_dequeue_pending;  // last cycle
  wire [DATA_WIDTH-1:0] main_forecast   = hybrid_systolic_heap.m_forecast;  // head after it
  wire                  heap_buf_write      = hybrid_systolic_heap.h_wrt;
  wire                  heap_buf_read       = hybrid_systolic_heap.h_read;
  wire [DATA_WIDTH-1:0] heap_buf_data       = hybrid_systolic_heap.h_data;
  wire                  heap_buf_read_ready = hybrid_systolic_heap.h_rd_rdy;
  wire                  heap_buf_enqueue_ok = hybrid_systolic_heap.h_enq_ok;
  wire                  heap_buf_empty      = hybrid_systolic_heap.heap_systolic_empty;
  wire                  heap_buf_dequeued   = hybrid_systolic_heap.h_dequeue_pending;
  wire [DATA_WIDTH-1:0] heap_buf_forecast   = hybrid_systolic_heap.h_forecast;
  wire [DATA_WIDTH-1:0] heap_buf_head       = hybrid_systolic_heap.h_head;

  // Tree commands issued this cycle, and the registered choice of the largest tree top.
  wire [TREE_COUNT-1:0]  tree_write = hybrid_systolic_heap.heap_write;
  wire [TREE_COUNT-1:0]  tree_read  = hybrid_systolic_heap.heap_read;
  wire [TREE_COUNT-1:0]  tree_ready = hybrid_systolic_heap.heap_ready;
  wire [TREE_COUNT-1:0]  owed       = hybrid_systolic_heap.owed;
  logic [DATA_WIDTH-1:0] tree_write_data [TREE_COUNT];
  always_comb
    for (int k = 0; k < TREE_COUNT; k++) tree_write_data[k] = hybrid_systolic_heap.heap_input[k];
  wire [DATA_WIDTH-1:0] max_top       = hybrid_systolic_heap.max_q;
  wire [TREE_IDX_W-1:0] max_tree      = hybrid_systolic_heap.max_idx_q;  // = max_node_idx
  wire                  max_valid     = hybrid_systolic_heap.max_v_q;
  wire                  any_top_moved = hybrid_systolic_heap.top_moved_any;

  wire                  pull         = hybrid_systolic_heap.pull_fire;
  wire                  evict        = hybrid_systolic_heap.evict_fire;
  wire                  spill        = hybrid_systolic_heap.spill_fire;
  wire                  owed_evict   = hybrid_systolic_heap.owe_evict;
  wire                  direct_write = hybrid_systolic_heap.dw_fire;
  wire [TREE_IDX_W-1:0] spill_target = hybrid_systolic_heap.spill_tgt;
  wire [TREE_IDX_W-1:0] evict_target = hybrid_systolic_heap.evict_tgt;

  // Each stand-in tree's model.
  logic [DATA_WIDTH-1:0]  model     [TREE_COUNT][TREE_SIZE];
  logic [MODEL_CNT_W-1:0] model_cnt [TREE_COUNT];
  for (genvar k = 0; k < TREE_COUNT; k++) begin : g_model
    always_comb begin
      model_cnt[k] = hybrid_systolic_heap.g_trees[k].heap_inst.u_contract.cnt;
      for (int i = 0; i < TREE_SIZE; i++)
        model[k][i] = hybrid_systolic_heap.g_trees[k].heap_inst.u_contract.m[i];
    end
  end

  // ---- counts ----------------------------------------------------------------------------------

  // Per tree: elements in its model, plus a write in flight, less a top already taken by a pull
  // or evict that the tree has yet to pop (a read in flight, or an owed pop).
  logic [CNT_W-1:0] tree_count [TREE_COUNT], tree_tracked [TREE_COUNT];
  for (genvar k = 0; k < TREE_COUNT; k++) begin : g_tree_count
    always_comb begin
      tree_count[k]   = '0;
      tree_tracked[k] = '0;
      for (int i = 0; i < TREE_SIZE; i++) begin
        tree_count[k]   += CNT_W'(model[k][i] != '0);
        tree_tracked[k] += CNT_W'(model[k][i] == tracked);
      end
      if (tree_write[k]) begin
        tree_count[k]   += CNT_W'(tree_write_data[k] != '0);
        tree_tracked[k] += CNT_W'(tree_write_data[k] == tracked);
      end
      if ((owed[k] || tree_read[k]) && model_cnt[k] != '0) begin
        tree_count[k]   -= CNT_W'(1);
        tree_tracked[k] -= CNT_W'(model[k][0] == tracked);
      end
    end
  end

  // Per buffer: elements in its slots.
  logic [BUF_CNT_W-1:0] main_count, main_tracked, heap_buf_count, heap_buf_tracked;
  always_comb begin
    main_count = '0; main_tracked = '0; heap_buf_count = '0; heap_buf_tracked = '0;
    for (int i = 0; i < HALF; i++) begin
      main_count       += BUF_CNT_W'(main_in[i] != '0) + BUF_CNT_W'(main_out[i] != '0);
      main_tracked     += BUF_CNT_W'(main_in[i] == tracked) + BUF_CNT_W'(main_out[i] == tracked);
      heap_buf_count   += BUF_CNT_W'(heap_buf_in[i] != '0) + BUF_CNT_W'(heap_buf_out[i] != '0);
      heap_buf_tracked += BUF_CNT_W'(heap_buf_in[i] == tracked)
                          + BUF_CNT_W'(heap_buf_out[i] == tracked);
    end
  end

  // Whole queue: both buffers and every tree.
  logic [CNT_W-1:0] queue_count, queue_tracked;
  always_comb begin
    queue_count   = '0;
    queue_tracked = '0;
    for (int i = 0; i < HALF; i++) begin
      queue_count   += CNT_W'(main_in[i] != '0) + CNT_W'(main_out[i] != '0)
                       + CNT_W'(heap_buf_in[i] != '0) + CNT_W'(heap_buf_out[i] != '0);
      queue_tracked += CNT_W'(main_in[i] == tracked) + CNT_W'(main_out[i] == tracked)
                       + CNT_W'(heap_buf_in[i] == tracked) + CNT_W'(heap_buf_out[i] == tracked);
    end
    for (int k = 0; k < TREE_COUNT; k++) begin
      queue_count   += tree_count[k];
      queue_tracked += tree_tracked[k];
    end
  end

  // Low in the first cycle after reset, when $past still reads reset values.
  logic has_past;
  always_ff @(posedge i_CLK or negedge i_RSTn)
    if (!i_RSTn) has_past <= 1'b0;
    else         has_past <= 1'b1;

  // ---- stage 1: per-tree, per-buffer and transfer facts ----------------------------------------

  for (genvar k = 0; k < TREE_COUNT; k++) begin : g_tree_facts
    // The model holds model_cnt elements sorted largest first, then zeros.
    logic model_sorted;
    always_comb begin
      model_sorted = 1'b1;
      for (int i = 0; i < TREE_SIZE; i++) begin
        model_sorted &= (model[k][i] != '0) == (i < model_cnt[k]);
        if (i + 1 < TREE_SIZE) model_sorted &= model[k][i] >= model[k][i + 1];
      end
    end
    // Each model stays sorted.
    a_model_shape : assert property (@(posedge i_CLK) disable iff (!i_RSTn) model_sorted);
    // No tree's top is the reserved all-ones value.
    a_model_no_ones : assert property (@(posedge i_CLK) disable iff (!i_RSTn) model[k][0] != '1);
    // A tree that owes a pop takes no write until the pop, so its top stays the value taken.
    a_owed_no_write : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        owed[k] |-> !tree_write[k]);
    // A top taken but not yet popped is still in its tree.
    a_taken_held : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        owed[k] || tree_read[k] |-> model_cnt[k] != '0);
    // Only a tree with more than its top can be busy when taken from, so an owing tree keeps one.
    a_owed_deep : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        owed[k] |-> model_cnt[k] > 1);
    // With no top moved since it was registered, the registered max is its tree's exact top:
    // what a pull or evict takes is what the tree pops.
    a_max_is_top : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        max_valid && !any_top_moved && max_tree == k && !owed[k] |-> max_top == model[k][0]);
    // A pop in flight on a tree's last element follows a pull or evict that left the top in the
    // heap buffer.
    a_taken_elsewhere : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        tree_read[k] |-> model_cnt[k] > 1 || heap_buf_count != '0);

    // A pull or evict from a busy tree, settled by a later pop; unreachable when the trees are
    // too small to be busy when taken from, so such a size cannot pass.
    c_owed_pop : cover property (@(posedge i_CLK) disable iff (!i_RSTn) owed[k] && tree_read[k]);
  end

  // A buffer's count changes by exactly what its commands insert and remove. A write lands on an
  // accepted enqueue or replace; a dequeue or replace on a non-empty buffer removes the head,
  // which the readies keep exact; a spill removes the main buffer's tail.
  wire main_inserts = main_enqueue_ok
                      || (main_write && main_read && (main_read_ready || main_empty));
  wire main_pops    = main_read && !main_empty && main_read_ready;
  wire heap_buf_inserts = heap_buf_enqueue_ok
                          || (heap_buf_write && heap_buf_read
                              && (heap_buf_read_ready || heap_buf_empty));
  wire heap_buf_pops    = heap_buf_read && !heap_buf_empty && heap_buf_read_ready;

  logic [BUF_CNT_W-1:0] main_count_next, main_tracked_next;
  logic [BUF_CNT_W-1:0] heap_buf_count_next, heap_buf_tracked_next;
  always_comb begin
    main_count_next       = main_count + BUF_CNT_W'(main_inserts) - BUF_CNT_W'(main_pops)
                            - BUF_CNT_W'(spill);
    main_tracked_next     = main_tracked + BUF_CNT_W'(main_inserts && main_data == tracked)
                            - BUF_CNT_W'(main_pops && main_out[0] == tracked)
                            - BUF_CNT_W'(spill && main_tail == tracked);
    heap_buf_count_next   = heap_buf_count + BUF_CNT_W'(heap_buf_inserts)
                            - BUF_CNT_W'(heap_buf_pops);
    heap_buf_tracked_next = heap_buf_tracked
                            + BUF_CNT_W'(heap_buf_inserts && heap_buf_data == tracked)
                            - BUF_CNT_W'(heap_buf_pops && heap_buf_out[0] == tracked);
  end

  // Each buffer's element count and tracked count follow its commands.
  a_main_conserve_all : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      has_past |-> main_count == $past(main_count_next));
  a_main_conserve_tracked : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      has_past |-> main_tracked == $past(main_tracked_next));
  a_heap_conserve_all : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      has_past |-> heap_buf_count == $past(heap_buf_count_next));
  a_heap_conserve_tracked : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      has_past |-> heap_buf_tracked == $past(heap_buf_tracked_next));

  // A readable buffer holds its maximum at its head, OB[0]; a readable queue's head outranks
  // every buffer slot and every tree write in flight.
  logic main_head_is_max, heap_buf_head_is_max, head_beats_buffers;
  always_comb begin
    main_head_is_max     = 1'b1;
    heap_buf_head_is_max = 1'b1;
    head_beats_buffers   = 1'b1;
    for (int i = 0; i < HALF; i++) begin
      main_head_is_max     &= main_in[i] <= main_out[0] && main_out[i] <= main_out[0];
      heap_buf_head_is_max &= heap_buf_in[i] <= heap_buf_out[0]
                              && heap_buf_out[i] <= heap_buf_out[0];
      head_beats_buffers   &= main_in[i] <= head && main_out[i] <= head
                              && heap_buf_in[i] <= head && heap_buf_out[i] <= head;
    end
    for (int k = 0; k < TREE_COUNT; k++)
      head_beats_buffers &= !tree_write[k] || tree_write_data[k] <= head;
  end
  // The main buffer's head is its maximum whenever it can be read.
  a_main_head_max : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      main_read_ready |-> main_head_is_max);
  // The heap buffer's head is its maximum whenever it can be read.
  a_heap_head_max : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      heap_buf_read_ready |-> heap_buf_head_is_max);
  // A readable queue's head outranks both buffers and every tree write in flight.
  a_read_head_max_buffers : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      read_ready |-> head_beats_buffers);

  // Every tree index names a tree.
  a_idx_range : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      max_tree < TREE_COUNT && spill_target < TREE_COUNT && evict_target < TREE_COUNT);
  // A spill moves a real element out of the main buffer.
  a_spill_moves : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      spill |-> main_tail != '0);
  // An evict moves a real element out of the heap buffer.
  a_evict_moves : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      evict |-> heap_buf_head != '0);
  for (genvar k = 0; k < TREE_COUNT; k++) begin : g_one_write
    wire write_by_evict  = evict && max_tree == k && tree_ready[k];
    wire write_by_spill  = spill && spill_target == k;
    wire write_by_owed   = owed_evict && evict_target == k;
    wire write_by_direct = direct_write && evict_target == k;
    // A tree is sent at most one write per cycle.
    a_one_write : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        $onehot0({write_by_evict, write_by_spill, write_by_owed, write_by_direct}));
  end

  // ---- stage 2: per-tree conservation ----------------------------------------------------------

  for (genvar k = 0; k < TREE_COUNT; k++) begin : g_tree_conserve
    wire taken   = (pull || evict) && max_tree == k;  // its top, popped next cycle or owed
    wire written = tree_write[k] && tree_write_data[k] != '0;
    // A tree's count changes by the write arriving, less the top taken last cycle.
    a_tree_conserve_all : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        has_past |-> tree_count[k] == $past(tree_count[k]) + CNT_W'(written)
                                      - CNT_W'($past(taken)));
    // A tree's tracked count changes by a write of tracked, less a taken top equal to tracked.
    a_tree_conserve_tracked : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
        has_past |-> tree_tracked[k] == $past(tree_tracked[k])
                                        + CNT_W'(written && tree_write_data[k] == tracked)
                                        - CNT_W'($past(taken && max_top == tracked)));
  end

  // ---- stage 3: the inductive invariant --------------------------------------------------------

  // No buffer slot, forecast or tree write in flight holds the reserved all-ones value.
  logic no_all_ones;
  always_comb begin
    no_all_ones = main_forecast != '1 && heap_buf_forecast != '1;
    for (int i = 0; i < HALF; i++)
      no_all_ones &= main_in[i] != '1 && main_out[i] != '1
                     && heap_buf_in[i] != '1 && heap_buf_out[i] != '1;
    for (int k = 0; k < TREE_COUNT; k++)
      no_all_ones &= !tree_write[k] || tree_write_data[k] != '1;
  end
  // A dequeue that empties a buffer leaves no forecast head behind.
  wire main_forecast_clear     = !(main_dequeued && main_empty) || main_forecast == '0;
  wire heap_buf_forecast_clear = !(heap_buf_dequeued && heap_buf_empty) || heap_buf_forecast == '0;

  // The counts, the forecasts and the reserved value depend on one another across a cycle, so
  // they are one property; stage 4 restates each part.
  a_queue_inv : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      queue_count == CNT_W'(hybrid_systolic_heap.u_spec.occ)
      && queue_tracked == CNT_W'(hybrid_systolic_heap.u_spec.cnt)
      && no_all_ones && main_forecast_clear && heap_buf_forecast_clear);

  // ---- stage 4: the parts of the invariant -----------------------------------------------------

  // No all-ones anywhere in the queue.
  a_no_ones : assert property (@(posedge i_CLK) disable iff (!i_RSTn) no_all_ones);
  // A dequeue that empties the main buffer leaves no forecast.
  a_main_forecast : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      main_dequeued && main_empty |-> main_forecast == '0);
  // A dequeue that empties the heap buffer leaves no forecast.
  a_heap_forecast : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      heap_buf_dequeued && heap_buf_empty |-> heap_buf_forecast == '0);
  // Every element the spec counts sits in a buffer slot, a tree or a tree write, exactly once.
  a_conserve_all : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      queue_count == CNT_W'(hybrid_systolic_heap.u_spec.occ));
  // Every copy of tracked the spec counts sits in a buffer slot, a tree or a tree write.
  a_conserve_tracked : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      queue_tracked == CNT_W'(hybrid_systolic_heap.u_spec.cnt));

  // ---- stage 5: ordering against the trees -----------------------------------------------------

  // A readable queue's head outranks every tree element, except a top already taken (owed or
  // popping), which is no longer in the tree.
  logic head_beats_tree [TREE_COUNT];
  for (genvar k = 0; k < TREE_COUNT; k++) begin : g_head_beats_tree
    always_comb begin
      head_beats_tree[k] = 1'b1;
      for (int i = 0; i < TREE_SIZE; i++)
        if (i != 0 || !(owed[k] || tree_read[k]))
          head_beats_tree[k] &= model[k][i] <= head;
    end
  end
  logic head_beats_trees;
  always_comb begin
    head_beats_trees = 1'b1;
    for (int k = 0; k < TREE_COUNT; k++) head_beats_trees &= head_beats_tree[k];
  end
  // A readable queue's head outranks every element left in every tree.
  a_read_head_max_trees : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      read_ready |-> head_beats_trees);
endmodule

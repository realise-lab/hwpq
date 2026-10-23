`default_nettype none
import bram_tree_pkg::*;

// Max-priority queue: larger value = higher priority. A node is just its value; 0 means "empty".

function automatic logic [DATA_WIDTH-1:0] max2(input logic [DATA_WIDTH-1:0] a, input logic [DATA_WIDTH-1:0] b);
  return (a >= b) ? a : b;
endfunction

function automatic logic [DATA_WIDTH-1:0] max4(
  input logic [DATA_WIDTH-1:0] a, input logic [DATA_WIDTH-1:0] b,
  input logic [DATA_WIDTH-1:0] c, input logic [DATA_WIDTH-1:0] d
);
  logic [DATA_WIDTH-1:0] max_ab, max_cd;
  max_ab = max2(a, b);
  max_cd = max2(c, d);
  return max2(max_ab, max_cd);
endfunction

function automatic logic [DATA_WIDTH-1:0] max6(
  input logic [DATA_WIDTH-1:0] a, input logic [DATA_WIDTH-1:0] b, input logic [DATA_WIDTH-1:0] c,
  input logic [DATA_WIDTH-1:0] d, input logic [DATA_WIDTH-1:0] e, input logic [DATA_WIDTH-1:0] f
);
  logic [DATA_WIDTH-1:0] max_abcd, max_ef;
  max_abcd = max4(a, b, c, d);
  max_ef   = max2(e, f);
  return max2(max_abcd, max_ef);
endfunction

module hybrid_systolic_heap (
  input var logic                   i_CLK,
  input var logic                   i_RSTn,

  // Input
  input var logic                   i_wrt,   // Enqueue signal
  input var logic                   i_read,  // Dequeue signal
  input var logic [DATA_WIDTH-1:0]  i_data,  // Node value input

  // Output
  output var logic                  o_write_ready, // High if systolic is full
  output var logic                  o_read_ready,
  output var logic [DATA_WIDTH-1:0] o_data        // Node value output
);
  // Constant
  localparam int HALF_SIZE = SYSTOLIC_QUEUE_SIZE / 2;
  parameter BRAM_TREE_ADDR_WIDTH = $clog2(TREE_COUNT);

  // Heap signals
  logic [TREE_COUNT-1:0]        heap_write;
  logic [TREE_COUNT-1:0]        heap_read;
  logic [TREE_COUNT-1:0]        heap_empty; 
  logic [TREE_COUNT-1:0]        heap_full;
  logic [DATA_WIDTH-1:0]        heap_input  [TREE_COUNT-1:0];
  logic [DATA_WIDTH-1:0]        heap_output [TREE_COUNT-1:0];
  logic [TREE_COUNT-1:0]        heap_ready;
  logic [TREE_COUNT-1:0]        heap_top_moved;

  // The spill target is chosen a cycle ahead, so the choice stays off the readiness paths:
  // the first ready, non-full tree after the last target, else the first non-full one, which
  // the spill then waits on. A tree that only frees up in between costs a cycle.
  logic [BRAM_TREE_ADDR_WIDTH-1:0]        spill_tgt, spill_tgt_next;
  logic                                   spill_found_rdy;

  logic [GEN_W-1:0]         tree_gen;
  logic                     tree_gen_pending, tree_filling;
  logic [ADDRESS_WIDTH-1:0] tree_fill_addr, tree_fill_cap;

  bram_tree_reset tree_reset (
    .i_CLK(i_CLK), .i_RSTn(i_RSTn),
    .o_gen(tree_gen), .o_gen_pending(tree_gen_pending),
    .o_filling(tree_filling), .o_fill_addr(tree_fill_addr), .o_fill_cap(tree_fill_cap)
  );

  generate
    for (genvar k=0; k<TREE_COUNT; k++) begin : g_trees
      bram_tree heap_inst (
        .i_CLK(i_CLK),
        .i_RSTn(i_RSTn),
        .i_wrt(heap_write[k]),
        .i_read(heap_read[k]),
        .i_data(heap_input[k]),
        .i_gen(tree_gen),
        .i_gen_pending(tree_gen_pending),
        .i_filling(tree_filling),
        .i_fill_addr(tree_fill_addr),
        .i_fill_cap(tree_fill_cap),
        .o_full(heap_full[k]),
        .o_empty(heap_empty[k]),
        .o_data(heap_output[k]),
        .o_ready(heap_ready[k]),
        .o_top_moved(heap_top_moved[k])
      );
    end
  endgenerate

  // Input Buffer (IB) and Output Buffer (OB)
  logic [DATA_WIDTH-1:0]   IB                  [HALF_SIZE];
  logic [DATA_WIDTH-1:0]   OB                  [HALF_SIZE];

  // Registers to store comparison results ("gt" = strictly higher priority = strictly larger)
  logic                    IB_gt_OB            [HALF_SIZE];
  logic                    IB_gt_IB_next       [HALF_SIZE-1];
  logic                    IB_gt_OB_next       [HALF_SIZE-1];
  logic                    OB_next_gt_OB       [HALF_SIZE-1];

  logic                    IB_shift            [HALF_SIZE-1];
  logic                    IB_shift_valid      [HALF_SIZE-1];

  logic                    OB_shift            [HALF_SIZE-1];
  logic                    OB_shift_valid      [HALF_SIZE-1];

  logic                    IB_shift_to_OB      [HALF_SIZE-1];

  logic                    spill_to_heap;
  logic                    spill_to_heap_valid;

  // Systolic control signals
  int                      systolic_size;
  logic                    systolic_full;
  logic                    systolic_empty;

  // Heap buffers & control logic for secondary systolic
  logic [DATA_WIDTH-1:0]   heap_IB                  [HALF_SIZE];
  logic [DATA_WIDTH-1:0]   heap_OB                  [HALF_SIZE];

  logic                    heap_IB_gt_OB            [HALF_SIZE];
  logic                    heap_IB_gt_IB_next       [HALF_SIZE-1];
  logic                    heap_IB_gt_OB_next       [HALF_SIZE-1];
  logic                    heap_OB_next_gt_OB       [HALF_SIZE-1];

  logic                    heap_IB_shift            [HALF_SIZE-1];
  logic                    heap_IB_shift_valid      [HALF_SIZE-1];

  logic                    heap_OB_shift            [HALF_SIZE-1];
  logic                    heap_OB_shift_valid      [HALF_SIZE-1];

  logic                    heap_IB_shift_to_OB      [HALF_SIZE-1];


  int                      heap_systolic_size;
  logic                    heap_systolic_full;
  logic                    heap_systolic_empty;

  logic                    output_from_heap_systolic;

  logic [DATA_WIDTH-1:0]           max_node;
  logic [BRAM_TREE_ADDR_WIDTH-1:0] max_node_idx;
  logic [DATA_WIDTH-1:0] o_max_value;

  localparam int SV_W = HALF_SIZE - 1;   // width of the *_shift_valid vectors (needs HALF_SIZE >= 3, same as your original loop)
  // Solves x[i] = g[i] | (p[i] & x[i+1]),  with p[SV_W-1] == 0 and x[SV_W-1] == g[SV_W-1]

  localparam int TOT  = 2*HALF_SIZE;              // must equal SYSTOLIC_QUEUE_SIZE
  localparam int TOTP = 1 << $clog2(TOT);

  logic [HALF_SIZE-1:0] ib_e, ob_e, hib_e, hob_e; // slot is empty (value == 0)
  logic [1:0]           m_empt, h_empt;           // #empty slots, saturating at 3
  logic                 h_last_write;             // the heap buffer takes exactly one more write
  logic                 pull_reserved;
  logic                 m_all_empty, h_all_empty;

  function automatic logic [1:0] empties_sat(input logic [TOT-1:0] e);
    logic [1:0] lvl [TOTP];
    logic [2:0] s;
    for (int i = 0; i < TOTP; i++) begin
      if (i < TOT) lvl[i] = {1'b0, e[i]};
      else         lvl[i] = 2'd0;
    end
    for (int n = TOTP; n > 1; n = n >> 1) begin
      for (int i = 0; i < n/2; i++) begin
        s      = {1'b0, lvl[2*i]} + {1'b0, lvl[2*i+1]};
        lvl[i] = (s > 3'd3) ? 2'd3 : s[1:0];
      end
    end
    return lvl[0];
  endfunction

  function automatic logic more_than_3(input logic [TOT-1:0] e);
    logic [2:0] lvl [TOTP];
    logic [3:0] s;
    for (int i = 0; i < TOTP; i++) lvl[i] = (i < TOT) ? {2'b0, e[i]} : 3'd0;
    for (int n = TOTP; n > 1; n = n >> 1) begin
      for (int i = 0; i < n/2; i++) begin
        s      = {1'b0, lvl[2*i]} + {1'b0, lvl[2*i+1]};
        lvl[i] = (s > 4'd4) ? 3'd4 : s[2:0];
      end
    end
    return lvl[0] == 3'd4;
  endfunction

  function automatic logic [SV_W-1:0] scan_bwd(input logic [SV_W-1:0] g,
                                               input logic [SV_W-1:0] p);
    logic [SV_W-1:0] G, P, Gn, Pn;
    G = g; P = p;
    for (int d = 1; d < SV_W; d = d << 1) begin
      for (int i = 0; i < SV_W; i++) begin
        if (i + d < SV_W) begin
          Gn[i] = G[i] | (P[i] & G[i+d]);
          Pn[i] = P[i] & P[i+d];
        end else begin
          Gn[i] = G[i];
          Pn[i] = P[i];
        end
      end
      G = Gn; P = Pn;
    end
    return G;
  endfunction

  // Solves x[i] = g[i] | (p[i] & x[i-1]),  with p[0] == 0 and x[0] == g[0]
  function automatic logic [SV_W-1:0] scan_fwd(input logic [SV_W-1:0] g,
                                               input logic [SV_W-1:0] p);
    logic [SV_W-1:0] G, P, Gn, Pn;
    G = g; P = p;
    for (int d = 1; d < SV_W; d = d << 1) begin
      for (int i = 0; i < SV_W; i++) begin
        if (i - d >= 0) begin
          Gn[i] = G[i] | (P[i] & G[i-d]);
          Pn[i] = P[i] & P[i-d];
        end else begin
          Gn[i] = G[i];
          Pn[i] = P[i];
        end
      end
      G = Gn; P = Pn;
    end
    return G;
  endfunction

  // scratch vectors
  logic [SV_W-1:0] ob_g,  ob_p,  ob_v;
  logic [SV_W-1:0] hob_g, hob_p, hob_v;
  logic [SV_W-1:0] ib_g,  ib_p,  ib_v;
  logic [SV_W-1:0] hib_g, hib_p, hib_v;
  logic            ib_b, hib_b;
  
  localparam int TC_P2 = 1 << BRAM_TREE_ADDR_WIDTH;

  logic [DATA_WIDTH-1:0] rd_sel;

  // max tree (heap-style indexing: node n has children 2n (lower idx) and 2n+1)
  logic [DATA_WIDTH-1:0]                t_val [2*TC_P2];
  logic                                 t_v   [2*TC_P2];
  logic [BRAM_TREE_ADDR_WIDTH-1:0]      t_i   [2*TC_P2];
  logic                                 t_rw;
  logic                                 max_valid;
  logic                                 max_rdy;

  // The max over tree tops is registered from last cycle's values, ignoring readiness. It is
  // exact unless a tree's top moved since (o_top_moved), which holds reads. Pulls and
  // evictions also wait while the max tree is busy (tree_hold), since they command it.
  logic [DATA_WIDTH-1:0]                max_q;
  logic [BRAM_TREE_ADDR_WIDTH-1:0]      max_idx_q;
  logic                                 max_v_q;
  logic                                 tree_hold, top_moved_any;
  // A command moves a tree's top for one cycle, and reads ignore it: max_q still holds the old
  // top, which bounds what a pull or evict leaves, and an insert adds only a spilled value, which
  // never outranks a head the hybrid serves. Aligned with the tree's o_top_moved.
  logic [TREE_COUNT-1:0]                cmd_moved;
  logic                                 top_moved_rd;
  // A pull from a max tree busy with a walk takes its exact top at once and owes the tree a
  // pop, issued once it is idle with the output discarded. The tree's top stays the value taken
  // until the pop, so its slot bounds it. While a pop is owed no other pull or evict fires and
  // no spill targets the tree; its full flag lags by the owed element, which only delays spills.
  logic [TREE_COUNT-1:0]                owed, pop_fire;
  logic                                 owe_ok;

  logic spill_fire, spill_hits_max;
  logic pull_fire, evict_fire, pull_ok, evict_ok;

  // Command-dependent control for each value of o_read_ready, indexed by it.
  logic [1:0]              c_user_heap, c_m_wrt, c_m_read, c_pull, c_evict, c_h_wrt, c_h_read;
  logic [1:0]              c_h_user, c_h_gt_ob1, c_m_enq_ok, c_m_enq_fwd, c_m_wr_ib0;
  logic [1:0]              c_h_enq_ok, c_h_enq_fwd, c_h_wr_ib0;
  logic [SV_W-1:0]         c_ib_v [2];
  logic [SV_W-1:0]         c_hib_v [2];

  logic [DATA_WIDTH-1:0] heap_rep_data;     // no reset, data only
  logic [DATA_WIDTH-1:0] heap_spill_data;   // no reset, data only
  logic [TREE_COUNT-1:0] heap_data_sel;     // 1 = replace data, 0 = spill data (registered with heap_write)

  // Per-buffer command, readies and head (systolic_array's i_wrt/i_read/i_data,
  // o_write_ready/o_read_ready/o_data).
  logic                    m_wrt, m_read, h_wrt, h_read;
  logic [DATA_WIDTH-1:0]   m_data, h_data;
  logic                    m_wr_rdy, m_rd_rdy, h_wr_rdy, h_rd_rdy;
  logic [DATA_WIDTH-1:0]   m_head, h_head;
  logic                    m_dequeue_pending, h_dequeue_pending;
  logic [DATA_WIDTH-1:0]   m_forecast, h_forecast;
  logic                    m_ib0_to_ob1, h_ib0_to_ob1;
  logic                    m_ib0_free, h_ib0_free;
  logic                    m_enq_ok, h_enq_ok, m_enq_fwd, h_enq_fwd;
  logic                    m_writing_ib0, h_writing_ib0;
  logic                    IB_room             [HALF_SIZE-1];
  logic                    heap_IB_room        [HALF_SIZE-1];
  logic [SV_W-1:0]         room_g, room_p, room_v, hroom_g, hroom_p, hroom_v;
  logic                    user_heap, user_heap_enq;

  // Comparisons are made against each register source and the 1-bit results selected, so no
  // wide mux sits in front of a wide compare on the command path.
  logic                    h_from_user;
  logic                    h_gt_ob0, h_gt_ob1, h_gt_ib0, h_gt_ib1, h_lt_ob0;
  logic                    h_ge_max, m_ge_max, rd_ge_max, max_gt_h_head;
  logic                    hybrid_empty, rep_empty;

  generate
    for (genvar k = 0; k < TREE_COUNT; k++) begin : g_heap_in
      assign heap_input[k] = heap_data_sel[k] ? heap_rep_data : heap_spill_data;
    end
  endgenerate

  // A tree head moves into the heap buffer when it has room (pull), or swaps with the
  // heap buffer's head when that buffer is full and the tree head outranks it (evict:
  // a replace on each side). Without the swap a full heap buffer can hide the maximum.
  assign pull_ok  = max_valid && (max_rdy || owe_ok) && !spill_hits_max && h_wr_rdy
                    && !pull_reserved;
  assign evict_ok = max_valid && max_rdy && !spill_hits_max
                    && (heap_systolic_full || pull_reserved) && h_rd_rdy && max_gt_h_head;

  // Room in either buffer takes a write, so one is accepted in the cycle after any read.
  assign o_write_ready = m_wr_rdy || h_wr_rdy;
  // The head is the larger buffer head, once both buffers and the trees can be compared.
  assign o_read_ready  = (output_from_heap_systolic ? h_rd_rdy : m_rd_rdy)
                         && (systolic_empty || m_rd_rdy) && (heap_systolic_empty || h_rd_rdy)
                         && rd_ge_max;

  logic [5:0][DATA_WIDTH-1:0] head_v;
  always_comb begin
    head_v  = {heap_OB[1], heap_IB[0], IB[0], OB[1], OB[0], heap_OB[0]};
    o_max_value = bram_tree_pkg::oh6_select(head_v, bram_tree_pkg::argmax6_oh(head_v));
  end

  always_ff @(posedge i_CLK) begin
    heap_rep_data   <= h_head;
    heap_spill_data <= IB[HALF_SIZE-1];
  end

  // Resets to "no tree holds a value"; every o_top_moved resets high, which holds the first cycle.
  always_ff @(posedge i_CLK or negedge i_RSTn) begin
    if (!i_RSTn) begin
      max_q     <= EMPTY_VAL;
      max_idx_q <= '0;
      max_v_q   <= 1'b0;
    end else begin
      max_q     <= t_v[1] ? t_val[1] : EMPTY_VAL;
      max_idx_q <= t_v[1] ? t_i[1] : '0;
      max_v_q   <= t_v[1];
    end
  end

  // Sequential logic
  always_ff @(posedge i_CLK or negedge i_RSTn) begin
    if (!i_RSTn) begin  // Reset
      heap_write  <= 0;
      heap_read   <= 0;
      cmd_moved   <= 0;
      owed        <= 0;
      spill_tgt <= 0;
      m_dequeue_pending <= 1'b0;
      h_dequeue_pending <= 1'b0;
      m_forecast <= EMPTY_VAL;
      h_forecast <= EMPTY_VAL;
      for (int i = 0; i < HALF_SIZE; i++) begin
        IB[i] <= EMPTY_VAL;  // initialize to the sentinel (0, lowest priority), since this is a max-queue
        OB[i] <= EMPTY_VAL;
        heap_IB[i] <= EMPTY_VAL;
        heap_OB[i] <= EMPTY_VAL;
      end
    end else begin
      for (int k = 0; k < TREE_COUNT; k++) begin
        heap_write[k]    <= (evict_fire && (k == max_node_idx)) || (spill_fire && (k == spill_tgt));
        heap_data_sel[k] <= evict_fire && (k == max_node_idx);
        heap_read[k]     <= ((pull_fire && heap_ready[k]) || evict_fire) && (k == max_node_idx)
                            || pop_fire[k];
        owed[k]          <= (pull_fire && !heap_ready[k] && (k == max_node_idx))
                            || (owed[k] && !pop_fire[k]);
        cmd_moved[k]     <= heap_write[k] || heap_read[k];
      end

      spill_tgt <= spill_tgt_next;

      // Main buffer: systolic_array's sorting network, driven by m_wrt/m_read/m_data.
      if (m_read && !m_wrt && !systolic_empty && m_rd_rdy) begin
        OB[0] <= EMPTY_VAL;
      end

      if (m_enq_ok) begin
        if (OB_shift[0] && OB_shift_valid[0]) begin
          if (m_data > OB[1]) begin
            OB[0] <= m_data;
          end else begin
            IB[0] <= m_data;
          end
        end else begin
          if (m_data > OB[0]) begin
            OB[0] <= m_data;
            IB[0] <= OB[0];
          end else begin
            IB[0] <= m_data;
          end
        end
      end

      if (m_wrt && m_read && (m_rd_rdy || systolic_empty)) begin
        if (systolic_empty) begin
          OB[0] <= m_data;
        end else begin
          if ((m_data > OB[1]) && (m_data > IB[1]) && (m_data > IB[0])) begin
            OB[0] <= m_data;
          end else begin
            IB[0] <= m_data;
            OB[0] <= EMPTY_VAL;
          end
        end
      end

      m_dequeue_pending <= m_read && m_rd_rdy;
      m_forecast        <= (IB[0] < OB[1]) ? OB[1] : IB[0];

      // The tail leaves for a tree; a shift or move into it later in this block wins.
      if (spill_fire) IB[HALF_SIZE-1] <= EMPTY_VAL;

      if (m_ib0_to_ob1 && (OB_shift_valid[0] && OB_shift[0]) && !m_enq_fwd) begin
        OB[1] <= IB[0];
        if (!m_writing_ib0 || (m_writing_ib0 && m_read && (m_data > OB[1]) && !IB_gt_OB_next[0]) || (m_writing_ib0 && !systolic_full && m_wr_rdy && OB_shift[0] && OB_shift_valid[0] && (m_data > OB[1]))) begin
          IB[0] <= EMPTY_VAL;
        end
      end

      for (int i = 0; i < HALF_SIZE; i++) begin
        priority case (1'b1)
          (i < HALF_SIZE-1) && OB_shift[i] && OB_shift_valid[i]
          && !(i > 0 && m_ib0_to_ob1 && (OB_shift_valid[0] && OB_shift[0]) && !m_enq_fwd)
          && !m_enq_fwd: begin
            OB[i] <= OB[i+1];
            if (!(i == 0 && m_ib0_to_ob1 && (OB_shift_valid[0] && OB_shift[0])) && (i == (HALF_SIZE - 2) || !OB_shift_valid[i+1] || !IB_shift_to_OB[i+1] || !OB_shift[i+1] || (OB[i+2] == 0))) OB[i+1] <= EMPTY_VAL;
          end
          default: begin
          end
        endcase

        priority case (1'b1)
          (i < HALF_SIZE-1) && IB_shift[i] && IB_shift_valid[i] &&
          !(m_ib0_to_ob1 && (OB_shift_valid[0] && OB_shift[0])) &&
          !(!m_dequeue_pending && OB_shift[i] && OB_shift_valid[i] && (i < HALF_SIZE - 2) && m_enq_ok && IB_gt_OB_next[i+1])
          : begin
            IB[i+1] <= IB[i];
            if (((i == 0 && !m_writing_ib0)
            || (i > 0 && (!IB_shift_valid[i-1] || (IB_shift_to_OB[i-1] && !m_enq_fwd)))
            || (i == 0 && m_writing_ib0 && m_read && (m_data > OB[1]) && !IB_gt_OB_next[0])
            || (i > 0 && !IB_shift[i-1] && !IB_gt_OB_next[i-1])
            || (i == 0 && m_writing_ib0 && !systolic_full && m_wr_rdy && OB_shift[0] && OB_shift_valid[0] && (m_data > OB[1])))
            && !(i>0 && m_ib0_to_ob1 && (OB_shift_valid[0] && OB_shift[0]) && IB_gt_OB_next[i-1]))
            IB[i] <= EMPTY_VAL;
          end
          default: begin
          end
        endcase

        priority case (1'b1)
          (i < HALF_SIZE-1) && OB_next_gt_OB[i] && !OB_shift_valid[i] && !IB_gt_OB[i]
          && (i > 0 && !IB_gt_OB_next[i-1]): begin
            OB[i+1] <= OB[i];
            OB[i] <= OB[i+1];
          end

          (i < HALF_SIZE-1) && IB_shift_to_OB[i]
          && !(m_ib0_to_ob1 && (OB_shift_valid[0] && OB_shift[0]))
          && !m_enq_fwd: begin
            OB[i] <= IB[i];
            if (i > 0 && !(IB_shift[i-1] && IB_shift_valid[i-1])) IB[i] <= EMPTY_VAL;
          end

          IB_gt_OB[i] && !(i < (HALF_SIZE-1) && OB_shift[i] && OB_shift_valid[i]): begin
            if (!(m_enq_ok && (m_data < OB[0]) && (i == 0))) IB[i] <= OB[i];
            OB[i] <= IB[i];
          end

          (i < HALF_SIZE-1) && IB_gt_OB_next[i] && (!IB_gt_OB[i+1])
          && ((IB[i+1] == 0) || (i+1 < HALF_SIZE-1 && IB_gt_OB_next[i+1])
          || (i+1 < HALF_SIZE-1 && IB_shift[i+1]) || (i+1 == HALF_SIZE-1 && spill_fire))
          && (IB_shift_valid[i] || (i+1 < HALF_SIZE-1 && IB_shift_valid[i+1]))
          && !(m_ib0_to_ob1 && (OB_shift_valid[0] && OB_shift[0])): begin
            OB[i+1] <= IB[i];
            IB[i+1] <= OB[i+1];
            if (i == 0 && m_writing_ib0) begin
              if (m_data > OB[0] && !m_read) begin
                IB[i] <= OB[0];
              end else begin
                IB[i] <= m_data;
              end
            end
            if ((i > 0 && (IB_shift_to_OB[i-1] && !m_enq_fwd
            || (IB_gt_OB[i-1] && (i-1 != 0)))) || (i == 0 && !m_writing_ib0)) begin
              IB[i] <= EMPTY_VAL;
            end
            if (i == 0 && m_wrt && m_read && m_rd_rdy && (m_data > OB[1]) && (m_data > IB[1]) && (m_data > IB[0])) begin
              IB[i] <= EMPTY_VAL;
            end
            if ((i > 0) && (IB_shift[i-1] && IB_shift_valid[i-1] && (IB[i-1] == EMPTY_VAL) && !(IB_gt_OB[i-1]) && !(IB_gt_OB_next[i-1]))) begin
              IB[i] <= EMPTY_VAL;
            end
          end

          (i < HALF_SIZE-1) && IB_gt_OB_next[i] && !IB_shift_valid[i] && !IB_gt_OB[i+1]: begin
            IB[i] <= OB[i+1];
            OB[i+1] <= IB[i];
          end

          (i < HALF_SIZE-1) && IB_gt_IB_next[i] && !IB_shift_valid[i]
          && ((i == (HALF_SIZE - 2)) || (!IB_gt_IB_next[i+1] && !IB_gt_OB_next[i+1]))
          && (!IB_gt_OB[i+1]): begin
            IB[i] <= IB[i+1];
            IB[i+1] <= IB[i];
          end

          default: begin
          end
        endcase
      end

      // Heap buffer: systolic_array's sorting network, driven by h_wrt/h_read/h_data.
      if (h_read && !h_wrt && !heap_systolic_empty && h_rd_rdy) begin
        heap_OB[0] <= EMPTY_VAL;
      end

      if (h_enq_ok) begin
        if (heap_OB_shift[0] && heap_OB_shift_valid[0]) begin
          if (h_gt_ob1) begin
            heap_OB[0] <= h_data;
          end else begin
            heap_IB[0] <= h_data;
          end
        end else begin
          if (h_gt_ob0) begin
            heap_OB[0] <= h_data;
            heap_IB[0] <= heap_OB[0];
          end else begin
            heap_IB[0] <= h_data;
          end
        end
      end

      if (h_wrt && h_read && (h_rd_rdy || heap_systolic_empty)) begin
        if (heap_systolic_empty) begin
          heap_OB[0] <= h_data;
        end else begin
          if (h_gt_ob1 && h_gt_ib1 && h_gt_ib0) begin
            heap_OB[0] <= h_data;
          end else begin
            heap_IB[0] <= h_data;
            heap_OB[0] <= EMPTY_VAL;
          end
        end
      end

      h_dequeue_pending <= h_read && h_rd_rdy;
      h_forecast        <= (heap_IB[0] < heap_OB[1]) ? heap_OB[1] : heap_IB[0];

      if (h_ib0_to_ob1 && (heap_OB_shift_valid[0] && heap_OB_shift[0]) && !h_enq_fwd) begin
        heap_OB[1] <= heap_IB[0];
        if (!h_writing_ib0 || (h_writing_ib0 && h_read && h_gt_ob1 && !heap_IB_gt_OB_next[0]) || (h_writing_ib0 && !heap_systolic_full && h_wr_rdy && heap_OB_shift[0] && heap_OB_shift_valid[0] && h_gt_ob1)) begin
          heap_IB[0] <= EMPTY_VAL;
        end
      end

      for (int i = 0; i < HALF_SIZE; i++) begin
        priority case (1'b1)
          (i < HALF_SIZE-1) && heap_OB_shift[i] && heap_OB_shift_valid[i]
          && !(i > 0 && h_ib0_to_ob1 && (heap_OB_shift_valid[0] && heap_OB_shift[0]) && !h_enq_fwd)
          && !h_enq_fwd: begin
            heap_OB[i] <= heap_OB[i+1];
            if (!(i == 0 && h_ib0_to_ob1 && (heap_OB_shift_valid[0] && heap_OB_shift[0])) && (i == (HALF_SIZE - 2) || !heap_OB_shift_valid[i+1] || !heap_IB_shift_to_OB[i+1] || !heap_OB_shift[i+1] || (heap_OB[i+2] == 0))) heap_OB[i+1] <= EMPTY_VAL;
          end
          default: begin
          end
        endcase

        priority case (1'b1)
          (i < HALF_SIZE-1) && heap_IB_shift[i] && heap_IB_shift_valid[i] &&
          !(h_ib0_to_ob1 && (heap_OB_shift_valid[0] && heap_OB_shift[0])) &&
          !(!h_dequeue_pending && heap_OB_shift[i] && heap_OB_shift_valid[i] && (i < HALF_SIZE - 2) && h_enq_ok && heap_IB_gt_OB_next[i+1])
          : begin
            heap_IB[i+1] <= heap_IB[i];
            if (((i == 0 && !h_writing_ib0)
            || (i > 0 && (!heap_IB_shift_valid[i-1] || (heap_IB_shift_to_OB[i-1] && !h_enq_fwd)))
            || (i == 0 && h_writing_ib0 && h_read && h_gt_ob1 && !heap_IB_gt_OB_next[0])
            || (i > 0 && !heap_IB_shift[i-1] && !heap_IB_gt_OB_next[i-1])
            || (i == 0 && h_writing_ib0 && !heap_systolic_full && h_wr_rdy && heap_OB_shift[0] && heap_OB_shift_valid[0] && h_gt_ob1))
            && !(i>0 && h_ib0_to_ob1 && (heap_OB_shift_valid[0] && heap_OB_shift[0]) && heap_IB_gt_OB_next[i-1]))
            heap_IB[i] <= EMPTY_VAL;
          end
          default: begin
          end
        endcase

        priority case (1'b1)
          (i < HALF_SIZE-1) && heap_OB_next_gt_OB[i] && !heap_OB_shift_valid[i] && !heap_IB_gt_OB[i]
          && (i > 0 && !heap_IB_gt_OB_next[i-1]): begin
            heap_OB[i+1] <= heap_OB[i];
            heap_OB[i] <= heap_OB[i+1];
          end

          (i < HALF_SIZE-1) && heap_IB_shift_to_OB[i]
          && !(h_ib0_to_ob1 && (heap_OB_shift_valid[0] && heap_OB_shift[0]))
          && !h_enq_fwd: begin
            heap_OB[i] <= heap_IB[i];
            if (i > 0 && !(heap_IB_shift[i-1] && heap_IB_shift_valid[i-1])) heap_IB[i] <= EMPTY_VAL;
          end

          heap_IB_gt_OB[i] && !(i < (HALF_SIZE-1) && heap_OB_shift[i] && heap_OB_shift_valid[i]): begin
            if (!(h_enq_ok && h_lt_ob0 && (i == 0))) heap_IB[i] <= heap_OB[i];
            heap_OB[i] <= heap_IB[i];
          end

          (i < HALF_SIZE-1) && heap_IB_gt_OB_next[i] && (!heap_IB_gt_OB[i+1])
          && ((heap_IB[i+1] == 0) || (i+1 < HALF_SIZE-1 && heap_IB_gt_OB_next[i+1])
          || (i+1 < HALF_SIZE-1 && heap_IB_shift[i+1]))
          && (heap_IB_shift_valid[i] || (i+1 < HALF_SIZE-1 && heap_IB_shift_valid[i+1]))
          && !(h_ib0_to_ob1 && (heap_OB_shift_valid[0] && heap_OB_shift[0])): begin
            heap_OB[i+1] <= heap_IB[i];
            heap_IB[i+1] <= heap_OB[i+1];
            if (i == 0 && h_writing_ib0) begin
              if (h_gt_ob0 && !h_read) begin
                heap_IB[i] <= heap_OB[0];
              end else begin
                heap_IB[i] <= h_data;
              end
            end
            if ((i > 0 && (heap_IB_shift_to_OB[i-1] && !h_enq_fwd
            || (heap_IB_gt_OB[i-1] && (i-1 != 0)))) || (i == 0 && !h_writing_ib0)) begin
              heap_IB[i] <= EMPTY_VAL;
            end
            if (i == 0 && h_wrt && h_read && h_rd_rdy && h_gt_ob1 && h_gt_ib1 && h_gt_ib0) begin
              heap_IB[i] <= EMPTY_VAL;
            end
            if ((i > 0) && (heap_IB_shift[i-1] && heap_IB_shift_valid[i-1] && (heap_IB[i-1] == EMPTY_VAL) && !(heap_IB_gt_OB[i-1]) && !(heap_IB_gt_OB_next[i-1]))) begin
              heap_IB[i] <= EMPTY_VAL;
            end
          end

          (i < HALF_SIZE-1) && heap_IB_gt_OB_next[i] && !heap_IB_shift_valid[i] && !heap_IB_gt_OB[i+1]: begin
            heap_IB[i] <= heap_OB[i+1];
            heap_OB[i+1] <= heap_IB[i];
          end

          (i < HALF_SIZE-1) && heap_IB_gt_IB_next[i] && !heap_IB_shift_valid[i]
          && ((i == (HALF_SIZE - 2)) || (!heap_IB_gt_IB_next[i+1] && !heap_IB_gt_OB_next[i+1]))
          && (!heap_IB_gt_OB[i+1]): begin
            heap_IB[i] <= heap_IB[i+1];
            heap_IB[i+1] <= heap_IB[i];
          end

          default: begin
          end
        endcase
      end
    end
  end

  // Combinational logic
  always_comb begin
    for (int i = 0; i < HALF_SIZE; i++) begin
      ib_e[i]  = (IB[i]      == EMPTY_VAL);
      ob_e[i]  = (OB[i]      == EMPTY_VAL);
      hib_e[i] = (heap_IB[i] == EMPTY_VAL);
      hob_e[i] = (heap_OB[i] == EMPTY_VAL);
    end
    m_empt = empties_sat({ib_e,  ob_e});
    h_empt = empties_sat({hib_e, hob_e});
    m_all_empty = &{ib_e,  ob_e};
    h_all_empty = &{hib_e, hob_e};

    systolic_full       = (m_empt != 2'd3);   // was size >= SIZE-2
    systolic_empty      = m_all_empty;
    heap_systolic_full  = (h_empt != 2'd3);
    h_last_write        = !heap_systolic_full && !more_than_3({hib_e, hob_e});
    // While the main buffer is full, the heap buffer's last write slot is the only room a write
    // can reach at once; a pull would move that room into a tree, so evict in its place.
    pull_reserved       = systolic_full && h_last_write;
    heap_systolic_empty = h_all_empty;

    // ---- log-depth max tree over tree tops; a later index wins a value-tie ----
    top_moved_any = |heap_top_moved;
    top_moved_rd  = |(heap_top_moved & ~cmd_moved);
    for (int i = 0; i < TC_P2; i++) begin
      if (i < TREE_COUNT) begin
        t_val[TC_P2+i] = heap_output[i];
        t_v[TC_P2+i]   = !heap_empty[i] && (heap_output[i] != EMPTY_VAL);
      end else begin
        t_val[TC_P2+i] = EMPTY_VAL;
        t_v[TC_P2+i]   = 1'b0;
      end
      t_i[TC_P2+i] = BRAM_TREE_ADDR_WIDTH'(i);
    end
    for (int n = TC_P2-1; n >= 1; n--) begin
      t_rw = t_v[2*n+1] && (!t_v[2*n] || (t_val[2*n+1] >= t_val[2*n]));
      t_v[n]   = t_v[2*n] | t_v[2*n+1];
      t_val[n] = t_rw ? t_val[2*n+1] : t_val[2*n];
      t_i[n]   = t_rw ? t_i[2*n+1]   : t_i[2*n];
    end

    // Pulls and evictions command only the max tree, so only that tree must be idle.
    tree_hold    = top_moved_any || (|owed) || !heap_ready[max_idx_q];
    // A busy tree's top bounds it once the tree has taken its command and the top has settled.
    owe_ok       = max_v_q && !top_moved_any && !(|owed)
                   && !heap_ready[max_idx_q] && !heap_write[max_idx_q] && !heap_read[max_idx_q];
    pop_fire     = owed & heap_ready;
    max_valid    = max_v_q || tree_hold;
    max_rdy      = max_v_q && !tree_hold;
    max_node_idx = max_idx_q;
    max_node     = tree_hold ? UNKNOWN_VAL : max_q;

    // ---- spill: registered-only inputs, no dependence on max_node ----
    spill_to_heap       = (!ib_e[HALF_SIZE-1]) && (IB[HALF_SIZE-1] <= OB[HALF_SIZE-1]) && !(&heap_full);
    spill_to_heap_valid = heap_ready[spill_tgt] && !heap_full[spill_tgt] && !owed[spill_tgt];
    spill_tgt_next      = spill_tgt;
    spill_found_rdy     = 1'b0;
    for (int d = TREE_COUNT; d >= 1; d--) begin
      if (!heap_full[(spill_tgt + d) % TREE_COUNT] && !owed[(spill_tgt + d) % TREE_COUNT])
        spill_tgt_next = BRAM_TREE_ADDR_WIDTH'((spill_tgt + d) % TREE_COUNT);
    end
    for (int d = TREE_COUNT; d >= 1; d--) begin
      if (heap_ready[(spill_tgt + d) % TREE_COUNT] && !heap_full[(spill_tgt + d) % TREE_COUNT]
          && !owed[(spill_tgt + d) % TREE_COUNT]) begin
        spill_tgt_next  = BRAM_TREE_ADDR_WIDTH'((spill_tgt + d) % TREE_COUNT);
        spill_found_rdy = 1'b1;
      end
    end
    spill_fire          = spill_to_heap && spill_to_heap_valid;

    // if a spill is going into the same heap this cycle, the spill wins and the pull retries next cycle
    spill_hits_max = spill_fire && (max_node_idx == spill_tgt);



    // Main buffer: state-only terms and readies.
    m_head      = m_dequeue_pending ? m_forecast : OB[0];
    m_ib0_to_ob1 = IB[0] > OB[2] && IB[0] < OB[1] && IB[0] > IB[1];

    for (int i = 0; i < HALF_SIZE-1; i++) begin
      OB_shift[i] = (OB[i+1] >= IB[i]) && (OB[i+1] >= IB[i+1]) && (OB[i+1] != EMPTY_VAL);
    end
    ob_g[0] = ob_e[0];
    ob_p[0] = 1'b0;
    for (int i = 1; i < SV_W; i++) begin
      ob_g[i] = ob_e[i-1] && OB_shift[i-1];
      ob_p[i] = OB_shift[i-1];
    end
    ob_v = scan_fwd(ob_g, ob_p);
    for (int i = 0; i < SV_W; i++) OB_shift_valid[i] = ob_v[i];

    for (int i = 0; i < HALF_SIZE; i++) begin
      IB_gt_OB[i] = (IB[i] > OB[i]);
    end
    for (int i = 0; i < HALF_SIZE - 1; i++) begin
      IB_gt_OB_next[i] = IB[i] > OB[i+1];
      IB_gt_IB_next[i] = IB[i] > IB[i+1];
      OB_next_gt_OB[i] = OB[i+1] > OB[i];
    end
    for (int i = HALF_SIZE-2; i >= 0; i--) begin
      IB_shift[i] = (i < (HALF_SIZE-2) && (IB_gt_OB_next[i+1] || IB_gt_IB_next[i+1]))
      || ((IB[i] <= OB[i]) && (IB[i] <= OB[i+1]) && (IB[i] != EMPTY_VAL))
      || ((OB[i] == 0) && (i == 0) && (IB[i] <= OB[i+1]));
    end

    // IB_shift_valid without its command-dependent head-forward term, so the readies
    // depend on state only.
    room_g[SV_W-1] = ib_e[HALF_SIZE-1] || spill_fire;
    room_p[SV_W-1] = 1'b0;
    for (int i = 0; i < SV_W-1; i++) begin
      ib_b  = !((IB_gt_OB[i+1] || IB_gt_OB[i]) && !(OB_shift[i] && OB_shift_valid[i]));
      room_g[i] = (ib_e[i+1] || (IB_gt_OB_next[i+1] && OB_shift[i] && OB_shift_valid[i]
                                     && OB_shift[0] && OB_shift_valid[0])) && ib_b;
      room_p[i] = ib_b;
    end
    room_v = scan_bwd(room_g, room_p);
    for (int i = 0; i < SV_W; i++) IB_room[i] = room_v[i];

    // IB[0] can take a write this cycle. Both readies drop without it: replace writes IB[0] too.
    m_ib0_free = ib_e[0] || IB_room[0];
    m_wr_rdy   = !systolic_full && m_ib0_free;
    m_rd_rdy   = !systolic_empty && (m_head != EMPTY_VAL) && !m_dequeue_pending && m_ib0_free;

    // Heap buffer: state-only terms and readies.
    h_head      = h_dequeue_pending ? h_forecast : heap_OB[0];
    h_ib0_to_ob1 = heap_IB[0] > heap_OB[2] && heap_IB[0] < heap_OB[1] && heap_IB[0] > heap_IB[1];

    for (int i = 0; i < HALF_SIZE-1; i++) begin
      heap_OB_shift[i] = (heap_OB[i+1] >= heap_IB[i]) && (heap_OB[i+1] >= heap_IB[i+1]) && (heap_OB[i+1] != EMPTY_VAL);
    end
    hob_g[0] = hob_e[0];
    hob_p[0] = 1'b0;
    for (int i = 1; i < SV_W; i++) begin
      hob_g[i] = hob_e[i-1] && heap_OB_shift[i-1];
      hob_p[i] = heap_OB_shift[i-1];
    end
    hob_v = scan_fwd(hob_g, hob_p);
    for (int i = 0; i < SV_W; i++) heap_OB_shift_valid[i] = hob_v[i];

    for (int i = 0; i < HALF_SIZE; i++) begin
      heap_IB_gt_OB[i] = (heap_IB[i] > heap_OB[i]);
    end
    for (int i = 0; i < HALF_SIZE - 1; i++) begin
      heap_IB_gt_OB_next[i] = heap_IB[i] > heap_OB[i+1];
      heap_IB_gt_IB_next[i] = heap_IB[i] > heap_IB[i+1];
      heap_OB_next_gt_OB[i] = heap_OB[i+1] > heap_OB[i];
    end
    for (int i = HALF_SIZE-2; i >= 0; i--) begin
      heap_IB_shift[i] = (i < (HALF_SIZE-2) && (heap_IB_gt_OB_next[i+1] || heap_IB_gt_IB_next[i+1]))
      || ((heap_IB[i] <= heap_OB[i]) && (heap_IB[i] <= heap_OB[i+1]) && (heap_IB[i] != EMPTY_VAL))
      || ((heap_OB[i] == 0) && (i == 0) && (heap_IB[i] <= heap_OB[i+1]));
    end

    // IB_shift_valid without its command-dependent head-forward term, so the readies
    // depend on state only.
    hroom_g[SV_W-1] = hib_e[HALF_SIZE-1] || 1'b0;
    hroom_p[SV_W-1] = 1'b0;
    for (int i = 0; i < SV_W-1; i++) begin
      hib_b  = !((heap_IB_gt_OB[i+1] || heap_IB_gt_OB[i]) && !(heap_OB_shift[i] && heap_OB_shift_valid[i]));
      hroom_g[i] = (hib_e[i+1] || (heap_IB_gt_OB_next[i+1] && heap_OB_shift[i] && heap_OB_shift_valid[i]
                                     && heap_OB_shift[0] && heap_OB_shift_valid[0])) && hib_b;
      hroom_p[i] = hib_b;
    end
    hroom_v = scan_bwd(hroom_g, hroom_p);
    for (int i = 0; i < SV_W; i++) heap_IB_room[i] = hroom_v[i];

    // IB[0] can take a write this cycle. Both readies drop without it: replace writes IB[0] too.
    h_ib0_free = hib_e[0] || heap_IB_room[0];
    h_wr_rdy   = !heap_systolic_full && h_ib0_free;
    h_rd_rdy   = !heap_systolic_empty && (h_head != EMPTY_VAL) && !h_dequeue_pending && h_ib0_free;

    output_from_heap_systolic = h_dequeue_pending
        ? (m_dequeue_pending ? (h_forecast > m_forecast) : (h_forecast > OB[0]))
        : (m_dequeue_pending ? (heap_OB[0] > m_forecast) : (heap_OB[0] > OB[0]));
    rd_sel = output_from_heap_systolic ? h_head : m_head;

    // A tree's top bounds its contents whenever o_top_moved is low, busy or not, so reads wait
    // only for a top moved other than by a command. Pulls and evictions command a tree and also
    // wait for it to be idle.
    h_ge_max  = h_dequeue_pending ? (h_forecast >= max_q) : (heap_OB[0] >= max_q);
    m_ge_max  = m_dequeue_pending ? (m_forecast >= max_q) : (OB[0] >= max_q);
    rd_ge_max = !top_moved_rd && (output_from_heap_systolic ? h_ge_max : m_ge_max);
    max_gt_h_head = h_dequeue_pending ? (max_q > h_forecast) : (max_q > heap_OB[0]);

    // Command routing: enqueue goes to the main buffer, or to the heap buffer while the main
    // one is full; dequeue and replace go to the buffer holding the head; the heap buffer
    // also takes pulls and evictions.
    // Replace on an empty queue inserts through the main buffer. A spill in flight is
    // still an element, so the queue is not empty until the tree has taken it.
    hybrid_empty = systolic_empty && heap_systolic_empty && (&heap_empty) && !(|heap_write);
    rep_empty = i_wrt && i_read && hybrid_empty && m_wr_rdy;
    // Every term below depends on o_read_ready, the deepest signal in the module. Each is
    // computed for both of its values and selected last, so the readies' scans run in parallel
    // with the decode they gate. Only control is duplicated; the data paths see the selection.
    user_heap_enq = i_wrt && !i_read && !m_wr_rdy && h_wr_rdy;
    for (int r = 0; r < 2; r++) begin
      c_user_heap[r] = i_read && r[0] && output_from_heap_systolic;
      c_m_wrt[r]  = (i_wrt && !i_read && m_wr_rdy)
                    || (i_wrt && i_read && (r[0] || rep_empty) && !output_from_heap_systolic);
      c_m_read[r] = i_read && (r[0] || rep_empty) && !output_from_heap_systolic;
      c_pull[r]   = !c_user_heap[r] && !user_heap_enq && pull_ok;
      c_evict[r]  = !c_user_heap[r] && !user_heap_enq && evict_ok;
      c_h_wrt[r]  = (c_user_heap[r] && i_wrt) || user_heap_enq || c_pull[r] || c_evict[r];
      c_h_read[r] = c_user_heap[r] || c_evict[r];
      c_h_user[r] = c_user_heap[r] || user_heap_enq;
      c_h_gt_ob1[r] = c_h_user[r] ? (i_data > heap_OB[1]) : (max_q > heap_OB[1]);

      // Main buffer: command-dependent terms.
      c_m_enq_ok[r]  = c_m_wrt[r] && !c_m_read[r] && !systolic_full && m_wr_rdy;
      // Not gated on the readies: that would put the IB_room chain in series with the sort
      // network. A refused forward only holds the OB shift for a cycle; the writes stay gated.
      c_m_enq_fwd[r] = c_m_wrt[r] && !c_m_read[r] && !systolic_full && (i_data > OB[1]);
      c_m_wr_ib0[r]  = c_m_enq_ok[r] || (c_m_wrt[r] && c_m_read[r] && (m_rd_rdy || systolic_empty));
      ib_g[SV_W-1] = ib_e[HALF_SIZE-1] || spill_fire;
      ib_p[SV_W-1] = 1'b0;
      for (int i = 0; i < SV_W-1; i++) begin
        ib_b    = !((IB_gt_OB[i+1] || IB_gt_OB[i]) && !(OB_shift[i] && OB_shift_valid[i]));
        ib_g[i] = (ib_e[i+1] || (IB_gt_OB_next[i+1] && OB_shift[i] && OB_shift_valid[i]
                                 && !c_m_enq_fwd[r])) && ib_b;
        ib_p[i] = ib_b;
      end
      c_ib_v[r] = scan_bwd(ib_g, ib_p);

      // Heap buffer: command-dependent terms.
      c_h_enq_ok[r]  = c_h_wrt[r] && !c_h_read[r] && !heap_systolic_full && h_wr_rdy;
      c_h_enq_fwd[r] = c_h_wrt[r] && !c_h_read[r] && !heap_systolic_full && c_h_gt_ob1[r];
      c_h_wr_ib0[r]  = c_h_enq_ok[r]
                       || (c_h_wrt[r] && c_h_read[r] && (h_rd_rdy || heap_systolic_empty));
      hib_g[SV_W-1] = hib_e[HALF_SIZE-1];
      hib_p[SV_W-1] = 1'b0;
      for (int i = 0; i < SV_W-1; i++) begin
        hib_b    = !((heap_IB_gt_OB[i+1] || heap_IB_gt_OB[i])
                     && !(heap_OB_shift[i] && heap_OB_shift_valid[i]));
        hib_g[i] = (hib_e[i+1] || (heap_IB_gt_OB_next[i+1] && heap_OB_shift[i]
                                   && heap_OB_shift_valid[i] && !c_h_enq_fwd[r])) && hib_b;
        hib_p[i] = hib_b;
      end
      c_hib_v[r] = scan_bwd(hib_g, hib_p);
    end

    user_heap     = c_user_heap[o_read_ready];
    m_wrt         = c_m_wrt[o_read_ready];
    m_read        = c_m_read[o_read_ready];
    m_data        = i_data;
    pull_fire     = c_pull[o_read_ready];
    evict_fire    = c_evict[o_read_ready];
    h_wrt         = c_h_wrt[o_read_ready];
    h_read        = c_h_read[o_read_ready];
    h_from_user   = c_h_user[o_read_ready];
    h_data        = h_from_user ? i_data : max_q;
    h_gt_ob0      = h_from_user ? (i_data > heap_OB[0]) : (max_q > heap_OB[0]);
    h_gt_ob1      = c_h_gt_ob1[o_read_ready];
    h_gt_ib0      = h_from_user ? (i_data > heap_IB[0]) : (max_q > heap_IB[0]);
    h_gt_ib1      = h_from_user ? (i_data > heap_IB[1]) : (max_q > heap_IB[1]);
    h_lt_ob0      = h_from_user ? (i_data < heap_OB[0]) : (max_q < heap_OB[0]);
    m_enq_ok      = c_m_enq_ok[o_read_ready];
    m_enq_fwd     = c_m_enq_fwd[o_read_ready];
    m_writing_ib0 = c_m_wr_ib0[o_read_ready];
    h_enq_ok      = c_h_enq_ok[o_read_ready];
    h_enq_fwd     = c_h_enq_fwd[o_read_ready];
    h_writing_ib0 = c_h_wr_ib0[o_read_ready];
    for (int i = 0; i < HALF_SIZE - 1; i++) begin
      IB_shift_to_OB[i] = IB_gt_OB_next[i] && (i > 0 && OB_shift[i-1] && OB_shift_valid[i-1])
                          && !m_enq_fwd;
      heap_IB_shift_to_OB[i] = heap_IB_gt_OB_next[i]
                               && (i > 0 && heap_OB_shift[i-1] && heap_OB_shift_valid[i-1])
                               && !h_enq_fwd;
    end
    for (int i = 0; i < SV_W; i++) begin
      IB_shift_valid[i]      = c_ib_v[o_read_ready][i];
      heap_IB_shift_valid[i] = c_hib_v[o_read_ready][i];
    end

    if (o_read_ready) begin
      o_data = rd_sel;
    end else begin
      o_data = max6(heap_OB[1], heap_IB[0], IB[0], OB[1], OB[0], heap_OB[0]);
    end
  end

endmodule
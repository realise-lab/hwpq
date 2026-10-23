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

  logic [BRAM_TREE_ADDR_WIDTH-1:0]        heap_round_robin;

  generate
    for (genvar k=0; k<TREE_COUNT; k++) begin : g_trees
      bram_tree heap_inst (
        .i_CLK(i_CLK),
        .i_RSTn(i_RSTn),
        .i_wrt(heap_write[k]),
        .i_read(heap_read[k]),
        .i_data(heap_input[k]),
        .o_full(heap_full[k]),
        .o_empty(heap_empty[k]),
        .o_data(heap_output[k]),
        .o_ready(heap_ready[k])
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

  logic                    heap_write_to_buffer;
  logic                    heap_replace_to_buffer;
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
  logic            ib_a, ib_b, hib_a, hib_b;
  
  localparam int TC_P2 = 1 << BRAM_TREE_ADDR_WIDTH;

  logic [DATA_WIDTH-1:0] rd_sel;

  // max tree (heap-style indexing: node n has children 2n (lower idx) and 2n+1)
  logic [DATA_WIDTH-1:0]                t_val [2*TC_P2];
  logic                                 t_v   [2*TC_P2];
  logic                                 t_r   [2*TC_P2];
  logic [BRAM_TREE_ADDR_WIDTH-1:0]      t_i   [2*TC_P2];
  logic                                 t_rw;
  logic                                 max_valid;

  logic hib0_empty, can_write, can_replace;
  logic spill_fire, spill_hits_max;
  logic pull_fire, replace_fire;

  logic [DATA_WIDTH-1:0] heap_rep_data;     // no reset, data only
  logic [DATA_WIDTH-1:0] heap_spill_data;   // no reset, data only
  logic [TREE_COUNT-1:0] heap_data_sel;     // 1 = replace data, 0 = spill data (registered with heap_write)

  generate
    for (genvar k = 0; k < TREE_COUNT; k++) begin : g_heap_in
      assign heap_input[k] = heap_data_sel[k] ? heap_rep_data : heap_spill_data;
    end
  endgenerate

  assign pull_fire    = heap_ready[max_node_idx] && (heap_write_to_buffer || heap_replace_to_buffer);
  assign replace_fire = heap_ready[max_node_idx] && heap_replace_to_buffer;


  // dont think i need (!systolic_full && (IB[0] == 0)
  assign o_write_ready = ((!systolic_full && !(&heap_full) && !heap_systolic_full) || (!systolic_full)) && (!ob_e[0] || systolic_empty);
  assign o_read_ready = (rd_sel != EMPTY_VAL)
    && (rd_sel >= max_node) && (rd_sel >= OB[1])      && (rd_sel >= heap_OB[1])
    && (rd_sel >= IB[0])    && (rd_sel >= heap_IB[0]);

  logic [5:0][DATA_WIDTH-1:0] head_v;
  always_comb begin
    head_v  = {heap_OB[1], heap_IB[0], IB[0], OB[1], OB[0], heap_OB[0]};
    o_max_value = oh6_select(head_v, argmax6_oh(head_v));
  end

  always_ff @(posedge i_CLK) begin
    heap_rep_data   <= heap_IB[2];
    heap_spill_data <= IB[HALF_SIZE-1];
  end

  // Sequential logic
  always_ff @(posedge i_CLK or negedge i_RSTn) begin
    if (!i_RSTn) begin  // Reset
      heap_write  <= 0;
      heap_read   <= 0;
      heap_round_robin <= 0;
      for (int i = 0; i < HALF_SIZE; i++) begin
        IB[i] <= EMPTY_VAL;  // initialize to the sentinel (0, lowest priority), since this is a max-queue
        OB[i] <= EMPTY_VAL;
        heap_IB[i] <= EMPTY_VAL;
        heap_OB[i] <= EMPTY_VAL;
      end
    end else begin
      heap_write  <= 0;
      heap_read   <= 0;


      // Dequeue operation
      if (i_read && !i_wrt && o_read_ready) begin // pop the head of OB
        if (output_from_heap_systolic) begin
          heap_OB[0] <= EMPTY_VAL;
        end else begin
          OB[0] <= EMPTY_VAL;
        end
      end

      // Enqueue operation
      if (i_wrt && !i_read && o_write_ready) begin
        if (i_data > OB[0]) begin
          OB[0] <= i_data;
          IB[0] <= OB[0];
        end else begin
          IB[0] <= i_data;  // insert the new node at the head of IB
        end
      end

      // Replace operation
      // Write stall doesn't trigger here, since it's replace we should always be able to write
      if (i_wrt && i_read && o_read_ready) begin
        // if the output is from the heap systolic we read from heap systolic, and write to main systolic
        if (output_from_heap_systolic) begin
          if (systolic_full) begin
            heap_IB[0] <= i_data;
            heap_OB[0] <= EMPTY_VAL;
          end else if (systolic_empty) begin
            OB[0] <= i_data;
            heap_OB[0] <= EMPTY_VAL;
          end else begin
            if (i_data > OB[0]) begin
              OB[0] <= i_data;
              IB[0] <= OB[0];
            end else begin
              IB[0] <= i_data;
            end
            heap_OB[0] <= EMPTY_VAL;
          end
        end else begin
          if (systolic_empty) begin
            OB[0] <= i_data;  // insert the new node at the head of OB
          end else begin
            IB[0] <= i_data;  // replace the head of IB
            OB[0] <= EMPTY_VAL;  // pop the head of OB
          end
        end
      end

      for (int k = 0; k < TREE_COUNT; k++) begin
        heap_write[k]    <= (replace_fire && (k == max_node_idx)) || (spill_fire && (k == heap_round_robin));
        heap_data_sel[k] <= replace_fire && (k == max_node_idx);
        heap_read[k]     <= pull_fire && (k == max_node_idx);
      end
      
      if (spill_to_heap) begin
        if (spill_to_heap_valid) begin
          if ((!(IB_shift_valid[HALF_SIZE-2]) && (IB_shift[HALF_SIZE-2] || !IB_gt_OB_next[HALF_SIZE-2])) || IB_shift_to_OB[HALF_SIZE-2]) IB[HALF_SIZE-1] <= EMPTY_VAL;
        end
        if (heap_round_robin == TREE_COUNT - 1) begin
          heap_round_robin <= 0;
        end else begin
          heap_round_robin <= heap_round_robin + 1;
        end
      end
      
      // writing to the heap_systolic
      if (heap_ready[max_node_idx]) begin
        if (heap_write_to_buffer) begin
          if ((max_node > heap_OB[0]) && (!hob_e[0] && heap_systolic_empty)) begin
            heap_OB[0] <= max_node;
            heap_IB[0] <= heap_OB[0];
          end else begin
            heap_IB[0] <= max_node;  
          end
        end else if (heap_replace_to_buffer) begin
          heap_IB[2] <= EMPTY_VAL;
          if (max_node > heap_OB[0] && (!hob_e[0])) begin
            heap_OB[0] <= max_node;
            heap_IB[0] <= heap_OB[0];
          end else begin
            heap_IB[0] <= max_node;  
          end
        end
      end

      // Sorting logic
      for (int i = 0; i < HALF_SIZE; i++) begin  // Iterate through each element
         priority case (1'b1)
          OB_shift[i] && OB_shift_valid[i]: begin
            OB[i] <= OB[i+1]; 
            if ((i == (HALF_SIZE - 2) || !OB_shift_valid[i+1] || !IB_shift_to_OB[i+1] || !OB_shift[i+1])) OB[i+1] <= EMPTY_VAL;
          end
          default: begin
            // No action needed
          end
        endcase

        priority case (1'b1)
          IB_shift[i] && IB_shift_valid[i]: begin
            // We slide this value down
            IB[i+1] <= IB[i];
            if ((i == 0 && !i_wrt) || (i > 0 && !IB_shift_valid[i-1])) IB[i] <= EMPTY_VAL;
          end
          default: begin
            // No action needed
          end
        endcase

        priority case (1'b1)
          OB_next_gt_OB[i] && !OB_shift_valid[i] && !IB_gt_OB[i]
          && (i > 0 && !IB_gt_OB_next[i-1]): begin
            // If we cannot shift, we can swap
            OB[i+1] <= OB[i];
            OB[i] <= OB[i+1];
          end

          IB_shift_to_OB[i]: begin
            // if OB is shifting while we want to swap in, we can just swap down instead
            OB[i] <= IB[i];
            if (!(IB_shift[i-1] && IB_shift_valid[i-1])) IB[i] <= EMPTY_VAL;
          end

          IB_gt_OB[i] && !(i < (HALF_SIZE-1) && OB_shift[i] && OB_shift_valid[i]): begin
            IB[i] <=  OB[i];
            OB[i] <=  IB[i];
          end

          IB_gt_OB_next[i] && (!IB_gt_OB[i+1])
          && ((ib_e[i+1]) || (IB_gt_OB_next[i+1]) || (IB_shift[i+1]) || (spill_to_heap && spill_to_heap_valid)) && IB_shift_valid[i]: begin
            // Move IB[i] to OB[i+1], and move OB[i+1] to IB[i+1]
            OB[i+1] <= IB[i];
            IB[i+1] <= OB[i+1];
            // if we are also writing this cycle, we need to replace the value with i_data or OB[0] if i_data > OB[0]
            if (i == 0 && i_wrt) begin
              if (i_data > OB[0] && !i_read) begin
                IB[i] <= OB[0];
              end else begin
                IB[i] <= i_data;
              end
            end
            if ((i > 0 && (IB_shift_to_OB[i-1] || IB_gt_OB[i-1])) || (i == 0 && !i_wrt)) begin
              IB[i] <= EMPTY_VAL;
            end
          end

          IB_gt_OB_next[i] && !IB_shift_valid[i] && !IB_gt_OB[i+1]: begin
            // If we cannot shift, we can swap
            IB[i] <= OB[i+1];
            OB[i+1] <= IB[i];
          end

          IB_gt_IB_next[i] && !IB_shift_valid[i]
          && ((i == (HALF_SIZE - 2)) || (!IB_gt_IB_next[i+1] && !IB_gt_OB_next[i+1]))
          && (!IB_gt_OB[i+1]): begin
            // If we cannot shift, we can swap
            IB[i] <= IB[i+1];
            IB[i+1] <= IB[i];
          end

          default: begin
            // No action needed
          end
        endcase
      end
      
      for (int i = 0; i < HALF_SIZE; i++) begin
         priority case (1'b1)
          heap_OB_shift[i] && heap_OB_shift_valid[i]: begin
            heap_OB[i] <= heap_OB[i+1]; 
            if ((i == (HALF_SIZE - 2) || !heap_OB_shift_valid[i+1] || !heap_IB_shift_to_OB[i+1] || !heap_OB_shift[i+1])) heap_OB[i+1] <= EMPTY_VAL;
          end
          default: begin
            // No action needed
          end
        endcase

        priority case (1'b1)
          heap_IB_shift[i] && heap_IB_shift_valid[i]: begin
            // We slide this value down
            heap_IB[i+1] <= heap_IB[i];
            if ((i == 0 && !((heap_write_to_buffer || heap_replace_to_buffer) && heap_ready[max_node_idx])) || (i > 0 && !heap_IB_shift_valid[i-1])) heap_IB[i] <= EMPTY_VAL;
          end
          default: begin
            // No action needed
          end
        endcase

        priority case (1'b1)
          heap_OB_next_gt_OB[i] && !heap_OB_shift_valid[i] && !heap_IB_gt_OB[i]
          && (i > 0 && !heap_IB_gt_OB_next[i-1]): begin
            // If we cannot shift, we can swap
            heap_OB[i+1] <= heap_OB[i];
            heap_OB[i] <= heap_OB[i+1];
          end

          heap_IB_shift_to_OB[i]: begin
            // if OB is shifting while we want to swap in, we can just swap down instead
            heap_OB[i] <= heap_IB[i];
            if (!(heap_IB_shift[i-1] && heap_IB_shift_valid[i-1])) heap_IB[i] <= EMPTY_VAL;
          end

          heap_IB_gt_OB[i] && !(i < (HALF_SIZE-1) && heap_OB_shift[i] && heap_OB_shift_valid[i]): begin
            heap_IB[i] <=  heap_OB[i];
            heap_OB[i] <=  heap_IB[i];
          end

          heap_IB_gt_OB_next[i] && (!heap_IB_gt_OB[i+1])
          && ((hib_e[i+1]) || (heap_IB_gt_OB_next[i+1]) || (heap_IB_shift[i+1])) && heap_IB_shift_valid[i]: begin
            // Move IB[i] to OB[i+1], and move OB[i+1] to IB[i+1]
            heap_OB[i+1] <= heap_IB[i];
            heap_IB[i+1] <= heap_OB[i+1];
            // if we are also writing this cycle, we need to replace the value with max_node or OB[0] if max_node > heap_OB[0]
            if (i == 0 && (heap_write_to_buffer || heap_replace_to_buffer)) begin
              if ( max_node > heap_OB[0] && !(heap_replace_to_buffer || (output_from_heap_systolic && i_read))) begin
                heap_IB[i] <= heap_OB[0];
              end else begin
                heap_IB[i] <= max_node;
              end
            end
            if ((i > 0 && (heap_IB_shift_to_OB[i-1] || heap_IB_gt_OB[i-1])) || (i == 0 && !((heap_write_to_buffer || heap_replace_to_buffer) && heap_ready[max_node_idx]))) begin
              heap_IB[i] <= EMPTY_VAL;
            end
          end

          heap_IB_gt_OB_next[i] && !heap_IB_shift_valid[i] && !heap_IB_gt_OB[i+1]: begin
            // If we cannot shift, we can swap
            heap_IB[i] <= heap_OB[i+1];
            heap_OB[i+1] <= heap_IB[i];
          end

          heap_IB_gt_IB_next[i] && !heap_IB_shift_valid[i]
          && ((i == (HALF_SIZE - 2)) || (!heap_IB_gt_IB_next[i+1] && !heap_IB_gt_OB_next[i+1]))
          && (!heap_IB_gt_OB[i+1]): begin
            // If we cannot shift, we can swap
            heap_IB[i] <= heap_IB[i+1];
            heap_IB[i+1] <= heap_IB[i];
          end

          default: begin
            // No action needed
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
    heap_systolic_empty = h_all_empty;

    // ---- log-depth max tree ----
    // A later index wins a value-tie only if it is ready.
    for (int i = 0; i < TC_P2; i++) begin
      if (i < TREE_COUNT) begin
        t_val[TC_P2+i] = heap_ready[i] ? heap_output[i] : UNKNOWN_VAL;
        t_v[TC_P2+i]   = !heap_empty[i] && ((heap_output[i] != EMPTY_VAL) || heap_ready[i]);
        t_r[TC_P2+i]   = heap_ready[i];
      end else begin
        t_val[TC_P2+i] = EMPTY_VAL;
        t_v[TC_P2+i]   = 1'b0;
        t_r[TC_P2+i]   = 1'b0;
      end
      t_i[TC_P2+i] = BRAM_TREE_ADDR_WIDTH'(i);
    end
    for (int n = TC_P2-1; n >= 1; n--) begin
      t_rw = t_v[2*n+1] && (!t_v[2*n] || (t_val[2*n+1] > t_val[2*n])
                            || ((t_val[2*n+1] == t_val[2*n]) && t_r[2*n+1]));
      t_v[n]   = t_v[2*n] | t_v[2*n+1];
      t_val[n] = t_rw ? t_val[2*n+1] : t_val[2*n];
      t_r[n]   = t_rw ? t_r[2*n+1]   : t_r[2*n];
      t_i[n]   = t_rw ? t_i[2*n+1]   : t_i[2*n];
    end

    max_valid    = t_v[1];
    max_node_idx = t_v[1] ? t_i[1] : '0;
    max_node     = t_v[1] ? t_val[1] : EMPTY_VAL;   // value comes straight from the tree, no wide idx mux

    // ---- spill: registered-only inputs, no dependence on max_node ----
    spill_to_heap       = (!ib_e[HALF_SIZE-1]) && (IB[HALF_SIZE-1] <= OB[HALF_SIZE-1]) && !(&heap_full);
    spill_to_heap_valid = heap_ready[heap_round_robin] && !heap_full[heap_round_robin];
    spill_fire          = spill_to_heap && spill_to_heap_valid;

    // ---- pull from heap into heap systolic ----
    hib0_empty  = hib_e[0];
    can_write   = hib0_empty && (h_empt == 2'd3);      // was heap_systolic_size <  SIZE-2
    can_replace = (h_empt == 2'd2) && !hib_e[2] && hib0_empty && hib_e[1]   // was == SIZE-2
                  && (heap_IB[2] <= heap_IB[3]) && (heap_IB[2] <= heap_OB[2]) && (heap_IB[2] <= heap_OB[3]);

    // if a spill is going into the same heap this cycle, the spill wins and the pull retries next cycle
    spill_hits_max = spill_fire && (max_node_idx == heap_round_robin);

    heap_write_to_buffer   = can_write   && max_valid && !spill_hits_max;
    heap_replace_to_buffer = can_replace && max_valid && (max_node > heap_IB[2]) && !spill_hits_max;

    output_from_heap_systolic = (heap_OB[0] > OB[0]);
    rd_sel = output_from_heap_systolic ? heap_OB[0] : OB[0];


    // comparison results (IB/OB/heap_IB/heap_OB are HALF_SIZE deep)
    for (int i=0; i<HALF_SIZE-1;i++) begin
      OB_shift[i] = (OB[i+1] >= IB[i]) && (OB[i+1] >= IB[i+1]) && (!ob_e[i+1]);
      heap_OB_shift[i] = (heap_OB[i+1] >= heap_IB[i]) && (heap_OB[i+1] >= heap_IB[i+1]) && (!hob_e[i+1]);
    end 

    // OB_shift_valid[i] = (OB[i-1]==EMPTY | OB_shift_valid[i-1]) & OB_shift[i-1]   (i>=1)
    // OB_shift_valid[0] = OB[0]==EMPTY
    ob_g[0]  = ob_e[0];            
    ob_p[0]  = 1'b0;
    hob_g[0] = (hob_e[0]);       
    hob_p[0] = 1'b0;
    for (int i = 1; i < SV_W; i++) begin
      ob_g[i]  = (ob_e[i-1])      && OB_shift[i-1];
      ob_p[i]  = OB_shift[i-1];
      hob_g[i] = (hob_e[i-1]) && heap_OB_shift[i-1];
      hob_p[i] = heap_OB_shift[i-1];
    end
    ob_v  = scan_fwd(ob_g,  ob_p);
    hob_v = scan_fwd(hob_g, hob_p);
    for (int i = 0; i < SV_W; i++) begin
      OB_shift_valid[i]      = ob_v[i];
      heap_OB_shift_valid[i] = hob_v[i];
    end

    for (int i = 0; i < HALF_SIZE; i++) begin
      // IB_gt_OB should not happen at the front of the array
      IB_gt_OB[i] = (IB[i] > OB[i]);
      heap_IB_gt_OB[i] = (heap_IB[i] > heap_OB[i]);
    end

    for (int i = 0; i < HALF_SIZE - 1; i++) begin
      IB_gt_OB_next[i] = IB[i] > OB[i+1];
      IB_gt_IB_next[i] = IB[i] > IB[i+1];
      OB_next_gt_OB[i] = OB[i+1] > OB[i];
      IB_shift_to_OB[i] = IB_gt_OB_next[i] && (i > 0 && OB_shift[i-1] && OB_shift_valid[i-1]);

      heap_IB_gt_OB_next[i] = heap_IB[i] > heap_OB[i+1];
      heap_IB_gt_IB_next[i] = heap_IB[i] > heap_IB[i+1];
      heap_OB_next_gt_OB[i] = heap_OB[i+1] > heap_OB[i];
      heap_IB_shift_to_OB[i] = heap_IB_gt_OB_next[i] && (i > 0 && heap_OB_shift[i-1] && heap_OB_shift_valid[i-1]);
    end

    for (int i=HALF_SIZE-2; i >= 0; i--) begin
      IB_shift[i] = (i < (HALF_SIZE-2) && (IB_gt_OB_next[i+1] || IB_gt_IB_next[i+1])) || ((IB[i] <= OB[i]) && (IB[i] <= OB[i+1])) || (ob_e[i] && (i == 0) && (IB[i] <= OB[i+1]));
      heap_IB_shift[i] = (i < (HALF_SIZE-2) && (heap_IB_gt_OB_next[i+1] || heap_IB_gt_IB_next[i+1])) || ((heap_IB[i] <= heap_OB[i]) && (heap_IB[i] <= heap_OB[i+1])) || (hob_e[i] && (i == 0) && (heap_IB[i] <= heap_OB[i+1]));
    end
    
    // seed element (HALF_SIZE-2): x = base, p = 0
    ib_g[SV_W-1]  = (ib_e[HALF_SIZE-1]) || (spill_to_heap && spill_to_heap_valid);
    ib_p[SV_W-1]  = 1'b0;
    hib_g[SV_W-1] = (hib_e[HALF_SIZE-1]);
    hib_p[SV_W-1] = 1'b0;

    for (int i = 0; i < SV_W-1; i++) begin
      // A: "room ahead" term that doesn't depend on the chain
      ib_a  = (ib_e[i+1]) || IB_shift_to_OB[i+1];
      hib_a = (hib_e[i+1]) || heap_IB_shift_to_OB[i+1];

      // B: local "not blocked" term
      ib_b  = !IB_shift_to_OB[i]
              && !((IB_gt_OB[i+1] || IB_gt_OB[i]) && !(OB_shift[i] && OB_shift_valid[i]));
      hib_b = !heap_IB_shift_to_OB[i]
              && !((heap_IB_gt_OB[i+1] || heap_IB_gt_OB[i]) && !(heap_OB_shift[i] && heap_OB_shift_valid[i]));

      ib_g[i]  = ib_a  & ib_b;   ib_p[i]  = ib_b;
      hib_g[i] = hib_a & hib_b;  hib_p[i] = hib_b;
    end

    ib_v  = scan_bwd(ib_g,  ib_p);
    hib_v = scan_bwd(hib_g, hib_p);
    for (int i = 0; i < SV_W; i++) begin
      IB_shift_valid[i]      = ib_v[i];
      heap_IB_shift_valid[i] = hib_v[i];
    end

    if (o_read_ready) begin
      if (output_from_heap_systolic) begin
        o_data = heap_OB[0];
      end else begin
        o_data = OB[0];
      end
    end else begin
      o_data = max6(heap_OB[1], heap_IB[0], IB[0], OB[1], OB[0], heap_OB[0]);
    end
  end

endmodule
`default_nettype none

module RegisterTree #(
    parameter int QUEUE_SIZE = 15,
    parameter int DATA_WIDTH = 16
) (
    // Synchronous Control
    input var logic i_CLK,
    input var logic i_RSTn,
    // Inputs
    input var logic i_wrt,
    input var logic i_read,
    input var logic [DATA_WIDTH-1:0] i_data,
    // Outputs
    output var logic o_full,
    output var logic o_empty,
    output var logic [DATA_WIDTH-1:0] o_data
);

  /*
    Parameters
  */
  localparam int TREE_DEPTH = $clog2(QUEUE_SIZE);  // depth of the tree
  localparam int NODES_NEEDED = (1 << TREE_DEPTH) - 1;  // number of nodes needed to initialize
  localparam int COMP_COUNT = NODES_NEEDED / 2;  // number of comparators

  /*
    Registers
  */
  // Register array to store the tree nodes
  logic [DATA_WIDTH-1:0] queue     [NODES_NEEDED];
  logic [DATA_WIDTH-1:0] next_queue[NODES_NEEDED];
  logic [$clog2(NODES_NEEDED)-1:0] enqueue_idx, next_enqueue_idx;
  // Size counter to keep track of the number of nodes in the queue
  logic [$clog2(NODES_NEEDED)-1:0] size;
  logic [$clog2(NODES_NEEDED)-1:0] next_size;
  logic empty, full;
  // Wires to connect the comparator units
  logic [DATA_WIDTH-1:0] old_parent     [COMP_COUNT];
  logic [DATA_WIDTH-1:0] old_left_child [COMP_COUNT];
  logic [DATA_WIDTH-1:0] old_right_child[COMP_COUNT];
  logic [DATA_WIDTH-1:0] new_parent     [COMP_COUNT];
  logic [DATA_WIDTH-1:0] new_left_child [COMP_COUNT];
  logic [DATA_WIDTH-1:0] new_right_child[COMP_COUNT];

  /*
    States
  */
  typedef enum logic [2:0] {
    IDLE                  = 3'b000,
    COMPARE_AND_SWAP_EVEN = 3'b001,
    COMPARE_AND_SWAP_ODD  = 3'b010,
    ENQUEUE               = 3'b011,
    DEQUEUE               = 3'b100,
    REPLACE               = 3'b101
  } state_t;
  state_t current_state, next_state;

  /*
    Generate components and initialize registers
  */
  // Generate comparators
  generate
    for (genvar i = 0; i < COMP_COUNT; i++) begin : l_gen_comparator
      Comparator #(
          .DATA_WIDTH(DATA_WIDTH)
      ) u_Comparator (
          .i_parent(old_parent[i]),
          .i_left_child(old_left_child[i]),
          .i_right_child(old_right_child[i]),
          .o_parent(new_parent[i]),
          .o_left_child(new_left_child[i]),
          .o_right_child(new_right_child[i])
      );
    end
  endgenerate

  // Initialize comparators
  generate
    for (genvar i = 0; i < COMP_COUNT; i++) begin : l_gen_comparators_init
      assign old_parent[i] = queue[i];
      assign old_left_child[i] = (2 * i + 1 < NODES_NEEDED) ? queue[2*i+1] : '0;
      assign old_right_child[i] = (2 * i + 2 < NODES_NEEDED) ? queue[2*i+2] : '0;
    end
  endgenerate

  /*
    Size Tracker
  */
  always_ff @(posedge i_CLK or negedge i_RSTn)
    if (!i_RSTn) size <= 0;
    else size <= next_size;

  always_comb
    next_size = i_wrt && !i_read ? size + 1 :
                !i_wrt && i_read ? size - 1 :
                i_wrt && i_read && size == 0 && i_data != 0 ? size + 1 :
                size;

  /*
    State machine control
  */
  always_ff @(posedge i_CLK or negedge i_RSTn)
    if (!i_RSTn) current_state <= IDLE;
    else current_state <= next_state;

  always_comb
    case (current_state)
      IDLE:
      if (i_wrt && !i_read) next_state = ENQUEUE;
      else if (!i_wrt && i_read) next_state = DEQUEUE;
      else if (i_wrt && i_read) next_state = REPLACE;
      else next_state = COMPARE_AND_SWAP_EVEN;

      COMPARE_AND_SWAP_EVEN:
      if (i_wrt && !i_read) next_state = ENQUEUE;
      else if (!i_wrt && i_read) next_state = DEQUEUE;
      else if (i_wrt && i_read) next_state = REPLACE;
      else next_state = COMPARE_AND_SWAP_ODD;

      COMPARE_AND_SWAP_ODD:
      if (i_wrt && !i_read) next_state = ENQUEUE;
      else if (!i_wrt && i_read) next_state = DEQUEUE;
      else if (i_wrt && i_read) next_state = REPLACE;
      else next_state = COMPARE_AND_SWAP_EVEN;

      ENQUEUE: next_state = COMPARE_AND_SWAP_EVEN;

      DEQUEUE: next_state = COMPARE_AND_SWAP_EVEN;

      REPLACE: next_state = COMPARE_AND_SWAP_EVEN;

      default: next_state = IDLE;
    endcase

  /*
    Queue Management
  */
  logic [DATA_WIDTH-1:0] reset_values[NODES_NEEDED];

  generate
    for (genvar itr = 0; itr < NODES_NEEDED; itr++) begin : l_gen_reset_values
      assign reset_values[itr] = '0;
    end
  endgenerate

  always_ff @(posedge i_CLK or negedge i_RSTn)
    if (!i_RSTn) queue <= reset_values;
    else queue <= next_queue;

  always_ff @(posedge i_CLK or negedge i_RSTn)
    if (!i_RSTn) enqueue_idx <= '0;
    else enqueue_idx <= next_enqueue_idx;

  function automatic void f_process_even_levels(input logic [DATA_WIDTH-1:0] q_in[NODES_NEEDED],
                                                input logic [DATA_WIDTH-1:0] parent[COMP_COUNT],
                                                input logic [DATA_WIDTH-1:0] left[COMP_COUNT],
                                                input logic [DATA_WIDTH-1:0] right[COMP_COUNT],
                                                output logic [DATA_WIDTH-1:0] q_out[NODES_NEEDED]);
    q_out = q_in;
    for (int lvl = 0; lvl < TREE_DEPTH; lvl++) begin
      if (lvl % 2 == 0 && lvl < TREE_DEPTH - 1) begin
        for (int i = (1 << lvl) - 1; i < (1 << (lvl + 1)) - 1; i++) begin
          q_out[i] = parent[i];
          q_out[2*i+1] = left[i];
          q_out[2*i+2] = right[i];
        end
      end
    end
  endfunction

  function automatic void f_process_odd_levels(input logic [DATA_WIDTH-1:0] q_in[NODES_NEEDED],
                                               input logic [DATA_WIDTH-1:0] parent[COMP_COUNT],
                                               input logic [DATA_WIDTH-1:0] left[COMP_COUNT],
                                               input logic [DATA_WIDTH-1:0] right[COMP_COUNT],
                                               output logic [DATA_WIDTH-1:0] q_out[NODES_NEEDED]);
    q_out = q_in;
    for (int lvl = 0; lvl < TREE_DEPTH; lvl++) begin
      if (lvl % 2 == 1 && lvl < TREE_DEPTH - 1) begin
        for (int i = (1 << lvl) - 1; i < (1 << (lvl + 1)) - 1; i++) begin
          q_out[i] = parent[i];
          q_out[2*i+1] = left[i];
          q_out[2*i+2] = right[i];
        end
      end
    end
  endfunction

  function automatic logic [$clog2(NODES_NEEDED)-1:0] f_find_empty_idx(
                                          input logic [DATA_WIDTH-1:0] q_in[NODES_NEEDED],
                                          input logic [$clog2(NODES_NEEDED)-1:0] size_in);
    logic [$clog2(NODES_NEEDED)-1:0] found_empty_idx = NODES_NEEDED;
    for (int i = NODES_NEEDED; i >= 0; i--) begin
      if (q_in[i] == 0) begin
        found_empty_idx = (i < found_empty_idx) ? i : found_empty_idx;
      end
    end
    return found_empty_idx;
  endfunction

  // Temporary variables for function calls and state-specific queues
  logic [DATA_WIDTH-1:0] even_swap_queue[NODES_NEEDED];
  logic [DATA_WIDTH-1:0] odd_swap_queue[NODES_NEEDED];
  logic [DATA_WIDTH-1:0] enq_queue[NODES_NEEDED];
  logic [DATA_WIDTH-1:0] deq_queue[NODES_NEEDED];
  logic [DATA_WIDTH-1:0] rep_queue[NODES_NEEDED];

  // Helper functions for each state
  function automatic void f_prepare_even_swap_queue();
    f_process_even_levels(queue, new_parent, new_left_child, new_right_child, even_swap_queue);
  endfunction

  function automatic void f_prepare_odd_swap_queue();
    f_process_odd_levels(queue, new_parent, new_left_child, new_right_child, odd_swap_queue);
  endfunction

  function automatic void f_prepare_enq_queue();
    enq_queue = queue;
    enq_queue[f_find_empty_idx(queue, size)] = i_data;
  endfunction

  function automatic void f_prepare_deq_queue();
    deq_queue = queue;
    deq_queue[0] = '0;
  endfunction

  function automatic void f_prepare_rep_queue();
    rep_queue = queue;
    rep_queue[0] = i_data;
  endfunction

  // Call helper functions
  always_comb f_prepare_even_swap_queue();
  always_comb f_prepare_odd_swap_queue();
  always_comb f_prepare_enq_queue();
  always_comb f_prepare_deq_queue();
  always_comb f_prepare_rep_queue();

  // Derive next_enqueue_idx
  always_comb next_enqueue_idx = (current_state == ENQUEUE) ? f_find_empty_idx(queue, size) : 0;

  // State-based next_queue selection
  always_comb
    case (current_state)
      IDLE: next_queue = queue;
      COMPARE_AND_SWAP_EVEN: next_queue = even_swap_queue;
      COMPARE_AND_SWAP_ODD: next_queue = odd_swap_queue;
      ENQUEUE: next_queue = enq_queue;
      DEQUEUE: next_queue = deq_queue;
      REPLACE: next_queue = rep_queue;
      default: next_queue = queue;
    endcase

  // Assign outputs
  assign empty = (size <= 0) ? 'b1 : 'b0;
  assign full = (size >= QUEUE_SIZE) ? 'b1 : 'b0;
  assign o_full = full;
  assign o_empty = empty;
  assign o_data = !empty ? queue[0] : 'd0;

endmodule

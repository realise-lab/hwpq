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
  *
  * Local Parameters
  *
  * */
  localparam int TREE_DEPTH = $clog2(QUEUE_SIZE);  // depth of the tree
  localparam int NODES_NEEDED = (1 << TREE_DEPTH) - 1;  // number of nodes needed to initialize
  localparam int COMP_COUNT = NODES_NEEDED / 2;  // number of comparators


  /*
  *
  * Internal Registers and Wires
  *
  * */
  logic [          DATA_WIDTH-1:0] queue      [NODES_NEEDED];  // the final queue for output
  logic [          DATA_WIDTH-1:0] next_queue [NODES_NEEDED];
  logic [          DATA_WIDTH-1:0] reset_queue[NODES_NEEDED];
  logic [          DATA_WIDTH-1:0] swap_queue [NODES_NEEDED];
  logic [          DATA_WIDTH-1:0] enq_queue  [NODES_NEEDED];
  logic [          DATA_WIDTH-1:0] deq_queue  [NODES_NEEDED];
  logic [          DATA_WIDTH-1:0] rep_queue  [NODES_NEEDED];
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
  *
  * FSM Initialization
  *
  * */
  typedef enum logic [2:0] {
    IDLE             = 3'b000,
    COMPARE_AND_SWAP = 3'b001,
    ENQUEUE          = 3'b010,
    DEQUEUE          = 3'b011,
    REPLACE          = 3'b100
  } state_t;
  state_t current_state, next_state;


  /*
  *
  * Generate components and initialize constants
  * 
  * */
  generate
    for (genvar i = 0; i < NODES_NEEDED; i++) begin : l_gen_reset_queue
      assign reset_queue[i] = '0;
    end
  endgenerate


  /*
  *
  * assignment
  *
  * */
  assign empty = (size <= 0) ? 'b1 : 'b0;
  assign full = (size >= QUEUE_SIZE) ? 'b1 : 'b0;
  assign o_full = full;
  assign o_empty = empty;
  assign o_data = !empty ? queue[0] : 'd0;


  /*
  *
  * FSM
  *
  * */
  always_ff @(posedge i_CLK or negedge i_RSTn)
    if (!i_RSTn) current_state <= IDLE;
    else current_state <= next_state;
  always_comb
    case (current_state)
      IDLE, COMPARE_AND_SWAP: next_state = (i_wrt && !i_read) ? ENQUEUE : 
                                           (!i_wrt && i_read) ? DEQUEUE : 
                                           (i_wrt && i_read) ? REPLACE : 
                                           COMPARE_AND_SWAP;
      ENQUEUE, DEQUEUE, REPLACE: next_state = COMPARE_AND_SWAP;
      default: next_state = IDLE;
    endcase


  /*
  *
  * size
  *
  * */
  always_ff @(posedge i_CLK or negedge i_RSTn)
    if (!i_RSTn) size <= 0;
    else size <= next_size;
  always_comb
    case (current_state)
      IDLE: next_size = size;
      COMPARE_AND_SWAP: next_size = size;
      ENQUEUE: next_size = (!full) ? size + 1 : size;
      DEQUEUE: next_size = (!empty) ? size - 1 : size;
      REPLACE: next_size = (size == 0 && i_data != '0) ? size + 1 : size;
      default: next_size = size;
    endcase


  /*
  *
  * queue
  *
  * */
  always_ff @(posedge i_CLK or negedge i_RSTn) begin : FSM_queue_seq
    if (!i_RSTn) queue <= reset_queue;
    else queue <= next_queue;
  end
  always_comb begin : FSM_queue_comb
    case (current_state)
      IDLE: next_queue = queue;
      COMPARE_AND_SWAP: next_queue = swap_queue;
      ENQUEUE: next_queue = enq_queue;
      DEQUEUE: next_queue = deq_queue;
      REPLACE: next_queue = rep_queue;
      default: next_queue = queue;
    endcase
  end


  always_comb begin : prepare_swap_queue
    // Temporary queue for even level processing
    automatic logic [DATA_WIDTH-1:0] even_phase_queue[NODES_NEEDED];
    even_phase_queue = queue;
    
    // Process even levels first
    for (int lvl = 0; lvl < TREE_DEPTH; lvl++) begin
      if (lvl % 2 == 0 && lvl < TREE_DEPTH - 1) begin
        for (int i = (1 << lvl) - 1; i < (1 << (lvl + 1)) - 1; i++) begin
          // Get parent and children
          automatic logic [DATA_WIDTH-1:0] parent = even_phase_queue[i];
          automatic logic [DATA_WIDTH-1:0] left_child = (2*i+1 < NODES_NEEDED) ? even_phase_queue[2*i+1] : '0;
          automatic logic [DATA_WIDTH-1:0] right_child = (2*i+2 < NODES_NEEDED) ? even_phase_queue[2*i+2] : '0;
          
          // Compare logic (same as in Comparator module)
          automatic logic left_greater_than_right = (left_child > right_child);
          automatic logic parent_less_than_left = (parent < left_child);
          automatic logic parent_less_than_right = (parent < right_child);
          
          // Determine new values based on comparison
          logic [DATA_WIDTH-1:0] new_parent, new_left, new_right;
          
          // Determine new parent (largest of the three)
          if (left_greater_than_right && parent_less_than_left) begin
            new_parent = left_child;
          end else if (!left_greater_than_right && parent_less_than_right) begin
            new_parent = right_child;
          end else begin
            new_parent = parent;
          end
            
          // Determine new left child
          if (left_greater_than_right && parent_less_than_left) begin
            new_left = parent;
          end else begin
            new_left = left_child;
          end
            
          // Determine new right child
          if (!left_greater_than_right && parent_less_than_right) begin
            new_right = parent;
          end else begin
            new_right = right_child;
          end
          
          // Update queue with new values
          even_phase_queue[i] = new_parent;
          if (2*i+1 < NODES_NEEDED) begin 
            even_phase_queue[2*i+1] = new_left;
          end else begin
          end
          if (2*i+2 < NODES_NEEDED) begin
            even_phase_queue[2*i+2] = new_right;
          end else begin
          end
        end
      end else begin
      end
    end
    
    // Start with results from even phase processing
    swap_queue = even_phase_queue;
    
    // Process odd levels
    for (int lvl = 0; lvl < TREE_DEPTH; lvl++) begin
      if (lvl % 2 == 1 && lvl < TREE_DEPTH - 1) begin
        for (int i = (1 << lvl) - 1; i < (1 << (lvl + 1)) - 1; i++) begin
          // Get parent and children
          automatic logic [DATA_WIDTH-1:0] parent = swap_queue[i];
          automatic logic [DATA_WIDTH-1:0] left_child = (2*i+1 < NODES_NEEDED) ? swap_queue[2*i+1] : '0;
          automatic logic [DATA_WIDTH-1:0] right_child = (2*i+2 < NODES_NEEDED) ? swap_queue[2*i+2] : '0;
          
          // Compare logic (same as in Comparator module)
          automatic logic left_greater_than_right = (left_child > right_child);
          automatic logic parent_less_than_left = (parent < left_child);
          automatic logic parent_less_than_right = (parent < right_child);
          
          // Determine new values based on comparison
          logic [DATA_WIDTH-1:0] new_parent, new_left, new_right;
          
          // Determine new parent (largest of the three)
          if (left_greater_than_right && parent_less_than_left) begin
            new_parent = left_child;
          end else if (!left_greater_than_right && parent_less_than_right) begin
            new_parent = right_child;
          end else begin
            new_parent = parent;
          end
            
          // Determine new left child
          if (left_greater_than_right && parent_less_than_left) begin
            new_left = parent;
          end else begin
            new_left = left_child;
          end
            
          // Determine new right child
          if (!left_greater_than_right && parent_less_than_right) begin
            new_right = parent;
          end else begin
            new_right = right_child;
          end
          
          // Update queue with new values
          swap_queue[i] = new_parent;
          if (2*i+1 < NODES_NEEDED) begin
            swap_queue[2*i+1] = new_left;
          end else begin
          end
          if (2*i+2 < NODES_NEEDED) begin
            swap_queue[2*i+2] = new_right;
          end else begin
          end
        end
      end else begin
      end
    end
  end

  always_comb begin : prepare_enq_queue
    automatic logic [$clog2(NODES_NEEDED)-1:0] found_empty_idx;
    found_empty_idx = NODES_NEEDED;
    for (int i = NODES_NEEDED; i >= 0; i--) begin
      if (queue[i] == 0) begin
        found_empty_idx = (i < found_empty_idx) ? i : found_empty_idx;
      end else begin
        found_empty_idx = found_empty_idx;
      end
    end
    enq_queue = queue;
    enq_queue[found_empty_idx] = i_data;
  end

  always_comb begin : prepare_deq_queue
    deq_queue = queue;
    deq_queue[0] = '0;
  end

  always_comb begin : prepare_rep_queue
    rep_queue = queue;
    rep_queue[0] = i_data;
  end

endmodule

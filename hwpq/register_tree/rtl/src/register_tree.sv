`default_nettype none

/*******************************************************************************
  Module Name: register_tree
  Date: 2026/06/22
  Description: A register-based priority queue that preserves the heap
               property across a binary tree of registers, closely
               resembling a software heap. Enqueue searches for the leftmost
               invalid entry and reorders the tree; dequeue and replace
               remove/update the root in a single cycle while alternating-
               level compare-and-swap operations restore heap order.
  Parameters: ENQ_ENA - Enables the enqueue datapath when set
              QUEUE_SIZE - Maximum number of elements in the priority queue
              DATA_WIDTH - Bit width of data elements
  Inputs: i_CLK - System clock
          i_RSTn - Active-low reset signal
          i_wrt - Write/insert command (enqueue/replace operation)
          i_read - Read/pop command (dequeue/replace operation)
          i_data - Input data to be enqueued (or used for replace)
  Outputs: o_write_ready - High when the queue has room to accept a write
           o_read_ready - High when the queue holds data available to read
           o_data - Output data from the highest priority element
*******************************************************************************/

module register_tree #(
    parameter bit ENQ_ENA = 1,    // Define if user would like to enable enqueue
    parameter int QUEUE_SIZE = 4095,
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
    output var logic o_write_ready,
    output var logic o_read_ready,
    output var logic [DATA_WIDTH-1:0] o_data
);

  //----------------------------------------------------------------------
  // Local Parameters
  //----------------------------------------------------------------------
  localparam int TREE_DEPTH = $clog2(QUEUE_SIZE);  // depth of the tree
  localparam int NODES_NEEDED = (1 << TREE_DEPTH) - 1;  // number of nodes needed to initialize

  //----------------------------------------------------------------------
  // Internal Registers and Wires
  //----------------------------------------------------------------------
  // Storage elements
  logic [DATA_WIDTH-1:0] queue[NODES_NEEDED];
  logic [DATA_WIDTH-1:0] reset_queue[NODES_NEEDED];
  
  // Size counter
  logic [$clog2(NODES_NEEDED)-1:0] size;
  logic empty, full;

  // Control signals
  logic enqueue, dequeue, replace;
  
  // Results of each operation - calculated in parallel
  logic [DATA_WIDTH-1:0] swap_result[NODES_NEEDED];
  logic [DATA_WIDTH-1:0] next_queue[NODES_NEEDED];
  
  // Size after each operation
  logic [$clog2(NODES_NEEDED)-1:0] next_size;

  logic [DATA_WIDTH-1:0] even_phase_queue[NODES_NEEDED];
  logic [DATA_WIDTH-1:0] final_swap_result[NODES_NEEDED];
  logic [DATA_WIDTH-1:0] parent, left_child, right_child;

  logic left_greater_than_right;
  logic parent_less_than_left;
  logic parent_less_than_right;
  logic [DATA_WIDTH-1:0] new_parent, new_left, new_right;

  int found_empty_index;

  //----------------------------------------------------------------------
  // Initialize reset_queue to zeros
  //----------------------------------------------------------------------
  generate
    for (genvar i = 0; i < QUEUE_SIZE; i++) begin : l_gen_reset_queue
      if (!ENQ_ENA) begin
        assign reset_queue[i] = '1;
      end else begin
        assign reset_queue[i] = '0;
      end
    end
  endgenerate

  //----------------------------------------------------------------------
  // Signals assignments
  //----------------------------------------------------------------------
  // Control signal assignment
  assign enqueue = ENQ_ENA && i_wrt && !i_read; // Only enable enqueue if ENQ_ENA is high
  assign dequeue = !i_wrt && i_read;
  assign replace = i_wrt && i_read;
  // Size counter signals
  assign empty = (size <= 0);
  assign full = (size >= QUEUE_SIZE);
  assign o_write_ready = !full;
  assign o_read_ready = !empty;
  assign o_data = queue[0];

  //----------------------------------------------------------------------
  // Compare and Swap operation
  //----------------------------------------------------------------------
  always_comb begin : prepare_swap_result
    for (int i = 0; i < NODES_NEEDED; i++) begin
      even_phase_queue[i] = queue[i];
    end
    
    // Process even levels first
    for (int lvl = 0; lvl < TREE_DEPTH; lvl++) begin
      if (lvl % 2 == 0 && lvl < TREE_DEPTH - 1) begin
        for (int i = 0; i < NODES_NEEDED; i++) begin
          // Get parent and children
          parent = even_phase_queue[i];
          left_child = (2*i+1 < NODES_NEEDED) ? even_phase_queue[2*i+1] : '0;
          right_child = (2*i+2 < NODES_NEEDED) ? even_phase_queue[2*i+2] : '0;
          
          // Compare logic
          left_greater_than_right = (left_child > right_child);
          parent_less_than_left = (parent < left_child);
          parent_less_than_right = (parent < right_child);
          
          if (left_greater_than_right && parent_less_than_left) begin
            new_parent = left_child;
          end else if (!left_greater_than_right && parent_less_than_right) begin
            new_parent = right_child;
          end else begin
            new_parent = parent;
          end
            
          if (left_greater_than_right && parent_less_than_left) begin
            new_left = parent;
          end else begin
            new_left = left_child;
          end
            
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
            // No left child
          end
          if (2*i+2 < NODES_NEEDED) begin
            even_phase_queue[2*i+2] = new_right;
          end else begin
            // No right child
          end
        end
      end else begin
        // Do nothing for odd levels in this pass
      end
    end

    for (int i = 0; i < NODES_NEEDED; i++) begin
      final_swap_result[i] = even_phase_queue[i];
    end
    
    // Process odd levels
    for (int lvl = 0; lvl < TREE_DEPTH; lvl++) begin
      if (lvl % 2 == 1 && lvl < TREE_DEPTH - 1) begin
        for (int i = 0; i < NODES_NEEDED; i++) begin
          // Get parent and children
          parent = final_swap_result[i];
          left_child = (2*i+1 < NODES_NEEDED) ? final_swap_result[2*i+1] : '0;
          right_child = (2*i+2 < NODES_NEEDED) ? final_swap_result[2*i+2] : '0;
          
          // Compare logic
          left_greater_than_right = (left_child > right_child);
          parent_less_than_left = (parent < left_child);
          parent_less_than_right = (parent < right_child);
          
          if (left_greater_than_right && parent_less_than_left) begin
            new_parent = left_child;
          end else if (!left_greater_than_right && parent_less_than_right) begin
            new_parent = right_child;
          end else begin
            new_parent = parent;
          end
            
          if (left_greater_than_right && parent_less_than_left) begin
            new_left = parent;
          end else begin
            new_left = left_child;
          end
            
          if (!left_greater_than_right && parent_less_than_right) begin
            new_right = parent;
          end else begin
            new_right = right_child;
          end
          
          // Update queue with new values
          final_swap_result[i] = new_parent;
          if (2*i+1 < NODES_NEEDED) begin
            final_swap_result[2*i+1] = new_left;
          end else begin
            // No left child
          end
          if (2*i+2 < NODES_NEEDED) begin
            final_swap_result[2*i+2] = new_right;
          end else begin
            // No right child
          end
        end
      end else begin
        // Do nothing for even levels in this pass
      end
    end
    
    // Store the final swap result
    for (int i = 0; i < NODES_NEEDED; i++) begin
      swap_result[i] = final_swap_result[i];
    end
  end

  always_comb begin : calcualte_next_queue
    case ({
      enqueue, dequeue, replace
    })
      3'b100: begin  // Enqueue
        found_empty_index = NODES_NEEDED - 1;  // Start from the last index
        for (int i = (1 << (TREE_DEPTH - 1)) - 1; i < (1 << (TREE_DEPTH)) - 1; i++) begin
          found_empty_index = (queue[i] == '0) ? i : found_empty_index;
        end
        for (int i = 0; i < NODES_NEEDED; i++) begin
          next_queue[i] = queue[i];
        end
        next_queue[found_empty_index] = i_data;
      end
      3'b010: begin  // Dequeue
        for (int i = 0; i < NODES_NEEDED; i++) begin
          next_queue[i] = queue[i];
        end
        next_queue[0] = '0;
      end
      3'b001: begin  // Replace
        for (int i = 0; i < NODES_NEEDED; i++) begin
          next_queue[i] = queue[i];
        end
        next_queue[0] = i_data;
      end
      default: begin
        for (int i = 0; i < NODES_NEEDED; i++) begin
          next_queue[i] = swap_result[i];
        end
      end
    endcase
  end

  always_comb begin : calculate_next_size
    case ({
      enqueue, dequeue, replace
    })
      3'b100: 
      next_size = (full) ? size :
                  size + 1;
      3'b010: 
      next_size = (empty) ? size :
                  size - 1;
      3'b001:
      next_size = (o_data == '1 && !ENQ_ENA)    ? size+1 : //special case since reset fills up the pq with highest prio item
                  (size == '0 && i_data != '0) ? size+1 :
                  (size != '0 && i_data == '0) ? size-1 :
                   size;
      default: next_size = size;
    endcase
  end

  always_ff @(posedge i_CLK or negedge i_RSTn) begin : update_registers
    if (!i_RSTn) begin
      for (int i = 0; i < NODES_NEEDED; i++) begin
        queue[i] <= reset_queue[i];
      end
      size            <= 0;
    end else begin
      for (int i = 0; i < NODES_NEEDED; i++) begin
        queue[i] <= next_queue[i];
      end
      size            <= next_size;
    end
  end

endmodule
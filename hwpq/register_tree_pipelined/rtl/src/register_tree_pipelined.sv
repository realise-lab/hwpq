`default_nettype none

module register_tree_pipelined #(
    parameter bit ENQ_ENA = 1,
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

  //----------------------------------------------------------------------
  // Local Parameters
  //----------------------------------------------------------------------
  localparam int TREE_DEPTH = $clog2(QUEUE_SIZE);  // depth of the tree
  localparam int NODES_NEEDED = (1 << TREE_DEPTH) - 1;  // number of nodes needed to initialize

  //----------------------------------------------------------------------
  // Internal Registers and Wires
  //----------------------------------------------------------------------

  logic [          DATA_WIDTH-1:0] queue      [NODES_NEEDED];
  logic [          DATA_WIDTH-1:0] next_queue [NODES_NEEDED];
  logic [          DATA_WIDTH-1:0] swap_result[NODES_NEEDED];
  logic [          DATA_WIDTH-1:0] reset_queue[NODES_NEEDED];

  logic [$clog2(NODES_NEEDED)-1:0] size;
  logic [$clog2(NODES_NEEDED)-1:0] next_size;

  logic empty, full, enqueue, dequeue, replace;
  logic even_cycle_flag, next_even_cycle_flag;

  int found_empty_index;

  //----------------------------------------------------------------------
  // Initialize reset_queue to zeros
  //----------------------------------------------------------------------
  generate
    for (genvar i = 0; i < NODES_NEEDED; i++) begin : l_gen_reset_queue
      assign reset_queue[i] = '0;
    end
  endgenerate

  //----------------------------------------------------------------------
  // Signals assignments
  //----------------------------------------------------------------------

  assign enqueue = (ENQ_ENA && i_wrt && !i_read) ? 1'b1 : 1'b0; // Only enable enqueue if ENQ_ENA is high
  assign dequeue = !i_wrt && i_read ? 1'b1 : 1'b0;
  assign replace = i_wrt && i_read ? 1'b1 : 1'b0;

  assign empty = (size <= 0) ? 1'b1 : 1'b0;
  assign full = (size >= QUEUE_SIZE) ? 1'b1 : 1'b0;
  assign o_full = full;
  assign o_empty = empty;
  assign o_data = queue[0];

  //----------------------------------------------------------------------
  // Compare and Swap operation
  //----------------------------------------------------------------------
  always_comb begin : calcualte_swap_result
    case (even_cycle_flag)
      1'b1: begin  // Even cycle
        swap_result = queue;  // Initialize swap_result with current queue
        for (int lvl = 0; lvl < TREE_DEPTH; lvl++) begin  // Iterate through levels
          if (lvl % 2 == 0 && lvl < TREE_DEPTH - 1) begin  // Process only even levels (0, 2, 4...)
            for (
                int i = (1 << lvl) - 1; i < (1 << (lvl + 1)) - 1; i++
            ) begin  // Iterate through nodes at this level
              if (queue[2*i+1] > queue[2*i+2]) begin // compare left and right children, if left > right
                if (queue[2*i+1] > queue[i]) begin  // compare with parent, if left > parent
                  swap_result[i] = queue[2*i+1];
                  swap_result[2*i+1] = queue[i];
                end else begin
                  swap_result[i] = queue[i];
                  swap_result[2*i+1] = queue[2*i+1];
                end
              end else begin  // if right > left
                if (queue[2*i+2] > queue[i]) begin  // compare with parent, if right > parent
                  swap_result[i] = queue[2*i+2];
                  swap_result[2*i+2] = queue[i];
                end else begin
                  swap_result[i] = queue[i];
                  swap_result[2*i+2] = queue[2*i+2];
                end
              end
            end
          end else begin  // Odd level
            // Do nothing
          end
        end
      end

      1'b0: begin  // Odd cycle
        swap_result = queue;  // Initialize swap_result with current queue
        for (int lvl = 0; lvl < TREE_DEPTH; lvl++) begin  // Iterate through levels
          if (lvl % 2 == 1 && lvl < TREE_DEPTH - 1) begin  // Process only odd levels (1, 3, 5...)
            for (
                int i = (1 << lvl) - 1; i < (1 << (lvl + 1)) - 1; i++
            ) begin  // Iterate through nodes at this level
              if (queue[2*i+1] > queue[2*i+2]) begin // compare left and right children, if left > right
                if (queue[2*i+1] > queue[i]) begin  // compare with parent, if left > parent
                  swap_result[i] = queue[2*i+1];
                  swap_result[2*i+1] = queue[i];
                end else begin
                  swap_result[i] = queue[i];
                  swap_result[2*i+1] = queue[2*i+1];
                end
              end else begin  // if right > left
                if (queue[2*i+2] > queue[i]) begin  // compare with parent, if right > parent
                  swap_result[i] = queue[2*i+2];
                  swap_result[2*i+2] = queue[i];
                end else begin
                  swap_result[i] = queue[i];
                  swap_result[2*i+2] = queue[2*i+2];
                end
              end
            end
          end else begin  // Even level
            // Do nothing
          end
        end
      end

      default: begin
        swap_result = queue;
      end
    endcase
  end

  always_comb begin : calcualte_next_even_cycle_flag
    if (enqueue || dequeue || replace) begin
      next_even_cycle_flag = 1'b1;  // Set to 1 if any operation is performed
    end else begin
      next_even_cycle_flag = !even_cycle_flag;  // toggle the flag
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
        next_queue = queue;
        next_queue[found_empty_index] = i_data;
      end
      3'b010: begin  // Dequeue
        next_queue = queue;
        next_queue[0] = '0;
      end
      3'b001: begin  // Replace
        next_queue = queue;
        next_queue[0] = i_data;
      end
      default: next_queue = swap_result;
    endcase
  end

  always_comb begin : calculate_next_size
    case ({
      enqueue, dequeue, replace
    })
      3'b100:  next_size = size + 1;  // Enqueue
      3'b010:  next_size = size - 1;  // Dequeue
      3'b001:  next_size = (size == 0 && i_data != '0) ? size + 1 : size;  // Replace
      default: next_size = size;  // No change
    endcase
  end

  always_ff @(posedge i_CLK or negedge i_RSTn) begin : update_registers
    if (!i_RSTn) begin
      queue           <= reset_queue;
      size            <= 0;
      even_cycle_flag <= 1'b1;
    end else begin
      queue           <= next_queue;
      size            <= next_size;
      even_cycle_flag <= next_even_cycle_flag;
    end
  end

endmodule

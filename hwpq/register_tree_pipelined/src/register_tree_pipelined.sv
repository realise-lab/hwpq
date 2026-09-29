`default_nettype none

/*******************************************************************************
  Module Name: register_tree_pipelined
  Date: 2026/06/21
  Description: A pipelined version of the register tree architecture that
               divides the compare-and-swap logic between clock cycles to
               reduce combinational path length, at the cost of enqueue
               taking two cycles to propagate a new entry into place.
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
    output var logic o_write_ready,
    output var logic o_read_ready,
    output var logic [DATA_WIDTH-1:0] o_data
);

  //----------------------------------------------------------------------
  // Local Parameters
  //----------------------------------------------------------------------
  localparam int TREE_DEPTH = $clog2(QUEUE_SIZE);  // depth of the tree
  localparam int NODES_NEEDED = (1 << TREE_DEPTH) - 1;  // number of nodes needed to initialize
  // Worst-case settle cycles. One level sifted per cycle => uniform bound for
  // every op (climb or sink): TREE_DEPTH-1 transitions + a parity-slack cycle.
  localparam int SETTLE_CYCLES = TREE_DEPTH;
  localparam int CNT_W         = $clog2(SETTLE_CYCLES + 1);

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
  logic next_empty, next_full;
  logic even_cycle_flag, next_even_cycle_flag;
  logic head_valid, can_accept;

  logic [CNT_W-1:0] settle_cnt, next_settle_cnt;

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

  // A command is refused unless the queue can honor it (this also gates size).
  // Enqueue/dequeue gate on full/empty; replace pops-and-pushes so needs neither.
  assign enqueue = (ENQ_ENA && i_wrt && !i_read) ? o_write_ready : 1'b0;
  assign dequeue = (!i_wrt && i_read) ? o_read_ready : 1'b0;
  assign replace = (i_wrt && i_read) ? (can_accept && head_valid) : 1'b0;

  // full/empty are REGISTERED (see update_registers): flopping the >=QUEUE_SIZE
  // comparator keeps it off the decode path; value is identical every cycle.
  assign next_empty = (next_size == 0) ? 1'b1 : 1'b0;
  assign next_full  = (next_size >= QUEUE_SIZE) ? 1'b1 : 1'b0;

  assign o_write_ready = !full && can_accept;
  assign o_read_ready = !empty && head_valid;
  assign o_data = queue[0];

  //----------------------------------------------------------------------
  // Compare and Swap operation
  //----------------------------------------------------------------------
  always_comb begin : calcualte_swap_result
    case (even_cycle_flag)
      1'b1: begin  // Even cycle
        for (int i = 0; i < NODES_NEEDED; i++) begin
          swap_result[i] = queue[i];
        end
        
        for (int lvl = 0; lvl < TREE_DEPTH; lvl++) begin  // Iterate through levels
          if (lvl % 2 == 0 && lvl < TREE_DEPTH - 1) begin  // Process only even levels (0, 2, 4...)
            for (int i = 0; i < NODES_NEEDED; i++) begin  // Iterate through nodes at this level
              if (i >= ((1 << lvl) - 1) && i < ((1 << (lvl + 1)) - 1)) begin 
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
            end
          end else begin  // Odd level
            // Do nothing
          end
        end
      end

      1'b0: begin  // Odd cycle
        // Initialize swap_result with current queue
        for (int i = 0; i < NODES_NEEDED; i++) begin
          swap_result[i] = queue[i];
        end
        for (int lvl = 0; lvl < TREE_DEPTH; lvl++) begin  // Iterate through levels
          if (lvl % 2 == 1 && lvl < TREE_DEPTH - 1) begin  // Process only odd levels (1, 3, 5...)
            for (int i = 0; i < NODES_NEEDED; i++) begin  // Iterate through nodes at this level
              if (i >= ((1 << lvl) - 1) && i < ((1 << (lvl + 1)) - 1)) begin 
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
            end
          end else begin  // Even level
            // Do nothing
          end
        end
      end

      default: begin
        for (int i = 0; i < NODES_NEEDED; i++) begin
          swap_result[i] = queue[i];
        end
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
      even_cycle_flag <= 1'b1;
      settle_cnt      <= '0;  // reset queue is settled
      full            <= 1'b0;
      empty           <= 1'b1;  // size resets to 0
    end else begin
      for (int i = 0; i < NODES_NEEDED; i++) begin
        queue[i] <= next_queue[i];
      end
      size            <= next_size;
      even_cycle_flag <= next_even_cycle_flag;
      settle_cnt      <= next_settle_cnt;
      full            <= next_full;
      empty           <= next_empty;
    end
  end

  // Settled detector: uniform settle countdown (see localparams). head_valid is
  // a compare against a counter flop, not an O(N) heap scan, to keep it off the
  // critical path (that cone failed by ~1ns when flopped)
  always_comb begin : calculate_next_settle_cnt
    if (enqueue || dequeue || replace) begin
      next_settle_cnt = SETTLE_CYCLES[CNT_W-1:0];
    end else if (settle_cnt != 0) begin
      next_settle_cnt = settle_cnt - 1'b1;
    end else begin
      next_settle_cnt = '0;
    end
  end

  assign head_valid = (settle_cnt == 0);

  // Data-adaptive alternative (releases earlier, but puts an O(N) cone on the
  // critical path). This module needs the FULL invariant even without enqueue:
  // it sifts one level-pair/cycle, so root-local reports settled early.
  
  // this decreased FMax but ultimately increased throughput for some queue sizes
  
  //   always_comb begin : heap_invariant_detector
  //     head_valid = 1'b1;
  //     for (int i = 0; i < NODES_NEEDED; i++) begin
  //       if (2*i+1 < NODES_NEEDED && queue[i] < queue[2*i+1]) head_valid = 1'b0;
  //       if (2*i+2 < NODES_NEEDED && queue[i] < queue[2*i+2]) head_valid = 1'b0;
  //     end
  //   end

  // Accepting a command mid-settle would discard the pending heapify (swap_result
  // is applied only in the default branch), so absorb requires the same quiescence.
  assign can_accept = head_valid;

endmodule

`default_nettype none

/*******************************************************************************
  Module Name: register_array_pipelined
  Date: 2026/06/21
  Description: A pipelined version of the register array priority queue that
               splits the array-wide compare-and-swap operation across two
               clock cycles (even-indexed pairs, then odd-indexed pairs) to
               shorten the combinational path and reach higher clock
               frequencies.
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

module register_array_pipelined #(
    parameter bit ENQ_ENA = 1,  // if user would like to enable enqueue
    parameter int QUEUE_SIZE = 4,  // size of the queue
    parameter int DATA_WIDTH = 16  // width of the data
) (
    // Inputs
    input var  logic                  i_CLK,    // clock
    input var  logic                  i_RSTn,   // reset
    input var  logic                  i_wrt,    // push
    input var  logic                  i_read,   // pop
    input var  logic [DATA_WIDTH-1:0] i_data,   // input data
    // Outputs
    output var logic                  o_write_ready,   // High if the queue can accept a write
    output var logic                  o_read_ready,  // High if the queue has data to read
    output var logic [DATA_WIDTH-1:0] o_data    // queue head
);

  localparam int PAIR_COUNT = QUEUE_SIZE / 2;

  logic [DATA_WIDTH-1:0] queue[QUEUE_SIZE];
  logic [DATA_WIDTH-1:0] next_queue[QUEUE_SIZE];
  logic [DATA_WIDTH-1:0] reset_queue[QUEUE_SIZE];
  // logic [DATA_WIDTH-1:0] max[PAIR_COUNT];
  // logic [DATA_WIDTH-1:0] min[PAIR_COUNT];
  logic [DATA_WIDTH-1:0] stage1[QUEUE_SIZE];
  // logic [DATA_WIDTH-1:0] stage2[QUEUE_SIZE];

  logic [$clog2(QUEUE_SIZE):0] size, next_size;

  logic full, empty, enqueue, dequeue, replace, even_cycle_flag, next_even_cycle_flag;
  logic head_valid, can_accept;

  generate
    for (genvar i = 0; i < QUEUE_SIZE; i++) begin : l_gen_reset_queue
      if (!ENQ_ENA) begin
        assign reset_queue[i] = '1;
      end else begin
        assign reset_queue[i] = '0;
      end
    end
  endgenerate

  assign enqueue = (ENQ_ENA && i_wrt && !i_read) ? o_write_ready : 'b0;
  assign dequeue = (!i_wrt && i_read) ? o_read_ready : 'b0;
  assign replace = (i_wrt && i_read) ? (can_accept && head_valid) : 'b0;
  assign full = (size >= QUEUE_SIZE) ? 'b1 : 'b0;
  assign empty = (size <= '0) ? 'b1 : 'b0;

  //   o_write_ready - can you take another value?
  //   o_read_ready  - is o_data trustworthy?
  assign o_write_ready = !full && can_accept;
  assign o_read_ready = !empty && head_valid;
  assign o_data = queue[0];

  always_ff @(posedge i_CLK or negedge i_RSTn) begin
    if (!i_RSTn) begin
      for (int i = 0; i < QUEUE_SIZE; i++) begin
        queue[i] <= reset_queue[i];
      end
      even_cycle_flag <= 1'b1;
      size <= '0;
    end else begin
      for (int i = 0; i < QUEUE_SIZE; i++) begin
        queue[i] <= next_queue[i];
      end
      even_cycle_flag <= next_even_cycle_flag;
      size <= next_size;
    end
  end

  always_comb begin : size_counter
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

  always_comb begin : queue_operation
    int empty_checked;
    empty_checked = QUEUE_SIZE - 1;
    case ({
      enqueue, dequeue, replace
    })
      3'b100: begin  // Enqueue operation (will only be active if ENQ_ENA is high)
        // Shift entire queue to the right by 1
        for (int i = 0; i < QUEUE_SIZE; i++) begin
          stage1[i] = queue[i];
        end
        for (int i = QUEUE_SIZE - 1; i >= 0; i--) begin
          empty_checked = (queue[i] == '0) ? i : empty_checked;
        end
        for (int i = 1; i < QUEUE_SIZE; i++) begin
          stage1[i] = (i <= empty_checked) ? queue[i-1] : queue[i];
        end
        stage1[0] = i_data;
      end
      3'b010: begin
        for (int i = 0; i < QUEUE_SIZE; i++) begin
          stage1[i] = queue[i];
        end
        stage1[0] = '0;
      end
      3'b001: begin
        for (int i = 0; i < QUEUE_SIZE; i++) begin
          stage1[i] = queue[i];
        end
        stage1[0] = i_data;
      end
      default: begin
        for (int i = 0; i < QUEUE_SIZE; i++) begin
          stage1[i] = queue[i];
        end
      end
    endcase
  end

  always_comb begin : next_queue_calc
    case (even_cycle_flag)
      1'b1: begin  // Even cycle
        for (int i = 0; i < QUEUE_SIZE; i++) begin
          next_queue[i] = stage1[i];
        end
        for (int i = 0; i < PAIR_COUNT; i++) begin
          if (stage1[2*i+1] > stage1[2*i]) begin
            // Swap if element at odd index is greater than element at even index
            next_queue[2*i]   = stage1[2*i+1];
            next_queue[2*i+1] = stage1[2*i];
          end else begin
            next_queue[2*i]   = stage1[2*i];
            next_queue[2*i+1] = stage1[2*i+1];
          end
        end
        next_even_cycle_flag = 1'b0;
      end

      1'b0: begin  // Odd cycle
        for (int i = 0; i < QUEUE_SIZE; i++) begin
          next_queue[i] = stage1[i];
        end
        for (int i = 0; i < PAIR_COUNT - 1; i++) begin
          if (stage1[2*i+2] > stage1[2*i+1]) begin
            // Swap if element at even index is greater than previous odd index
            next_queue[2*i+1] = stage1[2*i+2];
            next_queue[2*i+2] = stage1[2*i+1];
          end else begin
            next_queue[2*i+1] = stage1[2*i+1];
            next_queue[2*i+2] = stage1[2*i+2];
          end
        end
        next_even_cycle_flag = 1'b1;
      end

      default: begin
        for (int i = 0; i < QUEUE_SIZE; i++) begin
          next_queue[i] = stage1[i];
        end
        next_even_cycle_flag = 1'b1;
      end
    endcase
  end


  assign head_valid = (queue[0] >= queue[1]);
  assign can_accept = head_valid;

endmodule

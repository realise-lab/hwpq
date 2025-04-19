`default_nettype none

module register_array_cycled #(
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
    output var logic                  o_full,   // queue full
    output var logic                  o_empty,  // queue empty
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

  generate
    for (genvar i = 0; i < QUEUE_SIZE; i++) begin : l_gen_reset_queue
      assign reset_queue[i] = '0;
    end
  endgenerate

  assign enqueue = (ENQ_ENA && i_wrt && !i_read) ? 'b1 : 'b0;
  assign dequeue = (!i_wrt && i_read) ? 'b1 : 'b0;
  assign replace = (i_wrt && i_read) ? 'b1 : 'b0;
  assign full = (size >= QUEUE_SIZE) ? 'b1 : 'b0;
  assign empty = (size <= '0) ? 'b1 : 'b0;
  assign o_full = full;
  assign o_empty = empty;
  assign o_data = queue[0];

  always_ff @(posedge i_CLK or negedge i_RSTn) begin
    if (!i_RSTn) begin
      queue <= reset_queue;
      even_cycle_flag <= 1'b1;
      size <= '0;
    end else begin
      queue <= next_queue;
      even_cycle_flag <= next_even_cycle_flag;
      size <= next_size;
    end
  end

  always_comb begin : size_counter
    case ({
      enqueue, dequeue, replace
    })
      3'b100: next_size = size + 1;
      3'b010: next_size = size - 1;
      3'b001:
      next_size = (size == '0 && i_data != '0) ? size+1 :
                           (size != '0 && i_data == '0) ? size-1 :
                           size;
      default: next_size = size;
    endcase
  end

  always_comb begin : queue_operation
    case ({
      enqueue, dequeue, replace
    })
      3'b100: begin  // Enqueue operation (will only be active if ENQ_ENA is high)
        // Shift entire queue to the right by 1, if the last element is not empty
        // leave it unchanged.
        for (int i = 1; i < QUEUE_SIZE; i++) begin
          stage1[i] = (i == QUEUE_SIZE - 1 && queue[i] != '0) ? queue[i] : queue[i-1];
        end
        stage1[0] = i_data;
      end
      3'b010: begin
        stage1 = queue;
        stage1[0] = '0;
      end
      3'b001: begin
        stage1 = queue;
        stage1[0] = i_data;
      end
      default: stage1 = queue;
    endcase
  end

  always_comb begin : next_queue_calc
    case (even_cycle_flag)
      1'b1: begin  // Even cycle
        next_queue = stage1;
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
        next_queue = stage1;
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
        next_queue = stage1;
        next_even_cycle_flag = 1'b1;
      end
    endcase
  end

endmodule

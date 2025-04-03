`default_nettype none

module RegisterArray #(
    parameter bit ENQ_ENA = 0,    // if user would like to enable enqueue
    parameter int QUEUE_SIZE = 4, // size of the queue
    parameter int DATA_WIDTH = 16 // width of the data
) (
    // Inputs
    input  var logic                  i_CLK,    // clock
    input  var logic                  i_RSTn,   // reset
    input  var logic                  i_wrt,    // push
    input  var logic                  i_read,   // pop
    input  var logic [DATA_WIDTH-1:0] i_data,   // input data
    // Outputs
    output var logic                  o_full,   // queue full
    output var logic                  o_empty,  // queue empty
    output var logic [DATA_WIDTH-1:0] o_data    // queue head
);

  localparam int PAIR_COUNT = QUEUE_SIZE / 2;

  logic [DATA_WIDTH-1:0] queue[QUEUE_SIZE];
  logic [DATA_WIDTH-1:0] next_queue[QUEUE_SIZE];
  logic [DATA_WIDTH-1:0] reset_queue[QUEUE_SIZE];
  logic [DATA_WIDTH-1:0] max[PAIR_COUNT];
  logic [DATA_WIDTH-1:0] min[PAIR_COUNT];
  logic [DATA_WIDTH-1:0] stage1[QUEUE_SIZE];
  logic [DATA_WIDTH-1:0] stage2[QUEUE_SIZE];

  logic [$clog2(QUEUE_SIZE):0] size, next_size;

  logic full, empty, enqueue, dequeue, replace;

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
      size <= '0;
    end else begin
      queue <= next_queue;
      size  <= next_size;
    end
  end

  always_comb begin : size_counter
    case ({enqueue, dequeue, replace})
      3'b100 : next_size = size + 1;
      3'b010 : next_size = size - 1;
      3'b001 : next_size = (size == '0 && i_data != '0) ? size + 1 :
                           (size != '0 && i_data == '0) ? size - 1 :
                           size;
      default : next_size = size;
    endcase
  end

  always_comb begin : queue_operation
    automatic logic empty_found;
    empty_found = 0;
    case ({enqueue, dequeue, replace})
      3'b100 : begin // Enqueue operation (will only be active if ENQ_ENA is high)
        for (int i = 0; i < QUEUE_SIZE; i++) begin
          if (!empty_found && queue[i] == '0) begin
            stage1[i] = i_data;
            empty_found = 1;
          end else begin
            stage1[i] = queue[i];
          end
        end
      end
      3'b010 : begin
        stage1 = queue;
        stage1[0] = '0;
      end
      3'b001 : begin
        stage1 = queue;
        stage1[0] = i_data;
      end
      default : stage1 = queue;
    endcase
  end

  always_comb begin : next_queue_calc
    stage2 = queue;
    next_queue = queue;

    for (int i = 0; i < PAIR_COUNT; i++) begin
      if (stage1[2*i] > stage1[2*i+1]) begin
        max[i] = stage1[2*i];
        min[i] = stage1[2*i+1];
      end else begin
        max[i] = stage1[2*i+1];
        min[i] = stage1[2*i];
      end
    end

    for (int i = 0; i < PAIR_COUNT - 1; i++) begin
      stage2[2*i+1] = (min[i] > max[i+1]) ? min[i] : max[i+1];
      stage2[2*i+2] = (min[i] < max[i+1]) ? min[i] : max[i+1];
    end

    next_queue[0] = max[0];
    for (int i = 1; i < QUEUE_SIZE - 1; i++) begin
      next_queue[i] = stage2[i];
    end
    next_queue[QUEUE_SIZE-1] = min[PAIR_COUNT-1];
  end

endmodule


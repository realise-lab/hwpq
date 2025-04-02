`default_nettype none

module RegisterArray #(
    parameter int QUEUE_SIZE = 4,  // Define the size of the queue
    parameter int DATA_WIDTH = 16  // Define the width of the data
) (
    input  var logic                  i_CLK,    // Clock signal
    input  var logic                  i_RSTn,   // Reset signal
    // Inputs
    input  var logic                  i_wrt,    // Signal to indicate write
    input  var logic                  i_read,   // Signal to indicate read
    input  var logic [DATA_WIDTH-1:0] i_data,   // New entry to be inserted
    // Outputs
    output var logic                  o_full,   // Signal to indicate full
    output var logic                  o_empty,  // Signal to indicate empty
    output var logic [DATA_WIDTH-1:0] o_data    // Output the maximum entry
);


  //--------------------------------------------------------------------------
  // Local parameters
  //--------------------------------------------------------------------------
  localparam int PAIR_COUNT = QUEUE_SIZE / 2;  // number of pairs in the queue

  //--------------------------------------------------------------------------
  // Internal used wires and registers
  //--------------------------------------------------------------------------
  // Main register array for the queue.
  logic [DATA_WIDTH-1:0] queue[QUEUE_SIZE];
  logic [DATA_WIDTH-1:0] next_queue[QUEUE_SIZE];
  logic [DATA_WIDTH-1:0] reset_queue[QUEUE_SIZE];

  // Size counter for number of valid elements in the queue.
  logic [$clog2(QUEUE_SIZE):0] size, next_size;

  // Temporary signals for max-min pipeline computations.
  logic [DATA_WIDTH-1:0] max[PAIR_COUNT];
  logic [DATA_WIDTH-1:0] min[PAIR_COUNT];
  logic [DATA_WIDTH-1:0] stage1[QUEUE_SIZE];
  logic [DATA_WIDTH-1:0] stage2[QUEUE_SIZE];

  // Interal signals
  logic full, empty, enqueue, dequeue, replace;


  generate
    for (genvar i = 0; i < QUEUE_SIZE; i++) begin : l_gen_reset_queue
      assign reset_queue[i] = '0;
    end
  endgenerate

  //--------------------------------------------------------------------------
  // Output assignments.
  //--------------------------------------------------------------------------
  assign enqueue = (i_wrt && !i_read) ? 'b1 : 'b0;
  assign dequeue = (!i_wrt && i_read) ? 'b1 : 'b0;
  assign replace = (i_wrt && i_read) ? 'b1 : 'b0;
  assign full = (size >= QUEUE_SIZE) ? 'b1 : 'b0;
  assign empty = (size <= '0) ? 'b1 : 'b0;
  assign o_full = full;
  assign o_empty = empty;
  assign o_data = queue[0];

  //--------------------------------------------------------------------------
  // Sequential Logic: Register Updates
  //--------------------------------------------------------------------------
  always_ff @(posedge i_CLK or negedge i_RSTn) begin
    if (!i_RSTn) begin
      queue <= reset_queue;
      size <= '0;
    end else begin
      queue <= next_queue;
      size  <= next_size;
    end
  end

  //--------------------------------------------------------------------------
  // Next-State Calculation for 'size'
  //--------------------------------------------------------------------------
  always_comb begin : size_counter
    case ({enqueue, dequeue, replace})
      3'b100 : next_size = size + 1;
      3'b010 : next_size = size - 1;
      3'b001 : next_size = (size == '0 && i_data != '0) ? size + 1 : size;
      default : next_size = size;
    endcase
  end

  //--------------------------------------------------------------------------
  // Next-State Calculation for 'queue'
  //--------------------------------------------------------------------------
  always_comb begin : next_queue_calc
    stage1 = queue;
    stage2 = queue;
    next_queue = queue;

    case ({enqueue, dequeue, replace})
      3'b100 : begin
        for (int i = 1; i < QUEUE_SIZE; i++) begin
          stage1[i] = queue[i-1];
        end
        stage1[0] = i_data;
      end
      3'b010 : begin
        stage1[0] = '0;
      end
      3'b001 : begin
        stage1[0] = i_data;
      end
      default : stage1 = queue;
    endcase

    // --- Pipeline (max-min) Computation ---
    // Compute pairwise max and min.
    for (int i = 0; i < PAIR_COUNT; i++) begin
      if (stage1[2*i] > stage1[2*i+1]) begin
        max[i] = stage1[2*i];
        min[i] = stage1[2*i+1];
      end else begin
        max[i] = stage1[2*i+1];
        min[i] = stage1[2*i];
      end
    end
    // Combine adiacent pairs.
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

/*
    this is an implementation of the register-array verilog pseudocode proposed by Huang 2014
    Paper
*/
module register_array #(
    parameter int QUEUE_SIZE = 4,  // Define the size of the queue
    parameter int DATA_WIDTH = 16  // Define the width of the data
) (
    input  logic                  CLK,      // Clock signal
    input  logic                  RSTn,     // Reset signal
    // Inputs
    input  logic                  i_wrt,    // Signal to indicate write
    input  logic                  i_read,   // Signal to indicate read
    input  logic [DATA_WIDTH-1:0] i_data,   // New entry to be inserted
    // Outputs
    output logic                  o_full,   // Signal to indicate full
    output logic                  o_empty,  // Signal to indicate empty
    output logic [DATA_WIDTH-1:0] o_data    // Output the maximum entry
);


  /*
    Local parameters
  */
  localparam int PairCount = QUEUE_SIZE / 2;  // number of pairs in the queue


  /*
    Internal wires and registers
  */
  logic [DATA_WIDTH-1:0] queue[QUEUE_SIZE];
  logic [DATA_WIDTH-1:0] tmp_queue_stage1[QUEUE_SIZE];
  logic [DATA_WIDTH-1:0] tmp_queue_stage2[QUEUE_SIZE];
  logic [DATA_WIDTH-1:0] tmp_input_reg;
  logic [DATA_WIDTH-1:0] max[PairCount];
  logic [DATA_WIDTH-1:0] min[PairCount];
  int size;


  always_ff @(posedge CLK or negedge RSTn) begin : size_counter
    if (!RSTn) begin
      size <= 0;
    end else begin
      if (i_wrt && !i_read) begin  // enqueue
        size <= size + 1;
      end else if (!i_wrt && i_read) begin  // dequeue
        size <= size - 1;
      end else begin  // replace or no operation
        size <= size;
      end
    end
  end

  always_ff @(posedge CLK or negedge RSTn) begin : queue_update
    if (!RSTn) begin
      for (int i = 0; i < QUEUE_SIZE; i++) begin
        queue[i] <= '0;  // Initialize array entries with 0, since it's gonna be a max queue
        tmp_queue_stage1[i] <= '0;  // intermediate stage 1
        tmp_queue_stage2[i] <= '0;  // intermediate stage 2
      end
    end else begin
      queue <= tmp_queue_stage2;
      if (i_wrt && !i_read) begin  // enqueue
        queue[size] <= i_data;
      end else if (!i_wrt && i_read) begin  // dequeue
        queue[0] <= '0;
      end else if (i_wrt && i_read) begin  // replace
        queue[0] <= i_data;
      end
    end
  end

  always_comb begin : max_min_calc
    for (int i = 0; i < PairCount; i++) begin
      max[i] = (queue[2*i] > queue[2*i+1]) ? queue[2*i] : queue[2*i+1];
      min[i] = (queue[2*i] < queue[2*i+1]) ? queue[2*i] : queue[2*i+1];
    end
    for (int i = 0; i < PairCount - 1; i++) begin
      tmp_queue_stage1[2*i+1] = (min[i] > max[i+1]) ? min[i] : max[i+1];
      tmp_queue_stage1[2*i+2] = (min[i] < max[i+1]) ? min[i] : max[i+1];
    end
    tmp_queue_stage2[0] = max[0];
    for (int i = 1; i < QUEUE_SIZE - 1; i++) begin
      tmp_queue_stage2[i] = tmp_queue_stage1[i];
    end
    tmp_queue_stage2[QUEUE_SIZE-1] = min[PairCount-1];
  end

  /*
    Wire assignments
  */
  assign o_data  = queue[0];
  assign o_full  = (size == QUEUE_SIZE);
  assign o_empty = (size == 0);

endmodule

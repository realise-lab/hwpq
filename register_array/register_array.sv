/*
    this is an implementation of the register-array verilog pseudocode proposed by Huang 2014
    Paper
*/
module register_array #(
    parameter integer QUEUE_SIZE = 16,  // Define the size of the queue
    parameter integer DATA_WIDTH = 16   // Define the width of the data
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
  localparam integer PairCount = QUEUE_SIZE / 2;  // number of pairs in the queue


  // Main register array for the queue.
  logic [DATA_WIDTH-1:0] queue[QUEUE_SIZE-1:0];
  // Next-state version of the queue
  logic [DATA_WIDTH-1:0] next_queue[QUEUE_SIZE-1:0];


  // Size counter for number of valid elements in the queue.
  logic [$clog2(QUEUE_SIZE):0] size, next_size;


  // Temporary signals for max-min pipeline computations.
  logic [DATA_WIDTH-1:0] max[PairCount-1:0];
  logic [DATA_WIDTH-1:0] min[PairCount-1:0];
  logic [DATA_WIDTH-1:0] stage1[QUEUE_SIZE-1:0];
  logic [DATA_WIDTH-1:0] stage2[QUEUE_SIZE-1:0];


  integer i, j;  // for loop index


  //--------------------------------------------------------------------------
  // Next-State Calculation for 'size'
  //--------------------------------------------------------------------------

  always_comb begin : size_track
    if (i_wrt && !i_read) begin  // Enqueue
      next_size = size + 1;
    end else if (!i_wrt && i_read) begin  // Dequeue
      next_size = size - 1;
    end else begin  // Replace & No-op
      next_size = size;
    end
  end

  always_comb begin : next_queue_calc
    // --- Incorporate Shifting/Inserting Based on Control Signals ---
    if (i_wrt && !i_read) begin  // Enqueue
      // Shift right and insert new element at the front.
      stage1[0] = i_data;
      for (j = 1; j < QUEUE_SIZE; j++) begin
        stage1[j] = queue[j-1];
      end
    end else if (!i_wrt && i_read) begin  // Dequeue
      // Remove the first element.
      stage1[0] = '0;
      for (j = 1; j < QUEUE_SIZE; j++) begin
        stage1[j] = queue[j];
      end
    end else if (i_wrt && i_read) begin  // Replace
      // Replace the first element.
      stage1[0] = i_data;
      for (j = 1; j < QUEUE_SIZE; j++) begin
        stage1[j] = queue[j];
      end
    end else begin  // No-op
      stage1 = queue;
    end

    // --- Pipeline (max-min) Computation ---
    // Compute pairwise max and min.
    for (j = 0; j < PairCount; j++) begin
      if (stage1[2*j] > stage1[2*j+1]) begin
        max[j] = stage1[2*j];
        min[j] = stage1[2*j+1];
      end else begin
        max[j] = stage1[2*j+1];
        min[j] = stage1[2*j];
      end
    end

    // Combine adjacent pairs.
    for (j = 0; j < PairCount - 1; j++) begin
      stage2[2*j+1] = (min[j] > max[j+1]) ? min[j] : max[j+1];
      stage2[2*j+2] = (min[j] < max[j+1]) ? min[j] : max[j+1];
    end

    next_queue[0] = max[0];
    for (j = 1; j < QUEUE_SIZE - 1; j++) begin
      next_queue[j] = stage2[j];
    end
    next_queue[QUEUE_SIZE-1] = min[PairCount-1];
  end

  //--------------------------------------------------------------------------
  // Sequential Logic: Register Updates
  //
  // This always_ff block updates both 'queue' and 'size' with their
  // computed next-state values. There is now a single driver for each.
  //--------------------------------------------------------------------------

  always_ff @(posedge CLK or negedge RSTn) begin
    if (!RSTn) begin
      size <= '0;
      for (i = 0; i < QUEUE_SIZE; i++) begin
        queue[i] <= '0;
      end
    end else begin
      size  <= next_size;
      queue <= next_queue;
    end
  end

  //--------------------------------------------------------------------------
  // Output assignments.
  //--------------------------------------------------------------------------
  assign o_data  = queue[0];
  assign o_full  = (size == QUEUE_SIZE);
  assign o_empty = (size == 0);

endmodule

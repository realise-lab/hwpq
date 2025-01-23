/*
    this is an implementation of the register-array verilog pseudocode proposed by Huang 2014
    Paper
*/

module register_array #(
    parameter int QUEUE_SIZE = 8,  // Define the size of the queue
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

  localparam int PairCount = (QUEUE_SIZE + 1) / 2;  // Calculate the number of pairs

  logic [DATA_WIDTH-1:0] register[QUEUE_SIZE];  // Array to hold the register values

  logic [DATA_WIDTH-1:0] tmp_register[QUEUE_SIZE];  // Temporary register array

  logic [DATA_WIDTH-1:0] max[PairCount];  // Adjusted size for max array
  logic [DATA_WIDTH-1:0] min[PairCount];  // Adjusted size for min array

  int size = 0;

  always_ff @(posedge CLK or negedge RSTn) begin
    if (!RSTn) begin
      for (int j = 0; j < QUEUE_SIZE; j++) begin
        register[j] <= '0;  // Initialize tree entries with 0
        tmp_register[j] <= '0;
        size <= 0;
      end
    end else begin
      for (int i = 0; i < QUEUE_SIZE; i++) begin
        register[i] <= tmp_register[i];  // Update the register with temporary register values
      end
      if (i_wrt && !i_read) begin  // enqueue
        register[size] <= i_data;
        size <= size + 1;
      end else if (!i_wrt && i_read) begin  // dequeue
        register[0] <= '0;
        size <= size - 1;
      end else if (i_wrt && i_read) begin  // replace
        register[0] <= i_data;
      end
    end
  end

  always_comb begin
    // Copy register values to temporary register
    for (int i = 0; i < QUEUE_SIZE; i++) begin
      tmp_register[i] = register[i];
    end

    // Calculate max and min for pairs
    for (int i = 0; i < PairCount; i++) begin
      if ((2 * i + 1) < QUEUE_SIZE) begin
        max[i] = (register[2*i] > register[2*i+1]) ? register[2*i] : register[2*i+1];
        min[i] = (register[2*i] < register[2*i+1]) ? register[2*i] : register[2*i+1];
      end else begin
        max[i] = register[2*i];  // Only one element left
        min[i] = register[2*i];  // Only one element left
      end
    end

    // Update temporary register with min/max
    for (int i = 0; i < PairCount; i++) begin
      tmp_register[2*i-1] = (min[i-1] > max[i]) ? min[i-1] : max[i];
      tmp_register[2*i]   = (min[i-1] < max[i]) ? min[i-1] : max[i];
    end

    tmp_register[0] = max[0];
  end

  assign o_data  = register[0];
  assign o_full  = (size == QUEUE_SIZE);
  assign o_empty = (size == 0);

endmodule

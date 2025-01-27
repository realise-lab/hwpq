module systolic_array #(
    parameter int QUEUE_SIZE = 8,  // Size of the buffers (number of positions)
    parameter int DATA_WIDTH = 16  // Width of the node data (evaluation function value 'f')
) (
    input logic CLK,
    input logic RSTn,

    // Input
    input logic                  i_wrt,   // Enqueue signal
    input logic                  i_read,  // Dequeue signal
    input logic [DATA_WIDTH-1:0] i_data,  // Node data input

    // Output
    output logic                  o_full,   // Queue is full
    output logic                  o_empty,  // Queue is empty
    output logic [DATA_WIDTH-1:0] o_data    // Node data output
);

  // Constant
  localparam logic [DATA_WIDTH-1:0] MaxValue = '1;  // Represents the maximum value

  // Input Buffer (IB) and Output Buffer (OB)
  logic   [DATA_WIDTH-1:0] IB                  [  QUEUE_SIZE/2];
  logic   [DATA_WIDTH-1:0] OB                  [  QUEUE_SIZE/2];

  // Registers to store comparison results
  logic                    IB_less_than_OB     [  QUEUE_SIZE/2];
  logic                    IB_less_than_IB_next[QUEUE_SIZE/2-1];
  logic                    IB_less_than_OB_next[QUEUE_SIZE/2-1];
  logic                    OB_next_less_than_OB[QUEUE_SIZE/2-1];

  // Control signals
  integer                  size;
  integer                  size_next;
  logic                    full;
  logic                    empty;

  assign full  = (size == QUEUE_SIZE);
  assign empty = (size == 0);

  // Sequential logic
  always_ff @(posedge CLK or negedge RSTn) begin
    if (!RSTn) begin  // Reset
      size <= 0;
      for (int i = 0; i < QUEUE_SIZE; i++) begin
        IB[i] <= MaxValue;  // initialize IB to MaxValue, since this is a min-queue
        OB[i] <= MaxValue;  // initialize OB to MaxValue, since this is a min-queue
      end
    end else begin
      // Dequeue operation
      if (i_read && !i_wrt && !empty) begin
        OB[0] <= MaxValue;  // pop the head of OB
      end

      // Enqueue operation
      if (i_wrt && !i_read && !full) begin
        IB[0] <= i_data;  // insert the new node at the head of IB
      end

      // Replace operation
      if (i_wrt && i_read) begin
        if (full) begin
          IB[0] <= i_data;  // replace the head of IB
          OB[0] <= MaxValue;  // pop the head of OB
        end else if (empty) begin
          OB[0] <= i_data;  // insert the new node at the head of OB
        end else begin
          IB[0] <= i_data;  // replace the head of IB
          OB[0] <= MaxValue;  // pop the head of OB
        end
      end

      // update size
      size <= size_next;

      // Sorting logic
      for (int i = 0; i < QUEUE_SIZE; i++) begin  // Iterate through each element
        priority case (1'b1)
          IB_less_than_OB[i]: begin
            IB[i] <= OB[i];
            OB[i] <= IB[i];
          end

          (i != QUEUE_SIZE - 1) && OB_next_less_than_OB[i]: begin  // OB[i+1] < OB[i]
            // Swap OB[i] and OB[i+1]
            OB[i+1] <= OB[i];
            OB[i]   <= OB[i+1];
          end

          (i != QUEUE_SIZE - 1) && IB_less_than_OB_next[i] && (IB[i+1] == MaxValue): begin
            // Move IB[i] to OB[i+1], and move OB[i+1] to IB[i+1]
            OB[i+1] <= IB[i];
            IB[i+1] <= OB[i+1];
            IB[i]   <= MaxValue;
          end

          (i != QUEUE_SIZE - 1) && IB_less_than_IB_next[i]: begin  // IB[i] < IB[i+1]
            // Swap IB[i] and IB[i+1]
            IB[i+1] <= IB[i];
            IB[i]   <= IB[i+1];
          end

          default: begin
            // No action needed
          end
        endcase
      end
    end
  end

  // Combinational logic
  always_comb begin
    // comparsion results
    for (int i = 0; i < QUEUE_SIZE; i++) begin
      IB_less_than_OB[i] = IB[i] < OB[i];
    end
    for (int i = 0; i < QUEUE_SIZE - 1; i++) begin
      IB_less_than_OB_next[i] = IB[i] < OB[i+1];
      IB_less_than_IB_next[i] = IB[i] < IB[i+1];
      OB_next_less_than_OB[i] = OB[i+1] < OB[i];
    end

    // compute size_next
    if (i_wrt && !i_read && !full) begin
      size_next = size + 1;
    end else if (!i_wrt && i_read && !empty) begin
      size_next = size - 1;
    end else if (i_wrt && i_read && !full && !empty) begin
      size_next = size;
    end else if (i_wrt && i_read && full && !empty) begin
      size_next = size;
    end else if (i_wrt && i_read && !full && empty) begin
      size_next = size + 1;
    end else begin
      size_next = size;
    end

  end

  // Output assignments
  assign o_full  = full;
  assign o_empty = empty;
  assign o_data  = OB[0];

endmodule

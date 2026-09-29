`default_nettype none

/*******************************************************************************
  Module Name: systolic_array
  Date: 2026/06/18
  Description: A priority queue implementation using a systolic array of an
               input buffer (IB) and output buffer (OB). New nodes shift
               through the IB, swapping bubble-sort style with adjacent OB
               nodes so higher-priority values migrate into the
               OB; dequeuing the OB head propagates a "bubble" back through
               the array to refill it. The module reserves MIN_VALUE to
               represent an invalid entry, which is reflected in the test
               benches avoiding writing 0.
  Parameters: QUEUE_SIZE - Maximum number of elements in the priority queue
              DATA_WIDTH - Bit width of the node's evaluation value (f)
  Inputs: i_CLK - System clock
          i_RSTn - Active-low reset signal
          i_wrt - Enqueue signal
          i_read - Dequeue signal
          i_data - Node data input
  Outputs: o_write_ready - High when the queue has room to accept a write
           o_read_ready - High when the queue holds data available to read
           o_data - Node data output (highest priority element)
*******************************************************************************/

`default_nettype none

// this module cannot use the MIN_VALUE, we treat the MIN_VALUE as an invalid

module systolic_array #(
    parameter int QUEUE_SIZE = 128,  // Size of the buffers (number of positions)
    parameter int DATA_WIDTH = 16  // Width of the node data (evaluation function value 'f')
) (
    input var logic                   i_CLK,
    input var logic                   i_RSTn,

    // Input
    input var logic                   i_wrt,   // Enqueue signal
    input var logic                   i_read,  // Dequeue signal
    input var logic [DATA_WIDTH-1:0]  i_data,  // Node data input

    // Output
    output var logic [DATA_WIDTH-1:0] o_data,    // Node data output
    output var logic                  o_write_ready, // High if systolic is full
    output var logic                  o_read_ready

);

  // Constant
  localparam int MIN_VALUE = 0;  // Represents the minimum value for a max-queue
  localparam int HALF_SIZE = QUEUE_SIZE / 2;

  // Input Buffer (IB) and Output Buffer (OB)
  logic   [DATA_WIDTH-1:0] IB                  [HALF_SIZE];
  logic   [DATA_WIDTH-1:0] OB                  [HALF_SIZE];

  // Registers to store comparison results
  logic                    IB_greater_than_OB     [HALF_SIZE];
  logic                    IB_greater_than_IB_next[HALF_SIZE-1];
  logic                    IB_greater_than_OB_next[HALF_SIZE-1];
  logic                    OB_next_greater_than_OB[HALF_SIZE-1];

  logic                    IB_shift               [HALF_SIZE-1];
  logic                    IB_shift_valid               [HALF_SIZE-1];

  logic                    OB_shift               [HALF_SIZE-1];
  logic                    OB_shift_valid         [HALF_SIZE-1];

  logic                    IB_shift_to_OB         [HALF_SIZE-1];

  // Control signals
  int                      size;
  int                      size_next;
  logic                    full;
  logic                    empty;

  assign full  = (size >= QUEUE_SIZE - 2);
  assign empty = (size <= 0);
  assign o_data  = OB[0];
  // we need 2 empty spaces for the systolic to work, and we cannot write/read right after a read
  assign o_write_ready = !(size >= (QUEUE_SIZE - 3)) && (o_data != MIN_VALUE || empty); 
  assign o_read_ready = !empty && (o_data != MIN_VALUE);

  // Sequential logic
  always_ff @(posedge i_CLK or negedge i_RSTn) begin
    if (!i_RSTn) begin  // Reset
      size <= 0;
      for (int i = 0; i < HALF_SIZE; i++) begin
        IB[i] <= MIN_VALUE;  // initialize IB to MIN_VALUE, since this is a max-queue
        OB[i] <= MIN_VALUE;  // initialize OB to MIN_VALUE, since this is a max-queue
      end
    end else begin

      // Dequeue operation
      if (i_read && !i_wrt && !empty) begin
        OB[0] <= MIN_VALUE;  // pop the head of OB
      end

      // Enqueue operation
      if (i_wrt && !i_read && !full) begin
        if (i_data > OB[0]) begin
          OB[0] <= i_data;
          IB[0] <= OB[0];
        end else begin
          IB[0] <= i_data;  // insert the new node at the head of IB
        end
      end

      // Replace operation
      if (i_wrt && i_read) begin
        if (empty) begin
          OB[0] <= i_data;  // insert the new node at the head of OB
        end else begin
          IB[0] <= i_data;  // replace the head of IB
          OB[0] <= MIN_VALUE;  // pop the head of OB
        end
      end

      // update size
      size <= size_next;

      // Sorting logic
      for (int i = 0; i < HALF_SIZE; i++) begin  // Iterate through each element
        priority case (1'b1)
          OB_shift[i] && OB_shift_valid[i]: begin
            OB[i] <= OB[i+1]; 
            if ((i == (HALF_SIZE - 2) || !OB_shift_valid[i+1] || !IB_shift_to_OB[i+1] || !OB_shift[i+1] || (OB[i+2] == 0))) OB[i+1] <= MIN_VALUE;
          end
          default: begin
            // No action needed
          end
        endcase

        priority case (1'b1)
          IB_shift[i] && IB_shift_valid[i]: begin
            // We slide this value down
            IB[i+1] <= IB[i];
            if ((i == 0 && !i_wrt) || (i > 0 && !IB_shift_valid[i-1])) IB[i] <= MIN_VALUE;
          end
          default: begin
            // No action needed
          end
        endcase

        priority case (1'b1)
          OB_next_greater_than_OB[i] && !OB_shift_valid[i] && !IB_greater_than_OB[i]
          && (i > 0 && !IB_greater_than_OB_next[i-1]): begin
            // If we cannot shift, we can swap
            OB[i+1] <= OB[i];
            OB[i] <= OB[i+1];
          end

          IB_shift_to_OB[i]: begin
            // if OB is shifting while we want to swap in, we can just swap down instead
            OB[i] <= IB[i];
            if (!(IB_shift[i-1] && IB_shift_valid[i-1])) IB[i] <= MIN_VALUE;
          end

          IB_greater_than_OB[i] && !(i < (HALF_SIZE-1) && OB_shift[i] && OB_shift_valid[i]): begin
            IB[i] <=  OB[i];
            OB[i] <=  IB[i];
          end

          IB_greater_than_OB_next[i] && (!IB_greater_than_OB[i+1])
          && ((IB[i+1] == 0) || (IB_greater_than_OB_next[i+1]) || (IB_shift[i+1])) && IB_shift_valid[i]: begin
            // Move IB[i] to OB[i+1], and move OB[i+1] to IB[i+1]
            OB[i+1] <= IB[i];
            IB[i+1] <= OB[i+1];
            // if we are also writing this cycle, we need to replace the value with i_data or OB[0] is i_data > OB[0]
            if (i == 0 && i_wrt) begin
              if (i_data > OB[0] && !i_read) begin
                IB[i] <= OB[0];
              end else begin
                IB[i] <= i_data;
              end
            end
            if ((i > 0 && (IB_shift_to_OB[i-1] || IB_greater_than_OB[i-1])) || (i == 0 && !i_wrt)) begin
              IB[i] <= MIN_VALUE;
            end
          end

          IB_greater_than_OB_next[i] && !IB_shift_valid[i] && !IB_greater_than_OB[i+1]: begin
            // If we cannot shift, we can swap
            IB[i] <= OB[i+1];
            OB[i+1] <= IB[i];
          end

          IB_greater_than_IB_next[i] && !IB_shift_valid[i]
          && ((i == (HALF_SIZE - 2)) || (!IB_greater_than_IB_next[i+1] && !IB_greater_than_OB_next[i+1]))
          && (!IB_greater_than_OB[i+1]): begin
            // If we cannot shift, we can swap
            IB[i] <= IB[i+1];
            IB[i+1] <= IB[i];
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

    for (int i=0; i<HALF_SIZE-1;i++) begin
      OB_shift[i] = (OB[i+1] >= IB[i]) && (OB[i+1] >= IB[i+1]) && (OB[i+1] != MIN_VALUE);
    end 
    OB_shift_valid[0] = OB[0] == 0;
    for (int i=1; i<HALF_SIZE-1;i++) begin
      OB_shift_valid[i] = (OB[i-1] == 0 || OB_shift_valid[i-1]) && OB_shift[i-1];
    end


    // comparsion results
    for (int i = 0; i < HALF_SIZE; i++) begin
      // IB_greater_than_OB should not happen at the front of the array
      IB_greater_than_OB[i] = (IB[i] > OB[i]);
    end
    for (int i = 0; i < HALF_SIZE - 1; i++) begin
      IB_greater_than_OB_next[i] = IB[i] > OB[i+1];
      IB_greater_than_IB_next[i] = IB[i] > IB[i+1];
      OB_next_greater_than_OB[i] = OB[i+1] > OB[i];
      IB_shift_to_OB[i] = IB_greater_than_OB_next[i] && (i > 0 && OB_shift[i-1] && OB_shift_valid[i-1]);
    end

    for (int i=HALF_SIZE-2; i >= 0; i--) begin
      IB_shift[i] = (i < (HALF_SIZE-2) && (IB_greater_than_OB_next[i+1] || IB_greater_than_IB_next[i+1])) || ((IB[i] <= OB[i]) && (IB[i] <= OB[i+1])) || ((OB[i] == 0) && (i == 0) && (IB[i] <= OB[i+1]));
    end
    
    // maybe it should be if it is equal to min_value
    IB_shift_valid[HALF_SIZE-2] = IB[HALF_SIZE-1] == MIN_VALUE;
    for (int i=HALF_SIZE-3; i >= 0; i--) begin
      // we can do shifts if at some point the value ahead of us is 0, otherwise we must swap as there is no room for shifts
      IB_shift_valid[i] = (IB[i+1] == 0 || IB_shift_valid[i+1] || IB_shift_to_OB[i+1]) && !IB_shift_to_OB[i] 
      && !((IB_greater_than_OB[i+1] || IB_greater_than_OB[i]) && !(i < (HALF_SIZE-1) && OB_shift[i] && OB_shift_valid[i]));
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

endmodule

module register_tree #(
  parameter QUEUE_SIZE = 1024,
  parameter DATA_WIDTH = 32
) (
  // Synchronous Control
  input logic CLK,
  input logic RSTn,
  // Inputs
  input logic i_replace,
  input logic [DATA_WIDTH-1:0] i_data,
  // Outputs
  output logic [DATA_WIDTH-1:0] o_data
);

  // Calculate tree depth from queue size
  localparam TREE_DEPTH   = $clog2(QUEUE_SIZE+1);  // depth of the tree
  localparam NODES_NEEDED = 2**TREE_DEPTH - 1;     // number of nodes needed to initialize the tree
  localparam COMP_COUNT   = NODES_NEEDED/2;        // number of comparators

  // Register array to store the tree nodes
  logic [DATA_WIDTH-1:0] queue               [NODES_NEEDED-1:0];

  // Wires to connect the comparator units
  logic [DATA_WIDTH-1:0] new_parent          [COMP_COUNT-1:0];
  logic [DATA_WIDTH-1:0] new_left_child      [COMP_COUNT-1:0];
  logic [DATA_WIDTH-1:0] new_right_child     [COMP_COUNT-1:0];

  // State machine to control even and odd levels
  typedef enum logic [1:0] {
    IDLE              = 2'b00,
    COMPARE_AND_SWAP  = 2'b01,
    REPLACE           = 2'b10
  } state_t;
  state_t current_state, next_state;

  // Generate comparators
  genvar i;
  generate
    for (i = 0; i < COMP_COUNT; i++) begin : comparator_gen
      comparator #(
          .DATA_WIDTH(DATA_WIDTH)
      ) comparator_inst (
          .i_parent(queue[i]),
          .i_left_child(queue[2*i+1]),
          .i_right_child(queue[2*i+2]),
          .o_parent(new_parent[i]),
          .o_left_child(new_left_child[i]),
          .o_right_child(new_right_child[i])
      );
    end
  endgenerate

  integer j, k, m, n;

  // State machine control
  always @(posedge CLK or negedge RSTn) begin
    if (!RSTn) begin
      // REVIEW: Need to check with professor if this is the correct way for doing the reset. 
      for (j = 0; j < NODES_NEEDED; j++) begin 
        if (j >= QUEUE_SIZE) begin
          queue[j] <= '0;
        end else begin
          queue[j] <= (QUEUE_SIZE - j) * 10; // NOTE: this is only needed for the testbench
        end
      end
      current_state <= IDLE;
    end else begin
      case (current_state)
        IDLE: begin
        end

        COMPARE_AND_SWAP: begin
          queue[0] <= new_parent[0];
          queue[1] <= new_left_child[0];
          queue[2] <= new_right_child[0];
        end

        REPLACE: begin
          queue[0] <= i_data;
        end

        default: begin
        end
      endcase
      current_state <= next_state;
    end
  end

  always_comb begin
    case (current_state)
      IDLE: begin
        if (i_replace) begin
          next_state = REPLACE;
        end else begin
          next_state = COMPARE_AND_SWAP;
        end
      end

      COMPARE_AND_SWAP: begin
        // iterate through even levels of the tree
        for (k = 2; k < TREE_DEPTH; k = k + 2) begin
          if (k == TREE_DEPTH-1) begin // no comparators on the last level
            break;
          end else begin
            for (j = 2**k-1; j < 2**(k+1)-1; j++) begin
              queue[j]     = new_parent[j];
              queue[2*j+1] = new_left_child[j];
              queue[2*j+2] = new_right_child[j];
            end
          end
        end
        // iterate through odd levels of the tree
        for (m = 1; m < TREE_DEPTH; m = m + 2) begin
          if (m == TREE_DEPTH-1) begin // no comparators on the last level
            break;
          end else begin
            for (n = 2**m-1; n < 2**(m+1)-1; n++) begin
              queue[n]     = new_parent[n];
              queue[2*n+1] = new_left_child[n];
              queue[2*n+2] = new_right_child[n];
            end
          end
        end
        if (i_replace) begin
          next_state = REPLACE;
        end else begin
          next_state = COMPARE_AND_SWAP;
        end
      end

      REPLACE: begin
        next_state = COMPARE_AND_SWAP;
      end

      default: begin
        next_state = IDLE;
      end
    endcase
  end

  // Assign outputs
  assign o_data = queue[0];

endmodule


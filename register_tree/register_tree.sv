module register_tree #(
  parameter QUEUE_SIZE = 8,
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
  localparam TREE_DEPTH   = $clog2(QUEUE_SIZE);  // depth of the tree
  localparam NODES_NEEDED = (1 << (TREE_DEPTH + 1)) - 1;     // number of nodes needed to initialize the tree
  localparam COMP_COUNT   = NODES_NEEDED/2;        // number of comparators
  // Register array to store the tree nodes
  logic [DATA_WIDTH-1:0] queue        [NODES_NEEDED-1:0];
  // Wires to connect the comparator units
  logic [DATA_WIDTH-1:0] old_parent           [COMP_COUNT-1:0];
  logic [DATA_WIDTH-1:0] old_left_child       [COMP_COUNT-1:0];
  logic [DATA_WIDTH-1:0] old_right_child      [COMP_COUNT-1:0];
  logic [DATA_WIDTH-1:0] new_parent           [COMP_COUNT-1:0];
  logic [DATA_WIDTH-1:0] new_left_child       [COMP_COUNT-1:0];
  logic [DATA_WIDTH-1:0] new_right_child      [COMP_COUNT-1:0];
  // Declare arrays for start and end indices of each level
  logic [$clog2(COMP_COUNT)-1:0] level_start  [TREE_DEPTH-1:0];
  logic [$clog2(COMP_COUNT)-1:0] level_end    [TREE_DEPTH-1:0];
  


  /*
    Generate components and registers
  */
  genvar i, level;
  // Generate comparators
  generate
    for (i = 0; i < COMP_COUNT; i++) begin : comparator_gen
      comparator #(
          .DATA_WIDTH(DATA_WIDTH)
      ) comparator_inst (
          .i_parent(old_parent[i]),
          .i_left_child(old_left_child[i]),
          .i_right_child(old_right_child[i]),
          .o_parent(new_parent[i]),
          .o_left_child(new_left_child[i]),
          .o_right_child(new_right_child[i])
      );
    end
  endgenerate
  // Generate queue initialization
  generate
    for (i = 0; i < NODES_NEEDED; i++) begin : queue_init
      assign queue[i] = (i >= QUEUE_SIZE) ? '0 : (QUEUE_SIZE - i) * 10;
    end
  endgenerate
  // Initialize comparators
  generate
    for (i = 0; i < COMP_COUNT; i++) begin : queue_init_comparators
      assign old_parent[i] = queue[i];
      assign old_left_child[i] = queue[2*i + 1];
      assign old_right_child[i] = queue[2*i + 2];
    end
  endgenerate
  // Generate block to compute level indices
  generate
    for (level = 0; level < TREE_DEPTH; level++) begin : level_indices_calc
      assign level_start[level] = (1 << level) - 1;       // 2^level - 1
      assign level_end[level]   = (1 << (level + 1)) - 2; // 2^(level+1) - 2
    end
  endgenerate



  /*
    State machine control
  */
  typedef enum logic [1:0] {
    IDLE              = 2'b00,
    COMPARE_AND_SWAP  = 2'b01,
    REPLACE           = 2'b10
  } state_t;
  state_t current_state, next_state;

  always @(posedge CLK or negedge RSTn) begin
    if (!RSTn) begin
      current_state <= IDLE;
    end else begin
      current_state <= next_state;
    end
  end

  always_comb begin
    // Default next state assignment
    next_state = IDLE;

    case (current_state)
      IDLE: begin
        if (i_replace) begin
          next_state = REPLACE;
        end else begin
          next_state = COMPARE_AND_SWAP;
        end
      end

      COMPARE_AND_SWAP: begin
        if (i_replace) begin
          next_state = REPLACE;
        end else begin
          next_state = COMPARE_AND_SWAP;
        end
        // update even level comparators' outputs to queue
        for (int lvl = 0; lvl < TREE_DEPTH; lvl = lvl + 2) begin
          for (int j = level_start[lvl]; j <= level_end[lvl]; j++) begin
            queue[j]        = new_parent[j];
            queue[2*j + 1]  = new_left_child[j];
            queue[2*j + 2]  = new_right_child[j];
          end
        end
        // update odd level comparators' outputs to queue
        for (int lvl = 1; lvl < TREE_DEPTH; lvl = lvl + 2) begin
          for (int j = level_start[lvl]; j <= level_end[lvl]; j++) begin
            queue[j]        = new_parent[j];
            queue[2*j + 1]  = new_left_child[j];
            queue[2*j + 2]  = new_right_child[j];
          end
        end
      end

      REPLACE: begin
        next_state = COMPARE_AND_SWAP;
        queue[0] = i_data;
      end

      default: begin 
        next_state = IDLE;
      end
    endcase
  end



  // Assign outputs
  assign o_data = queue[0];

endmodule

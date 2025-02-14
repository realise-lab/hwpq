module register_tree #(
    parameter integer QUEUE_SIZE = 3,
    parameter integer DATA_WIDTH = 16
) (
    // Synchronous Control
    input logic CLK,
    input logic RSTn,
    // Inputs
    input logic i_wrt,
    input logic i_read,
    input logic [DATA_WIDTH-1:0] i_data,
    // Outputs
    output logic o_full,
    output logic o_empty,
    output logic [DATA_WIDTH-1:0] o_data
);

  /*
    Parameters
  */
  localparam integer TreeDepth = $clog2(QUEUE_SIZE);  // depth of the tree
  localparam integer NodesNeeded = (1 << (TreeDepth + 1)) - 1;  // number of nodes needed to initialize
  localparam integer CompCount = NodesNeeded / 2;  // number of comparators

  /*
    Registers
  */
  // Register array to store the tree nodes
  logic [         DATA_WIDTH-1:0] queue          [NodesNeeded];
  // Size counter to keep track of the number of nodes in the queue
  logic [$clog2(NodesNeeded)-1:0] size;
  // Wires to connect the comparator units
  logic [         DATA_WIDTH-1:0] old_parent     [  CompCount];
  logic [         DATA_WIDTH-1:0] old_left_child [  CompCount];
  logic [         DATA_WIDTH-1:0] old_right_child[  CompCount];
  logic [         DATA_WIDTH-1:0] new_parent     [  CompCount];
  logic [         DATA_WIDTH-1:0] new_left_child [  CompCount];
  logic [         DATA_WIDTH-1:0] new_right_child[  CompCount];

  /*
    States
  */
  typedef enum logic [2:0] {
    IDLE                  = 3'b000,
    COMPARE_AND_SWAP_EVEN = 3'b001,
    COMPARE_AND_SWAP_ODD  = 3'b010,
    WRITE_TO_QUEUE        = 3'b011,
    READ_FROM_QUEUE       = 3'b100,
    REPLACE               = 3'b101
  } state_t;
  state_t current_state, next_state;

  /*
    Generate components and initialize registers
  */
  genvar i, level;
  // Generate comparators
  generate
    for (i = 0; i < CompCount; i++) begin : gen_comparator
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

  // Initialize comparators
  generate
    for (i = 0; i < CompCount; i++) begin : gen_comparators_init
      assign old_parent[i] = queue[i];
      assign old_left_child[i] = (2 * i + 1 < NodesNeeded) ? queue[2*i+1] : '0;
      assign old_right_child[i] = (2 * i + 2 < NodesNeeded) ? queue[2*i+2] : '0;
    end
  endgenerate

  /*
    Size Tracker
  */
  always_ff @(posedge CLK or negedge RSTn) begin : size_tracker
    if (!RSTn) begin
      size <= 0;
    end else begin
      case (current_state)
        IDLE: begin
        end

        COMPARE_AND_SWAP_EVEN: begin
        end

        COMPARE_AND_SWAP_ODD: begin
        end

        WRITE_TO_QUEUE: begin
          size <= size + 1;
        end

        READ_FROM_QUEUE: begin
          size <= size - 1;
        end

        REPLACE: begin
        end

        default: begin
        end
      endcase
    end
  end

  /*
    State machine control
  */
  always @(posedge CLK or negedge RSTn) begin : state_machine_control
    if (!RSTn) begin
      current_state <= IDLE;
    end else begin
      current_state <= next_state;
    end
  end

  always_comb begin : state_machine_comb_logic
    // Default next state assignment
    next_state = IDLE;

    case (current_state)
      IDLE: begin
        if (i_wrt && !i_read && size < QUEUE_SIZE) begin
          next_state = WRITE_TO_QUEUE;
        end else if (!i_wrt && i_read && size > 0) begin
          next_state = READ_FROM_QUEUE;
        end else if (i_wrt && i_read) begin
          next_state = REPLACE;
        end else begin
          next_state = COMPARE_AND_SWAP_EVEN;
        end
      end

      COMPARE_AND_SWAP_EVEN: begin
        if (i_wrt && !i_read && size < QUEUE_SIZE) begin
          next_state = WRITE_TO_QUEUE;
        end else if (!i_wrt && i_read && size > 0) begin
          next_state = READ_FROM_QUEUE;
        end else if (i_wrt && i_read) begin
          next_state = REPLACE;
        end else begin
          next_state = COMPARE_AND_SWAP_ODD;
        end
      end

      COMPARE_AND_SWAP_ODD: begin
        if (i_wrt && !i_read && size < QUEUE_SIZE) begin
          next_state = WRITE_TO_QUEUE;
        end else if (!i_wrt && i_read && size > 0) begin
          next_state = READ_FROM_QUEUE;
        end else if (i_wrt && i_read) begin
          next_state = REPLACE;
        end else begin
          next_state = COMPARE_AND_SWAP_EVEN;
        end
      end

      WRITE_TO_QUEUE: begin
        next_state = COMPARE_AND_SWAP_EVEN;
      end

      READ_FROM_QUEUE: begin
        next_state = COMPARE_AND_SWAP_EVEN;
      end

      REPLACE: begin
        next_state = COMPARE_AND_SWAP_EVEN;
      end

      default: begin
        next_state = IDLE;
      end
    endcase
  end

  /*
    Queue Management
  */
  int itr, lvl;
  always_ff @(posedge CLK or negedge RSTn) begin : queue_management
    if (!RSTn) begin
      for (itr = 0; itr < NodesNeeded; itr++) begin
        queue[itr] <= '0;
      end
    end else begin
      case (current_state)
        IDLE: begin
        end

        COMPARE_AND_SWAP_EVEN: begin
          for (lvl = 0; lvl < TreeDepth; lvl = lvl + 2) begin
            // Compute level bounds directly
            automatic int s = (1 << lvl) - 1;  // start index
            automatic int e = (1 << (lvl + 1)) - 2;  // end index
            for (itr = s; itr <= e; itr++) begin
              queue[itr] <= new_parent[itr];
              queue[2*itr+1] <= new_left_child[itr];
              queue[2*itr+2] <= new_right_child[itr];
            end
          end
        end

        COMPARE_AND_SWAP_ODD: begin
          for (lvl = 1; lvl < TreeDepth; lvl = lvl + 2) begin
            // Compute level bounds directly
            automatic int s = (1 << lvl) - 1;  // start index
            automatic int e = (1 << (lvl + 1)) - 2;  // end index
            for (itr = s; itr <= e; itr++) begin
              queue[itr] <= new_parent[itr];
              queue[2*itr+1] <= new_left_child[itr];
              queue[2*itr+2] <= new_right_child[itr];
            end
          end
        end

        WRITE_TO_QUEUE: begin
          for (itr = (1 << TreeDepth) - 1; itr < (1 << (TreeDepth + 1)) - 1; itr++) begin
            if (queue[itr] == '0) begin
              queue[itr] <= i_data;
              break;
            end
          end
        end

        READ_FROM_QUEUE: begin
          queue[0] <= '0;
        end

        REPLACE: begin
          queue[0] <= i_data;
        end

        default: begin
        end
      endcase
    end
  end

  // Assign outputs
  assign o_full  = size == QUEUE_SIZE;
  assign o_empty = size == 0;
  assign o_data  = (size > 0) ? queue[0] : '0;

endmodule

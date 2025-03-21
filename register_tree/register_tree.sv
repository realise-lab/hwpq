module register_tree #(
    parameter integer QUEUE_SIZE = 2047,
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
  localparam integer NodesNeeded = (1 << TreeDepth) - 1;  // number of nodes needed to initialize
  localparam integer CompCount = NodesNeeded / 2;  // number of comparators

  /*
    Registers
  */
  // Register array to store the tree nodes
  logic [DATA_WIDTH-1:0] queue     [NodesNeeded];
  logic [DATA_WIDTH-1:0] next_queue[NodesNeeded];
  logic [DATA_WIDTH-1:0] enqueue_idx, next_enqueue_idx;
  // Size counter to keep track of the number of nodes in the queue
  logic [$clog2(NodesNeeded)-1:0] size;
  logic [$clog2(NodesNeeded)-1:0] next_size;
  logic empty, full;
  // Wires to connect the comparator units
  logic [DATA_WIDTH-1:0] old_parent     [CompCount];
  logic [DATA_WIDTH-1:0] old_left_child [CompCount];
  logic [DATA_WIDTH-1:0] old_right_child[CompCount];
  logic [DATA_WIDTH-1:0] new_parent     [CompCount];
  logic [DATA_WIDTH-1:0] new_left_child [CompCount];
  logic [DATA_WIDTH-1:0] new_right_child[CompCount];

  /*
    States
  */
  typedef enum logic [2:0] {
    IDLE                  = 3'b000,
    COMPARE_AND_SWAP_EVEN = 3'b001,
    COMPARE_AND_SWAP_ODD  = 3'b010,
    ENQUEUE               = 3'b011,
    DEQUEUE               = 3'b100,
    REPLACE               = 3'b101
  } state_t;
  state_t current_state, next_state;

  /*
    Generate components and initialize registers
  */
  genvar i;
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
  always_ff @(posedge CLK or negedge RSTn) begin : queue_size_seq
    if (!RSTn) begin
      size <= 0;
    end else begin
      size <= next_size;
    end
  end

  always_comb begin : size_comb
    next_size = size;
    if (i_wrt && !i_read) begin  // enqueue
      next_size = size + 1;
    end else if (!i_wrt && i_read) begin  // dequeue
      next_size = size - 1;
    end else if (i_wrt && i_read) begin  // replace
      next_size = size;
      if (size == 0 && i_data != 0) begin  // this would be a special case for replace
        next_size = size + 1;
      end
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
    next_state = current_state;
    case (current_state)
      IDLE: begin
        next_state = COMPARE_AND_SWAP_EVEN;
        if (i_wrt && !i_read) begin  // enqueue
          next_state = ENQUEUE;
        end else if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      COMPARE_AND_SWAP_EVEN: begin
        next_state = COMPARE_AND_SWAP_ODD;
        if (i_wrt && !i_read) begin  // enqueue
          next_state = ENQUEUE;
        end else if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      COMPARE_AND_SWAP_ODD: begin
        next_state = COMPARE_AND_SWAP_EVEN;
        if (i_wrt && !i_read) begin  // enqueue
          next_state = ENQUEUE;
        end else if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      ENQUEUE: begin
        next_state = COMPARE_AND_SWAP_EVEN;
      end

      DEQUEUE: begin
        next_state = COMPARE_AND_SWAP_EVEN;
      end

      REPLACE: begin
        next_state = COMPARE_AND_SWAP_EVEN;
      end

      default: begin  // Fault Proof
        next_state = IDLE;
      end
    endcase
  end

  /*
    Queue Management
  */
  always_ff @(posedge CLK or negedge RSTn) begin : queue_management_seq
    if (!RSTn) begin
      for (int itr = 0; itr < NodesNeeded; itr++) begin
        queue[itr] <= '0;
      end
      enqueue_idx <= 0;
    end else begin
      for (int itr = 0; itr < NodesNeeded; itr++) begin
        queue[itr] <= next_queue[itr];
      end
      enqueue_idx <= next_enqueue_idx;
    end
  end

  always_comb begin : queue_management_comb
    next_queue = queue;
    next_enqueue_idx = 0;
    case (current_state)
      IDLE: begin
        next_queue = queue;
      end

      COMPARE_AND_SWAP_EVEN: begin
        for (int lvl = 0; lvl < TreeDepth; lvl++) begin
          if (lvl % 2 == 0 && lvl < TreeDepth - 1) begin  // even level
            for (int i = (1 << lvl) - 1; i < (1 << (lvl + 1)) - 1; i++) begin
              next_queue[i] = new_parent[i];
              next_queue[2*i+1] = new_left_child[i];
              next_queue[2*i+2] = new_right_child[i];
            end
          end
        end
      end

      COMPARE_AND_SWAP_ODD: begin
        for (int lvl = 0; lvl < TreeDepth; lvl++) begin
          if (lvl % 2 == 1 && lvl < TreeDepth - 1) begin  // even level
            for (int i = (1 << lvl) - 1; i < (1 << (lvl + 1)) - 1; i++) begin
              next_queue[i] = new_parent[i];
              next_queue[2*i+1] = new_left_child[i];
              next_queue[2*i+2] = new_right_child[i];
            end
          end
        end
      end

      ENQUEUE: begin
        for (int i = 0; i < size; i++) begin
          if (queue[i] == 0) begin
            next_enqueue_idx = (i > next_enqueue_idx) ? i : next_enqueue_idx;
          end
        end
        next_queue[next_enqueue_idx] = i_data;
      end

      DEQUEUE: begin
        next_queue[0] = '0;
      end

      REPLACE: begin
        next_queue[0] = i_data;
      end

      default: begin
        next_queue = queue;
      end
    endcase

  end

  // Assign outputs
  assign empty = (size <= 0) ? 'b1 : 'b0;
  assign full = (size >= QUEUE_SIZE) ? 'b1 : 'b0;
  assign o_full = full;
  assign o_empty = empty;
  assign o_data = !empty ? queue[0] : 'd0;

endmodule

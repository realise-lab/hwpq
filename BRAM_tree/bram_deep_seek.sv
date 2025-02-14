module bram_deep_seek #(
    parameter integer QUEUE_SIZE = 3,
    parameter integer DATA_WIDTH = 16
) (
    input  logic                  CLK,
    input  logic                  RSTn,
    // Inputs
    input  logic                  i_wrt,    // Write/insert command
    input  logic                  i_read,   // Read/pop command
    input  logic [DATA_WIDTH-1:0] i_data,   // Data to insert/replace
    // Outputs
    output logic                  o_full,   // Heap full indicator
    output logic                  o_empty,  // Heap empty indicator
    output logic [DATA_WIDTH-1:0] o_data    // Popped value
);

  //-------------------------------------------------------------------------
  // Local Parameters
  //-------------------------------------------------------------------------
  localparam integer TREE_DEPTH = $clog2(QUEUE_SIZE);  // Heap depth
  localparam integer BRAM_WIDTH = 18;  // BRAM data width
  localparam integer BRAM_DEPTH = 1024;  // BRAM depth
  localparam integer ADDR_WIDTH = $clog2(BRAM_DEPTH);  // Address width
  localparam integer COUNTER_WIDTH = $clog2(QUEUE_SIZE);  // Queue counter

  //-------------------------------------------------------------------------
  // BRAM Interface Signals
  //-------------------------------------------------------------------------
  logic [   ADDR_WIDTH-1:0] bram_addr                                   [TREE_DEPTH];
  logic [   BRAM_WIDTH-1:0] bram_din                                    [TREE_DEPTH];
  logic [   BRAM_WIDTH-1:0] bram_dout                                   [TREE_DEPTH];
  logic [              1:0] bram_we                                     [TREE_DEPTH];
  logic                     bram_en                                     [TREE_DEPTH];

  //-------------------------------------------------------------------------
  // Heap Control Signals
  //-------------------------------------------------------------------------
  logic [COUNTER_WIDTH-1:0] queue_size;  // Current heap size
  logic                     process_even;  // Even level processing flag
  logic [   ADDR_WIDTH-1:0] node_index;  // Current node index
  logic [   TREE_DEPTH-1:0] current_level;  // Current heap level

  //-------------------------------------------------------------------------
  // FSM States
  //-------------------------------------------------------------------------
  typedef enum logic [2:0] {
    IDLE,
    READ_PARENT,
    READ_CHILDREN,
    COMPARE_SWAP,
    WRITE_BACK,
    UPDATE_INDEX,
    ENQUEUE_PHASE,
    DEQUEUE_PHASE
  } state_t;
  state_t current_state, next_state;

  //-------------------------------------------------------------------------
  // BRAM Instantiation
  //-------------------------------------------------------------------------
  generate
    genvar i;
    for (i = 0; i < TREE_DEPTH; i++) begin : gen_bram
      RAMB18E2 #(
          .DOA_REG(0),
          .DOB_REG(0),
          .READ_WIDTH_A(BRAM_WIDTH),
          .WRITE_WIDTH_A(BRAM_WIDTH),
          .READ_WIDTH_B(BRAM_WIDTH),
          .WRITE_WIDTH_B(BRAM_WIDTH)
      ) bram_inst (
          .CLKARDCLK(CLK),
          .ENARDEN(bram_en[i]),
          .ADDRARDADDR(bram_addr[i]),
          .DOUTADOUT(bram_dout[i]),
          .DINADIN(bram_din[i]),
          .WEA(bram_we[i]),
          // Unused ports tied off
          .CLKBWRCLK(CLK),
          .ENBWREN(1'b0),
          .ADDRBWRADDR(0),
          .DINBDIN(0),
          .WEBWE(0),
          .REGCEAREGCE(0),
          .RSTRAMARSTRAM(0),
          .RSTREGARSTREG(0),
          .SLEEP(0),
          .CASDIMUXA(0),
          .CASDOMUXEN_A(0)
      );
    end
  endgenerate

  //-------------------------------------------------------------------------
  // FSM Control Logic
  //-------------------------------------------------------------------------
  always_ff @(posedge CLK or negedge RSTn) begin
    if (!RSTn) begin
      current_state <= IDLE;
      queue_size <= 0;
      process_even <= 1;
      node_index <= 0;
      current_level <= 0;
    end else begin
      current_state <= next_state;
      case (current_state)
        IDLE: begin
          if (i_wrt && !o_full) begin
            queue_size <= queue_size + 1;
            next_state <= ENQUEUE_PHASE;
          end else if (i_read && !o_empty) begin
            queue_size <= queue_size - 1;
            next_state <= DEQUEUE_PHASE;
          end
        end

        ENQUEUE_PHASE: begin
          // Insert at last position and heapify up
          node_index <= queue_size;  // New node index
          current_level <= TREE_DEPTH - 1;  // Start from bottom
          next_state <= READ_PARENT;
        end

        DEQUEUE_PHASE: begin
          // Replace root with last element and heapify down
          node_index <= 0;  // Start from root
          current_level <= 0;
          next_state <= READ_PARENT;
        end

        READ_PARENT: begin
          // Read parent node from current level
          bram_addr[current_level] <= node_index;
          bram_en[current_level] <= 1;
          next_state <= READ_CHILDREN;
        end

        READ_CHILDREN: begin
          // Read children from next level
          if (current_level < TREE_DEPTH - 1) begin
            bram_addr[current_level+1] <= node_index * 2;
            bram_en[current_level+1]   <= 1;
          end
          next_state <= COMPARE_SWAP;
        end

        COMPARE_SWAP: begin
          // Compare parent with children and swap if needed
          // (Comparator logic here)
          next_state <= WRITE_BACK;
        end

        WRITE_BACK: begin
          // Write updated values back to BRAM
          bram_we[current_level] <= 2'b11;
          if (current_level < TREE_DEPTH - 1) bram_we[current_level+1] <= 2'b11;
          next_state <= UPDATE_INDEX;
        end

        UPDATE_INDEX: begin
          // Move to next node/level
          if (process_even) begin
            if (node_index < (1 << current_level) - 1) begin
              node_index <= node_index + 1;
              next_state <= READ_PARENT;
            end else begin
              process_even <= 0;
              current_level <= 0;
              next_state <= IDLE;
            end
          end else begin
            // Odd level processing (similar logic)
          end
        end
      endcase
    end
  end

  //-------------------------------------------------------------------------
  // Comparator and Data Path
  //-------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] parent, left_child, right_child;
  logic [DATA_WIDTH-1:0] new_parent, new_left, new_right;

  assign parent = bram_dout[current_level];
  assign left_child = (current_level < TREE_DEPTH - 1) ? bram_dout[current_level+1] : 0;
  assign right_child = (current_level < TREE_DEPTH - 1) ? bram_dout[current_level+1] : 0;

  // Max-heap comparison logic
  always_comb begin
    if (left_child > parent && left_child >= right_child) begin
      new_parent = left_child;
      new_left   = parent;
    end else if (right_child > parent) begin
      new_parent = right_child;
      new_right  = parent;
    end else begin
      new_parent = parent;
      new_left   = left_child;
      new_right  = right_child;
    end
  end

  assign bram_din[current_level] = new_parent;
  assign bram_din[current_level+1] = (node_index % 2) ? new_right : new_left;

  //-------------------------------------------------------------------------
  // Output Assignment
  //-------------------------------------------------------------------------
  assign o_full = (queue_size == QUEUE_SIZE);
  assign o_empty = (queue_size == 0);
  assign o_data = bram_dout[0];  // Root value

endmodule

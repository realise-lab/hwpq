module pipelined_bram_tree #(
    parameter integer QUEUE_SIZE = 7,
    parameter integer DATA_WIDTH = 16
) (
    input  logic                  CLK,
    input  logic                  RSTn,
    // Inputs
    input  logic                  i_wrt,    // Write/insert command
    input  logic                  i_read,   // Read/pop command
    input  logic [DATA_WIDTH-1:0] i_data,   // Data to be inserted (or used for replace)
    // Outputs
    output logic                  o_full,   // High if the heap is full
    output logic                  o_empty,  // High if the heap is empty
    output logic [DATA_WIDTH-1:0] o_data    // Output data (popped value)
);

  //-------------------------------------------------------------------------
  // Local parameters
  //-------------------------------------------------------------------------

  // General local parameters
  localparam integer TREE_DEPTH = $clog2(QUEUE_SIZE + 1);  // depth of the heap tree
  localparam integer NODES_NEEDED = (1 << TREE_DEPTH) - 1;  // number of actual slots needed for the queue
                                                            // to store the heap, need to caculate this so
                                                            // that we could take any arbitrary queue size
  localparam integer ADDRESS_WIDTH = TREE_DEPTH - 1;  // address width of the BRAMs

  //-------------------------------------------------------------------------
  // Internal used wires and registers
  //-------------------------------------------------------------------------

  // Memory used wires and registers
  logic [31:0] addr_a[TREE_DEPTH-1:0];
  logic [31:0] addr_b[TREE_DEPTH-1:0];
  logic [DATA_WIDTH-1:0] dout_a[TREE_DEPTH-1:0];
  logic [DATA_WIDTH-1:0] dout_b[TREE_DEPTH-1:0];
  logic [DATA_WIDTH-1:0] din_a[TREE_DEPTH-1:0];
  logic [DATA_WIDTH-1:0] din_b[TREE_DEPTH-1:0];
  logic we_a[TREE_DEPTH-1:0];
  logic we_b[TREE_DEPTH-1:0];

  logic [31:0] next_addr_a[TREE_DEPTH-1:0];
  logic [31:0] next_addr_b[TREE_DEPTH-1:0];
  logic [DATA_WIDTH-1:0] next_din_a[TREE_DEPTH-1:0];
  logic [DATA_WIDTH-1:0] next_din_b[TREE_DEPTH-1:0];
  logic next_we_a[TREE_DEPTH-1:0];
  logic next_we_b[TREE_DEPTH-1:0];

  // Comparator used wires and registers
  logic [DATA_WIDTH-1:0] comp_parent_in;
  logic [DATA_WIDTH-1:0] comp_left_child_in;
  logic [DATA_WIDTH-1:0] comp_right_child_in;

  logic [DATA_WIDTH-1:0] next_comp_parent_in;
  logic [DATA_WIDTH-1:0] next_comp_left_child_in;
  logic [DATA_WIDTH-1:0] next_comp_right_child_in;

  logic [DATA_WIDTH-1:0] comp_parent_out;
  logic [DATA_WIDTH-1:0] comp_left_child_out;
  logic [DATA_WIDTH-1:0] comp_right_child_out;

  // Index tracker for each level
  logic [$clog2(TREE_DEPTH)-1:0] parent_lvl, next_parent_lvl;
  logic [ADDRESS_WIDTH-1:0] parent_idx, next_parent_idx;

  // Size counter to keep track of the number of nodes in the queue
  logic [31:0] queue_size, next_queue_size;

  // integers for iteration
  integer lvl_seq, itr_seq, lvl_comb, itr_comb;

  //-------------------------------------------------------------------------
  // FSM state declaration
  //-------------------------------------------------------------------------

  typedef enum logic [2:0] {
    IDLE         = 3'd0,
    READ_MEM     = 3'd1,
    COMPARE_SWAP = 3'd2,
    WRITE_MEM    = 3'd3,
    DEQUEUE      = 3'd4,
    REPLACE      = 3'd5,
    WAIT         = 3'd6
  } state_t;
  state_t state, next_state;

  //-------------------------------------------------------------------------
  // Memory declaration and initialization
  //-------------------------------------------------------------------------

  genvar i;
  generate
    for (i = 0; i < TREE_DEPTH; i++) begin : gen_bram  // Using BRAM starts from level 2
      rams_tdp_rf_rf #(
          .WIDTH(DATA_WIDTH),
          .DEPTH(1 << i)
      ) bram_inst (
          .clka (CLK),
          .ena  (1'b1),
          .wea  (we_a[i]),
          .addra(addr_a[i]),
          .dia  (din_a[i]),
          .doa  (dout_a[i]),
          .clkb (CLK),
          .enb  (1'b1),
          .web  (we_b[i]),
          .addrb(addr_b[i]),
          .dib  (din_b[i]),
          .dob  (dout_b[i])
      );
    end
  endgenerate

  //-------------------------------------------------------------------------
  // Comparator instantiation
  //-------------------------------------------------------------------------

  comparator #(
      .DATA_WIDTH(DATA_WIDTH)
  ) comparator_inst (
      .i_parent(comp_parent_in),
      .i_left_child(comp_left_child_in),
      .i_right_child(comp_right_child_in),
      .o_parent(comp_parent_out),
      .o_left_child(comp_left_child_out),
      .o_right_child(comp_right_child_out)
  );

  //-------------------------------------------------------------------------
  // FSM
  //-------------------------------------------------------------------------

  always_ff @(posedge CLK or negedge RSTn) begin : fsm_seq
    if (!RSTn) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

  always_comb begin : fsm_comb
    next_state = IDLE;  // default next state, latch preventing
    case (state)
      IDLE: begin
        next_state = READ_MEM;
        if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end
        else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      READ_MEM: begin
        next_state = WAIT;
        if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end
        else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      COMPARE_SWAP: begin
        next_state = WRITE_MEM;
        if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end
        else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      WRITE_MEM: begin
        next_state = READ_MEM;
        if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end
        else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      DEQUEUE: begin
        next_state = READ_MEM;
      end

      REPLACE: begin
        next_state = READ_MEM;
      end

      WAIT: begin
        next_state = COMPARE_SWAP;
        if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end
        else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      default: begin
        next_state = IDLE;
      end
    endcase
  end

  //-------------------------------------------------------------------------
  // BRAM read & write, heap management
  //-------------------------------------------------------------------------

  always_ff @(posedge CLK or negedge RSTn) begin : bram_seq
    if (!RSTn) begin
      parent_lvl <= '0;
      parent_idx <= '0;
      for (lvl_seq = 0; lvl_seq < TREE_DEPTH; lvl_seq++) begin  // initialize BRAMs' ports
        addr_a[lvl_seq] <= '0;
        addr_b[lvl_seq] <= '0;
        din_a[lvl_seq]  <= '0;
        din_b[lvl_seq]  <= '0;
        we_a[lvl_seq]   <= '0;
        we_b[lvl_seq]   <= '0;
      end
      comp_parent_in <= '0;
      comp_left_child_in <= '0;
      comp_right_child_in <= '0;
    end else begin
      parent_lvl <= next_parent_lvl;
      parent_idx <= next_parent_idx;
      for (lvl_seq = 0; lvl_seq < TREE_DEPTH; lvl_seq++) begin
        addr_a[lvl_seq] <= next_addr_a[lvl_seq];
        addr_b[lvl_seq] <= next_addr_b[lvl_seq];
        din_a[lvl_seq]  <= next_din_a[lvl_seq];
        din_b[lvl_seq]  <= next_din_b[lvl_seq];
        we_a[lvl_seq]   <= next_we_a[lvl_seq];
        we_b[lvl_seq]   <= next_we_b[lvl_seq];
      end
      comp_parent_in <= next_comp_parent_in;
      comp_left_child_in <= next_comp_left_child_in;
      comp_right_child_in <= next_comp_right_child_in;
    end
  end

  always_comb begin : bram_comb
    next_parent_lvl = parent_lvl;
    next_parent_idx = parent_idx;
    for (lvl_comb = 0; lvl_comb < TREE_DEPTH; lvl_comb++) begin
      next_addr_a[lvl_comb] = addr_a[lvl_comb];
      next_addr_b[lvl_comb] = addr_b[lvl_comb];
      next_din_a[lvl_comb]  = din_a[lvl_comb];
      next_din_b[lvl_comb]  = din_b[lvl_comb];
      next_we_a[lvl_comb]   = 1'b0;  // default to read
      next_we_b[lvl_comb]   = 1'b0;
    end
    next_comp_parent_in = comp_parent_in;
    next_comp_left_child_in = comp_left_child_in;
    next_comp_right_child_in = comp_right_child_in;
    case (state)
      IDLE: begin
      end

      READ_MEM: begin  // in order to read from BRAMs, we will need to send addresses in
        next_addr_a[parent_lvl]   = parent_idx;
        next_addr_a[parent_lvl+1] = 2 * parent_idx;
        next_addr_b[parent_lvl+1] = 2 * parent_idx + 1;
      end

      COMPARE_SWAP: begin
        next_comp_parent_in = dout_a[parent_lvl];
        next_comp_left_child_in = dout_a[parent_lvl+1];
        next_comp_right_child_in = dout_b[parent_lvl+1];
      end

      WRITE_MEM: begin  // in order to write to BRAMs, we need enable write signals
        next_din_a[parent_lvl]   = comp_parent_out;
        next_din_a[parent_lvl+1] = comp_left_child_out;
        next_din_b[parent_lvl+1] = comp_right_child_out;

        // find where the next parent index is
        if (comp_left_child_out != comp_left_child_in) begin
          next_parent_lvl = parent_lvl + 1;
          next_parent_idx = 2 * parent_idx;
        end else if (comp_right_child_out != comp_right_child_in) begin
          next_parent_lvl = parent_lvl + 1;
          next_parent_idx = 2 * parent_idx + 1;
        end else begin  // if no change, then we are done
          next_parent_lvl = 'd0;
          next_parent_idx = 'd0;
        end

       if (parent_lvl == TREE_DEPTH - 1) begin  // if we are at the last level
          next_parent_lvl = 'd0;
          next_parent_idx = 'd0;
          next_we_a[parent_lvl] = 1'b0;
          next_we_b[parent_lvl] = 1'b0;
        end else begin
          next_we_a[parent_lvl]   = 1'b1;
          next_we_a[parent_lvl+1] = 1'b1;
          next_we_b[parent_lvl+1] = 1'b1;
        end
      end

      DEQUEUE: begin
        next_addr_a[0] = 'd0;
        next_din_a[0] = 'd0;
        next_we_a[0] = 1'b1;
        next_parent_lvl = 'd0;
        next_parent_idx = 'd0;
      end

      REPLACE: begin
        next_addr_a[0] = 'd0;
        next_din_a[0] = i_data;
        next_we_a[0] = 1'b1;
        next_parent_lvl = 'd0;
        next_parent_idx = 'd0;
      end

      WAIT: begin  // this is a do nothing state, just for reading from RAM
      end

      default: begin
      end
    endcase
  end

  //-------------------------------------------------------------------------
  // Queue size counter
  //-------------------------------------------------------------------------

  always_ff @(posedge CLK or negedge RSTn) begin : queue_size_seq
    if (!RSTn) begin
      queue_size <= 0;
    end else begin
      queue_size <= next_queue_size;
    end
  end

  always_comb begin : queue_size_comb
    next_queue_size = queue_size;
    if (i_wrt && !i_read) begin  // enqueue
      next_queue_size = queue_size + 1;
    end else if (!i_wrt && i_read) begin  // dequeue
      next_queue_size = queue_size - 1;
    end else if (i_wrt && i_read) begin  // replace
      if (queue_size == 0 && i_data != 0) begin  // this would be a special case for replace, function as enqueue
        next_queue_size = queue_size + 1;
      end else begin
        next_queue_size = queue_size;
      end
    end
  end

  //-------------------------------------------------------------------------
  // Assignments for status and output.
  //-------------------------------------------------------------------------
  assign o_full  = (queue_size >= QUEUE_SIZE);
  assign o_empty = (queue_size <= 0);
  assign o_data  = dout_a[0];

endmodule

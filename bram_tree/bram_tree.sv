/*******************************************************************************
  Module Name: bram_tree
  Date: 2025/03/05
  Description: 
  Parameters: QUEUE_SIZE - 
              DATA_WIDTH -
  Inputs: CLK - 
          RSTn - 
          i_wrt - 
          i_read - 
          i_data -
  Outputs: o_full - 
           o_empty - 
           o_data -
*******************************************************************************/

module bram_tree #(
    parameter integer QUEUE_SIZE = 7,
    parameter integer DATA_WIDTH = 16
) (
    input  logic                  CLK,
    input  logic                  RSTn,
    // Inputs
    input  logic                  i_wrt,    // Write/insert command
    input  logic                  i_read,   // Read/pop command
    input  logic [DATA_WIDTH-1:0] i_data,   // Input data
    // Outputs
    output logic                  o_full,   // High if the heap is full
    output logic                  o_empty,  // High if the heap is empty
    output logic [DATA_WIDTH-1:0] o_data    // Output data
);

  //-------------------------------------------------------------------------
  // Local parameters
  //-------------------------------------------------------------------------

  // BRAM local parameters
  localparam integer BRAM_DEPTH = 655360;  // In this case, this module would use 200 36K BRAMs, and 200 18K BRAMs
  localparam integer ADDRESS_WIDTH = $clog2(BRAM_DEPTH);

  // General local parameters
  localparam integer TREE_DEPTH = $clog2(QUEUE_SIZE + 1);
  localparam integer NODES_NEEDED = (1 << TREE_DEPTH) - 1;  // number of actual slots needed for the queue
  localparam integer COUNTER_WIDTH = $clog2(NODES_NEEDED);

  //-------------------------------------------------------------------------
  // Internal used wires and registers
  //-------------------------------------------------------------------------

  // Output registers
  logic [DATA_WIDTH-1:0] out_reg, next_out_reg;

  // Temperature register for parent and children
  logic [DATA_WIDTH-1:0] temp_parent;
  logic [DATA_WIDTH-1:0] temp_left_child;
  logic [DATA_WIDTH-1:0] temp_right_child;

  // Indicator for reading for parent node or children nodes
  logic read_parent, next_read_parent;

  // Memory used wires and registers
  logic [ADDRESS_WIDTH-1:0] addr_a;
  logic [ADDRESS_WIDTH-1:0] addr_b;
  logic [DATA_WIDTH-1:0] dout_a;
  logic [DATA_WIDTH-1:0] dout_b;
  logic [DATA_WIDTH-1:0] din_a;
  logic [DATA_WIDTH-1:0] din_b;
  logic we_a;
  logic we_b;

  logic [ADDRESS_WIDTH-1:0] next_addr_a;
  logic [ADDRESS_WIDTH-1:0] next_addr_b;
  logic [DATA_WIDTH-1:0] next_din_a;
  logic [DATA_WIDTH-1:0] next_din_b;
  logic next_we_a;
  logic next_we_b;

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
  integer queue_size, next_queue_size;

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
    ENQUEUE      = 3'd4,
    DEQUEUE      = 3'd5,
    REPLACE      = 3'd6,
    WAIT         = 3'd7
  } state_t;
  state_t state, next_state;

  //-------------------------------------------------------------------------
  // Memory declaration and initialization
  //-------------------------------------------------------------------------
  blk_mem_gen_0 bram_inst (
      .addra(addr_a),
      .clka (CLK),
      .dina (din_a),
      .douta(dout_a),
      .wea  (we_a),
      .addrb(addr_b),
      .clkb (CLK),
      .dinb (din_b),
      .doutb(dout_b),
      .web  (we_b)
  );

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
        end else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      READ_MEM: begin
        next_state = WAIT;
        if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      COMPARE_SWAP: begin
        if (read_parent) begin
          next_state = READ_MEM;
        end else begin
          next_state = WRITE_MEM;
        end

        if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      WRITE_MEM: begin
        next_state = READ_MEM;
        if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      ENQUEUE: begin
        next_state = READ_MEM;
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
        end else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      default: begin
        next_state = IDLE;
      end
    endcase
  end

  //-------------------------------------------------------------------------
  // BRAM read&write, heap management
  //-------------------------------------------------------------------------
  always_ff @(posedge CLK or negedge RSTn) begin : bram_seq
    if (!RSTn) begin
      read_parent <= 1'b1;
      parent_idx <= '0;
      addr_a <= '0;
      addr_b <= '0;
      din_a <= '0;
      din_b <= '0;
      we_a <= 1'b0;
      we_b <= 1'b0;
      comp_parent_in <= '0;
      comp_left_child_in <= '0;
      comp_right_child_in <= '0;
      out_reg <= '0;
    end else begin
      read_parent <= next_read_parent;
      parent_idx <= next_parent_idx;
      addr_a <= next_addr_a;
      addr_b <= next_addr_b;
      din_a <= next_din_a;
      din_b <= next_din_b;
      we_a <= next_we_a;
      we_b <= next_we_b;
      comp_parent_in <= next_comp_parent_in;
      comp_left_child_in <= next_comp_left_child_in;
      comp_right_child_in <= next_comp_right_child_in;
      out_reg <= next_out_reg;
    end
  end

  always_comb begin : bram_comb
    next_read_parent = read_parent;
    next_parent_idx = parent_idx;
    next_addr_a = addr_a;
    next_addr_b = addr_b;
    next_din_a = din_a;
    next_din_b = din_b;
    next_we_a = 1'b0;
    next_we_b = 1'b0;
    next_comp_parent_in = comp_parent_in;
    next_comp_left_child_in = comp_left_child_in;
    next_comp_right_child_in = comp_right_child_in;
    next_out_reg = out_reg;

    case (state)
      IDLE: begin
      end

      READ_MEM: begin  // In order to read from BRAMs, we will need to send addresses in
        if (read_parent) begin
          next_addr_a = parent_idx;
        end else begin
          next_addr_a = 2 * parent_idx + 1;
          next_addr_b = 2 * parent_idx + 2;
        end
      end

      COMPARE_SWAP: begin  // assigning BRAM data into comparator
        if (read_parent) begin
          if (parent_idx == 'd0) begin
            next_out_reg = dout_a;
          end
          next_comp_parent_in = dout_a;
          next_read_parent = 1'b0;
        end else begin
          next_comp_left_child_in = dout_a;
          next_comp_right_child_in = dout_b;
          next_read_parent = 1'b1;
        end
      end

      WRITE_MEM: begin  // In order to write to BRAMs, we need enable write signals
        if (comp_left_child_out != comp_left_child_in) begin // if comparator's left child output is different from input, then the only option is that the original parent needs to be swapped with the left child. 
          next_addr_a = parent_idx;
          next_din_a = comp_parent_out;
          next_we_a = 1'b1;
          next_addr_b = 2 * parent_idx + 1;
          next_din_b = comp_left_child_out;
          next_we_b = 1'b1;
          next_parent_idx = 2 * parent_idx + 1;
          if ((2 * parent_idx + 1) > ((1 << (TREE_DEPTH - 1)) - 2)) begin
            next_parent_idx = 'd0;
          end
          if (parent_idx == 'd0) begin
            next_out_reg = comp_parent_out;
          end
        end else if (comp_right_child_out != comp_right_child_in) begin
          next_addr_a = parent_idx;
          next_din_a = comp_parent_out;
          next_we_a = 1'b1;
          next_addr_b = 2 * parent_idx + 2;
          next_din_b = comp_right_child_out;
          next_we_b = 1'b1;
          next_parent_idx = 2 * parent_idx + 2;
          if ((2 * parent_idx + 1) > ((1 << (TREE_DEPTH - 1)) - 2)) begin
            next_parent_idx = 'd0;
          end
          if (parent_idx == 'd0) begin
            next_out_reg = comp_parent_out;
          end
        end else begin
          next_addr_a = 'd0;
          next_din_a = 'd0;
          next_addr_b = 'd0;
          next_din_b = 'd0;
          next_parent_idx = 'd0;
        end
      end

      ENQUEUE: begin  // * We will eventually need to implement enqueue
      end

      DEQUEUE: begin
        next_addr_a = 'd0;
        next_din_a = 'd0;
        next_we_a = 1'b1;
        next_parent_idx = 'd0;
        next_read_parent = 1'b1;
      end

      REPLACE: begin
        next_addr_a = 'd0;
        next_din_a = i_data;
        next_we_a = 1'b1;
        next_parent_idx = 'd0;
        next_read_parent = 1'b1;
      end

      WAIT: begin  // This is a do nothing state, just for reading from RAM
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
      next_queue_size = queue_size;
      if (queue_size == 0 && i_data != 0) begin  // this would be a special case for replace, function as enqueue
        next_queue_size = queue_size + 1;
      end
    end
  end

  //-------------------------------------------------------------------------
  // Assignments for status and output.
  //-------------------------------------------------------------------------
  assign o_full  = (queue_size == QUEUE_SIZE);
  assign o_empty = (queue_size == 0);
  assign o_data  = out_reg;

endmodule

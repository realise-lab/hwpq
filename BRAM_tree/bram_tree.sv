module bram_tree #(
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
  localparam integer TREE_DEPTH = $clog2(QUEUE_SIZE + 1);  // depth of the tree calculated from the queue size
                                                           // = how many BRAMs are needed
  localparam integer BRAM_WIDTH = 18;  // width of the BRAMs, as Xilinx BRAMs are only supported for width of
                                       // 0, 1, 2, 4, 9, 18, 36, 72
  localparam integer BRAM_DEPTH = 1024;  // depth of the BRAMs, 18 Kb = 18 * 1024 bits
  localparam integer NODES_NEEDED = (1 << (TREE_DEPTH + 1)) - 1;  // number of actual slots needed for the queue
                                                                  // to store the heap, need to caculate this so
                                                                  // that we could take any arbitrary queue size
  localparam integer COMPARATORS_NEEDED = (TREE_DEPTH - 1) / 2;  // number of comparators needed for the heap
  localparam integer ADDRESS_WIDTH = $clog2(BRAM_DEPTH);  // width for the address/index of the BRAMs
  localparam integer COUNTER_WIDTH = $clog2(NODES_NEEDED);  // width for the counter of the queue size

  //-------------------------------------------------------------------------
  // Internal used wires and registers
  //-------------------------------------------------------------------------

  // Memory used wires and registers
  logic [ADDRESS_WIDTH-1:0] addr_a[TREE_DEPTH];
  logic [ADDRESS_WIDTH-1:0] addr_b[TREE_DEPTH];
  logic [DATA_WIDTH-1:0] dout_a[TREE_DEPTH];
  logic [DATA_WIDTH-1:0] dout_b[TREE_DEPTH];
  logic [DATA_WIDTH-1:0] din_a[TREE_DEPTH];
  logic [DATA_WIDTH-1:0] din_b[TREE_DEPTH];
  logic we_a[TREE_DEPTH];
  logic we_b[TREE_DEPTH];

  logic [ADDRESS_WIDTH-1:0] next_addr_a[TREE_DEPTH];
  logic [ADDRESS_WIDTH-1:0] next_addr_b[TREE_DEPTH];
  logic [DATA_WIDTH-1:0] next_din_a[TREE_DEPTH];
  logic [DATA_WIDTH-1:0] next_din_b[TREE_DEPTH];
  logic next_we_a[TREE_DEPTH];
  logic next_we_b[TREE_DEPTH];

  // Comparator used wires and registers
  logic [DATA_WIDTH-1:0] comp_parent_in[COMPARATORS_NEEDED];  // comparator input data
  logic [DATA_WIDTH-1:0] comp_left_child_in[COMPARATORS_NEEDED];
  logic [DATA_WIDTH-1:0] comp_right_child_in[COMPARATORS_NEEDED];

  logic [DATA_WIDTH-1:0] comp_parent_out[COMPARATORS_NEEDED];  // comparator output data
  logic [DATA_WIDTH-1:0] comp_left_child_out[COMPARATORS_NEEDED];
  logic [DATA_WIDTH-1:0] comp_right_child_out[COMPARATORS_NEEDED];

  // Size counter to keep track of the number of nodes in the queue
  logic [31:0] queue_size, next_queue_size;

  // Change tracker
  logic [ADDRESS_WIDTH-1:0] changed_addr[TREE_DEPTH][0:1];  // tracker for changed node
  logic [ADDRESS_WIDTH-1:0] next_changed_addr[TREE_DEPTH][0:1];

  logic even_flag, next_even_flag;

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
  genvar i;
  generate
    for (i = 0; i < TREE_DEPTH; i++) begin : gen_bram
      blk_mem_gen_0 blk_mem_gen_0_inst (
          .clka (CLK),
          .wea  (we_a[i]),
          .addra(addr_a[i]),
          .dina (din_a[i]),
          .douta(dout_a[i]),
          .clkb (CLK),
          .web  (we_b[i]),
          .addrb(addr_b[i]),
          .dinb (din_b[i]),
          .doutb(dout_b[i])
      );
    end
  endgenerate

  //-------------------------------------------------------------------------
  // Comparator instantiation
  //-------------------------------------------------------------------------
  genvar j;
  generate
    for (j = 0; j < COMPARATORS_NEEDED; j++) begin : gen_comparator
      comparator #(
          .DATA_WIDTH(DATA_WIDTH)
      ) comparator_inst (
          .i_parent(comp_parent_in[j]),
          .i_left_child(comp_left_child_in[j]),
          .i_right_child(comp_right_child_in[j]),
          .o_parent(comp_parent_out[j]),
          .o_left_child(comp_left_child_out[j]),
          .o_right_child(comp_right_child_out[j])
      );
    end
  endgenerate

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
        if (i_wrt && !i_read) begin  // enqueue
          next_state = ENQUEUE;
        end else if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      READ_MEM: begin
        next_state = COMPARE_SWAP;
        if (i_wrt && !i_read) begin  // enqueue
          next_state = ENQUEUE;
        end else if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      COMPARE_SWAP: begin
        next_state = WRITE_MEM;
        if (i_wrt && !i_read) begin  // enqueue
          next_state = ENQUEUE;
        end else if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      WRITE_MEM: begin
        next_state = READ_MEM;
        if (i_wrt && !i_read) begin  // enqueue
          next_state = ENQUEUE;
        end else if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      ENQUEUE: begin
        next_state = READ_MEM;
        if (i_wrt && !i_read) begin  // enqueue
          next_state = ENQUEUE;
        end else if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      DEQUEUE: begin
        next_state = READ_MEM;
        if (i_wrt && !i_read) begin  // enqueue
          next_state = ENQUEUE;
        end else if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      REPLACE: begin
        next_state = READ_MEM;
        if (i_wrt && !i_read) begin  // enqueue
          next_state = ENQUEUE;
        end else if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      WAIT: begin
        next_state = WRITE_MEM;
        if (i_wrt && !i_read) begin  // enqueue
          next_state = ENQUEUE;
        end else if (!i_wrt && i_read) begin  // dequeue
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
      even_flag <= 1'b0;
      for (lvl_seq = 0; lvl_seq < TREE_DEPTH; lvl_seq++) begin
        addr_a[lvl_seq] <= '0;
        addr_b[lvl_seq] <= '0;
        din_a[lvl_seq]  <= '0;
        din_b[lvl_seq]  <= '0;
        we_a[lvl_seq]   <= '0;
        we_b[lvl_seq]   <= '0;
      end
      for (lvl_seq = 0; lvl_seq < COMPARATORS_NEEDED; lvl_seq++) begin
        comp_parent_in[lvl_seq] <= '0;
        comp_left_child_in[lvl_seq] <= '0;
        comp_right_child_in[lvl_seq] <= '0;
      end
      for (lvl_seq = 0; lvl_seq < TREE_DEPTH; lvl_seq++) begin
        for (itr_seq = 0; itr_seq < 2; itr_seq++) begin
          changed_addr[lvl_seq][itr_seq] <= '0;
        end
      end
    end else begin
      even_flag <= next_even_flag;
      for (lvl_seq = 0; lvl_seq < TREE_DEPTH; lvl_seq++) begin
        addr_a[lvl_seq] <= next_addr_a[lvl_seq];
        addr_b[lvl_seq] <= next_addr_b[lvl_seq];
        din_a[lvl_seq]  <= next_din_a[lvl_seq];
        din_b[lvl_seq]  <= next_din_b[lvl_seq];
        we_a[lvl_seq]   <= next_we_a[lvl_seq];
        we_b[lvl_seq]   <= next_we_b[lvl_seq];
      end
      for (lvl_seq = 0; lvl_seq < TREE_DEPTH; lvl_seq++) begin
        for (itr_seq = 0; itr_seq < 2; itr_seq++) begin
          next_changed_addr[lvl_seq][itr_seq] <= changed_addr[lvl_seq][itr_seq];
        end
      end
    end
  end

  always_comb begin : bram_comb
    next_even_flag = even_flag;
    for (lvl_comb = 0; lvl_comb < TREE_DEPTH; lvl_comb++) begin : bram_reset
      next_addr_a[lvl_comb] = addr_a[lvl_comb];
      next_addr_b[lvl_comb] = addr_b[lvl_comb];
      next_din_a[lvl_comb]  = '0;
      next_din_b[lvl_comb]  = '0;
      next_we_a[lvl_comb]   = '0;
      next_we_b[lvl_comb]   = '0;
      for (itr_comb = 0; itr_comb < 2; itr_comb++) begin
        next_changed_addr[lvl_comb][itr_comb] = changed_addr[lvl_comb][itr_comb];
      end
    end
    case (state)
      IDLE: begin
      end

      READ_MEM: begin
        if (even_flag) begin
          next_addr_a[0] = 0;
          next_addr_b[0] = 0;
          next_addr_a[1] = 0;
          next_addr_b[1] = 1;
          next_addr_a[2] = 0;  // level 2 BRAM not used
          next_addr_b[2] = 0;
        end else begin
          next_addr_a[0] = 0;  // level 0 BRAM not used
          next_addr_b[0] = 0;
          next_addr_a[1] = 0;
          next_addr_b[1] = 1;
          next_addr_a[2] = 2;
          next_addr_b[2] = 3;
        end
      end

      COMPARE_SWAP: begin  // Wait mem output ready
      end

      WRITE_MEM: begin
        if (even_flag) begin
          comp_parent_in[0] = dout_b[0];
          comp_left_child_in[0] = dout_a[1];
          comp_right_child_in[0] = dout_b[1];
          next_din_b[0] = comp_parent_out[0];
          next_din_a[1] = comp_left_child_out[0];
          next_din_b[1] = comp_right_child_out[0];

          next_we_b[0] = '1;
          next_we_a[1] = '1;
          next_we_b[1] = '1;
        end else begin
          comp_parent_in[0] = dout_a[1];
          comp_left_child_in[0] = dout_a[2];
          comp_right_child_in[0] = dout_b[2];
          next_din_b[1] = comp_parent_out[0];
          next_din_a[2] = comp_left_child_out[0];
          next_din_b[2] = comp_right_child_out[0];

          next_we_b[1] = '1;
          next_we_a[2] = '1;
          next_we_b[2] = '1;
        end
        next_even_flag = ~even_flag;
      end

      ENQUEUE: begin
        next_addr_b[$clog2(queue_size+1)-1] = queue_size - (1 << ($clog2(queue_size + 1) - 1));
        next_din_b[$clog2(queue_size+1)-1] = i_data;
        next_we_b[$clog2(queue_size+1)-1] = 1'b1;

        next_changed_addr[$clog2(queue_size+1)-1][1] = queue_size - (1 << ($clog2(queue_size + 1) - 1));
        next_even_flag = 1'b1;
      end

      DEQUEUE: begin
        next_addr_b[0] = 0;
        next_din_b[0] = '0;
        next_we_b[0] = 1'b1;

        next_changed_addr[0][0] = 0;
        next_even_flag = 1'b1;
      end

      REPLACE: begin
        next_addr_b[0] = 0;
        next_din_b[0] = i_data;
        next_we_b[0] = 1'b1;

        next_changed_addr[0][0] = 0;
        next_even_flag = 1'b1;
      end

      WAIT: begin  // * Temporary state for clock testing
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

  always_comb begin : queue_size_counter_comb
    next_queue_size = queue_size;
    if (i_wrt && !i_read) begin
      next_queue_size = queue_size + 1;
    end else if (!i_wrt && i_read) begin
      next_queue_size = queue_size - 1;
    end
  end

  //-------------------------------------------------------------------------
  // Assignments for status and output.
  //-------------------------------------------------------------------------
  assign o_full  = (queue_size == QUEUE_SIZE);
  assign o_empty = (queue_size == 0);
  assign o_data  = dout_a[0];

endmodule

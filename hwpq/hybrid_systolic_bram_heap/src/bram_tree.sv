import bram_tree_pkg::*;

// Max-heap: larger value = higher priority. A node is just its value; 0 means "empty".
module bram_tree (
    input  logic                  i_CLK,
    input  logic                  i_RSTn,
    // Inputs
    input  logic                  i_wrt,    // Write/insert command
    input  logic                  i_read,   // Read/pop command
    input  logic [DATA_WIDTH-1:0] i_data,   // Input data
    // Reset generation and memory fill, from the bram_tree_reset shared by every tree
    input  logic [GEN_W-1:0]         i_gen,
    input  logic                     i_gen_pending,  // gen has not yet counted the last reset
    input  logic                     i_filling,
    input  logic [ADDRESS_WIDTH-1:0] i_fill_addr,
    input  logic [ADDRESS_WIDTH-1:0] i_fill_cap,
    // Outputs
    output logic                  o_full,   // High if the heap is full
    output logic                  o_empty,  // High if the heap is empty
    output logic [DATA_WIDTH-1:0] o_data,   // Output data (Root node, the max)
    output logic                  o_ready   // Stall if we are still propagating/rebalancing
);

  typedef enum logic [3:0] {
    IDLE           = 4'd0,
    // Enqueue 
    ENQUEUE_COMPARE_ROOT    = 4'd1,
    ENQUEUE_READ_CHILD      = 4'd2,
    ENQUEUE_COMPARE_CHILD   = 4'd3,
    // Dequeue
    DEQUEUE_READ_ROOT_CHILDREN = 4'd4,
    DEQUEUE_COMPARE_ROOT    = 4'd5,
    DEQUEUE_READ_CHILD      = 4'd6,
    DEQUEUE_COMPARE_CHILD   = 4'd7,
    // Replace
    REPLACE_READ_ROOT    = 4'd8,
    REPLACE_COMPARE_ROOT = 4'd9,
    REPLACE_READ_CHILD   = 4'd10,
    REPLACE_COMPARE_CHILD = 4'd11
  } state_t;

  // Struct builders in place of assignment patterns, which iverilog does not parse.
  function automatic bram_tree_mem_t mem_node(input logic a, input logic [DATA_WIDTH-1:0] v,
                                              input logic [ADDRESS_WIDTH-1:0] c);
    mem_node.gen = i_gen; mem_node.active = a; mem_node.value = v; mem_node.capacity = c;
  endfunction

  function automatic logic [ADDRESS_WIDTH-1:0] node_cap(input logic [ADDRESS_WIDTH-1:0] idx);
    node_cap = NODES_NEEDED;
    for (int l = 1; l < TREE_DEPTH; l++)
      if (idx >= ADDRESS_WIDTH'((1 << l) - 1)) node_cap = ADDRESS_WIDTH'(NODES_NEEDED >> l);
  endfunction

  function automatic bram_tree_curr_t curr_node(input logic [DATA_WIDTH-1:0] v,
                                                input logic [ADDRESS_WIDTH-1:0] p,
                                                input logic [ADDRESS_WIDTH-1:0] c);
    curr_node.value = v; curr_node.position = p; curr_node.capacity = c;
  endfunction

  state_t state, next_state;
  bram_tree_curr_t curr, next;
  bram_tree_mem_t  top_level, next_top_level;
  logic [ADDRESS_WIDTH:0] parent_idx, child_idx_left, child_idx_right;
  logic [QUEUE_COUNT_WIDTH-1:0] queue_size, next_queue_size;

  // BRAM signals
  logic [ADDRESS_WIDTH-1:0] addr_a;
  logic [ADDRESS_WIDTH-1:0] addr_b;
  bram_tree_mem_t           din_a;
  bram_tree_mem_t           din_b;
  logic                     we_a;
  logic                     we_b;
  bram_tree_mem_t           dout_a;
  bram_tree_mem_t           dout_b;
  bram_tree_mem_t           ram_a, ram_b;
  logic [ADDRESS_WIDTH-1:0] addr_a_q, addr_b_q;
  // value of the second-best candidate. UNKNOWN_VAL (all ones) = not known: pessimistic, shows as the
  // best possible priority while rebalancing so the hybrid stalls reads. Mirror of the min-heap's 0.
  logic [DATA_WIDTH-1:0] second_largest, next_second_largest;

  rams_tdp_rf_rf bram_inst (
    .clka (i_CLK), .ena(1'b1), .wea(we_a), .addra(addr_a), .dia(din_a), .doa(ram_a),
    .clkb (i_CLK), .enb(1'b1), .web(we_b), .addrb(addr_b), .dib(din_b), .dob(ram_b)
  );

  always_ff @(posedge i_CLK) begin
    addr_a_q <= addr_a;
    addr_b_q <= addr_b;
  end

  // A node from an earlier generation reads as empty, with its whole subtree free.
  assign dout_a = (ram_a.gen == i_gen) ? ram_a : mem_node(1'b0, EMPTY_VAL, node_cap(addr_a_q));
  assign dout_b = (ram_b.gen == i_gen) ? ram_b : mem_node(1'b0, EMPTY_VAL, node_cap(addr_b_q));

  always_ff @(posedge i_CLK or negedge i_RSTn) begin : fsm_seq
    if (!i_RSTn) begin
      state          <= IDLE;
      queue_size     <= '0;
      curr           <= '0;
      second_largest <= UNKNOWN_VAL;
      top_level      <= mem_node(1'b0, EMPTY_VAL, BRAM_TREE_QUEUE_SIZE);
    end else begin
      state          <= next_state;
      queue_size     <= next_queue_size;
      curr           <= next;
      second_largest <= next_second_largest;
      top_level      <= next_top_level;
    end
  end

  always_comb begin : fsm_comb
    next_state       = state;
    next_queue_size  = queue_size;
    next             = curr;
    addr_a = '0;
    addr_b = '0;
    din_a  = '0;
    din_b  = '0;
    we_a   = 1'b0;
    we_b   = 1'b0;
    next_second_largest = second_largest;
    next_top_level      = top_level;

    parent_idx      = (curr.position - 1) >> 1;
    child_idx_left  = curr.position * 2 + 1;
    child_idx_right = curr.position * 2 + 2;

    if (i_filling) begin
      // Park the walk in IDLE while the sweep rewrites the node memory.
      next_state = IDLE;
      addr_a     = i_fill_addr;
      we_a       = 1'b1;
      din_a      = mem_node(1'b0, EMPTY_VAL, i_fill_cap);
    end else begin
    case (state)
      IDLE: begin
        if (i_wrt && !i_read && !o_full) begin // --- ENQUEUE ---
          if (queue_size == 0) begin
            next_top_level = mem_node(1, i_data, BRAM_TREE_QUEUE_SIZE - 1);
            next_state = IDLE;
          end else begin
            if (i_data > top_level.value) begin
              next_top_level = mem_node(1, i_data, top_level.capacity-1);
              next = curr_node(top_level.value, '0, top_level.capacity-1);
              next_second_largest = top_level.value;
            end else begin
              next_top_level = mem_node(1, top_level.value, top_level.capacity-1);
              next = curr_node(i_data, '0, top_level.capacity-1);
            end
            addr_a = 1;
            addr_b = 2;
            next_state = ENQUEUE_COMPARE_CHILD;
          end
          next_queue_size = queue_size + 1;
        end else if (!i_wrt && i_read && !o_empty) begin // --- DEQUEUE ---
          if (second_largest > top_level.value) begin
            // the second_largest should not be greater than the largest... can happen if queue_size is 1
            next_top_level = mem_node(0, EMPTY_VAL, top_level.capacity+1);
          end else begin
            next_top_level = mem_node(0, second_largest, top_level.capacity+1);
          end
          next = curr_node(EMPTY_VAL, '0, top_level.capacity+1);
          addr_a = 1;
          addr_b = 2;
          next_queue_size = queue_size - 1;
          next_state = DEQUEUE_COMPARE_ROOT;
        end else if (i_wrt && i_read) begin // --- REPLACE ---
          next = curr_node(i_data, '0, (o_empty) ? top_level.capacity+1 : top_level.capacity);
          if (queue_size == 0) begin
            next_top_level = mem_node(1, i_data, top_level.capacity+1);
            next_state = IDLE;
          end else begin
            if (i_data > second_largest) begin
              // new root beats even the second-best candidate, so it's guaranteed >= both children too - skip straight to IDLE
              next_top_level = mem_node(1, i_data, top_level.capacity);
              next_state = IDLE;
            end else begin
              next_top_level = mem_node(0, second_largest, top_level.capacity);
              next_state = REPLACE_COMPARE_ROOT;
            end
          end
          addr_a = 1;
          addr_b = 2;
          next_queue_size = (o_empty) ? queue_size + 1 : queue_size;
        end
      end

      ENQUEUE_READ_CHILD: begin
        //read child_idx_left and child_idx_right
        addr_a = child_idx_left;
        addr_b = child_idx_right;
        next_state = ENQUEUE_COMPARE_CHILD;
      end

      ENQUEUE_COMPARE_CHILD: begin
        //if inactive we write into it, if active we check, if larger than we swap, if smaller than we traverse down the cheaper route
        if (!dout_a.active && (dout_a.capacity > 0)) begin
          //Write into left
          addr_a = child_idx_left;
          we_a   = 1;
          din_a  = mem_node(1, curr.value, dout_a.capacity - 1);
          if (curr.value > second_largest) next_second_largest = curr.value;
          next_state = IDLE;
        end else if (!dout_b.active && (dout_b.capacity > 0)) begin
          //Write into right
          addr_b = child_idx_right;
          we_b   = 1;
          din_b  = mem_node(1, curr.value, dout_b.capacity - 1);
          if (curr.value > second_largest) next_second_largest = curr.value;
          next_state = IDLE;
        end else if (dout_a.active && (dout_a.capacity > 0) && (curr.value <= dout_a.value)) begin
          // Check children of left next
          addr_a = child_idx_left;
          we_a   = 1;
          din_a  = mem_node(1, dout_a.value, dout_a.capacity - 1);
          if (dout_a.value > second_largest) next_second_largest = dout_a.value;
          next = curr_node(curr.value, child_idx_left, dout_a.capacity - 1);
          next_state = ENQUEUE_READ_CHILD; 
        end else if (dout_b.active && (dout_b.capacity > 0) && (curr.value <= dout_b.value)) begin
          // Check children of right next
          addr_b = child_idx_right;
          we_b   = 1;
          din_b  = mem_node(1, dout_b.value, dout_b.capacity - 1); 
          if (dout_b.value > second_largest) next_second_largest = dout_b.value;
          next = curr_node(curr.value, child_idx_right, dout_b.capacity - 1);
          next_state = ENQUEUE_READ_CHILD; 
        end else if (dout_a.active && (dout_a.capacity > 0) && (curr.value > dout_a.value) && ((dout_a.value <= dout_b.value) || (dout_b.capacity == 0))) begin
          //swap Left and Curr, check children of right
          addr_a = child_idx_left;
          we_a   = 1;
          din_a  = mem_node(1, curr.value, dout_a.capacity - 1);
          if (curr.value > second_largest) next_second_largest = curr.value;
          next = curr_node(dout_a.value, child_idx_left, dout_a.capacity - 1);
          next_state = ENQUEUE_READ_CHILD; 
        end else if (dout_b.active && (dout_b.capacity > 0) && (curr.value > dout_b.value) && ((dout_a.value > dout_b.value) || (dout_a.capacity == 0))) begin
          //swap Right and Curr, check children of left
          addr_b = child_idx_right;
          we_b   = 1;
          din_b  = mem_node(1, curr.value, dout_b.capacity - 1);
          if (curr.value > second_largest) next_second_largest = curr.value;
          next = curr_node(dout_b.value, child_idx_right, dout_b.capacity - 1);
          next_state = ENQUEUE_READ_CHILD; 
        end
      end

      DEQUEUE_COMPARE_ROOT: begin
        //if both nodes are inactive or we are at the end, we go to idle next, because this is root, we set the next max out
        if ((!dout_a.active && !dout_b.active) || (child_idx_left > BRAM_TREE_QUEUE_SIZE) || (child_idx_right > BRAM_TREE_QUEUE_SIZE)) begin
          next_top_level = mem_node(0, EMPTY_VAL, BRAM_TREE_QUEUE_SIZE);
          next_second_largest = UNKNOWN_VAL;
          next_state = IDLE;
        end else begin
          // if only one is inactive we pull that value
          if (dout_a.active && !dout_b.active) begin
            addr_b = child_idx_left;
            we_b = 1;
            din_b = mem_node(0, EMPTY_VAL, dout_a.capacity + 1);

            next = curr_node(curr.value, child_idx_left, dout_a.capacity + 1);
            next_top_level = mem_node(1, dout_a.value, curr.capacity);
          end else if (dout_b.active && !dout_a.active) begin
            addr_a = child_idx_right;
            we_a = 1;
            din_a = mem_node(0, EMPTY_VAL, dout_b.capacity + 1);

            next = curr_node(curr.value, child_idx_right, dout_b.capacity + 1);
            next_top_level = mem_node(1, dout_b.value, curr.capacity);
          end else if (dout_a.active && dout_b.active) begin
            if (dout_a.value >= dout_b.value) begin
              addr_b = child_idx_left;
              we_b = 1;
              din_b = mem_node(0, EMPTY_VAL, dout_a.capacity + 1);

              next = curr_node(curr.value, child_idx_left, dout_a.capacity + 1);
              next_top_level = mem_node(1, dout_a.value, curr.capacity);
              next_second_largest = dout_b.value;
            end else begin
              addr_a = child_idx_right;
              we_a = 1;
              din_a = mem_node(0, EMPTY_VAL, dout_b.capacity + 1);

              next = curr_node(curr.value, child_idx_right, dout_b.capacity + 1);
              next_top_level = mem_node(1, dout_b.value, curr.capacity);
              next_second_largest = dout_a.value;
            end
          end
          next_state = DEQUEUE_READ_CHILD;
        end
      end

      DEQUEUE_READ_CHILD: begin
        //read child_idx_left and child_idx_right
        if ((child_idx_left > BRAM_TREE_QUEUE_SIZE) || (child_idx_right > BRAM_TREE_QUEUE_SIZE)) begin
          next_state = IDLE;
        end else begin
          addr_a = child_idx_left;
          addr_b = child_idx_right;
          next_state = DEQUEUE_COMPARE_CHILD;
        end
      end

      DEQUEUE_COMPARE_CHILD: begin
        //if both nodes are inactive or we are at the end, we go to idle next
        if ((!dout_a.active && !dout_b.active) || (child_idx_left > BRAM_TREE_QUEUE_SIZE) || (child_idx_right > BRAM_TREE_QUEUE_SIZE)) begin
          next_state = IDLE;
        end else begin
          // if only one is inactive we pull that value
          if (dout_a.active && !dout_b.active) begin
            addr_a = curr.position;
            we_a = 1;
            din_a = mem_node(1, dout_a.value, curr.capacity);

            addr_b = child_idx_left;
            we_b = 1;
            din_b = mem_node(0, EMPTY_VAL, dout_a.capacity + 1);

            next = curr_node(curr.value, child_idx_left, dout_a.capacity + 1);
            if (dout_a.value > second_largest) next_second_largest = dout_a.value;
          end else if (dout_b.active && !dout_a.active) begin
            addr_b = curr.position;
            we_b = 1;
            din_b = mem_node(1, dout_b.value, curr.capacity);

            addr_a = child_idx_right;
            we_a = 1;
            din_a = mem_node(0, EMPTY_VAL, dout_b.capacity + 1);

            next = curr_node(curr.value, child_idx_right, dout_b.capacity + 1);
            if (dout_b.value > second_largest) next_second_largest = dout_b.value;
          end else if (dout_a.active && dout_b.active) begin
            if (dout_a.value >= dout_b.value) begin
              addr_a = curr.position;
              we_a = 1;
              din_a = mem_node(1, dout_a.value, curr.capacity);

              addr_b = child_idx_left;
              we_b = 1;
              din_b = mem_node(0, EMPTY_VAL, dout_a.capacity + 1);

              next = curr_node(curr.value, child_idx_left, dout_a.capacity + 1);
              if (dout_a.value > second_largest) next_second_largest = dout_a.value;
            end else begin
              addr_b = curr.position;
              we_b = 1;
              din_b = mem_node(1, dout_b.value, curr.capacity);

              addr_a = child_idx_right;
              we_a = 1;
              din_a = mem_node(0, EMPTY_VAL, dout_b.capacity + 1);

              next = curr_node(curr.value, child_idx_right, dout_b.capacity + 1);
              if (dout_b.value > second_largest) next_second_largest = dout_b.value;
            end
          end
          next_state = DEQUEUE_READ_CHILD;
        end
      end

      REPLACE_READ_ROOT: begin
        //get the current capacity, and then read the children
        addr_a = child_idx_left;
        addr_b = child_idx_right;
        next = curr_node(curr.value, '0, dout_a.capacity);
        next_state = REPLACE_COMPARE_ROOT;
      end

      REPLACE_COMPARE_ROOT: begin
        //if the current node is the only node or the largest node, we just write into it and go back to idle
        if ((!dout_a.active && !dout_b.active) || (child_idx_left > BRAM_TREE_QUEUE_SIZE) || (child_idx_right > BRAM_TREE_QUEUE_SIZE) || ((curr.value >= dout_a.value) && (curr.value >= dout_b.value))) begin
          next_top_level = mem_node(1, curr.value, curr.capacity);
          next_state = IDLE;
        end else begin
          // otherwise swap with the higher priority (larger) node
          // swap with A
          if ((dout_a.active && !dout_b.active) || (dout_a.value >= dout_b.value)) begin
            addr_b = child_idx_left;
            we_b = 1;
            din_b = mem_node(1, curr.value, dout_a.capacity);

            next = curr_node(curr.value, child_idx_left, dout_a.capacity);
            next_top_level = mem_node(1, dout_a.value, curr.capacity);
            if (curr.value > dout_b.value) begin
              next_second_largest = curr.value;
            end else begin
              next_second_largest = dout_b.value;
            end
          end else if ((dout_b.active && !dout_a.active) || (dout_b.value >= dout_a.value)) begin
            addr_a = child_idx_right;
            we_a = 1;
            din_a = mem_node(1, curr.value, dout_b.capacity);

            next = curr_node(curr.value, child_idx_right, dout_b.capacity);
            next_top_level = mem_node(1, dout_b.value, curr.capacity);
            if (curr.value > dout_a.value) begin
              next_second_largest = curr.value;
            end else begin
              next_second_largest = dout_a.value;
            end
          end
          next_state = REPLACE_READ_CHILD;
        end
      end

      REPLACE_READ_CHILD: begin
        //read child_idx_left and child_idx_right
        if ((child_idx_left > BRAM_TREE_QUEUE_SIZE) || (child_idx_right > BRAM_TREE_QUEUE_SIZE)) begin
          next_state = IDLE;
        end else begin
          addr_a = child_idx_left;
          addr_b = child_idx_right;
          next_state = REPLACE_COMPARE_CHILD;
        end
      end
      
      REPLACE_COMPARE_CHILD: begin
        if ((!dout_a.active && !dout_b.active) || (child_idx_left > BRAM_TREE_QUEUE_SIZE) || (child_idx_right > BRAM_TREE_QUEUE_SIZE) || ((curr.value >= dout_a.value) && (curr.value >= dout_b.value))) begin
          addr_a = curr.position;
          we_a = 1;
          din_a = mem_node(1, curr.value, curr.capacity);
          next_state = IDLE;
        end else begin
          // otherwise swap with the higher priority (larger) node
          // swap with A
          if ((dout_a.active && !dout_b.active) || (dout_a.value >= dout_b.value)) begin
            addr_a = curr.position;
            we_a = 1;
            din_a = mem_node(1, dout_a.value, curr.capacity);

            addr_b = child_idx_left;
            we_b = 1;
            din_b = mem_node(1, curr.value, dout_a.capacity);

            next = curr_node(curr.value, child_idx_left, dout_a.capacity);
            if (dout_a.value > second_largest) next_second_largest = dout_a.value;
          end else if ((dout_b.active && !dout_a.active) || (dout_b.value >= dout_a.value)) begin
            addr_b = curr.position;
            we_b = 1;
            din_b = mem_node(1, dout_b.value, curr.capacity);

            addr_a = child_idx_right;
            we_a = 1;
            din_a = mem_node(1, curr.value, dout_b.capacity);

            next = curr_node(curr.value, child_idx_right, dout_b.capacity);
            if (dout_b.value > second_largest) next_second_largest = dout_b.value;
          end
          next_state = REPLACE_READ_CHILD;
        end
      end
    endcase
    end
  end

  assign o_full  = (queue_size == BRAM_TREE_QUEUE_SIZE);
  assign o_empty = (queue_size == 0);
  assign o_data  = top_level.value;
  // Low until gen has advanced and through the fill, so no command reads a stale node as live.
  assign o_ready = (state == IDLE) && !i_filling && !i_gen_pending && !(i_read || i_wrt);
endmodule

// Reset generation and tree memory fill, shared by trees that reset together.
module bram_tree_reset (
    input  logic                     i_CLK,
    input  logic                     i_RSTn,
    output logic [GEN_W-1:0]         o_gen,
    output logic                     o_gen_pending,
    output logic                     o_filling,
    output logic [ADDRESS_WIDTH-1:0] o_fill_addr,
    output logic [ADDRESS_WIDTH-1:0] o_fill_cap
);
  // Counts resets, so it is not reset itself.
  logic [GEN_W-1:0] gen        = '0;
  logic             rst_pend;
  logic             rst_pend_q = 1'b0;

  // The BRAM has no reset port: a reset retires its contents by advancing gen, and the fill
  // rewrites every node only when gen wraps, since a wrapped tag can match a stale node.
  logic                            filling    = POWERUP_FILL;
  logic [ADDRESS_WIDTH-1:0]        fill_cnt   = '0;
  logic [$clog2(TREE_DEPTH+1)-1:0] fill_level = '0;
  logic [ADDRESS_WIDTH+1:0]        fill_bound = 'd1;
  logic [ADDRESS_WIDTH-1:0]        fill_cap;

  // fill_cap halves per fill_level, so each depth's nodes get that subtree's capacity.
  assign fill_cap = ADDRESS_WIDTH'(((NODES_NEEDED + 1) >> fill_level) - 1);

  // gen advances when rst_pend falls, so it counts each reset pulse without sampling i_RSTn.
  always_ff @(posedge i_CLK or negedge i_RSTn) begin
    if (!i_RSTn) rst_pend <= 1'b1;
    else         rst_pend <= 1'b0;
  end

  always_ff @(posedge i_CLK) begin : gen_seq
    rst_pend_q <= rst_pend;
    if (rst_pend_q && !rst_pend) gen <= gen + 1'b1;
  end

  always_ff @(posedge i_CLK) begin : fill_seq
    if (rst_pend_q && !rst_pend && &gen) begin
      filling    <= 1'b1;
      fill_cnt   <= '0;
      fill_level <= '0;
      fill_bound <= 'd1;
    end else if (filling && !rst_pend) begin
      if (fill_cnt == ADDRESS_WIDTH'(NODES_NEEDED - 1)) begin
        filling <= 1'b0;
      end else begin
        fill_cnt <= fill_cnt + 1'b1;
        if ((fill_cnt + 1'b1) == fill_bound[ADDRESS_WIDTH-1:0]) begin
          fill_level <= fill_level + 1'b1;
          fill_bound <= (fill_bound << 1) + 'd1;
        end
      end
    end
  end

  assign o_gen         = gen;
  assign o_gen_pending = rst_pend || rst_pend_q;
  assign o_filling     = filling;
  assign o_fill_addr   = fill_cnt;
  assign o_fill_cap    = fill_cap;
endmodule

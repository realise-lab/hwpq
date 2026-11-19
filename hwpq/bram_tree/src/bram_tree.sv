/*******************************************************************************
  Module Name: bram_tree
  Description: A priority queue implementation using a binary max-heap structure
               stored in block RAM (BRAM). Supports enqueue, dequeue, and replace
               operations.
  Parameters: QUEUE_SIZE - Maximum number of elements in the priority queue
              DATA_WIDTH - Bit width of data elements
  Inputs: i_CLK - System clock
          i_RSTn - Active-low reset signal
          i_wrt - Write/insert command (enqueue operation)
          i_read - Read/pop command (dequeue operation)
          i_data - Input data to be enqueued
  Outputs: o_write_ready - High when the queue has room to accept a write
           o_read_ready - High when the queue holds data available to read
           o_data - Output data from the highest priority element
  Constraints: QUEUE_SIZE must be 2^k - 1, the full-tree node count.
               '0 and all-ones are reserved payloads, never legal on i_data.
*******************************************************************************/

module bram_tree #(
    parameter integer QUEUE_SIZE = 7,
    parameter integer DATA_WIDTH = 16
) (
    input  logic                  i_CLK,
    input  logic                  i_RSTn,
    // Inputs
    input  logic                  i_wrt,    // Write/insert command
    input  logic                  i_read,   // Read/pop command
    input  logic [DATA_WIDTH-1:0] i_data,   // Input data
    // Outputs
    output logic                  o_write_ready,   // High if the heap can accept a write
    output logic                  o_read_ready,  // High if the heap has data to read
    output logic [DATA_WIDTH-1:0] o_data   // Output data (Root node)
);

  localparam integer TREE_DEPTH    = $clog2(QUEUE_SIZE + 1);
  localparam integer NODES_NEEDED  = (1 << TREE_DEPTH) - 1;
  localparam integer ADDRESS_WIDTH = $clog2(NODES_NEEDED);

  typedef struct packed {
    logic active;
    logic [DATA_WIDTH-1:0] value;
    logic [ADDRESS_WIDTH-1:0] capacity;
  } bram_tree_mem_t;

  typedef struct packed {
    logic [DATA_WIDTH-1:0] value;
    logic [ADDRESS_WIDTH-1:0] position;
    logic [ADDRESS_WIDTH-1:0] capacity;
  } bram_tree_curr_t;

  typedef enum logic [3:0] {
    IDLE                    = 4'd0,
    // Enqueue
    ENQUEUE_READ_CHILD      = 4'd1,
    ENQUEUE_COMPARE_CHILD   = 4'd2,
    // Dequeue
    DEQUEUE_COMPARE_ROOT    = 4'd3,
    DEQUEUE_READ_CHILD      = 4'd4,
    DEQUEUE_COMPARE_CHILD   = 4'd5,
    // Replace
    REPLACE_COMPARE_ROOT    = 4'd6,
    REPLACE_READ_CHILD      = 4'd7,
    REPLACE_COMPARE_CHILD   = 4'd8
  } state_t;

  state_t state, next_state;
  bram_tree_curr_t curr, next;
  bram_tree_mem_t  top_level, next_top_level;
  logic [ADDRESS_WIDTH:0] child_idx_left, child_idx_right;
  integer queue_size, next_queue_size;
  logic empty;

  logic children_out_of_range;
  logic both_children_inactive;
  logic fsm_idle;

  // The BRAM has no reset port; the fill sequencer runs after every reset to
  // explicitly write the initial values to all nodes.
  logic                            filling;
  logic [ADDRESS_WIDTH-1:0]        fill_cnt;
  logic [$clog2(TREE_DEPTH+1)-1:0] fill_level;
  logic [ADDRESS_WIDTH+1:0]        fill_bound;
  logic [ADDRESS_WIDTH-1:0]        fill_cap;

  // fill_cap halves per fill_level, so each depth's nodes get that subtree's capacity.
  assign fill_cap = ADDRESS_WIDTH'(((NODES_NEEDED + 1) >> fill_level) - 1);


  // BRAM signals
  logic [ADDRESS_WIDTH-1:0] addr_a;
  logic [ADDRESS_WIDTH-1:0] addr_b;
  bram_tree_mem_t     din_a;
  bram_tree_mem_t     din_b;
  logic                     we_a;
  logic                     we_b;
  bram_tree_mem_t     dout_a;
  bram_tree_mem_t     dout_b;

  // RAM struct<->vector conversions stay explicit (not an implicit port coercion),
  // because simulators disagree on implicit struct-to-vector port connections.

  localparam integer MEM_WIDTH = $bits(bram_tree_mem_t);

  logic [MEM_WIDTH-1:0] ram_din_a, ram_din_b, ram_dout_a, ram_dout_b;

  assign ram_din_a = din_a;
  assign ram_din_b = din_b;
  assign dout_a    = bram_tree_mem_t'(ram_dout_a);
  assign dout_b    = bram_tree_mem_t'(ram_dout_b);

  rams_tdp_rf_rf #(
      .WIDTH    (MEM_WIDTH),
      .DEPTH    (NODES_NEEDED),
      .CAP_WIDTH(ADDRESS_WIDTH)
  ) bram_inst (
    .clka (i_CLK), .ena(1'b1), .wea(we_a), .addra(addr_a), .dia(ram_din_a), .doa(ram_dout_a),
    .clkb (i_CLK), .enb(1'b1), .web(we_b), .addrb(addr_b), .dib(ram_din_b), .dob(ram_dout_b)
  );

  always_ff @(posedge i_CLK or negedge i_RSTn) begin : fsm_seq
    if (!i_RSTn) begin
      state      <= IDLE;
      queue_size <= 0;
      curr       <= '0;
      top_level.active   <= 1'b0;
      top_level.value    <= '0;
      top_level.capacity <= QUEUE_SIZE;
    end else begin
      state      <= next_state;
      queue_size <= next_queue_size;
      curr       <= next;
      top_level  <= next_top_level;
    end
  end

  // Reset fill sequencer
  always_ff @(posedge i_CLK or negedge i_RSTn) begin : fill_seq
    if (!i_RSTn) begin
      filling    <= 1'b1;
      fill_cnt   <= '0;
      fill_level <= '0;
      fill_bound <= 'd1;
    end else if (filling) begin
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

  always @* begin : fsm_comb
    next_state      = state;
    next_queue_size = queue_size;
    next            = curr;
    addr_a = '0;
    addr_b = '0;
    din_a  = '0;
    din_b  = '0;
    we_a   = 1'b0;
    we_b   = 1'b0;
    next_top_level = top_level;

    child_idx_left  = curr.position * 2 + 1;
    child_idx_right = curr.position * 2 + 2;

    children_out_of_range  = (child_idx_left > QUEUE_SIZE) || (child_idx_right > QUEUE_SIZE);
    both_children_inactive = !dout_a.active && !dout_b.active;

    if (filling) begin
      // During the filling phase, the FSM is parked in IDLE and the BRAM is being written with initial values
      next_state     = IDLE;
      addr_a         = fill_cnt;
      we_a           = 1'b1;
      din_a.active   = 1'b0;
      din_a.value    = '0;
      din_a.capacity = fill_cap;
      we_b           = 1'b0;
    end else begin
    case (state)
      IDLE: begin
        if (i_wrt && !i_read && (queue_size != QUEUE_SIZE)) begin // --- ENQUEUE ---
          if (queue_size == 0) begin
            next_top_level.active   = 1'b1;
            next_top_level.value    = i_data;
            next_top_level.capacity = QUEUE_SIZE - 1;
            next_state = IDLE;
          end else begin
            if(i_data > top_level.value) begin
              next_top_level.active   = 1'b1;
              next_top_level.value    = i_data;
              next_top_level.capacity = top_level.capacity - 1;

              next.value    = top_level.value;
              next.position = '0;
              next.capacity = top_level.capacity - 1;
            end else begin
              next_top_level.active   = 1'b1;
              next_top_level.value    = top_level.value;
              next_top_level.capacity = top_level.capacity - 1;

              next.value    = i_data;
              next.position = 0;
              next.capacity = top_level.capacity - 1;
            end
            addr_a = 1;
            addr_b = 2;
            next_state = ENQUEUE_COMPARE_CHILD;
          end
          next_queue_size = queue_size + 1;
        end else if (!i_wrt && i_read && (queue_size != 0)) begin // --- DEQUEUE ---
          next_top_level.active   = 1'b0;
          next_top_level.value    = '0;
          next_top_level.capacity = top_level.capacity + 1;

          next.value    = '0;
          next.position = 0;
          next.capacity = top_level.capacity + 1;

          addr_a = 1;
          addr_b = 2;
          next_queue_size = queue_size - 1;
          next_state = DEQUEUE_COMPARE_ROOT;
        end else if (i_wrt && i_read) begin // --- REPLACE ---
          next.value    = i_data;
          next.position = 0;
          // A replace on an empty queue inserts: capacity drops to QUEUE_SIZE-1.
          next.capacity = (empty) ? ADDRESS_WIDTH'(QUEUE_SIZE - 1) : top_level.capacity;

          if (queue_size == 0) begin
            next_top_level.active   = 1'b1;
            next_top_level.value    = i_data;
            next_top_level.capacity = ADDRESS_WIDTH'(QUEUE_SIZE - 1);
            next_state = IDLE;
          end else begin
            next_top_level.active   = 1'b0;
            next_top_level.value    = '0;
            next_top_level.capacity = top_level.capacity;
            next_state = REPLACE_COMPARE_ROOT;
          end
          addr_a = 1;
          addr_b = 2;
          next_queue_size = (empty) ? queue_size + 1 : queue_size;
        end
      end

      ENQUEUE_READ_CHILD: begin
        //read child_idx_left and child_idx_right
        addr_a = child_idx_left;
        addr_b = child_idx_right;
        next_state = ENQUEUE_COMPARE_CHILD;
      end

      ENQUEUE_COMPARE_CHILD: begin
        //if inactive we write into it, if active we check, if greater than we swap, if less than we traverse down the cheaper route
        if (!dout_a.active && (dout_a.capacity > 0)) begin
          //Write into left
          addr_a = child_idx_left;
          we_a   = 1;
          din_a.active   = 1'b1;
          din_a.value    = curr.value;
          din_a.capacity = dout_a.capacity - 1;
          next_state = IDLE;
        end else if (!dout_b.active && (dout_b.capacity > 0)) begin
          //Write into right
          addr_b = child_idx_right;
          we_b   = 1;
          din_b.active   = 1'b1;
          din_b.value    = curr.value;
          din_b.capacity = dout_b.capacity - 1;
          next_state = IDLE;
        end else if (dout_a.active && (dout_a.capacity > 0) && (curr.value <= dout_a.value)) begin
          // Check children of left next
          addr_a = child_idx_left;
          we_a   = 1;
          din_a.active   = 1'b1;
          din_a.value    = dout_a.value;
          din_a.capacity = dout_a.capacity - 1;

          next.value    = curr.value;
          next.position = child_idx_left;
          next.capacity = dout_a.capacity - 1;
          next_state = ENQUEUE_READ_CHILD;
        end else if (dout_b.active && (dout_b.capacity > 0) && (curr.value <= dout_b.value)) begin
          // Check children of right next
          addr_b = child_idx_right;
          we_b   = 1;
          din_b.active   = 1'b1;
          din_b.value    = dout_b.value;
          din_b.capacity = dout_b.capacity - 1;

          next.value    = curr.value;
          next.position = child_idx_right;
          next.capacity = dout_b.capacity - 1;
          next_state = ENQUEUE_READ_CHILD;
        end else if (dout_a.active && (dout_a.capacity > 0) && (curr.value > dout_a.value) && ((dout_a.value <= dout_b.value) || (dout_b.capacity == 0))) begin
          //swap Left and Curr, check children of right
          addr_a = child_idx_left;
          we_a   = 1;
          din_a.active   = 1'b1;
          din_a.value    = curr.value;
          din_a.capacity = dout_a.capacity - 1;

          next.value    = dout_a.value;
          next.position = child_idx_left;
          next.capacity = dout_a.capacity - 1;
          next_state = ENQUEUE_READ_CHILD;
        end else if (dout_b.active && (dout_b.capacity > 0) && (curr.value > dout_b.value) && ((dout_a.value > dout_b.value) || (dout_a.capacity == 0))) begin
          //swap Right and Curr, check children of left
          addr_b = child_idx_right;
          we_b   = 1;
          din_b.active   = 1'b1;
          din_b.value    = curr.value;
          din_b.capacity = dout_b.capacity - 1;

          next.value    = dout_b.value;
          next.position = child_idx_right;
          next.capacity = dout_b.capacity - 1;
          next_state = ENQUEUE_READ_CHILD;
        end
      end

      DEQUEUE_COMPARE_ROOT: begin
        //if both nodes are inactive or we are past the end, this is root: reset next max out
        if (both_children_inactive || children_out_of_range) begin
          next_top_level.active   = 1'b0;
          next_top_level.value    = '0;
          next_top_level.capacity = QUEUE_SIZE;
          next_state = IDLE;
        end else begin
          // if only one is inactive we pull that value
          if (dout_a.active && !dout_b.active) begin
            addr_b = child_idx_left;
            we_b = 1;
            din_b.active   = 1'b0;
            din_b.value    = '0;
            din_b.capacity = dout_a.capacity + 1;

            next.value    = curr.value;
            next.position = child_idx_left;
            next.capacity = dout_a.capacity + 1;

            next_top_level.active   = 1'b1;
            next_top_level.value    = dout_a.value;
            next_top_level.capacity = curr.capacity;
          end else if (dout_b.active && !dout_a.active) begin
            addr_a = child_idx_right;
            we_a = 1;
            din_a.active   = 1'b0;
            din_a.value    = '0;
            din_a.capacity = dout_b.capacity + 1;

            next.value    = curr.value;
            next.position = child_idx_right;
            next.capacity = dout_b.capacity + 1;

            next_top_level.active   = 1'b1;
            next_top_level.value    = dout_b.value;
            next_top_level.capacity = curr.capacity;
          end else if (dout_a.active && dout_b.active) begin
            if (dout_a.value >= dout_b.value) begin
              addr_b = child_idx_left;
              we_b = 1;
              din_b.active   = 1'b0;
              din_b.value    = '0;
              din_b.capacity = dout_a.capacity + 1;

              next.value    = curr.value;
              next.position = child_idx_left;
              next.capacity = dout_a.capacity + 1;

              next_top_level.active   = 1'b1;
              next_top_level.value    = dout_a.value;
              next_top_level.capacity = curr.capacity;
            end else begin
              addr_a = child_idx_right;
              we_a = 1;
              din_a.active   = 1'b0;
              din_a.value    = '0;
              din_a.capacity = dout_b.capacity + 1;

              next.value    = curr.value;
              next.position = child_idx_right;
              next.capacity = dout_b.capacity + 1;

              next_top_level.active   = 1'b1;
              next_top_level.value    = dout_b.value;
              next_top_level.capacity = curr.capacity;
            end
          end
          next_state = DEQUEUE_READ_CHILD;
        end
      end

      DEQUEUE_READ_CHILD: begin
        //read child_idx_left and child_idx_right
        if (children_out_of_range) begin
          next_state = IDLE;
        end else begin
          addr_a = child_idx_left;
          addr_b = child_idx_right;
          next_state = DEQUEUE_COMPARE_CHILD;
        end
      end

      DEQUEUE_COMPARE_CHILD: begin
        //if both nodes are inactive or we are past the end, we go to idle next
        if (both_children_inactive || children_out_of_range) begin
          next_state = IDLE;
        end else begin
          // if only one is inactive we pull that value
          if (dout_a.active && !dout_b.active) begin
            addr_a = curr.position;
            we_a = 1;
            din_a.active   = 1'b1;
            din_a.value    = dout_a.value;
            din_a.capacity = curr.capacity;

            addr_b = child_idx_left;
            we_b = 1;
            din_b.active   = 1'b0;
            din_b.value    = '0;
            din_b.capacity = dout_a.capacity + 1;

            next.value    = curr.value;
            next.position = child_idx_left;
            next.capacity = dout_a.capacity + 1;
          end else if (dout_b.active && !dout_a.active) begin
            addr_b = curr.position;
            we_b = 1;
            din_b.active   = 1'b1;
            din_b.value    = dout_b.value;
            din_b.capacity = curr.capacity;

            addr_a = child_idx_right;
            we_a = 1;
            din_a.active   = 1'b0;
            din_a.value    = '0;
            din_a.capacity = dout_b.capacity + 1;

            next.value    = curr.value;
            next.position = child_idx_right;
            next.capacity = dout_b.capacity + 1;
          end else if (dout_a.active && dout_b.active) begin
            if (dout_a.value >= dout_b.value) begin
              addr_a = curr.position;
              we_a = 1;
              din_a.active   = 1'b1;
              din_a.value    = dout_a.value;
              din_a.capacity = curr.capacity;

              addr_b = child_idx_left;
              we_b = 1;
              din_b.active   = 1'b0;
              din_b.value    = '0;
              din_b.capacity = dout_a.capacity + 1;

              next.value    = curr.value;
              next.position = child_idx_left;
              next.capacity = dout_a.capacity + 1;
            end else begin
              addr_b = curr.position;
              we_b = 1;
              din_b.active   = 1'b1;
              din_b.value    = dout_b.value;
              din_b.capacity = curr.capacity;

              addr_a = child_idx_right;
              we_a = 1;
              din_a.active   = 1'b0;
              din_a.value    = '0;
              din_a.capacity = dout_b.capacity + 1;

              next.value    = curr.value;
              next.position = child_idx_right;
              next.capacity = dout_b.capacity + 1;
            end
          end
          next_state = DEQUEUE_READ_CHILD;
        end
      end

      REPLACE_COMPARE_ROOT: begin
        //if the current node is the only node or the greatest node, we just write into it and go back to idle
        if (both_children_inactive || children_out_of_range || ((curr.value >= dout_a.value) && (curr.value >= dout_b.value))) begin
          next_top_level.active   = 1'b1;
          next_top_level.value    = curr.value;
          next_top_level.capacity = curr.capacity;
          next_state = IDLE;
        end else begin
          // otherwise swap with the higher priority node
          // swap with A
          if ((dout_a.active && !dout_b.active) || (dout_a.value >= dout_b.value)) begin
            addr_b = child_idx_left;
            we_b = 1;
            din_b.active   = 1'b1;
            din_b.value    = curr.value;
            din_b.capacity = dout_a.capacity;

            next.value    = curr.value;
            next.position = child_idx_left;
            next.capacity = dout_a.capacity;

            next_top_level.active   = 1'b1;
            next_top_level.value    = dout_a.value;
            next_top_level.capacity = curr.capacity;
          end else if ((dout_b.active && !dout_a.active) || (dout_b.value >= dout_a.value)) begin
            addr_a = child_idx_right;
            we_a = 1;
            din_a.active   = 1'b1;
            din_a.value    = curr.value;
            din_a.capacity = dout_b.capacity;

            next.value    = curr.value;
            next.position = child_idx_right;
            next.capacity = dout_b.capacity;

            next_top_level.active   = 1'b1;
            next_top_level.value    = dout_b.value;
            next_top_level.capacity = curr.capacity;
          end
          next_state = REPLACE_READ_CHILD;
        end
      end

      REPLACE_READ_CHILD: begin
        //read child_idx_left and child_idx_right
        if (children_out_of_range) begin
          next_state = IDLE;
        end else begin
          addr_a = child_idx_left;
          addr_b = child_idx_right;
          next_state = REPLACE_COMPARE_CHILD;
        end
      end

      REPLACE_COMPARE_CHILD: begin
        if (both_children_inactive || children_out_of_range || ((curr.value >= dout_a.value) && (curr.value >= dout_b.value))) begin
          addr_a = curr.position;
          we_a = 1;
          din_a.active   = 1'b1;
          din_a.value    = curr.value;
          din_a.capacity = curr.capacity;
          next_state = IDLE;
        end else begin
          // otherwise swap with the higher priority node
          // swap with A
          if ((dout_a.active && !dout_b.active) || (dout_a.value >= dout_b.value)) begin
            addr_a = curr.position;
            we_a = 1;
            din_a.active   = 1'b1;
            din_a.value    = dout_a.value;
            din_a.capacity = curr.capacity;

            addr_b = child_idx_left;
            we_b = 1;
            din_b.active   = 1'b1;
            din_b.value    = curr.value;
            din_b.capacity = dout_a.capacity;

            next.value    = curr.value;
            next.position = child_idx_left;
            next.capacity = dout_a.capacity;
          end else if ((dout_b.active && !dout_a.active) || (dout_b.value >= dout_a.value)) begin
            addr_b = curr.position;
            we_b = 1;
            din_b.active   = 1'b1;
            din_b.value    = dout_b.value;
            din_b.capacity = curr.capacity;

            addr_a = child_idx_right;
            we_a = 1;
            din_a.active   = 1'b1;
            din_a.value    = curr.value;
            din_a.capacity = dout_b.capacity;

            next.value    = curr.value;
            next.position = child_idx_right;
            next.capacity = dout_b.capacity;
          end
          next_state = REPLACE_READ_CHILD;
        end
      end
    endcase
    end
  end

  // fsm_idle is gated on !filling so both readies stay low through the reset fill.
  assign fsm_idle      = (state == IDLE) && !filling;
  // Readies depend on state only, never on i_wrt/i_read, or a hold-valid master deadlocks.
  assign o_write_ready = (queue_size != QUEUE_SIZE) && fsm_idle;
  assign o_read_ready  = (queue_size != 0)          && fsm_idle;
  assign o_data        = (queue_size == 0) ? 0 : top_level.value;
  assign empty          = (queue_size == 0);
endmodule
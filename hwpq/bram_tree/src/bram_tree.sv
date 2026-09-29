/*******************************************************************************
  Module Name: bram_tree
  Date: 2025/03/05
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

  Cleanup notes (relative to original):
    - Removed parent_idx and the parent/left_child/right_child registers
      (next_state logic never wrote or read them).
    - Removed three unreachable states: ENQUEUE_COMPARE_ROOT,
      DEQUEUE_READ_ROOT_CHILDREN, REPLACE_READ_ROOT.
    - Factored the repeated "are we past the last valid child / are both
      children inactive" checks into children_out_of_range and
      both_children_inactive.
    - Factored the repeated "(state == IDLE) && !(i_read || i_wrt)" term
      used by all three ready/valid outputs into idle_and_no_new_request.
    - Replaced all `'{field: value, ...}` assignment-pattern struct literals
      with field-by-field assignment (next.value = ...; next.position = ...;
      etc.) for Icarus Verilog compatibility. Plain '0 fills are unaffected.
*******************************************************************************/

package bram_tree_pkg;
  localparam integer DATA_WIDTH = 16;
  localparam integer QUEUE_SIZE = 7;
  localparam integer TREE_DEPTH    = $clog2(QUEUE_SIZE + 1);
  localparam integer NODES_NEEDED  = (1 << TREE_DEPTH) - 1;
  localparam integer ADDRESS_WIDTH = $clog2(NODES_NEEDED);

  // Define your structs here so all modules can see them
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
endpackage

import bram_tree_pkg::*;

module bram_tree (
    input  logic                  i_CLK,
    input  logic                  i_RSTn,
    // Inputs
    input  logic                  i_wrt,    // Write/insert command
    input  logic                  i_read,   // Read/pop command
    input  logic [DATA_WIDTH-1:0] i_data,   // Input data
    // Outputs
    output logic                  o_write_ready,   // High if the heap is full
    output logic                  o_read_ready,  // High if the heap is empty
    output logic [DATA_WIDTH-1:0] o_data   // Output data (Root node)
);

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
  logic idle_and_no_new_request;


  // BRAM signals
  logic [ADDRESS_WIDTH-1:0] addr_a;
  logic [ADDRESS_WIDTH-1:0] addr_b;
  bram_tree_mem_t     din_a;
  bram_tree_mem_t     din_b;
  logic                     we_a;
  logic                     we_b;
  bram_tree_mem_t     dout_a;
  bram_tree_mem_t     dout_b;

  rams_tdp_rf_rf bram_inst (
    .clka (i_CLK), .ena(1'b1), .wea(we_a), .addra(addr_a), .dia(din_a), .doa(dout_a),
    .clkb (i_CLK), .enb(1'b1), .web(we_b), .addrb(addr_b), .dib(din_b), .dob(dout_b)
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

    case (state)
      IDLE: begin
        if (i_wrt && !i_read) begin // --- ENQUEUE ---
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
        end else if (!i_wrt && i_read) begin // --- DEQUEUE ---
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
          next.capacity = (empty) ? top_level.capacity + 1 : top_level.capacity;

          if (queue_size == 0) begin
            next_top_level.active   = 1'b1;
            next_top_level.value    = i_data;
            next_top_level.capacity = top_level.capacity + 1;
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

  assign idle_and_no_new_request = (state == IDLE) && !(i_read || i_wrt);
  assign o_write_ready = (queue_size != QUEUE_SIZE) && idle_and_no_new_request;
  assign o_read_ready  = (queue_size != 0)           && idle_and_no_new_request;
  assign o_data        = (queue_size == 0) ? 0 : top_level.value;
  assign empty          = (queue_size == 0);
endmodule
/*******************************************************************************
  Module Name: bram_tree_pipelined
  Description: A pipelined priority queue implementation using a binary max-heap
               structure stored in block RAM, with the top few levels
               kept in registers. Supports enqueue, dequeue, and replace
               operations, trading throughput (one replace every four cycles)
               for improved scalability over the non-pipelined BRAM tree.
  Parameters: QUEUE_SIZE - Maximum number of elements in the priority queue
              DATA_WIDTH - Bit width of data elements
  Inputs: i_CLK - System clock
          i_RSTn - Active-low reset signal
          i_wrt - Write/insert command (enqueue operation)
          i_read - Read/pop command (dequeue operation)
          i_data - Input data to be inserted (or used for replace)
  Outputs: o_write_ready - High when the queue has room to accept a write
           o_read_ready - High when the queue holds data available to read
           o_data - Output data from the highest priority element
  Constraints: QUEUE_SIZE must be 2^k - 1, the full-tree node count.
               '0 and all-ones are reserved payloads, never legal on i_data.
               Reset leaves the queue physically full of all-ones placeholders
               while queue_size reports 0, so the queue never advertises full.
*******************************************************************************/

module bram_tree_pipelined #(
    parameter integer QUEUE_SIZE = 7,
    parameter integer DATA_WIDTH = 16
) (
    input  logic                  i_CLK,
    input  logic                  i_RSTn,
    // Inputs
    input  logic                  i_wrt,    // Write/insert command
    input  logic                  i_read,   // Read/pop command
    input  logic [DATA_WIDTH-1:0] i_data,   // Data to be inserted (or used for replace)
    // Outputs
    output logic                  o_write_ready,   // High if the queue can accept a write
    output logic                  o_read_ready,  // High if the queue has data to read
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
  localparam integer ADDRESS_WIDTH = $clog2(NODES_NEEDED)-1;  // address width of the BRAMs

  //-------------------------------------------------------------------------
  // Internal used wires and registers
  //-------------------------------------------------------------------------
  // Registers for root node and its children
  logic [DATA_WIDTH-1:0] level_0;
  logic [DATA_WIDTH-1:0] level_1[2];
  logic [DATA_WIDTH-1:0] next_level_0;
  logic [DATA_WIDTH-1:0] next_level_1[2];

  // Memory used wires and registers
  logic [ADDRESS_WIDTH:0] addr_a[2:TREE_DEPTH-1];
  logic [ADDRESS_WIDTH:0] addr_b[2:TREE_DEPTH-1];
  logic [DATA_WIDTH-1:0] dout_a[2:TREE_DEPTH-1];
  logic [DATA_WIDTH-1:0] dout_b[2:TREE_DEPTH-1];
  logic [DATA_WIDTH-1:0] din_a[2:TREE_DEPTH-1];
  logic [DATA_WIDTH-1:0] din_b[2:TREE_DEPTH-1];
  logic we_a[2:TREE_DEPTH-1];
  logic we_b[2:TREE_DEPTH-1];

  logic [ADDRESS_WIDTH:0] next_addr_a[2:TREE_DEPTH-1];
  logic [ADDRESS_WIDTH:0] next_addr_b[2:TREE_DEPTH-1];
  logic [DATA_WIDTH-1:0] next_din_a[2:TREE_DEPTH-1];
  logic [DATA_WIDTH-1:0] next_din_b[2:TREE_DEPTH-1];
  logic next_we_a[2:TREE_DEPTH-1];
  logic next_we_b[2:TREE_DEPTH-1];

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

  logic sift_done, next_sift_done;  // whole walk finished - may accept a command
  logic root_done, next_root_done;  // root written back - o_data is trustworthy
  logic cmd_dequeue, cmd_replace;
  logic accept_ok;                  // quiescent and initialised: may take a command
  logic head_servable;              // the root holds data, not a placeholder

  // The BRAMs have no reset port, and the `initial` block in rams_tdp_rf_rf.sv is
  // simulation-only: synthesis takes it as a power-up value only. The fill
  // sequencer below re-establishes the all-ones placeholder fill on every reset.
  // FILL_LAST is one past the last address because addr/din/we are registered, so
  // the write issued at NODES_NEEDED-1 does not commit until the cycle after.
  localparam integer FILL_LAST = NODES_NEEDED + 1;
  logic filling;
  logic [$clog2(FILL_LAST+1)-1:0] fill_cnt;
  logic [DATA_WIDTH-1:0] cmd_data;   // command payload latched at accept

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
    for (i = 2; i < TREE_DEPTH; i++) begin : gen_bram  // Using BRAM starts from level 2
      rams_tdp_rf_rf #(
          .WIDTH(DATA_WIDTH),
          .DEPTH(NODES_NEEDED)
      ) bram_inst (
          .clka (i_CLK),
          .ena  (1'b1),
          .wea  (we_a[i]),
          .addra(addr_a[i]),
          .dia  (din_a[i]),
          .doa  (dout_a[i]),
          .clkb (i_CLK),
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
  always_ff @(posedge i_CLK or negedge i_RSTn) begin : fsm_seq
    if (!i_RSTn) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

  always_comb begin : fsm_comb
    next_state = IDLE;  // default next state, latch preventing
    // Parked during the reset fill. IDLE otherwise advances to READ_MEM
    // unconditionally, so without this guard the walk would free-run with no
    // command outstanding, driving the comparator from memory mid-sweep and
    // writing that result over the fill.
    if (filling) begin
      next_state = IDLE;
    end else begin
    case (state)
      IDLE: begin
        next_state = READ_MEM;
        if (cmd_dequeue) begin  // dequeue
          next_state = DEQUEUE;
        end else if (cmd_replace) begin  // replace
          next_state = REPLACE;
        end
      end

      READ_MEM: begin
        next_state = WAIT;
        if (cmd_dequeue) begin  // dequeue
          next_state = DEQUEUE;
        end else if (cmd_replace) begin  // replace
          next_state = REPLACE;
        end
      end

      COMPARE_SWAP: begin
        next_state = WRITE_MEM;
        if (cmd_dequeue) begin  // dequeue
          next_state = DEQUEUE;
        end else if (cmd_replace) begin  // replace
          next_state = REPLACE;
        end
      end

      WRITE_MEM: begin
        next_state = READ_MEM;
        if (cmd_dequeue) begin  // dequeue
          next_state = DEQUEUE;
        end else if (cmd_replace) begin  // replace
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
        if (cmd_dequeue) begin  // dequeue
          next_state = DEQUEUE;
        end else if (cmd_replace) begin  // replace
          next_state = REPLACE;
        end
      end

      default: begin
        next_state = IDLE;
      end
    endcase
    end
  end

  //-------------------------------------------------------------------------
  // BRAM read&write, heap management
  //-------------------------------------------------------------------------
  always_ff @(posedge i_CLK or negedge i_RSTn) begin : bram_seq
    if (!i_RSTn) begin
      parent_lvl <= '0;
      parent_idx <= '0;
      level_0 <= '1;
      for (itr_seq = 0; itr_seq < 2; itr_seq++) begin  // initialize 2 registers on level_1 
        level_1[itr_seq] <= '1;
      end
      for (lvl_seq = 2; lvl_seq < TREE_DEPTH; lvl_seq++) begin  // initialize BRAMs' ports
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
      level_0 <= next_level_0;
      for (itr_seq = 0; itr_seq < 2; itr_seq++) begin
        level_1[itr_seq] <= next_level_1[itr_seq];
      end
      for (lvl_seq = 2; lvl_seq < TREE_DEPTH; lvl_seq++) begin
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
    next_level_0 = level_0;
    for (itr_comb = 0; itr_comb < 2; itr_comb++) begin
      next_level_1[itr_comb] = level_1[itr_comb];
    end
    for (lvl_comb = 2; lvl_comb < TREE_DEPTH; lvl_comb++) begin
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
        if (parent_lvl == 'd1) begin
          next_addr_a[2] = 2 * parent_idx;
          next_addr_b[2] = 2 * parent_idx + 1;
        end else if (parent_lvl > 'd1) begin
          next_addr_a[parent_lvl]   = parent_idx;
          // The per-level arrays are [2:TREE_DEPTH-1], so [parent_lvl+1] is out
          // of range at the deepest level, where there are no children to
          // address anyway. Simulation discarded these writes silently; the
          // guard says so.
          if (parent_lvl < TREE_DEPTH - 1) begin
            next_addr_a[parent_lvl+1] = 2 * parent_idx;
            next_addr_b[parent_lvl+1] = 2 * parent_idx + 1;
          end
        end
      end

      COMPARE_SWAP: begin
        if (parent_lvl == 'd0) begin
          next_comp_parent_in = level_0;
          next_comp_left_child_in = level_1[0];
          next_comp_right_child_in = level_1[1];
        end else if (parent_lvl == 'd1) begin
          next_comp_parent_in = level_1[parent_idx];
          next_comp_left_child_in = dout_a[2];
          next_comp_right_child_in = dout_b[2];
        end else if (parent_lvl > 'd1) begin
          next_comp_parent_in = dout_a[parent_lvl];
          // At the deepest level there are no children and dout_*[parent_lvl+1]
          // is out of range, returning X. Every downstream compare then went X,
          // no branch was taken, and the walk terminated by accident. Feeding
          // the minimum makes that same outcome explicit and well defined: the
          // parent outranks both absent children, so no swap is possible.
          if (parent_lvl < TREE_DEPTH - 1) begin
            next_comp_left_child_in = dout_a[parent_lvl+1];
            next_comp_right_child_in = dout_b[parent_lvl+1];
          end else begin
            next_comp_left_child_in = '0;
            next_comp_right_child_in = '0;
          end
        end
      end

      WRITE_MEM: begin  // in order to write to BRAMs, we need enable write signals
        if (parent_lvl == 'd0) begin
          next_level_0 = comp_parent_out;
          next_level_1[0] = comp_left_child_out;
          next_level_1[1] = comp_right_child_out;
          if (comp_left_child_out != comp_left_child_in) begin
            next_parent_lvl = 'd1;
            next_parent_idx = 0;
          end else if (comp_right_child_out != comp_right_child_in) begin
            next_parent_lvl = 'd1;
            next_parent_idx = 1;
          end else begin  // if no change, then we are done
            next_parent_lvl = 'd0;
            next_parent_idx = 'd0;
          end
        end else if (parent_lvl == 'd1) begin
          next_level_1[parent_idx] = comp_parent_out;
          next_din_a[2] = comp_left_child_out;
          next_din_b[2] = comp_right_child_out;
          // find where the next parent index is
          if (comp_left_child_out != comp_left_child_in) begin
            next_parent_lvl = 'd2;
            next_parent_idx = 2 * parent_idx;
          end else if (comp_right_child_out != comp_right_child_in) begin
            next_parent_lvl = 'd2;
            next_parent_idx = 2 * parent_idx + 1;
          end else begin  // if no change, then we are done
            next_parent_lvl = 'd0;
            next_parent_idx = 'd0;
          end

          next_we_a[2] = 1'b1;
          next_we_b[2] = 1'b1;
        end else if (parent_lvl > 'd1) begin
          next_din_a[parent_lvl]   = comp_parent_out;
          // The write ENABLES for the deepest level are already cleared below;
          // these data assignments were not, and index out of range there.
          if (parent_lvl < TREE_DEPTH - 1) begin
            next_din_a[parent_lvl+1] = comp_left_child_out;
            next_din_b[parent_lvl+1] = comp_right_child_out;
          end
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
      end

      DEQUEUE: begin
        next_level_0 = 'd0;
        next_parent_lvl = 'd0;
        next_parent_idx = 'd0;
      end

      REPLACE: begin
        next_level_0 = cmd_data;  // latched at accept; i_data may be gone by now
        next_parent_lvl = 'd0;
        next_parent_idx = 'd0;
      end

      WAIT: begin  // this is a do nothing state, just for reading from RAM
      end

      default: begin
      end
    endcase

    // The fill overrides the walk's port driving. It cannot collide with it: no
    // command is accepted while `filling`, so no walk is in flight.
    if (filling) begin
      next_parent_lvl = '0;
      next_parent_idx = '0;
      next_level_0    = '1;
      next_level_1[0] = '1;
      next_level_1[1] = '1;
      for (lvl_comb = 2; lvl_comb < TREE_DEPTH; lvl_comb++) begin
        next_addr_a[lvl_comb] = fill_cnt[ADDRESS_WIDTH:0];
        next_din_a[lvl_comb]  = '1;
        next_we_a[lvl_comb]   = (fill_cnt < NODES_NEEDED[$bits(fill_cnt)-1:0]);
        next_we_b[lvl_comb]   = 1'b0;
      end
    end
  end

  //-------------------------------------------------------------------------
  // Queue size counter
  //-------------------------------------------------------------------------
  always_ff @(posedge i_CLK or negedge i_RSTn) begin : queue_size_seq
    if (!i_RSTn) begin
      queue_size <= 0;
    end else begin
      queue_size <= next_queue_size;
    end
  end

  // No enqueue branch: this module has no enqueue path in the FSM. Counting
  // (i_wrt && !i_read) here would let a master driving i_wrt alone bump queue_size
  // with nothing ever inserted, over-reporting occupancy.
  always_comb begin : queue_size_comb
    next_queue_size = queue_size;
    if (cmd_dequeue) begin
      next_queue_size = queue_size - 1; // cmd_dequeue is gated on !empty so this cannot underflow
    end else if (cmd_replace) begin
      // o_data == '1 means the root still holds a placeholder. That is normally the
      // fill phase, but the root can hold one while the queue is already occupied,
      // so the queue_size < QUEUE_SIZE guard is load-bearing: without it a replace
      // in that state would count an insert the queue has no room for.
      if (o_data == '1 && queue_size < QUEUE_SIZE) begin
        next_queue_size = queue_size + 1;
      end else if (queue_size == 0 && i_data != 0) begin  // replace on empty acts as enqueue
        next_queue_size = queue_size + 1;
      end else begin
        next_queue_size = queue_size;
      end
    end
  end

  //-------------------------------------------------------------------------
  // Reset fill sequencer
  //-------------------------------------------------------------------------
  // Runs after every reset, not just the first. No command is accepted while it
  // runs, so it cannot race the sift walk.
  always_ff @(posedge i_CLK or negedge i_RSTn) begin : fill_seq
    if (!i_RSTn) begin
      filling  <= 1'b1;
      fill_cnt <= '0;
    end else if (filling) begin
      if (fill_cnt == FILL_LAST[$bits(fill_cnt)-1:0]) filling <= 1'b0;
      else                                            fill_cnt <= fill_cnt + 1'b1;
    end
  end

  // Sift-down completion detector
  
  //   root_done: the root compare-swap has been written back, so level_0 now
  //                holds the true maximum.  o_data is trustworthy from here,
  //                even though the walk may still be sifting deeper down.

  //   sift_done: the whole walk terminated.  Only now may a new command be
  //                accepted; one arriving earlier abandons the walk part-way
  //                down and leaves the heap broken.
  
  // sift_done implies root_done so gating every command on sift_done alone is sufficient and
  // root_done is free to report the earlier instant to a reader.
  always_ff @(posedge i_CLK or negedge i_RSTn) begin : done_seq
    if (!i_RSTn) begin
      sift_done <= 1'b1;
      root_done <= 1'b1;
    end else begin
      sift_done <= next_sift_done;
      root_done <= next_root_done;
    end
  end

  always_comb begin : done_comb
    next_sift_done = sift_done;
    next_root_done = root_done;
    if (cmd_dequeue || cmd_replace) begin
      next_sift_done = 1'b0;
      next_root_done = 1'b0;
    end else if (state == WRITE_MEM) begin
      if (parent_lvl == '0)      next_root_done = 1'b1;  // root written back
      if (next_parent_lvl == '0) next_sift_done = 1'b1;  // walk terminated
    end
  end

  // "May accept a command": quiescent AND past the reset fill. One notion, used by
  // both the ready ports and the command decode, so the two cannot drift apart.
  assign accept_ok = sift_done && !filling;

  // Head-sentinel gate, the same containment the four register architectures
  // carry: this queue boots physically full of all-ones placeholders while
  // queue_size reports 0, so during the fill phase the root can hold a
  // placeholder the queue must not hand out as data.
  //
  // The term is on the COMMAND as well as on the port. Gating the port alone
  // would leave cmd_dequeue accepting a dequeue that o_read_ready does not
  // advertise, so a contract-violating dequeue becomes inert instead of
  // corrupting the size accounting.
  assign head_servable = (level_0 != '1);

  assign cmd_dequeue = !i_wrt && i_read && accept_ok && (queue_size != 0) && head_servable;
  assign cmd_replace = i_wrt && i_read && accept_ok;

  // The replace state does not execute until the cycle after the command is
  // accepted, so sampling i_data there would read whatever the master drives one
  // cycle later. Latching the value here matches every other queue in this repo,
  // which captures i_data in the accept cycle.
  always_ff @(posedge i_CLK or negedge i_RSTn) begin : cmd_data_seq
    if (!i_RSTn) begin
      cmd_data <= '0;
    end else if (cmd_replace) begin
      cmd_data <= i_data;
    end
  end

  //-------------------------------------------------------------------------
  // Assignments for status and output.
  //-------------------------------------------------------------------------
  assign o_write_ready = accept_ok;
  // root_done rises on the ROOT write-back, the first step of the walk; sift_done
  // only when the walk terminates, up to TREE_DEPTH-1 levels and ~4 cycles per
  // level later. Gating on root_done alone would advertise a dequeue that
  // cmd_dequeue (gated on sift_done) would then silently discard.
  //
  // Gating on sift_done costs nothing: no command could be accepted inside that
  // window anyway. The only thing lost is an early data-valid hint, and the
  // six-port interface gives no way for a caller to consume one.
  assign o_read_ready  = !(queue_size == 0) && accept_ok && head_servable;
  assign o_data  = level_0;

endmodule

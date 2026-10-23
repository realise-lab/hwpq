import bram_tree_pkg::*;

// Max-heap: larger value = higher priority. A node is just its value; 0 means "empty".
// Ports and behaviour match bram_tree. Siblings share one memory word, so every level of a walk
// is one pair read and one pair write: the walk moves a level per cycle.
module bram_tree_pair (
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
    output logic                  o_ready,  // Stall if we are still propagating/rebalancing
    output logic                  o_top_moved,  // o_data or o_empty may differ from last cycle
    // Upper bound on every value below the top, valid while o_next_ok; registered from last cycle
    output logic [DATA_WIDTH-1:0] o_next,
    output logic                  o_next_ok
);

  // INSERT carries a value down from node curr.position, whose children pair is being read.
  // SIFT refills the hole at curr.position, whose children pair is being read, with a value from
  // below; a replace carries its new value down, a dequeue carries nothing and frees the last hole.
  typedef enum logic [1:0] {
    IDLE   = 2'd0,
    INSERT = 2'd1,
    SIFT   = 2'd2
  } state_t;

  // Pair p holds nodes 2p+1 and 2p+2, the children of node p; node 0 (the top) is a register.
  typedef struct packed {
    bram_tree_mem_t l;
    bram_tree_mem_t r;
  } bram_tree_pair_t;
  localparam integer PAIRS       = (NODES_NEEDED - 1) / 2;
  localparam integer PAIR_W      = (PAIRS > 1) ? $clog2(PAIRS) : 1;
  localparam integer LAST_PARENT = (NODES_NEEDED - 3) / 2;

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
  logic [QUEUE_COUNT_WIDTH-1:0] queue_size, next_queue_size;
  logic            deq, next_deq;
  // The pair holding a SIFT's hole, written once the hole is refilled.
  bram_tree_pair_t par, next_par;

  // Memory signals
  logic            we;
  logic [PAIR_W-1:0] wr_addr, rd_addr, rd_addr_q;
  bram_tree_pair_t din, ram_out, dout;
  // Pair 0 (the root's children) mirrored in registers, so a command decides its first level at
  // once. Every write to pair 0 must update the copy.
  bram_tree_pair_t child;

  bram_tree_pair_ram #(.DEPTH(PAIRS), .ADDR_W(PAIR_W)) bram_inst (
    .clk(i_CLK), .we(we), .wr_addr(wr_addr), .din(din), .rd_addr(rd_addr), .dout(ram_out)
  );

  always_ff @(posedge i_CLK) rd_addr_q <= rd_addr;

  // Reset clears the copy along with the tree; the fill and every walk write through.
  always_ff @(posedge i_CLK or negedge i_RSTn) begin
    if (!i_RSTn) begin
      child            <= '0;
      child.l.capacity <= node_cap(1);
      child.r.capacity <= node_cap(2);
    end else if (we && wr_addr == '0) begin
      child <= din;
    end
  end

  // A node from an earlier generation reads as empty, with its whole subtree free.
  always_comb begin
    dout = ram_out;
    if (ram_out.l.gen != i_gen)
      dout.l = mem_node(1'b0, EMPTY_VAL, node_cap(ADDRESS_WIDTH'(2 * rd_addr_q + 1)));
    if (ram_out.r.gen != i_gen)
      dout.r = mem_node(1'b0, EMPTY_VAL, node_cap(ADDRESS_WIDTH'(2 * rd_addr_q + 2)));
  end

  // Set after every FSM state that may assign next_top_level or next_queue_size: only IDLE.
  // A state that starts writing either must be added here.
  logic top_moved;
  always_ff @(posedge i_CLK or negedge i_RSTn) begin
    if (!i_RSTn) top_moved <= 1'b1;
    else         top_moved <= state == IDLE && (i_wrt || i_read);
  end
  assign o_top_moved = top_moved;

  // Below the top every value sits under a root child or is a walk's carry. A SIFT leaves a root
  // child above its subtree only while its hole is in pair 0, so no bound then.
  // Registered a cycle late: a command's carry is in curr before a caller can owe the tree.
  logic [DATA_WIDTH-1:0] next_l, next_r, next_c;
  always_comb begin
    next_l = child.l.active ? child.l.value : EMPTY_VAL;
    next_r = child.r.active ? child.r.value : EMPTY_VAL;
    next_c = (state != IDLE) ? curr.value : EMPTY_VAL;
  end
  always_ff @(posedge i_CLK or negedge i_RSTn) begin
    if (!i_RSTn) begin
      o_next    <= EMPTY_VAL;
      o_next_ok <= 1'b0;
    end else begin
      o_next    <= (next_l >= next_r) ? ((next_l >= next_c) ? next_l : next_c)
                                      : ((next_r >= next_c) ? next_r : next_c);
      o_next_ok <= !(state == SIFT && curr.position <= 2) && !i_filling;
    end
  end

  always_ff @(posedge i_CLK or negedge i_RSTn) begin : fsm_seq
    if (!i_RSTn) begin
      state      <= IDLE;
      queue_size <= '0;
      curr       <= '0;
      deq        <= 1'b0;
      par        <= '0;
      top_level  <= mem_node(1'b0, EMPTY_VAL, BRAM_TREE_QUEUE_SIZE);
    end else begin
      state      <= next_state;
      queue_size <= next_queue_size;
      curr       <= next;
      deq        <= next_deq;
      par        <= next_par;
      top_level  <= next_top_level;
    end
  end

  // One level of each walk, shared by IDLE (pair 0 from the copy) and the walk states (from memory).
  bram_tree_pair_t lvl;            // children of the node being decided
  logic [ADDRESS_WIDTH-1:0] at;    // that node
  logic [DATA_WIDTH-1:0] carry;
  logic                  sift_deq;
  // insert: place the carry in a free child, or keep the larger of carry and child and go down
  bram_tree_pair_t       ins_pair;
  logic                  ins_done, ins_left;
  logic [DATA_WIDTH-1:0] ins_carry;
  // sift: stop with the carry, or promote the larger child into the hole and go down
  logic                  sift_stop, sift_left;
  bram_tree_mem_t        sift_z;
  logic [ADDRESS_WIDTH-1:0] at_l, at_r;

  // Each input is assigned once per evaluation: the FSM reads the step's results.
  always_comb begin
    if (state == IDLE) begin
      lvl      = child;
      at       = '0;
      sift_deq = !i_wrt;
      if (!i_read)     carry = (i_data > top_level.value) ? top_level.value : i_data;
      else if (i_wrt)  carry = i_data;
      else             carry = EMPTY_VAL;
    end else begin
      lvl      = dout;
      at       = curr.position;
      sift_deq = deq;
      carry    = curr.value;
    end
  end

  always_comb begin
    at_l = ADDRESS_WIDTH'(2 * at + 1);
    at_r = ADDRESS_WIDTH'(2 * at + 2);

    ins_pair  = lvl;
    ins_done  = 1'b0;
    ins_left  = 1'b0;
    ins_carry = carry;
    if (!lvl.l.active && lvl.l.capacity > 0) begin
      ins_pair.l = mem_node(1, carry, lvl.l.capacity - 1);
      ins_done   = 1'b1;
    end else if (!lvl.r.active && lvl.r.capacity > 0) begin
      ins_pair.r = mem_node(1, carry, lvl.r.capacity - 1);
      ins_done   = 1'b1;
    end else if (lvl.l.active && lvl.l.capacity > 0 && carry <= lvl.l.value) begin
      ins_pair.l = mem_node(1, lvl.l.value, lvl.l.capacity - 1);
      ins_left   = 1'b1;
    end else if (lvl.r.active && lvl.r.capacity > 0 && carry <= lvl.r.value) begin
      ins_pair.r = mem_node(1, lvl.r.value, lvl.r.capacity - 1);
    end else if (lvl.l.active && lvl.l.capacity > 0
                 && (lvl.l.value <= lvl.r.value || lvl.r.capacity == 0)) begin
      ins_pair.l = mem_node(1, carry, lvl.l.capacity - 1);
      ins_left   = 1'b1;
      ins_carry  = lvl.l.value;
    end else begin
      ins_pair.r = mem_node(1, carry, lvl.r.capacity - 1);
      ins_carry  = lvl.r.value;
    end

    sift_left = lvl.l.active && (!lvl.r.active || lvl.l.value >= lvl.r.value);
    sift_z    = sift_left ? lvl.l : lvl.r;
    sift_stop = !(lvl.l.active || lvl.r.active) || at > ADDRESS_WIDTH'(LAST_PARENT)
                || (!sift_deq && carry >= lvl.l.value && carry >= lvl.r.value);
  end

  always_comb begin : fsm_comb
    next_state      = state;
    next_queue_size = queue_size;
    next            = curr;
    next_deq        = deq;
    next_par        = par;
    next_top_level  = top_level;
    we      = 1'b0;
    wr_addr = '0;
    din     = '0;
    rd_addr = '0;

    if (i_filling) begin
      // Park the walk in IDLE while the sweep rewrites the node memory, a pair per left child.
      next_state = IDLE;
      we         = i_fill_addr[0];
      wr_addr    = PAIR_W'((i_fill_addr - 1) >> 1);
      din.l      = mem_node(1'b0, EMPTY_VAL, i_fill_cap);
      din.r      = din.l;
    end else begin
    case (state)
      IDLE: begin
        if (i_wrt && !i_read && !o_full) begin // --- ENQUEUE ---
          next_queue_size = queue_size + 1;
          if (queue_size == 0) begin
            next_top_level = mem_node(1, i_data, BRAM_TREE_QUEUE_SIZE - 1);
          end else begin
            // The larger of top and new value stays on top; the other walks down.
            next_top_level = mem_node(1, (i_data > top_level.value) ? i_data : top_level.value,
                                      top_level.capacity - 1);
            we      = 1'b1;
            wr_addr = '0;
            din     = ins_pair;
            if (!ins_done) begin
              next       = curr_node(ins_carry, ins_left ? at_l : at_r, '0);
              rd_addr    = PAIR_W'(ins_left ? at_l : at_r);
              next_state = INSERT;
            end
          end
        end else if (!i_wrt && i_read && !o_empty) begin // --- DEQUEUE ---
          next_queue_size = queue_size - 1;
          if (!(child.l.active || child.r.active)) begin
            next_top_level = mem_node(0, EMPTY_VAL, BRAM_TREE_QUEUE_SIZE);
          end else begin
            next_top_level = mem_node(1, sift_z.value, top_level.capacity + 1);
            next     = curr_node(EMPTY_VAL, sift_left ? at_l : at_r, sift_z.capacity + 1);
            next_deq = 1'b1;
            next_par = child;
            rd_addr  = PAIR_W'(sift_left ? at_l : at_r);
            next_state = SIFT;
          end
        end else if (i_wrt && i_read) begin // --- REPLACE ---
          next_queue_size = o_empty ? queue_size + 1 : queue_size;
          if (o_empty) begin
            next_top_level = mem_node(1, i_data, top_level.capacity + 1);
          end else if (sift_stop) begin
            next_top_level = mem_node(1, i_data, top_level.capacity);
          end else begin
            next_top_level = mem_node(1, sift_z.value, top_level.capacity);
            next     = curr_node(i_data, sift_left ? at_l : at_r, sift_z.capacity);
            next_deq = 1'b0;
            next_par = child;
            rd_addr  = PAIR_W'(sift_left ? at_l : at_r);
            next_state = SIFT;
          end
        end
      end

      INSERT: begin
        we      = 1'b1;
        wr_addr = PAIR_W'(at);
        din     = ins_pair;
        if (ins_done) begin
          next_state = IDLE;
        end else begin
          next    = curr_node(ins_carry, ins_left ? at_l : at_r, '0);
          rd_addr = PAIR_W'(ins_left ? at_l : at_r);
        end
      end

      SIFT: begin
        // The hole's own pair: index (hole - 1) / 2, the hole on the left when its index is odd.
        we      = 1'b1;
        wr_addr = PAIR_W'((at - 1) >> 1);
        din     = par;
        if (sift_stop) begin
          if (at[0]) din.l = mem_node(!deq, carry, curr.capacity);
          else       din.r = mem_node(!deq, carry, curr.capacity);
          next_state = IDLE;
        end else begin
          if (at[0]) din.l = mem_node(1, sift_z.value, curr.capacity);
          else       din.r = mem_node(1, sift_z.value, curr.capacity);
          next     = curr_node(carry, sift_left ? at_l : at_r,
                               deq ? sift_z.capacity + 1 : sift_z.capacity);
          next_par = dout;
          rd_addr  = PAIR_W'(sift_left ? at_l : at_r);
        end
      end

      default: next_state = IDLE;
    endcase
    end
  end

  assign o_full  = (queue_size == BRAM_TREE_QUEUE_SIZE);
  assign o_empty = (queue_size == 0);
  assign o_data  = top_level.value;
  // Low until gen has advanced and through the fill, so no command reads a stale node as live.
  assign o_ready = (state == IDLE) && !i_filling && !i_gen_pending && !(i_read || i_wrt);
endmodule

// Simple dual-port block RAM of node pairs, as flat {left, right} words: one write port, one read
// port with a cycle of latency. A read of the address being written returns the old word.
(* ram_style = "block"*)
module bram_tree_pair_ram #(
    parameter integer DEPTH  = 1,
    parameter integer ADDR_W = 1
) (
    input  logic                                clk,
    input  logic                                we,
    input  logic [ADDR_W-1:0]                   wr_addr,
    input  logic [2*$bits(bram_tree_mem_t)-1:0] din,
    input  logic [ADDR_W-1:0]                   rd_addr,
    output logic [2*$bits(bram_tree_mem_t)-1:0] dout
);
  // Flat words: an array of structs infers a separate RAM for each field.
  logic [2*$bits(bram_tree_mem_t)-1:0] ram [DEPTH-1:0];

  // Power-up contents: every node inactive, with its whole subtree free.
  initial begin
    int level;
    bram_tree_mem_t n;
    for (int p = 0; p < DEPTH; p++) begin
      level      = $clog2(2 * p + 3) - 1;
      n          = '0;
      n.capacity = ADDRESS_WIDTH'(((NODES_NEEDED + 1) >> level) - 1);
      ram[p]     = {n, n};
    end
  end

  always @(posedge clk) begin
    if (we) ram[wr_addr] <= din;
    dout <= ram[rd_addr];
  end
endmodule

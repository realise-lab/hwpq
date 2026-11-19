/*******************************************************************************
  Module Name: bram_tree_pair
  Description: A binary max-heap priority queue in block RAM that stores each
               pair of sibling nodes in one memory word, so a walk reads and
               writes one pair per level and moves a level per cycle. The root
               is a register, and the root's two children are mirrored in
               registers so a command decides its first level at once.
  Parameters: QUEUE_SIZE - Maximum number of elements in the priority queue
              DATA_WIDTH - Bit width of data elements
  Inputs: i_CLK - System clock
          i_RSTn - Active-low reset signal
          i_wrt - Write/insert command (enqueue/replace operation)
          i_read - Read/pop command (dequeue/replace operation)
          i_data - Input data to be enqueued (or used for replace)
  Outputs: o_write_ready - High when the queue has room to accept a write
           o_read_ready - High when the queue holds data available to read
           o_data - Output data from the highest priority element
  Constraints: QUEUE_SIZE must be 2^k - 1 with k >= 2, the full-tree node count.
               '0 and all-ones are reserved payloads, never legal on i_data.
               Both readies stay low through the reset fill, one cycle per pair.
*******************************************************************************/

module bram_tree_pair #(
    parameter integer QUEUE_SIZE = 7,
    parameter integer DATA_WIDTH = 16
) (
    input  logic                  i_CLK,
    input  logic                  i_RSTn,
    // Inputs
    input  logic                  i_wrt,
    input  logic                  i_read,
    input  logic [DATA_WIDTH-1:0] i_data,
    // Outputs
    output logic                  o_write_ready,
    output logic                  o_read_ready,
    output logic [DATA_WIDTH-1:0] o_data
);

  localparam integer TREE_DEPTH    = $clog2(QUEUE_SIZE + 1);
  localparam integer NODES_NEEDED  = (1 << TREE_DEPTH) - 1;
  localparam integer ADDRESS_WIDTH = $clog2(NODES_NEEDED);
  localparam integer COUNT_WIDTH   = $clog2(QUEUE_SIZE + 1);
  // Pair p holds nodes 2p+1 and 2p+2, the children of node p.
  localparam integer PAIRS         = (NODES_NEEDED - 1) / 2;
  localparam integer PAIR_W        = (PAIRS > 1) ? $clog2(PAIRS) : 1;
  localparam integer LAST_PARENT   = (NODES_NEEDED - 3) / 2;
  localparam logic [DATA_WIDTH-1:0] EMPTY_VAL = '0;

  // capacity: free slots in the node's subtree, the node itself included.
  typedef struct packed {
    logic                     active;
    logic [DATA_WIDTH-1:0]    value;
    logic [ADDRESS_WIDTH-1:0] capacity;
  } node_t;

  typedef struct packed {
    node_t l;
    node_t r;
  } pair_t;

  // A walk's carried value and the node it is deciding below.
  typedef struct packed {
    logic [DATA_WIDTH-1:0]    value;
    logic [ADDRESS_WIDTH-1:0] position;
    logic [ADDRESS_WIDTH-1:0] capacity;
  } curr_t;

  // INSERT carries a value down from node curr.position, whose children pair is being read.
  // SIFT refills the hole at curr.position, whose children pair is being read, with a value from
  // below; a replace carries its new value down, a dequeue carries nothing and frees the last hole.
  typedef enum logic [1:0] {
    IDLE   = 2'd0,
    INSERT = 2'd1,
    SIFT   = 2'd2
  } state_t;

  // Struct builders in place of assignment patterns, which iverilog does not parse.
  function automatic node_t mem_node(input logic a, input logic [DATA_WIDTH-1:0] v,
                                     input logic [ADDRESS_WIDTH-1:0] c);
    mem_node.active = a; mem_node.value = v; mem_node.capacity = c;
  endfunction

  // Capacity of an empty subtree rooted at node idx.
  function automatic logic [ADDRESS_WIDTH-1:0] node_cap(input logic [ADDRESS_WIDTH-1:0] idx);
    node_cap = ADDRESS_WIDTH'(NODES_NEEDED);
    for (int l = 1; l < TREE_DEPTH; l++)
      if (idx >= ADDRESS_WIDTH'((1 << l) - 1)) node_cap = ADDRESS_WIDTH'(NODES_NEEDED >> l);
  endfunction

  function automatic curr_t curr_node(input logic [DATA_WIDTH-1:0] v,
                                      input logic [ADDRESS_WIDTH-1:0] p,
                                      input logic [ADDRESS_WIDTH-1:0] c);
    curr_node.value = v; curr_node.position = p; curr_node.capacity = c;
  endfunction

  state_t state, next_state;
  curr_t  curr, next;
  node_t  top_level, next_top_level;
  logic [COUNT_WIDTH-1:0] queue_size, next_queue_size;
  logic   full, empty;
  logic   deq, next_deq;
  // The pair holding a SIFT's hole, written once the hole is refilled.
  pair_t  par, next_par;

  // The RAM has no reset port: after every reset the fill writes each pair empty, one per cycle.
  logic              filling;
  logic [PAIR_W-1:0] fill_pair;

  // Memory signals
  logic              we;
  logic [PAIR_W-1:0] wr_addr, rd_addr;
  pair_t             din, dout;
  // Pair 0 (the root's children) mirrored in registers. Every write to pair 0 must update the copy.
  pair_t             child;

  localparam integer PAIR_BITS = $bits(pair_t);
  logic [PAIR_BITS-1:0] ram_dout;
  assign dout = pair_t'(ram_dout);

  bram_tree_pair_ram #(
      .WIDTH (PAIR_BITS),
      .DEPTH (PAIRS),
      .ADDR_W(PAIR_W)
  ) bram_inst (
      .clk(i_CLK), .we(we), .wr_addr(wr_addr), .din(PAIR_BITS'(din)), .rd_addr(rd_addr),
      .dout(ram_dout)
  );

  always_ff @(posedge i_CLK or negedge i_RSTn) begin : fill_seq
    if (!i_RSTn) begin
      filling   <= 1'b1;
      fill_pair <= '0;
    end else if (filling) begin
      if (fill_pair == PAIR_W'(PAIRS - 1)) filling <= 1'b0;
      else                                 fill_pair <= fill_pair + 1'b1;
    end
  end

  always_ff @(posedge i_CLK or negedge i_RSTn) begin
    if (!i_RSTn) begin
      child            <= '0;
      child.l.capacity <= node_cap(1);
      child.r.capacity <= node_cap(2);
    end else if (we && wr_addr == '0) begin
      child <= din;
    end
  end

  always_ff @(posedge i_CLK or negedge i_RSTn) begin : fsm_seq
    if (!i_RSTn) begin
      state      <= IDLE;
      queue_size <= '0;
      curr       <= '0;
      deq        <= 1'b0;
      par        <= '0;
      top_level  <= mem_node(1'b0, EMPTY_VAL, ADDRESS_WIDTH'(QUEUE_SIZE));
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
  pair_t                 lvl;      // children of the node being decided
  logic [ADDRESS_WIDTH-1:0] at;    // that node
  logic [DATA_WIDTH-1:0] carry;
  logic                  sift_deq;
  // insert: place the carry in a free child, or keep the larger of carry and child and go down
  pair_t                 ins_pair;
  logic                  ins_done, ins_left;
  logic [DATA_WIDTH-1:0] ins_carry;
  // sift: stop with the carry, or promote the larger child into the hole and go down
  logic                  sift_stop, sift_left;
  node_t                 sift_z;
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

    if (filling) begin
      // The FSM stays parked in IDLE while the fill writes both nodes of each pair empty.
      next_state = IDLE;
      we         = 1'b1;
      wr_addr    = fill_pair;
      din.l      = mem_node(1'b0, EMPTY_VAL, node_cap(ADDRESS_WIDTH'(2 * fill_pair + 1)));
      din.r      = din.l;
    end else begin
    case (state)
      IDLE: begin
        if (i_wrt && !i_read && !full) begin // --- ENQUEUE ---
          next_queue_size = queue_size + 1'b1;
          if (empty) begin
            next_top_level = mem_node(1, i_data, ADDRESS_WIDTH'(QUEUE_SIZE - 1));
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
        end else if (!i_wrt && i_read && !empty) begin // --- DEQUEUE ---
          next_queue_size = queue_size - 1'b1;
          if (!(child.l.active || child.r.active)) begin
            next_top_level = mem_node(0, EMPTY_VAL, ADDRESS_WIDTH'(QUEUE_SIZE));
          end else begin
            next_top_level = mem_node(1, sift_z.value, top_level.capacity + 1);
            next     = curr_node(EMPTY_VAL, sift_left ? at_l : at_r, sift_z.capacity + 1);
            next_deq = 1'b1;
            next_par = child;
            rd_addr  = PAIR_W'(sift_left ? at_l : at_r);
            next_state = SIFT;
          end
        end else if (i_wrt && i_read) begin // --- REPLACE ---
          // A replace on an empty queue inserts: capacity drops to QUEUE_SIZE-1.
          next_queue_size = empty ? queue_size + 1'b1 : queue_size;
          if (empty) begin
            next_top_level = mem_node(1, i_data, ADDRESS_WIDTH'(QUEUE_SIZE - 1));
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

  assign full  = (queue_size == COUNT_WIDTH'(QUEUE_SIZE));
  assign empty = (queue_size == '0);
  // Readies depend on state only, never on i_wrt/i_read, or a hold-valid master deadlocks.
  assign o_write_ready = (state == IDLE) && !filling && !full;
  assign o_read_ready  = (state == IDLE) && !filling && !empty;
  assign o_data        = top_level.value;
endmodule

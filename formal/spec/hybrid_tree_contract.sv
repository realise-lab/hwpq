// Contract between hybrid_systolic_heap and each tree it instantiates (HYBRID_TREE_MODULE).
// TREE_SIDE=1 checks a real tree: caller obligations assumed, tree guarantees asserted.
// TREE_SIDE=0 constrains hybrid_tree_standin: tree guarantees assumed, caller obligations
// asserted against the hybrid. Both proofs must run at the same tree size for the pair to hold.
module hybrid_tree_contract #(
    parameter int QUEUE_SIZE = 3,
    parameter int DATA_WIDTH = 3,
    parameter int MAX_BUSY   = 2,  // longest run of busy cycles after a command
    parameter bit TREE_SIDE  = 1
) (
    input logic                  i_CLK,
    input logic                  i_RSTn,
    input logic                  i_wrt,
    input logic                  i_read,
    input logic [DATA_WIDTH-1:0] i_data,
    input logic                  i_filling,
    input logic                  i_gen_pending,
    input logic                  o_full,
    input logic                  o_empty,
    input logic [DATA_WIDTH-1:0] o_data,
    input logic                  o_ready,
    input logic                  o_top_moved,
    input logic [DATA_WIDTH-1:0] o_next,
    input logic                  o_next_ok
);
  localparam int CW = $clog2(QUEUE_SIZE + 1);
  localparam int BW = $clog2(MAX_BUSY + 2);

  wire cmd  = i_wrt || i_read;
  wire held = i_filling || i_gen_pending;

  // Reference contents, largest first, unused slots '0. A command updates them the cycle it is
  // issued, as the tree's top and count do.
  logic [DATA_WIDTH-1:0] m [QUEUE_SIZE];
  logic [DATA_WIDTH-1:0] popped [QUEUE_SIZE];
  logic [DATA_WIDTH-1:0] m_next [QUEUE_SIZE];
  logic [CW-1:0]         cnt;
  logic                  do_pop, do_push;

  always_comb begin
    do_pop  = i_read && cnt != '0;
    do_push = i_wrt && (i_read || cnt != CW'(QUEUE_SIZE));
    for (int i = 0; i < QUEUE_SIZE; i++)
      popped[i] = !do_pop ? m[i] : (i + 1 < QUEUE_SIZE) ? m[i + 1] : '0;
    for (int i = 0; i < QUEUE_SIZE; i++) begin
      if (!do_push || popped[i] >= i_data)    m_next[i] = popped[i];
      else if (i == 0 || popped[i-1] >= i_data) m_next[i] = i_data;
      else                                    m_next[i] = popped[i-1];
    end
  end

  // live: not the first cycle after reset, when $past still sees reset values.
  logic          live;
  logic [BW-1:0] busy;
  always_ff @(posedge i_CLK or negedge i_RSTn) begin
    if (!i_RSTn) begin
      cnt  <= '0;
      live <= 1'b0;
      busy <= '0;
      for (int i = 0; i < QUEUE_SIZE; i++) m[i] <= '0;
    end else begin
      cnt  <= cnt - CW'(do_pop) + CW'(do_push);
      live <= 1'b1;
      busy <= (o_ready || cmd || held) ? '0 : (busy == '1) ? busy : busy + 1'b1;
      for (int i = 0; i < QUEUE_SIZE; i++) m[i] <= m_next[i];
    end
  end

  // Caller obligations.
  property p_cmd_when_ready;
    @(posedge i_CLK) disable iff (!i_RSTn) cmd |-> live && $past(o_ready) && !held;
  endproperty
  property p_no_enq_full;
    @(posedge i_CLK) disable iff (!i_RSTn) i_wrt && !i_read |-> !o_full;
  endproperty
  property p_no_deq_empty;
    @(posedge i_CLK) disable iff (!i_RSTn) i_read && !i_wrt |-> !o_empty;
  endproperty
  property p_no_write_sentinel;
    @(posedge i_CLK) disable iff (!i_RSTn) i_wrt |-> i_data != '0;
  endproperty

  // Tree guarantees. The top and count are exact every cycle; o_top_moved marks the cycle after
  // a command; o_next bounds everything below the top once that cycle has passed.
  property p_empty;
    @(posedge i_CLK) disable iff (!i_RSTn) o_empty == (cnt == '0);
  endproperty
  property p_full;
    @(posedge i_CLK) disable iff (!i_RSTn) o_full == (cnt == CW'(QUEUE_SIZE));
  endproperty
  property p_data;
    @(posedge i_CLK) disable iff (!i_RSTn) o_data == m[0];
  endproperty
  property p_moved;
    @(posedge i_CLK) disable iff (!i_RSTn) o_top_moved == (!live || $past(cmd));
  endproperty
  property p_next;
    @(posedge i_CLK) disable iff (!i_RSTn) o_next_ok && !o_top_moved |-> o_next >= m[1];
  endproperty
  property p_ready_idle;
    @(posedge i_CLK) disable iff (!i_RSTn) o_ready |-> !cmd && !held;
  endproperty
  property p_ready_stays;
    @(posedge i_CLK) disable iff (!i_RSTn) live && $past(o_ready) && !cmd && !held |-> o_ready;
  endproperty
  property p_busy_bounded;
    @(posedge i_CLK) disable iff (!i_RSTn) busy <= BW'(MAX_BUSY);
  endproperty

  generate
    if (TREE_SIDE) begin : g_tree
      am_cmd_when_ready    : assume property (p_cmd_when_ready);
      am_no_enq_full       : assume property (p_no_enq_full);
      am_no_deq_empty      : assume property (p_no_deq_empty);
      am_no_write_sentinel : assume property (p_no_write_sentinel);
      a_empty              : assert property (p_empty);
      a_full               : assert property (p_full);
      a_data               : assert property (p_data);
      a_moved              : assert property (p_moved);
      a_next               : assert property (p_next);
      a_ready_idle         : assert property (p_ready_idle);
      a_ready_stays        : assert property (p_ready_stays);
      a_busy_bounded       : assert property (p_busy_bounded);

      c_full       : cover property (@(posedge i_CLK) disable iff (!i_RSTn) o_full);
      c_busy_max   : cover property (@(posedge i_CLK) disable iff (!i_RSTn)
                                     busy == BW'(MAX_BUSY));
      c_next_bound : cover property (@(posedge i_CLK) disable iff (!i_RSTn)
                                     o_next_ok && !o_top_moved && !o_ready && cnt > CW'(1));
      c_replace    : cover property (@(posedge i_CLK) disable iff (!i_RSTn)
                                     i_wrt && i_read && cnt == CW'(QUEUE_SIZE));
`ifdef HWPQ_SELFTEST
      a_selftest_must_fail : assert property (@(posedge i_CLK) disable iff (!i_RSTn) 1'b0);
`endif
    end else begin : g_standin
      a_cmd_when_ready    : assert property (p_cmd_when_ready);
      a_no_enq_full       : assert property (p_no_enq_full);
      a_no_deq_empty      : assert property (p_no_deq_empty);
      a_no_write_sentinel : assert property (p_no_write_sentinel);
      am_empty            : assume property (p_empty);
      am_full             : assume property (p_full);
      am_data             : assume property (p_data);
      am_moved            : assume property (p_moved);
      am_next             : assume property (p_next);
      am_ready_idle       : assume property (p_ready_idle);
      am_ready_stays      : assume property (p_ready_stays);
      am_busy_bounded     : assume property (p_busy_bounded);
    end
  endgenerate
endmodule

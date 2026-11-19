`default_nettype none
// White-box addendum for systolic_array: capacity and handshake agreement.
//
// Kept separate from hwpq_spec.sv, which reads only the six interface ports;
// this file reaches inside one module.
//
// systolic_array has two notions of "no more room" that must agree:
//
//   full          =  (size >= QUEUE_SIZE - 2)     what the enqueue path enforces
//   o_write_ready = !full && (bubble term)        what the queue advertises
//
// A separate threshold on either side, such as o_write_ready one slot tighter
// than `full`, would let the queue advertise no room while still accepting
// writes: a usable slot lost for a caller that honours the ready, and a window
// that behaves differently for one that does not. o_write_ready is derived from
// `full`, and these properties are what guard that coupling.

module hwpq_systolic_aux #(
    parameter int QUEUE_SIZE = 8
) (
    input var logic i_CLK,
    input var logic i_RSTn,
    input var logic i_wrt,
    input var logic i_read,
    input var logic o_write_ready,
    input var logic o_read_ready,
    input var int   size,
    input var logic full,
    input var logic empty
);

  wire settled     = o_write_ready || o_read_ready;
  wire cmd_enqueue = i_wrt && !i_read;

  // While quiescent, what the queue advertises is exactly what it will accept.
  // `settled` rules out the other reason o_write_ready drops: a MIN_VALUE bubble
  // at the head, which is a busy state rather than a capacity limit. A separate
  // threshold on either side breaks this immediately.
  a_ready_matches_accept : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      settled |-> (o_write_ready == !full));

  // The real capacity, two below nominal. The two reserved slots are what keeps
  // the shift network able to move; one is provably not enough.
  a_size_bounded : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      size <= QUEUE_SIZE - 2);

  // Anti-vacuity. Both asserts are trivial on a queue that never fills, and
  // a_ready_matches_accept says nothing unless o_write_ready is seen low while
  // settled - which is the whole case it exists to pin down.
  c_at_capacity   : cover property (@(posedge i_CLK) disable iff (!i_RSTn)
      settled && size == QUEUE_SIZE - 2);
  c_write_refused : cover property (@(posedge i_CLK) disable iff (!i_RSTn)
      settled && cmd_enqueue && !o_write_ready);

`ifdef HWPQ_SELFTEST
  // Bound without hwpq_spec, so it does not inherit that file's self-test hook.
  // A configuration with no way to fail has stopped checking.
  a_selftest_must_fail : assert property (@(posedge i_CLK) disable iff (!i_RSTn) 1'b0);
`endif


  // Is a SECOND reset in scope? Deliberately NOT disabled on !i_RSTn - the point
  // is to witness the low phase. If this is ever unreachable, the reset harness
  // is not in place and every property here describes the post-first-reset run
  // only, with any mid-operation-reset defect invisible.
  c_reset_reasserted : cover property (@(posedge i_CLK)
      i_RSTn ##1 !i_RSTn ##1 i_RSTn);

endmodule

`default_nettype wire

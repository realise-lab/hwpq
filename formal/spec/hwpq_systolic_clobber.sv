`default_nettype none
// White-box addendum for systolic_array: does a write ever destroy IB[0]?
//
// Kept separate from hwpq_systolic_aux.sv, which characterises the ready/accept
// window under no assumptions at all. This file needs the payload-alphabet
// convention to state anything, since a tracked value must be distinguishable
// from an empty cell, so merging the two would weaken the other file's results.
//
// Every enqueue and every replace writes IB[0] unconditionally, with no check
// that IB[0] is free. Whatever sat there is overwritten unless the sorting
// network moved it out in the same cycle. The shift chain that does the moving
// is anchored on the last IB slot being empty and propagates backward one cell
// per cycle, so the queue's slack decides whether IB[0] drains in time.
//
// Method: the counting abstraction hwpq_spec uses for ordering, applied to the
// physical cells instead of the interface. Pick one arbitrary value, count how
// many copies live in IB and OB, and require the count to fall only when the
// head is popped. A clobbered IB[0] is a copy that vanishes with no pop to
// account for it.

module hwpq_systolic_clobber #(
    parameter int QUEUE_SIZE = 8,
    parameter int DATA_WIDTH = 3,
    parameter int HALF_SIZE  = 4
) (
    input var logic                  i_CLK,
    input var logic                  i_RSTn,
    input var logic                  i_wrt,
    input var logic                  i_read,
    input var logic [DATA_WIDTH-1:0] i_data,
    input var logic                  o_write_ready,
    input var logic                  o_read_ready,
    input var logic [DATA_WIDTH-1:0] IB    [HALF_SIZE],
    input var logic [DATA_WIDTH-1:0] OB    [HALF_SIZE],
    input var int                    size,
    input var logic                  full,
    input var logic                  empty
);

  localparam logic [DATA_WIDTH-1:0] MIN_VALUE = '0;

  wire settled     = o_write_ready || o_read_ready;
  wire cmd_enqueue = i_wrt && !i_read;

  // MIN_VALUE is the module's reserved empty-cell sentinel, so driving it as a
  // payload is outside the supported input range and wedges the queue.
  am_payload_legal : assume property (@(posedge i_CLK) disable iff (!i_RSTn)
      i_data != MIN_VALUE);

  // The quiescence convention shared with hwpq_spec.
  am_no_cmd_while_busy : assume property (@(posedge i_CLK) disable iff (!i_RSTn)
      !settled |-> !i_wrt && !i_read);

  // The tracked value: undriven, so the tool explores every choice at once.
  logic [DATA_WIDTH-1:0] tv;

  am_tv_stable : assume property (@(posedge i_CLK) disable iff (!i_RSTn)
      ##1 $stable(tv));
  am_tv_legal : assume property (@(posedge i_CLK) disable iff (!i_RSTn)
      tv != MIN_VALUE);

  // How many copies of tv are physically resident, across both buffers.
  int phys_count;
  always_comb begin : count_copies
    phys_count = 0;
    for (int i = 0; i < HALF_SIZE; i++) begin
      if (IB[i] == tv) phys_count = phys_count + 1;
      if (OB[i] == tv) phys_count = phys_count + 1;
    end
  end

  // The one legitimate way a copy leaves is a pop of the head; both arms zero
  // OB[0]. These are the DUT's own internal accept gates rather than the
  // advertised readies, which need not agree with them.
  wire deq_fires = i_read && !i_wrt && !empty;
  wire rep_fires = i_wrt && i_read && !empty;
  wire pops_tv   = (deq_fires || rep_fires) && (OB[0] == tv);

  logic past_valid;
  always_ff @(posedge i_CLK or negedge i_RSTn) begin
    if (!i_RSTn) past_valid <= 1'b0;
    else past_valid <= 1'b1;
  end

  // No copy disappears without a pop to account for it. A write that overwrites
  // a live IB[0] is exactly a copy going missing with pops_tv low, so this fires
  // on a clobber and on nothing else.
  a_no_clobber : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      past_valid |-> ($past(phys_count) - phys_count) <= ($past(pops_tv) ? 1 : 0));

  // Anti-vacuity: a queue that never puts the tracked value in IB[0], or never
  // writes while it is there, satisfies a_no_clobber trivially.
  c_tv_in_ib0 : cover property (@(posedge i_CLK) disable iff (!i_RSTn)
      IB[0] == tv);

  // The risk scenario itself: a write arrives while IB[0] holds a live value.
  c_write_onto_live_ib0 : cover property (@(posedge i_CLK) disable iff (!i_RSTn)
      settled && cmd_enqueue && IB[0] == tv);

  // Replace writes IB[0] as well, and is gated on no ready at all.
  c_replace_onto_live_ib0 : cover property (@(posedge i_CLK) disable iff (!i_RSTn)
      settled && i_wrt && i_read && !empty && IB[0] == tv);

  // Soundness diagnostic for a_no_clobber. phys_count counts cells equal to tv,
  // which is a valid proxy for the copies the queue holds only if the array
  // leaves no stale cells behind: values logically gone but never overwritten
  // with MIN_VALUE. The array clears vacated cells only under some conditions,
  // so if live_cells can exceed `size` then a_no_clobber can fire on an
  // overwrite of a stale cell and is not a sound data-loss detector.
  int live_cells;
  always_comb begin : count_live
    live_cells = 0;
    for (int i = 0; i < HALF_SIZE; i++) begin
      if (IB[i] != MIN_VALUE) live_cells = live_cells + 1;
      if (OB[i] != MIN_VALUE) live_cells = live_cells + 1;
    end
  end

  // An assert rather than a cover: the absence of stale cells is the desired
  // outcome, and a cover whose unreachability is the good news would trip the
  // vacuity gate and report a pass as a failure.
  a_no_ghost_cells : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
      settled |-> live_cells <= size);

`ifdef HWPQ_SELFTEST
  // Bound without hwpq_spec, so it does not inherit that file's self-test hook.
  // A configuration with no way to fail has stopped checking.
  a_selftest_must_fail : assert property (@(posedge i_CLK) disable iff (!i_RSTn) 1'b0);
`endif


  // Witnesses that a second reset is in scope, so it is deliberately not disabled
  // on !i_RSTn: the low phase is the thing being covered. If this is unreachable
  // the reset harness is absent, and every property here describes only the run
  // after the first reset, leaving mid-operation reset defects invisible.
  c_reset_reasserted : cover property (@(posedge i_CLK)
      i_RSTn ##1 !i_RSTn ##1 i_RSTn);

endmodule

`default_nettype wire

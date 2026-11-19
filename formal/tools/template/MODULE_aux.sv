`default_nettype none
// white-box addendum for @MODULE@
//
// OPTIONAL. Write one when the module keeps internal state the interface does
// not fully determine, and in particular when it keeps REDUNDANT internal
// accounting: the redundancy is what hides corruption from the ports, leaving
// every interface-level assert and cover green while the state itself is wrong.
//
// Separate from hwpq_spec.sv on purpose. The shared spec reads only the six
// interface ports, which is what lets it bind to every architecture unchanged.
// This file reaches inside one module. Keeping them apart stops the portable
// spec acquiring module-specific dependencies.
//
// State the internal claim this file checks before writing any property. If you
// cannot say what claim the design is making and why the interface cannot check
// it, you do not need this file.
//
// Two rules learned the hard way:
//
//   Do not assert a mechanism against itself. If the design derives a signal
//   from a hand-computed bound, asserting the bound against that signal proves
//   nothing. Invert it: prove the design's claim is CONSERVATIVE.
//
//   Do not write a property whose only virtue is that it reddens when a fix is
//   reverted. A property that detects an edit rather than a defect is mutation
//   detection wearing verification's clothes. Ask what PASSING looks like
//   before you run it.

module hwpq_@MODULE@_aux #(
    parameter int DATA_WIDTH = 3,
    parameter int QUEUE_SIZE = 7
) (
    input var logic i_CLK,
    input var logic i_RSTn
    // Add the internal signals this addendum reads. Use `input var logic` so
    // the ports stay single-driver under `default_nettype none`.
);

  // Every property carries its own explicit clock and disable, matching
  // hwpq_spec.sv, rather than relying on `default clocking` tool support.
  //
  // a_example : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
  //     <the internal invariant> );
  //
  // Pair each assert with a cover establishing its precondition is REACHABLE.
  // An assert over a state the design never enters is green and worthless, and
  // the cover set is the only thing that detects it.
  //
  // c_example : cover property (@(posedge i_CLK) disable iff (!i_RSTn)
  //     <the state the assert is about> );

endmodule

`default_nettype wire

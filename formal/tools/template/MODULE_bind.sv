// Attaches hwpq_spec to @MODULE@
//
// Answer the four questions marked ANSWER before proving anything. Port-map
// explicitly rather than `.*`, and pass every parameter explicitly: the
// spec's own defaults are placeholders and must not be relied on.

bind @MODULE@ hwpq_spec #(
    .QUEUE_SIZE (QUEUE_SIZE),
    .DATA_WIDTH (DATA_WIDTH),
    .ENQ_ENA    (ENQ_ENA),

    // ANSWER 1: HAS_BUSY. Do BOTH readies drop while an operation is in
    // flight? 0 makes `settled` constant 1 and swaps a_progress for the
    // stronger a_plumbing. Get this wrong high and a_progress is vacuous;
    // wrong low and the spec samples the DUT mid-operation.
    .HAS_BUSY   (1'b1),

    // ANSWER 2: MAX_SETTLE. Upper bound in cycles on staying unsettled.
    // Pass the DUT's OWN localparam where one exists, not a hardcoded number:
    // that makes a_progress a real check that the timer is big enough rather
    // than a tautology, and it tracks QUEUE_SIZE automatically.
    .MAX_SETTLE (1),

    // ANSWER 3: HAS_FULL. Does !o_write_ready actually mean full, or only
    // busy? A replace-only DUT with no enqueue path gates nothing on fullness.
    // This is NOT the same question as ENQ_ENA.
    .HAS_FULL   (1'b1),

    // ANSWER 4: CAPACITY. How many elements the DUT really holds, if that is
    // not QUEUE_SIZE. Omit unless it differs. Do NOT reach for HAS_FULL=0 to
    // work around a capacity mismatch: that silently drops two asserts and two
    // covers, with nothing in the results table to show it happened.
    // .CAPACITY (QUEUE_SIZE - 2),

`ifdef HWPQ_UNGATED
    // run.sh --ungated drops the switchable assumptions so a recorded
    // shortcoming reproduces. Delete this block if no assumption applies.
    .ASSUME_FILL_FIRST (1'b0)
`else
    .ASSUME_FILL_FIRST (1'b1)
`endif
) u_spec (
    .i_CLK        (i_CLK),
    .i_RSTn       (i_RSTn),
    .i_wrt        (i_wrt),
    .i_read       (i_read),
    .i_data       (i_data),
    .o_write_ready(o_write_ready),
    .o_read_ready (o_read_ready),
    .o_data       (o_data)
);


// Reset harness: the elaboration top for this module's proofs. NOT optional.
//
// The tool holds the declared reset inactive after init; declaring
// i_init_RSTn keeps the DUT's i_RSTn free for mid-operation resets. The bind
// above is unaffected: it targets the module TYPE, so it still attaches to
// u_dut, and property leaf names do not change.
//
// CHECK: c_reset_reasserted must be reachable. If it comes back unreachable,
// this harness is missing or the reset expression is wrong.
module hwpq_rst_@MODULE@ #(
    parameter int QUEUE_SIZE = 7,
    parameter int DATA_WIDTH = 3,
    parameter bit ENQ_ENA    = 1
) (
    input  logic                  i_CLK,
    input  logic                  i_init_RSTn,
    input  logic                  i_RSTn,
    input  logic                  i_wrt,
    input  logic                  i_read,
    input  logic [DATA_WIDTH-1:0] i_data,
    output logic                  o_write_ready,
    output logic                  o_read_ready,
    output logic [DATA_WIDTH-1:0] o_data
);
  @MODULE@ #(
      .QUEUE_SIZE(QUEUE_SIZE), .DATA_WIDTH(DATA_WIDTH), .ENQ_ENA(ENQ_ENA)
  ) u_dut (
      .i_CLK(i_CLK), .i_RSTn(i_init_RSTn & i_RSTn),
      .i_wrt(i_wrt), .i_read(i_read), .i_data(i_data),
      .o_write_ready(o_write_ready), .o_read_ready(o_read_ready), .o_data(o_data)
  );
endmodule

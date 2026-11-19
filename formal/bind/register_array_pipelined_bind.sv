// Attaches hwpq_spec to register_array_pipelined
//
// Port-map explicitly rather than `.*`, and pass every parameter explicitly.
//
// Sequential, like register_tree, but it reaches `settled` a different way.
// register_tree counts down a hand-computed timer; this design derives
// head_valid straight from the data - `queue[0] >= queue[1]`
// (register_array_pipelined.sv:198) - and gates both readies on it
// (:74-75), so HAS_BUSY=1.
//
// MAX_SETTLE is therefore NOT read from a localparam here, because there is no
// timer to read: the settle time is however long the compare-exchange network
// takes to get the two leading elements in order. 2 covers the even/odd phase
// pair. If a_progress fails, that number is wrong and is the thing to raise -
// the property is what pins it down.
//
// ASSUME_FILL_FIRST is wired the same way register_array_bind.sv and
// register_tree_bind.sv wire it. hwpq_spec.sv:152 guards the assumption on
// `!ENQ_ENA`, so it is inert in the ENQ_ENA=1 run above and this changes
// nothing there; it exists for the replace-only build, where the ordering and
// occupancy asserts reproduce without it. Without the `ifdef the parameter
// would default to 1 and --ungated would silently leave the assumption ON --
// green while checking nothing.
bind register_array_pipelined hwpq_spec #(
    .QUEUE_SIZE (QUEUE_SIZE),
    .DATA_WIDTH (DATA_WIDTH),
    .ENQ_ENA    (ENQ_ENA),
    .HAS_BUSY   (1'b1),
    .MAX_SETTLE (2),
    .HAS_FULL   (1'b1),
`ifdef HWPQ_UNGATED
    // run.sh --ungated: drop the workaround and reproduce the recorded defect.
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


// Reset harness: the elaboration top for this module's proofs. The tool
// holds the declared reset inactive after init; declaring i_init_RSTn keeps
// the DUT's i_RSTn free for mid-operation resets.
//
// It lives in this file rather than its own because bind/ is already the
// per-module formal glue. The bind above is unaffected: it targets the module
// TYPE, so it still attaches to u_dut, and property leaf names do not change.
module hwpq_rst_register_array_pipelined #(
    parameter int QUEUE_SIZE = 4,
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
  register_array_pipelined #(
      .QUEUE_SIZE(QUEUE_SIZE), .DATA_WIDTH(DATA_WIDTH), .ENQ_ENA(ENQ_ENA)
  ) u_dut (
      .i_CLK(i_CLK), .i_RSTn(i_init_RSTn & i_RSTn),
      .i_wrt(i_wrt), .i_read(i_read), .i_data(i_data),
      .o_write_ready(o_write_ready), .o_read_ready(o_read_ready), .o_data(o_data)
  );
endmodule

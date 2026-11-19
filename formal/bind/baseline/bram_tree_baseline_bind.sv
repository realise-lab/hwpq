// Attaches hwpq_spec to the baseline bram_tree.
//
// Port-map and parameters are written out explicitly rather than with `.*`.
//
// ENQ_ENA=1: the enqueue datapath is present, so both command forms are live.
// HAS_FULL=1: o_write_ready carries (queue_size != QUEUE_SIZE), so !o_write_ready
// means full rather than busy.
// HAS_BUSY=1: both readies are ANDed with a quiescence term, so they drop
// together while the sift walk runs.
//
// MAX_SETTLE=8 is hand-derived, not read from the design: no localparam holds it,
// so it does not track QUEUE_SIZE. The walk costs roughly two cycles per level
// plus accept and return (2*TREE_DEPTH+2 = 8 at QUEUE_SIZE=7). Re-derive it when
// the walk structure or QUEUE_SIZE changes.
//
// Trap: at this baseline the readies are ANDed with !(i_read || i_wrt), so
// am_no_cmd_while_busy reduces to "if a command is issued then no command is
// issued". Every assert then proves for free and the run is vacuous. The command
// covers are the only detector, so read them before reading the assert table.
bind bram_tree hwpq_spec #(
    .QUEUE_SIZE (QUEUE_SIZE),
    .DATA_WIDTH (DATA_WIDTH),
    .ENQ_ENA    (1'b1),
    .HAS_BUSY   (1'b1),
    .MAX_SETTLE (8),
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


// Baseline variant: black-box spec only, with no white-box addendum.
//
// The aux bind is omitted because it reaches for `fsm_idle` and `filling`, which
// this RTL does not declare, so binding it stops the run at elaboration.
// Baseline measurement of this module is therefore black-box only: mark
// white-box rows unavailable rather than inferring them, since a defect caught
// by exactly one white-box property cannot appear in this table at all.


// Reset harness: the elaboration top for this module's proofs. The tool holds
// the declared reset inactive after init; declaring i_init_RSTn keeps the DUT's
// i_RSTn free for mid-operation resets.
//
// The per-node capacity fields live in the RAM, which has no reset port and whose
// `initial` fill is simulation-only. Mid-operation reset therefore leaves the
// free-space accounting untouched, which is what this harness makes reachable.
module hwpq_rst_bram_tree #(
    parameter int QUEUE_SIZE = 7,
    parameter int DATA_WIDTH = 3
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
  bram_tree #(
      .QUEUE_SIZE(QUEUE_SIZE), .DATA_WIDTH(DATA_WIDTH)
  ) u_dut (
      .i_CLK(i_CLK), .i_RSTn(i_init_RSTn & i_RSTn),
      .i_wrt(i_wrt), .i_read(i_read), .i_data(i_data),
      .o_write_ready(o_write_ready), .o_read_ready(o_read_ready), .o_data(o_data)
  );
endmodule

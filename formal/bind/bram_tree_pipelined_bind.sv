// Attaches hwpq_spec and hwpq_bram_aux to bram_tree_pipelined.
//
// Port-map and parameters are written out explicitly rather than with `.*`.
//
// HAS_BUSY=1: sift_done drops for the whole walk, so both readies can be low
// together and the settle contract applies.
//
// HAS_FULL=0 with CAPACITY=QUEUE_SIZE. The module has no enqueue datapath, and
// no command it accepts has fullness as a precondition, since a replace on a
// populated queue is size-neutral. o_write_ready is sift_done, so it reports
// quiescence and never capacity: !o_write_ready does not mean full. Capacity is
// still QUEUE_SIZE, reached by evicting every placeholder, which keeps
// a_occ_bounded meaningful. hwpq_bram_aux states what the port does mean
// (a_wready_is_quiescence) and carries the two covers HAS_FULL=0 drops.
//
// MAX_SETTLE=14 is hand-derived, not read from the design: no localparam holds
// it, so it does not track QUEUE_SIZE. The walk costs four cycles per level plus
// accept and return (4*TREE_DEPTH+2 = 14 at QUEUE_SIZE=7). Re-derive it when the
// walk structure or QUEUE_SIZE changes.
bind bram_tree_pipelined hwpq_spec #(
    .QUEUE_SIZE (QUEUE_SIZE),
    .DATA_WIDTH (DATA_WIDTH),
    .ENQ_ENA    (1'b0),
    .HAS_BUSY   (1'b1),
    .MAX_SETTLE (14),
    .HAS_FULL   (1'b0),
    .CAPACITY   (QUEUE_SIZE),
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


// The white-box addendum binds to the harness rather than the DUT: it needs
// i_init_RSTn to tell the first reset from a later one, and that signal exists
// only one level up. Everything from the design arrives by hierarchical
// reference through these port connections.
bind hwpq_rst_bram_tree_pipelined hwpq_bram_aux #(
    .QUEUE_SIZE   (QUEUE_SIZE),
    .DATA_WIDTH   (DATA_WIDTH),
    .TREE_DEPTH   (3),
    .NODES_NEEDED (7)
) u_bram_aux (
    .i_CLK        (i_CLK),
    .i_init_RSTn  (i_init_RSTn),
    .i_RSTn       (i_RSTn),
    .state        (u_dut.state),
    .parent_lvl   (u_dut.parent_lvl),
    .parent_idx   (u_dut.parent_idx),
    .queue_size   (u_dut.queue_size),
    .sift_done    (u_dut.sift_done),
    .root_done    (u_dut.root_done),
    .filling      (u_dut.filling),
    .cmd_replace  (u_dut.cmd_replace),
    .cmd_dequeue  (u_dut.cmd_dequeue),
    .o_write_ready(o_write_ready),
    .o_read_ready (o_read_ready),
    .o_data       (o_data),
    .level_0      (u_dut.level_0),
    .level_1      (u_dut.level_1),
    .ram_l2       (u_dut.gen_bram[2].bram_inst.ram)
);


// Reset harness: the elaboration top for this module's proofs. The tool holds
// the declared reset inactive after init; declaring i_init_RSTn keeps the DUT's
// i_RSTn free for mid-operation resets, which is what makes a second reset
// reachable at all.
//
// It lives in this file because bind/ already holds the per-module formal glue.
// The binds above are unaffected: the spec targets the module type, so it still
// attaches to u_dut.
module hwpq_rst_bram_tree_pipelined #(
    parameter int QUEUE_SIZE = 15,
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
  bram_tree_pipelined #(
      .QUEUE_SIZE(QUEUE_SIZE), .DATA_WIDTH(DATA_WIDTH)
  ) u_dut (
      .i_CLK(i_CLK), .i_RSTn(i_init_RSTn & i_RSTn),
      .i_wrt(i_wrt), .i_read(i_read), .i_data(i_data),
      .o_write_ready(o_write_ready), .o_read_ready(o_read_ready), .o_data(o_data)
  );
endmodule

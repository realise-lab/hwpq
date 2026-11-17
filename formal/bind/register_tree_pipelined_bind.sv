// Attaches hwpq_spec and hwpq_tree_aux to register_tree_pipelined

// Port-map explicitly rather than `.*`, and pass every parameter explicitly.

// HAS_BUSY: the readies drop after a command; the read side returns first, once the root
// outranks the tree.
// MAX_SETTLE is taken from the DUT's own SETTLE_CYCLES localparam rather than
// hardcoded, so it tracks QUEUE_SIZE automatically.
// HAS_FULL: !o_write_ready means full, not merely busy.
// ASSUME_FILL_FIRST is inert when ENQ_ENA=1; without the `ifdef, --ungated would leave it on.
bind register_tree_pipelined hwpq_spec #(
    .QUEUE_SIZE (QUEUE_SIZE),
    .DATA_WIDTH (DATA_WIDTH),
    .ENQ_ENA    (ENQ_ENA),
    .HAS_BUSY   (1'b1),
    .MAX_SETTLE (SETTLE_CYCLES),
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

bind register_tree_pipelined hwpq_tree_aux #(
    .DATA_WIDTH  (DATA_WIDTH),
    .NODES_NEEDED(NODES_NEEDED),
    .EARLY_HEAD  (HEAD_CYCLES < SETTLE_CYCLES)
) u_aux (
    .i_CLK     (i_CLK),
    .i_RSTn    (i_RSTn),
    .head_valid(head_valid),
    .head_ready(head_ready),
    .queue     (queue)
);


// Reset harness - the elaboration top for this module's proofs. The tool holds
// the declared reset inactive after init; declaring i_init_RSTn keeps the DUT's
// i_RSTn free for mid-operation resets.
module hwpq_rst_register_tree_pipelined #(
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
  register_tree_pipelined #(
      .QUEUE_SIZE(QUEUE_SIZE), .DATA_WIDTH(DATA_WIDTH), .ENQ_ENA(ENQ_ENA)
  ) u_dut (
      .i_CLK(i_CLK), .i_RSTn(i_init_RSTn & i_RSTn),
      .i_wrt(i_wrt), .i_read(i_read), .i_data(i_data),
      .o_write_ready(o_write_ready), .o_read_ready(o_read_ready), .o_data(o_data)
  );
endmodule

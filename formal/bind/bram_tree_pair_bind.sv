// Attaches hwpq_spec to bram_tree_pair

// Port-map explicitly rather than `.*`, and pass every parameter explicitly.

// HAS_BUSY: both readies drop together through the reset fill and a walk.
// HAS_FULL: !o_write_ready means full, not merely busy.
// MAX_SETTLE is the longer of the reset fill (PAIRS cycles) and a walk (at most TREE_DEPTH
// cycles, a level per cycle), from the DUT's own localparams.
bind bram_tree_pair hwpq_spec #(
    .QUEUE_SIZE (QUEUE_SIZE),
    .DATA_WIDTH (DATA_WIDTH),
    .ENQ_ENA    (1'b1),
    .HAS_BUSY   (1'b1),
    .MAX_SETTLE ((PAIRS > TREE_DEPTH) ? PAIRS : TREE_DEPTH),
    .HAS_FULL   (1'b1)
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


// Reset harness - the elaboration top for this module's proofs. The tool holds
// the declared reset inactive after init; declaring i_init_RSTn keeps the DUT's
// i_RSTn free for mid-operation resets.
module hwpq_rst_bram_tree_pair #(
    parameter int QUEUE_SIZE = 7,
    parameter int DATA_WIDTH = 2
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
  bram_tree_pair #(
      .QUEUE_SIZE(QUEUE_SIZE), .DATA_WIDTH(DATA_WIDTH)
  ) u_dut (
      .i_CLK(i_CLK), .i_RSTn(i_init_RSTn & i_RSTn),
      .i_wrt(i_wrt), .i_read(i_read), .i_data(i_data),
      .o_write_ready(o_write_ready), .o_read_ready(o_read_ready), .o_data(o_data)
  );
endmodule

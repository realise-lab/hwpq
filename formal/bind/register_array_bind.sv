// Attaches hwpq_spec to register_array
//
// Port-map explicitly rather than `.*`, and pass every parameter explicitly
//
// register_array folds the whole operation into a combinational sort network in
// one cycle, and both `full` and `empty` are pure functions of `size`
// so both readies can never be low together: HAS_BUSY=0, MAX_SETTLE=1
bind register_array hwpq_spec #(
    .QUEUE_SIZE (QUEUE_SIZE),
    .DATA_WIDTH (DATA_WIDTH),
    .ENQ_ENA    (ENQ_ENA),
    .HAS_BUSY   (1'b0),
    .MAX_SETTLE (1),
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
module hwpq_rst_register_array #(
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
  register_array #(
      .QUEUE_SIZE(QUEUE_SIZE), .DATA_WIDTH(DATA_WIDTH), .ENQ_ENA(ENQ_ENA)
  ) u_dut (
      .i_CLK(i_CLK), .i_RSTn(i_init_RSTn & i_RSTn),
      .i_wrt(i_wrt), .i_read(i_read), .i_data(i_data),
      .o_write_ready(o_write_ready), .o_read_ready(o_read_ready), .o_data(o_data)
  );
endmodule

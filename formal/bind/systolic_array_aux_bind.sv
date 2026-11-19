// Attaches hwpq_systolic_aux to systolic_array
//
// Bound alone, without hwpq_spec: this file asks a white-box question about the
// module's two capacity thresholds, and needs no interface-level assumptions to
// do it.
bind systolic_array hwpq_systolic_aux #(
    .QUEUE_SIZE(QUEUE_SIZE)
) u_sys_aux (
    .i_CLK        (i_CLK),
    .i_RSTn       (i_RSTn),
    .i_wrt        (i_wrt),
    .i_read       (i_read),
    .o_write_ready(o_write_ready),
    .o_read_ready (o_read_ready),
    .size         (size),
    .full         (full),
    .empty        (empty)
);


// Reset harness: the elaboration top for this module's proofs. The tool
// holds the declared reset inactive after init; declaring i_init_RSTn keeps
// the DUT's i_RSTn free for mid-operation resets.
//
// It lives in this file rather than its own because bind/ is already the
// per-module formal glue. The bind above is unaffected: it targets the module
// TYPE, so it still attaches to u_dut, and property leaf names do not change.
module hwpq_rst_systolic_array #(
    parameter int QUEUE_SIZE = 8,
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
  systolic_array #(
      .QUEUE_SIZE(QUEUE_SIZE), .DATA_WIDTH(DATA_WIDTH)
  ) u_dut (
      .i_CLK(i_CLK), .i_RSTn(i_init_RSTn & i_RSTn),
      .i_wrt(i_wrt), .i_read(i_read), .i_data(i_data),
      .o_write_ready(o_write_ready), .o_read_ready(o_read_ready), .o_data(o_data)
  );
endmodule

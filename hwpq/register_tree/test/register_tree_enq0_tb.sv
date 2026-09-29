`default_nettype none
// register_tree shim (ENQ_ENA=0 / replace-only) for the shared testbench body.

module register_tree_enq0_tb;
  localparam int QUEUE_SIZE = 31;
  localparam int DATA_WIDTH = 16;
  localparam bit ENQ_ENA    = 0;

  `include "hwpq_tb_common.svh"

  register_tree #(
      .ENQ_ENA(ENQ_ENA),
      .QUEUE_SIZE(QUEUE_SIZE),
      .DATA_WIDTH(DATA_WIDTH)
  ) u_dut (
      .i_CLK(i_CLK),
      .i_RSTn(i_RSTn),
      .i_wrt(i_wrt),
      .i_read(i_read),
      .i_data(i_data),
      .o_write_ready(o_write_ready),
      .o_read_ready(o_read_ready),
      .o_data(o_data)
  );

  assign settled = o_write_ready || o_read_ready;
endmodule

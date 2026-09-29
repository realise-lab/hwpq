`default_nettype none
// systolic_array shim for the shared testbench body 

// Note: the DUT reserves MIN_VALUE (0) as an invalid sentinel; the shared body's
// stimulus is $urandom_range(1,1023), so it never drives 0 — required here.
module systolic_array_tb;
  localparam int QUEUE_SIZE = 16;
  localparam int DATA_WIDTH = 16;
  localparam bit ENQ_ENA    = 1;

  `include "hwpq_tb_common.svh"

  systolic_array #(
      .QUEUE_SIZE(QUEUE_SIZE),
      .DATA_WIDTH(DATA_WIDTH)
  ) u_dut (
      .i_CLK(i_CLK),
      .i_RSTn(i_RSTn),
      .i_wrt(i_wrt),
      .i_read(i_read),
      .i_data(i_data),
      .o_data(o_data),
      .o_write_ready(o_write_ready),
      .o_read_ready(o_read_ready)
  );

  // busy is encoded in the ready signals (head == MIN_VALUE means not ready)
  assign settled = o_write_ready || o_read_ready;
endmodule

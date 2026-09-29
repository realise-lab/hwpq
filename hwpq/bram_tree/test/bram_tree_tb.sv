`default_nettype none
// bram_tree shim for the shared testbench body (test/common/hwpq_tb_common.svh).
// bram_tree is pkg-locked, so the shim imports the package instead of
// overriding params. It is enqueue-capable and single-instance, so ENQ_ENA=1
// selects the enqueue-enabled program.
import bram_tree_pkg::*;

module bram_tree_tb;
  localparam bit ENQ_ENA = 1;

  `include "hwpq_tb_common.svh"

  bram_tree u_dut (
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

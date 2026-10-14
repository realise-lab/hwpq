`default_nettype none
// hybrid_systolic_heap shim for the shared testbench body.
// Sizes come from bram_tree_pkg; compile with a small model, e.g.
//   -DHYBRID_TREE_COUNT=2 -DHYBRID_BRAM_TREE_QUEUE_SIZE=7
// The reference model is quadratic in QUEUE_SIZE, so the default build is too large to run.

module shared_hybrid_systolic_heap_tb;
  // Every tree full plus each systolic buffer at its full threshold (two slots of shift margin).
  localparam int QUEUE_SIZE = bram_tree_pkg::TREE_COUNT * bram_tree_pkg::BRAM_TREE_QUEUE_SIZE
                            + 2 * (bram_tree_pkg::SYSTOLIC_QUEUE_SIZE - 2);
  localparam int DATA_WIDTH = bram_tree_pkg::DATA_WIDTH;
  localparam bit ENQ_ENA    = 1;

  // o_read_ready waits for the head to resolve, which can take a tree walk, while
  // o_write_ready stays up; o_write_ready drops while the front buffer cannot take a write.
  `define TB_INDEPENDENT_READIES 1
  `define TB_READ_RECOVERY 1

  `include "hwpq_tb_common.svh"

  hybrid_systolic_heap u_dut (
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

`default_nettype none
// bram_tree_pipelined shim for the shared testbench body (test/common/hwpq_tb_common.svh).
//
// settle contract is module-specific here: o_write_ready == sift_done is the true
// "ready to accept the next command" signal (full never blocks a replace, so it is
// deliberately not gated on full). o_read_ready exposes root_done, which goes high one
// cycle earlier than sift_done, so OR-ing it into settled would release the next command
// mid-sift and it would be dropped
module bram_tree_pipelined_tb;
  localparam int QUEUE_SIZE = 15;
  localparam int DATA_WIDTH = 16;
  localparam bit ENQ_ENA    = 0;

  // o_write_ready == sift_done here (no enqueue path, so it never advertises full);
  // skip the ENQ_ENA=0 program's "!o_write_ready == full" post-fill check.
  `define TB_TRACKS_FULL 0

  `include "hwpq_tb_common.svh"

  bram_tree_pipelined #(
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

  assign settled = o_write_ready; // see above
endmodule

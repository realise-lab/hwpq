`default_nettype none
// register_tree_pipelined shim (ENQ_ENA=0 / replace-only) for the shared testbench body.

module register_tree_pipelined_enq0_tb;
  localparam int QUEUE_SIZE = 15;
  localparam int DATA_WIDTH = 16;
  localparam bit ENQ_ENA    = 0;

  `define TB_CHECK_INTERNAL check_heap();

  `include "hwpq_tb_common.svh"

  register_tree_pipelined #(
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
  // The heap invariant, checked by hierarchical reference. `queue` is an
  // implicit binary heap (children of i are 2i+1, 2i+2), and NODES_NEEDED ==
  // QUEUE_SIZE for the 2^k-1 sizes this module requires. Safe to check at
  // every settled point: a_timer_is_sound in formal/spec/hwpq_tree_aux.sv
  // proves head_valid implies heap_holds, so the settle timer never releases
  // the head before the invariant holds. The port alone cannot see a
  // violation: a differently shaped heap still returns a plausible o_data.
  task automatic check_heap();
    for (int i = 0; i < QUEUE_SIZE; i++) begin
      if (2 * i + 1 < QUEUE_SIZE)
        assert (u_dut.queue[i] >= u_dut.queue[2*i+1])
        else begin error_count++; $error("Heap: node %0d (%d) < left child %0d (%d)",
                                         i, u_dut.queue[i], 2*i+1, u_dut.queue[2*i+1]); end
      if (2 * i + 2 < QUEUE_SIZE)
        assert (u_dut.queue[i] >= u_dut.queue[2*i+2])
        else begin error_count++; $error("Heap: node %0d (%d) < right child %0d (%d)",
                                         i, u_dut.queue[i], 2*i+2, u_dut.queue[2*i+2]); end
    end
  endtask

endmodule

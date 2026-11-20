`default_nettype none
// bram_tree shim for the shared testbench body (test/common/hwpq_tb_common.svh).
// Enqueue-capable only, so ENQ_ENA=1 selects the enqueue-enabled program.

module bram_tree_tb;
  localparam int QUEUE_SIZE = 7;   // must be 2^k - 1, k >= 2
  localparam int DATA_WIDTH = 16;
  localparam bit ENQ_ENA    = 1;

  `define TB_CHECK_INTERNAL check_root_capacity(); check_pair_heap();

  `include "hwpq_tb_common.svh"

  bram_tree #(
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

  wire bp_idle = (u_dut.state == u_dut.IDLE) && !u_dut.filling;

  task automatic check_root_capacity();
    if (bp_idle)
      assert (u_dut.top_level.capacity == QUEUE_SIZE - u_dut.queue_size)
      else begin
        error_count++;
        $error("Root capacity: idle with top_level.capacity=%0d but %0d of %0d held",
               u_dut.top_level.capacity, u_dut.queue_size, QUEUE_SIZE);
      end
  endtask

  // Node n >= 1 lives in pair (n-1)/2, on the left when n is odd. Each pair word is
  // {left, right}, each node {active, value, capacity}; node 0 is the top_level register.
  localparam int BP_DEPTH  = $clog2(QUEUE_SIZE + 1);
  localparam int BP_NODES  = (1 << BP_DEPTH) - 1;
  localparam int BP_ADDR_W = $clog2(BP_NODES);
  localparam int BP_NODE_W = 1 + DATA_WIDTH + BP_ADDR_W;

  function automatic logic [BP_NODE_W-1:0] bp_node(input int n);
    logic [2*BP_NODE_W-1:0] w;
    w = u_dut.bram_inst.ram[(n - 1) / 2];
    return (n % 2) ? w[2*BP_NODE_W-1 -: BP_NODE_W] : w[BP_NODE_W-1:0];
  endfunction

  task automatic check_pair_heap();
    logic [BP_NODE_W-1:0] c, p;
    logic                 p_active;
    logic [DATA_WIDTH-1:0] p_value;
    if (bp_idle) begin
      // The pair-0 register copy must match the memory word it mirrors.
      assert (u_dut.child == u_dut.bram_inst.ram[0])
      else begin error_count++; $error("Pair 0: register copy disagrees with memory"); end
      for (int n = 1; n < BP_NODES; n++) begin
        c = bp_node(n);
        if ((n - 1) / 2 == 0) begin
          p_active = u_dut.top_level.active;
          p_value  = u_dut.top_level.value;
        end else begin
          p        = bp_node((n - 1) / 2);
          p_active = p[BP_NODE_W-1];
          p_value  = p[BP_NODE_W-2 -: DATA_WIDTH];
        end
        if (c[BP_NODE_W-1] && p_active)
          assert (p_value >= c[BP_NODE_W-2 -: DATA_WIDTH])
          else begin
            error_count++;
            $error("Heap: node %0d (%0d) outranked by child %0d (%0d)",
                   (n - 1) / 2, p_value, n, c[BP_NODE_W-2 -: DATA_WIDTH]);
          end
      end
    end
  endtask

endmodule

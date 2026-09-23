`default_nettype none
// bram_tree shim for the shared testbench body (test/common/hwpq_tb_common.svh).
// It is enqueue-capable and single-instance, so ENQ_ENA=1 selects the
// enqueue-enabled program.
//
// QUEUE_SIZE and DATA_WIDTH are module parameters, and this shim supplies them
// the same way every other shim in the suite does.

module bram_tree_tb;
  localparam int QUEUE_SIZE = 7;   // must be 2^k - 1
  localparam int DATA_WIDTH = 16;
  localparam bit ENQ_ENA    = 1;

  `define TB_CHECK_INTERNAL check_root_capacity(); check_bram_heap();

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

  // top_level.capacity must equal QUEUE_SIZE - queue_size whenever idle; a
  // naive off-by-one here silently corrupts free-space accounting at small
  // widths. Transcribed from a_root_capacity_agrees in
  // formal/spec/hwpq_bram_tree_aux.sv, which is proven.
  task automatic check_root_capacity();
    if (u_dut.fsm_idle)
      assert (u_dut.top_level.capacity == QUEUE_SIZE - u_dut.queue_size)
      else begin
        error_count++;
        $error("Root capacity: idle with top_level.capacity=%0d but %0d of %0d held (expected %0d)",
               u_dut.top_level.capacity, u_dut.queue_size, QUEUE_SIZE,
               QUEUE_SIZE - u_dut.queue_size);
      end
  endtask

  // The heap invariant over the node memory: not proven for this module since
  // formal stalls past DATA_WIDTH 2, so simulation covers what formal cannot.
  //
  // LAYOUT: bram_inst.ram is indexed by heap position, children of p are 2p+1
  // and 2p+2, and the word is the packed struct
  // {active, value[DATA_WIDTH-1:0], capacity[ADDRESS_WIDTH-1:0]}, so the
  // active flag is the MSB. Position 0 is DEAD: the root lives in the
  // top_level register, and ram[0] only ever holds what the reset sweep wrote.
  // Comparing against ram[0] instead of top_level would be a false finding
  // generator. Gated on fsm_idle, since mid-descent the memory is half-rewritten.
  localparam int BT_TREE_DEPTH = $clog2(QUEUE_SIZE + 1);
  localparam int BT_NODES      = (1 << BT_TREE_DEPTH) - 1;
  localparam int BT_ADDR_W     = $clog2(BT_NODES);
  localparam int BT_MEM_W      = 1 + DATA_WIDTH + BT_ADDR_W;

  function automatic logic bt_active(input int idx);
    return u_dut.bram_inst.ram[idx][BT_MEM_W-1];
  endfunction

  function automatic logic [DATA_WIDTH-1:0] bt_value(input int idx);
    return u_dut.bram_inst.ram[idx][BT_MEM_W-2 -: DATA_WIDTH];
  endfunction

  task automatic check_bram_heap();
    int par;
    logic par_active;
    logic [DATA_WIDTH-1:0] par_value;
    if (u_dut.fsm_idle) begin
      for (int c = 1; c < BT_NODES; c++) begin
        par = (c - 1) / 2;
        // The root is the register, not ram[0].
        par_active = (par == 0) ? u_dut.top_level.active : bt_active(par);
        par_value  = (par == 0) ? u_dut.top_level.value  : bt_value(par);
        if (bt_active(c) && par_active)
          assert (par_value >= bt_value(c))
          else begin
            error_count++;
            $error("Heap: node %0d (%d) outranked by child %0d (%d)",
                   par, par_value, c, bt_value(c));
          end
      end
    end
  endtask

endmodule

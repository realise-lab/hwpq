`default_nettype none
// bram_tree_pipelined shim for the shared testbench body (test/common/hwpq_tb_common.svh).

module bram_tree_pipelined_tb;
  localparam int QUEUE_SIZE = 15;
  localparam int DATA_WIDTH = 16;
  localparam bit ENQ_ENA    = 0;

  // o_write_ready == sift_done here (no enqueue path, so it never advertises full);
  // skip the ENQ_ENA=0 program's "!o_write_ready == full" post-fill check.
  `define TB_TRACKS_FULL 0

  `define TB_CHECK_INTERNAL check_tree_invariants(); check_deep_heap();

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

  assign settled = o_write_ready || o_read_ready;
  // The top two levels of this design are registers rather than memory, so the
  // interesting invariants are reachable without decoding the RAM. All three
  // are transcribed from formal/spec/hwpq_bram_aux.sv, where they are proven,
  // and gated on sift_done: the walk is mid-flight otherwise.
  task automatic check_tree_invariants();
    if (u_dut.sift_done) begin
      // a_queue_size_bounded
      assert (u_dut.queue_size <= QUEUE_SIZE)
      else begin error_count++; $error("Occupancy: queue_size=%0d exceeds QUEUE_SIZE=%0d",
                                       u_dut.queue_size, QUEUE_SIZE); end

      // a_root_outranks_children
      assert (u_dut.level_0 >= u_dut.level_1[0] && u_dut.level_0 >= u_dut.level_1[1])
      else begin error_count++; $error("Heap: root %d outranked by children {%d, %d}",
                                       u_dut.level_0, u_dut.level_1[0], u_dut.level_1[1]); end

      // a_no_placeholder_at_capacity - every placeholder has been evicted by the
      // time the queue is full, so the root holds real data there.
      if (u_dut.queue_size == QUEUE_SIZE)
        assert (u_dut.level_0 !== '1)
        else begin error_count++; $error("Placeholder: root still holds the '1 placeholder at capacity"); end
    end
  endtask

  // The heap invariant over the WHOLE tree, including the BRAM levels: not
  // proven for this module, since formal only reaches QUEUE_SIZE=7 (one BRAM
  // level) at DATA_WIDTH=2 (too few payloads to order). This testbench runs
  // QUEUE_SIZE=15, DATA_WIDTH=16: two BRAM levels and a real payload alphabet,
  // unreachable by proof, so simulation covers it instead.
  //
  // LAYOUT, read off the RTL. Levels 0 and 1 are registers (level_0, level_1[2]);
  // levels 2..TREE_DEPTH-1 are one rams_tdp_rf_rf per level in the gen_bram
  // generate loop, each indexed by the node's index WITHIN its level. Children
  // of (L, i) are (L+1, 2i) and (L+1, 2i+1), per next_addr_a[2] = 2*parent_idx.
  // The word is a bare value, no active flag: '1 is the max-priority
  // placeholder and outranks everything, so it sits at the top and the
  // invariant holds through the fill phase too.
  //
  // A hierarchical reference into gen_bram[] needs a CONSTANT index, so the
  // levels are flattened into one array by a generate loop and the walk reads
  // the copy.
  //
  // Gated on sift_done && !filling. sift_done resets HIGH, so without !filling
  // a window opens inside the reset sweep and reads a tree still being written.
  localparam int BTP_TREE_DEPTH = $clog2(QUEUE_SIZE + 1);
  localparam int BTP_MAX_LVL_N  = 1 << (BTP_TREE_DEPTH - 1);

  logic [DATA_WIDTH-1:0] btp_node [BTP_TREE_DEPTH][BTP_MAX_LVL_N];

  assign btp_node[0][0] = u_dut.level_0;
  assign btp_node[1][0] = u_dut.level_1[0];
  assign btp_node[1][1] = u_dut.level_1[1];

  genvar gl, gi;
  generate
    for (gl = 2; gl < BTP_TREE_DEPTH; gl = gl + 1) begin : g_lvl
      for (gi = 0; gi < (1 << gl); gi = gi + 1) begin : g_idx
        assign btp_node[gl][gi] = u_dut.gen_bram[gl].bram_inst.ram[gi];
      end
    end
  endgenerate

  task automatic check_deep_heap();
    if (u_dut.sift_done && !u_dut.filling) begin
      for (int lvl = 0; lvl < BTP_TREE_DEPTH - 1; lvl++) begin
        for (int idx = 0; idx < (1 << lvl); idx++) begin
          assert (btp_node[lvl][idx] >= btp_node[lvl+1][2*idx])
          else begin error_count++; $error("Heap: node (%0d,%0d)=%d outranked by left child (%0d,%0d)=%d",
                                           lvl, idx, btp_node[lvl][idx], lvl+1, 2*idx, btp_node[lvl+1][2*idx]); end
          assert (btp_node[lvl][idx] >= btp_node[lvl+1][2*idx+1])
          else begin error_count++; $error("Heap: node (%0d,%0d)=%d outranked by right child (%0d,%0d)=%d",
                                           lvl, idx, btp_node[lvl][idx], lvl+1, 2*idx+1, btp_node[lvl+1][2*idx+1]); end
        end
      end
    end
  endtask


  // X on the sift comparator inputs: a tripwire on the deepest-level override,
  // not a defect detector. The out-of-range child accesses this watches are
  // provably benign: formal, this suite, and synthesis all agree that removing
  // their guards changes nothing observable.
  //
  // What makes the X harmless is an override at the end of the sift arm:
  //
  //   if (parent_lvl == TREE_DEPTH - 1) begin
  //     next_parent_lvl = 'd0; next_parent_idx = 'd0;
  //     next_we_a[parent_lvl] = 1'b0; next_we_b[parent_lvl] = 1'b0;
  //
  // It runs after the X-poisoned branch logic and overwrites it, so every
  // tainted path is discarded or aimed at storage that does not exist. Nothing
  // else in this repository watches that override, so edit it and the X goes
  // live with no other check objecting. Reported once, since the condition
  // holds for thousands of cycles once true.
  bit btp_x_reported = 0;

  always @(posedge i_CLK) begin
    if (i_RSTn && !btp_x_reported &&
        ($isunknown(u_dut.comp_left_child_in) || $isunknown(u_dut.comp_right_child_in))) begin
      btp_x_reported = 1;
      error_count++;
      $error("Sift: comparator child inputs are X {left=%h, right=%h} at parent_lvl=%0d: the walk is comparing against undefined data",
             u_dut.comp_left_child_in, u_dut.comp_right_child_in, u_dut.parent_lvl);
    end
  end

endmodule

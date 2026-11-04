// Proof harness for the hybrid's bram_tree_pair against hybrid_tree_contract, sized by the
// bram_tree_pkg macros. One tree and the shared reset block, driven as the hybrid drives them.
module hwpq_hybrid_tree_pair (
    input logic                                 i_CLK,
    input logic                                 i_init_RSTn,
    input logic                                 i_RSTn,
    input logic                                 i_wrt,
    input logic                                 i_read,
    input logic [bram_tree_pkg::DATA_WIDTH-1:0] i_data
);
  import bram_tree_pkg::*;

  wire rstn = i_init_RSTn & i_RSTn;

  logic [GEN_W-1:0]         gen;
  logic                     gen_pending, filling;
  logic [ADDRESS_WIDTH-1:0] fill_addr, fill_cap;
  logic                     full, empty, ready, top_moved, next_ok;
  logic [DATA_WIDTH-1:0]    data, next;

  bram_tree_reset tree_reset (
      .i_CLK(i_CLK), .i_RSTn(rstn), .o_gen(gen), .o_gen_pending(gen_pending),
      .o_filling(filling), .o_fill_addr(fill_addr), .o_fill_cap(fill_cap)
  );

  bram_tree_pair u_tree (
      .i_CLK(i_CLK), .i_RSTn(rstn), .i_wrt(i_wrt), .i_read(i_read), .i_data(i_data),
      .i_gen(gen), .i_gen_pending(gen_pending), .i_filling(filling),
      .i_fill_addr(fill_addr), .i_fill_cap(fill_cap),
      .o_full(full), .o_empty(empty), .o_data(data), .o_ready(ready),
      .o_top_moved(top_moved), .o_next(next), .o_next_ok(next_ok)
  );

  hybrid_tree_contract #(
      .QUEUE_SIZE(BRAM_TREE_QUEUE_SIZE),
      .DATA_WIDTH(DATA_WIDTH),
      .MAX_BUSY  (`HWPQ_HYB_TREE_MAX_BUSY),
      .TREE_SIDE (1'b1)
  ) u_contract (
      .i_CLK(i_CLK), .i_RSTn(rstn), .i_wrt(i_wrt), .i_read(i_read), .i_data(i_data),
      .i_filling(filling), .i_gen_pending(gen_pending),
      .o_full(full), .o_empty(empty), .o_data(data), .o_ready(ready),
      .o_top_moved(top_moved), .o_next(next), .o_next_ok(next_ok)
  );

  // The reset block's unreset flops take their declaration values at power-up; the tool
  // leaves them free. Later resets and the tree memory stay unconstrained.
  logic first;
  always_ff @(posedge i_CLK or negedge i_init_RSTn)
    if (!i_init_RSTn) first <= 1'b1;
    else              first <= 1'b0;

  am_powerup_values: assume property (@(posedge i_CLK) first |->
      tree_reset.gen == '0 && tree_reset.filling == POWERUP_FILL
      && tree_reset.fill_cnt == '0 && tree_reset.fill_level == '0
      && tree_reset.fill_bound == 'd1);
endmodule

// White-box helpers for this harness.
bind hwpq_hybrid_tree_pair hwpq_hybrid_tree_aux u_aux (.i_CLK(i_CLK), .i_RSTn(rstn));

// Swaps every hybrid tree for hybrid_tree_standin. Listed ahead of hybrid_systolic_heap.sv.
`define HYBRID_TREE_MODULE hybrid_tree_standin

import bram_tree_pkg::*;

// Formal-only stand-in for a hybrid tree, selected with HYBRID_TREE_MODULE. Its outputs are free
// except for the tree guarantees of hybrid_tree_contract, so it is any tree that meets the
// contract; the contract's caller obligations are asserted against the hybrid.
module hybrid_tree_standin (
    input  logic                     i_CLK,
    input  logic                     i_RSTn,
    input  logic                     i_wrt,
    input  logic                     i_read,
    input  logic [DATA_WIDTH-1:0]    i_data,
    input  logic [GEN_W-1:0]         i_gen,
    input  logic                     i_gen_pending,
    input  logic                     i_filling,
    input  logic [ADDRESS_WIDTH-1:0] i_fill_addr,
    input  logic [ADDRESS_WIDTH-1:0] i_fill_cap,
    output logic                     o_full,
    output logic                     o_empty,
    output logic [DATA_WIDTH-1:0]    o_data,
    output logic                     o_ready,
    output logic                     o_top_moved,
    output logic [DATA_WIDTH-1:0]    o_next,
    output logic                     o_next_ok
);
  // Undriven on purpose: the tool treats each as a free input, constrained by the contract.
  logic                  f_full, f_empty, f_ready, f_top_moved, f_next_ok;
  logic [DATA_WIDTH-1:0] f_data, f_next;

  assign o_full      = f_full;
  assign o_empty     = f_empty;
  assign o_data      = f_data;
  assign o_ready     = f_ready;
  assign o_top_moved = f_top_moved;
  assign o_next      = f_next;
  assign o_next_ok   = f_next_ok;

  hybrid_tree_contract #(
      .QUEUE_SIZE(BRAM_TREE_QUEUE_SIZE),
      .DATA_WIDTH(DATA_WIDTH),
      .MAX_BUSY  (`HWPQ_HYB_TREE_MAX_BUSY),
      .TREE_SIDE (1'b0)
  ) u_contract (
      .i_CLK(i_CLK), .i_RSTn(i_RSTn), .i_wrt(i_wrt), .i_read(i_read), .i_data(i_data),
      .i_filling(i_filling), .i_gen_pending(i_gen_pending),
      .o_full(o_full), .o_empty(o_empty), .o_data(o_data), .o_ready(o_ready),
      .o_top_moved(o_top_moved), .o_next(o_next), .o_next_ok(o_next_ok)
  );
endmodule

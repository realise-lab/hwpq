import bram_tree_pkg::*;

// Reset generation and tree memory fill, shared by trees that reset together.
module bram_tree_reset (
    input  logic                     i_CLK,
    input  logic                     i_RSTn,
    output logic [GEN_W-1:0]         o_gen,
    output logic                     o_gen_pending,
    output logic                     o_filling,
    output logic [ADDRESS_WIDTH-1:0] o_fill_addr,
    output logic [ADDRESS_WIDTH-1:0] o_fill_cap
);
  // Counts resets, so it is not reset itself.
  logic [GEN_W-1:0] gen        = '0;
  logic             rst_pend;
  logic             rst_pend_q = 1'b0;

  // The BRAM has no reset port: a reset retires its contents by advancing gen, and the fill
  // rewrites every node only when gen wraps, since a wrapped tag can match a stale node.
  logic                            filling    = POWERUP_FILL;
  logic [ADDRESS_WIDTH-1:0]        fill_cnt   = '0;
  logic [$clog2(TREE_DEPTH+1)-1:0] fill_level = '0;
  logic [ADDRESS_WIDTH+1:0]        fill_bound = 'd1;
  logic [ADDRESS_WIDTH-1:0]        fill_cap;

  // fill_cap halves per fill_level, so each depth's nodes get that subtree's capacity.
  assign fill_cap = ADDRESS_WIDTH'(((NODES_NEEDED + 1) >> fill_level) - 1);

  // gen advances when rst_pend falls, so it counts each reset pulse without sampling i_RSTn.
  always_ff @(posedge i_CLK or negedge i_RSTn) begin
    if (!i_RSTn) rst_pend <= 1'b1;
    else         rst_pend <= 1'b0;
  end

  // Plain always, not always_ff: strict simulators count the declaration initializers as a
  // second driver, and the initializers are what give these unreset flops a power-up value.
  always @(posedge i_CLK) begin : gen_seq
    rst_pend_q <= rst_pend;
    if (rst_pend_q && !rst_pend) gen <= gen + 1'b1;
  end

  always @(posedge i_CLK) begin : fill_seq
    if (rst_pend_q && !rst_pend && &gen) begin
      filling    <= 1'b1;
      fill_cnt   <= '0;
      fill_level <= '0;
      fill_bound <= 'd1;
    end else if (filling && !rst_pend) begin
      if (fill_cnt == ADDRESS_WIDTH'(NODES_NEEDED - 1)) begin
        filling <= 1'b0;
      end else begin
        fill_cnt <= fill_cnt + 1'b1;
        if ((fill_cnt + 1'b1) == fill_bound[ADDRESS_WIDTH-1:0]) begin
          fill_level <= fill_level + 1'b1;
          fill_bound <= (fill_bound << 1) + 'd1;
        end
      end
    end
  end

  assign o_gen         = gen;
  assign o_gen_pending = rst_pend || rst_pend_q;
  assign o_filling     = filling;
  assign o_fill_addr   = fill_cnt;
  assign o_fill_cap    = fill_cap;
endmodule

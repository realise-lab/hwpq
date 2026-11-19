// Dual-port block RAM with two write ports. Takes plain packed vectors and the
// field widths it needs, since the caller's struct type is module-local once its
// widths are parameters. CAP_WIDTH sizes the capacity field the power-up fill
// below writes into the low bits of each word.

(* ram_style = "block"*)
module rams_tdp_rf_rf #(
    parameter integer WIDTH     = 20,  // full word width, i.e. $bits(bram_tree_mem_t)
    parameter integer DEPTH     = 7,   // NODES_NEEDED
    parameter integer CAP_WIDTH = 3    // width of the capacity field, i.e. ADDRESS_WIDTH
) (
    input logic clka,
    input logic ena,
    input logic wea,
    input logic [$clog2(DEPTH)-1:0] addra,
    input logic [WIDTH-1:0] dia,
    output logic [WIDTH-1:0] doa,
    input logic clkb,
    input logic enb,
    input logic web,
    input logic [$clog2(DEPTH)-1:0] addrb,
    input logic [WIDTH-1:0] dib,
    output logic [WIDTH-1:0] dob
);
  logic [WIDTH-1:0] ram [DEPTH-1:0];

  // Power-up contents: every node inactive, value zero, capacity set to the size
  // of the subtree it roots. Simulation only: synthesis takes this as a
  // bitstream init value, and nothing restores it on a reset. The high
  // (WIDTH-CAP_WIDTH) bits are the `active` flag and the value field, both zero.
  initial begin
    int level;
    int node_capacity;
    for (int i = 0; i < DEPTH; i++) begin
      level         = $clog2(i + 2) - 1;
      node_capacity = ((DEPTH + 1) >> level) - 1;
      ram[i] = {{(WIDTH-CAP_WIDTH){1'b0}}, CAP_WIDTH'(node_capacity)};
    end
  end

  // Both write ports drive `ram` from a SINGLE process. Splitting them across two
  // always blocks, as a vendor RAM template typically does, makes every bit of the
  // array multiply driven. Simulation is unaffected, because the two ports write
  // different addresses and the non-blocking assignments land on different
  // elements, but a formal tool has to resolve the drivers instead and writes
  // become unreliably observable in the array: a write to address 0 need not be
  // there on the next cycle, and every memory-dependent property is proved against
  // that.
  //
  // Merging is sound because bram_tree ties clka and clkb to i_CLK; a genuinely
  // dual-clock instance would need a different model. The read paths stay
  // per-port and per-clock, and read-first ordering is preserved: the outputs
  // still sample `ram` before this cycle's writes land, because every assignment
  // here is non-blocking.
  always @(posedge clka) begin
    if (ena && wea) ram[addra] <= dia;
    if (enb && web) ram[addrb] <= dib;
  end

  always @(posedge clka) begin
    if (ena) doa <= ram[addra];
  end

  always @(posedge clkb) begin
    if (enb) dob <= ram[addrb];
  end

endmodule

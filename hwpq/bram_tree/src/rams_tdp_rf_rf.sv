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

  // Synthesis needs each port's write in its own process to infer block RAM; simulation and
  // formal need one writing process, or every bit of the array is multiply driven. The two
  // agree unless both ports write one address in a cycle, which no caller does. Every caller
  // ties clka and clkb together. Reads are read-first: they sample before this cycle's writes.
`ifdef SYNTHESIS
  always @(posedge clka) begin
    if (ena) begin
      if (wea) ram[addra] <= dia;
      doa <= ram[addra];
    end
  end

  always @(posedge clkb) begin
    if (enb) begin
      if (web) ram[addrb] <= dib;
      dob <= ram[addrb];
    end
  end
`else
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
`endif

endmodule

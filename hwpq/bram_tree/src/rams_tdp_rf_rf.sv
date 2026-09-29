import bram_tree_pkg::*;
// Dual-Port Block RAM with Two Write Ports
// File: rams_tdp_rf_rf.v

(* ram_style = "block"*)
module rams_tdp_rf_rf #(
    parameter integer WIDTH = DATA_WIDTH,
    parameter integer DEPTH = NODES_NEEDED
) (
    input logic clka,
    input logic ena,
    input logic wea,
    input logic [$clog2(DEPTH)-1:0] addra,
    input bram_tree_mem_t dia,
    output bram_tree_mem_t doa,
    input logic clkb,
    input logic enb,
    input logic web,
    input logic [$clog2(DEPTH)-1:0] addrb,
    input bram_tree_mem_t dib,
    output bram_tree_mem_t dob
);
  localparam STRUCT_WIDTH = $bits(bram_tree_mem_t);
  logic [STRUCT_WIDTH-1:0] ram [DEPTH-1:0];

  initial begin
    int level;
    int node_capacity;
    for (int i = 0; i < DEPTH; i++) begin
      level         = $clog2(i + 2) - 1;
      node_capacity = ((DEPTH + 1) >> level) - 1; 
      ram[i] = {1'b0, '0, ADDRESS_WIDTH'(node_capacity)};
    end
  end

  always @(posedge clka) begin
    if (ena) begin
      if (wea) ram[addra] <= dia;
      doa <= bram_tree_mem_t'(ram[addra]);
    end
  end

  always @(posedge clkb) begin
    if (enb) begin
      if (web) ram[addrb] <= dib;
      dob <= bram_tree_mem_t'(ram[addrb]);
    end
  end

endmodule
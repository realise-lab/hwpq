// Simple dual-port block RAM: one write port, one read port with a cycle of latency.
// A read of the address being written may return either word; bram_tree_pair never uses one.
// Words are flat vectors: an array of structs infers a separate RAM for each field.
(* ram_style = "block" *)
module bram_tree_pair_ram #(
    parameter integer WIDTH  = 1,
    parameter integer DEPTH  = 1,
    parameter integer ADDR_W = 1
) (
    input  logic              clk,
    input  logic              we,
    input  logic [ADDR_W-1:0] wr_addr,
    input  logic [WIDTH-1:0]  din,
    input  logic [ADDR_W-1:0] rd_addr,
    output logic [WIDTH-1:0]  dout
);
  logic [WIDTH-1:0] ram [DEPTH-1:0];

  always @(posedge clk) begin
    if (we) ram[wr_addr] <= din;
    dout <= ram[rd_addr];
  end
endmodule

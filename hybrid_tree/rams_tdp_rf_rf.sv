// Dual-Port Block RAM with Two Write Ports
// File: rams_tdp_rf_rf.v

module rams_tdp_rf_rf #(
    parameter integer WIDTH = 16,
    parameter integer DEPTH = 1024
) (
    input logic clka,
    input logic ena,
    input logic wea,
    input logic [31:0] addra,
    input logic [WIDTH-1:0] dia,
    output logic [WIDTH-1:0] doa,
    input logic clkb,
    input logic enb,
    input logic web,
    input logic [31:0] addrb,
    input logic [WIDTH-1:0] dib,
    output logic [WIDTH-1:0] dob
);

  logic [WIDTH-1:0] ram[DEPTH-1:0];

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

endmodule

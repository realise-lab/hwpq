// Dual-Port Block RAM with Two Write Ports

module rams_tdp_wf_wf #(
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
      if (wea) begin
        ram[addra] <= dia;
        doa <= dia;
      end else begin
        doa <= ram[addra];
      end
    end
  end

  always @(posedge clkb) begin
    if (enb) begin
      if (web) begin
        ram[addrb] <= dib;
        dob <= dib;
      end else begin
        dob <= ram[addrb];
      end
    end
  end

endmodule

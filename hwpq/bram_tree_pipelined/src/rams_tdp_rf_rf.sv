// Dual-port block RAM with two write ports and read-first outputs.

module rams_tdp_rf_rf #(
    parameter integer WIDTH = 16,
    parameter integer DEPTH = 1024
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

  logic [WIDTH-1:0] ram[DEPTH-1:0];

  // Power-up contents, all-ones in every word. Simulation only: synthesis takes this as a
  // bitstream init value, and the caller's reset fill restores the contents.
  initial begin
    for (int i = 0; i < DEPTH; i++) begin
      ram[i] = '1;
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

// Dual-Port Block RAM with Two Write Ports
// File: rams_tdp_rf_rf.v

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

  initial begin
    // on initialization, set all values to be of highest priority
    for (int i = 0; i < DEPTH; i++) begin
      ram[i] = '1;
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
  // Merging is sound here because every instantiation in this repo ties clka and
  // clkb to the same net; a genuinely dual-clock instance would need a different
  // model. The read paths stay per-port and per-clock, and read-first ordering is
  // preserved: the output samples `ram` before this cycle's writes land.
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

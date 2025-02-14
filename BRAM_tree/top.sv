/*
 * Top module for the testing if BRAM is synthesized by Vivado.
 */
module top(
  input logic CLK,
  // Inputs
  input logic [1:0] i_sw,
  // Outputs
  output logic o_led
);

  localparam integer DataWidth = 32;
  localparam integer RamDepth = 256;

  logic [$clog2(RamDepth)-1:0] i_addr;
  logic [DataWidth-1:0] i_data;
  logic [$clog2(RamDepth)-1:0] o_addr;
  logic [DataWidth-1:0] o_data;

  bram #(
    .DATA_WIDTH(DataWidth),
    .RAM_DEPTH(RamDepth)
  ) bram_inst (
    .CLK(CLK),
    .i_write(i_sw[0]),
    .i_read(i_sw[1]),
    .i_wrt_addr(i_addr),
    .i_read_addr(o_addr),
    .i_data(i_data),
    .o_data(o_data)
  );

  // Do something with the data read from bram so that it does not get eliminated in synthesis.
  assign o_led = o_data > 100 ? 1 : 0;

endmodule

module top(
  input logic CLK,
  // Inputs
  input logic [3:0] i_sw,
  // Outputs
  output logic [1:0] o_led
);

  reg [7:0] i_data_a; 
  reg [7:0] i_addr_a; 
  reg [7:0] o_addr_a; 
  reg [7:0] o_data_a; 
  reg [7:0] i_data_b; 
  reg [7:0] i_addr_b; 
  reg [7:0] o_addr_b; 
  reg [7:0] o_data_b; 

  counter counter_inst_a(
    .CLK(CLK),
    .o_w_data(i_data_a),
    .o_w_addr(i_addr_a),
    .o_r_addr(o_addr_a)
  );

  counter counter_inst_b(
    .CLK(CLK),
    .o_w_data(i_data_b),
    .o_w_addr(i_addr_b),
    .o_r_addr(o_addr_b)
  );

  dual_port_bram # (
    .BRAM_WIDTH(8),
    .BRAM_DEPTH(8)
  ) dual_port_bram_inst(
    .CLK_a(CLK),
    .CLK_b(CLK),
    .i_we_a(i_sw[0]),
    .i_addr_a(o_addr_a),
    .i_ena_a(i_sw[1]),
    .i_din_a(i_data_a),
    .i_we_b(i_sw[2]),
    .i_addr_b(o_addr_b),
    .i_ena_b(i_sw[3]),
    .i_din_b(i_data_b),
    .o_dout_a(o_data_a),
    .o_dout_b(o_data_b)
  );

  // Do something with the data read from bram so that it does not get
  // eliminated in synthesis.
  assign o_led[0] = o_data_a > 100 ? 1 : 0;
  assign o_led[1] = o_data_b > 100 ? 1 : 0;

endmodule

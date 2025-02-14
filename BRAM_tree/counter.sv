module counter#(
  parameter integer DATA_WIDTH = 32,
  parameter integer RAM_DEPTH = 256
)(
  input logic CLK,
  // Outputs
  output logic [DATA_WIDTH-1:0] o_w_data,
  output logic [$clog2(RAM_DEPTH)-1:0] o_w_addr,
  output logic [$clog2(RAM_DEPTH)-1:0] o_r_addr
);
  always @(posedge CLK) begin
    o_w_data <= (o_w_data == 1024) ? 32'd0 : o_w_data + 32'd1;
    o_w_addr <= (o_w_addr == 8'd255) ? 8'd0 : o_w_addr + 8'd1;
    o_r_addr <= (o_r_addr == 8'd255) ? 8'd0 : o_r_addr + 8'd1;
  end
endmodule
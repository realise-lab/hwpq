module counter(
  input logic CLK,
  // Outputs
  output logic [7:0] o_w_data,
  output logic [7:0] o_w_addr,
  output logic [7:0] o_r_addr
);
  always @(posedge CLK) begin
    o_w_data <= (o_w_data == 255) ? 8'd0 : o_w_data + 8'd1;
    o_w_addr <= (o_w_addr == 255) ? 8'd0 : o_w_addr + 8'd1;
    o_r_addr <= (o_r_addr == 255) ? 8'd0 : o_r_addr + 8'd1;
  end
endmodule
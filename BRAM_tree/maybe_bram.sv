module maybe_bram(
  input clk,
  input [7:0] i_addr,
  input [7:0] i_data,
  input [7:0] o_addr,
  input write,
  input read,
  output logic [7:0] o_read
  );

  logic [7:0] ram [255:0];

  always @(posedge clk) begin
    if (write) begin
	    ram[i_addr] <= i_data;
    end
    if (read) begin
      o_read <= ram[o_addr];
    end
  end
endmodule
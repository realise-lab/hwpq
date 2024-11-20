module bram #(
  parameter DATA_WIDTH = 32, 
  parameter RAM_DEPTH = 256
)(
  input CLK,
  input RSTn,
  // Inputs
  input i_write,
  input i_read,
  input [RAM_DEPTH-1:0] i_wrt_addr,
  input [RAM_DEPTH-1:0] i_read_addr,
  input [DATA_WIDTH-1:0] i_data,
  // Outputs
  output reg [DATA_WIDTH-1:0] o_data
);

  reg [DATA_WIDTH-1:0] ram [RAM_DEPTH-1:0];

  always @(posedge CLK or negedge RSTn) begin
    if (!RSTn) begin
      // reset every register to 0
      for (int i = 0; i < RAM_DEPTH; i++) begin
        ram[i] <= 0;
      end
    end else begin
      if (i_write) begin
        ram[i_wrt_addr] <= i_data;
      end
      if (i_read) begin
        o_data <= ram[i_read_addr];
      end
    end
  end
endmodule
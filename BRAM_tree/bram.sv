module bram #(
    parameter integer DATA_WIDTH = 32,
    parameter integer RAM_DEPTH  = 256 // Need at least 256 to make Vivado synthesize BRAM
) (
    input logic CLK,
    // Inputs
    input logic i_write,
    input logic i_read,
    input logic [$clog2(RAM_DEPTH)-1:0] i_wrt_addr,
    input logic [$clog2(RAM_DEPTH)-1:0] i_read_addr,
    input logic [DATA_WIDTH-1:0] i_data,
    // Outputs
    output logic [DATA_WIDTH-1:0] o_data
);

  logic [DATA_WIDTH-1:0] ram[RAM_DEPTH];

  always @(posedge CLK) begin
    if (i_write) begin
      ram[i_wrt_addr] <= i_data;
    end
    if (i_read) begin
      o_data <= ram[i_read_addr];
    end
  end

endmodule

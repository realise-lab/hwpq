module bram #(
    parameter int DATA_WIDTH = 32,
    parameter int RAM_DEPTH  = 256
) (
    input logic CLK,
    input logic RSTn,
    // Inputs
    input logic i_write,
    input logic i_read,
    input logic [RAM_DEPTH-1:0] i_wrt_addr,
    input logic [RAM_DEPTH-1:0] i_read_addr,
    input logic [DATA_WIDTH-1:0] i_data,
    // Outputs
    output logic [DATA_WIDTH-1:0] o_data
);

  // Local parameters
  localparam logic [DATA_WIDTH-1:0] MaxValue = {DATA_WIDTH{1'b1}};

  // BRAM
  logic [DATA_WIDTH-1:0] ram[RAM_DEPTH];

  always @(posedge CLK or negedge RSTn) begin
    if (!RSTn) begin
      // reset every register to MAX_VALUE
      for (int i = 0; i < RAM_DEPTH; i++) begin
        ram[i] <= MaxValue;
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

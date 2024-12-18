module dual_port_bram #(
  parameter RAM_WIDTH = 32,    // Width of the data
  parameter RAM_DEPTH = 128    // Width of the address
)(
  // Clock signals
  input logic                            CLK_a,         // Clock signal
  input logic                            CLK_b,         // Clock signal
  // Port A Inputs
  input logic                            i_we_a,        // Write enable for port A
  input logic   [$clog2(RAM_DEPTH)-1:0]  i_addr_a,      // Access Address for port A
  input logic   [RAM_WIDTH-1:0]          i_din_a,       // Data input for port A
  // Port B Inputs
  input logic                            i_we_b,        // Write enable for port B
  input logic   [$clog2(RAM_DEPTH)-1:0]  i_addr_b,      // Access Address for port B
  input logic   [RAM_WIDTH-1:0]          i_din_b,       // Data input for port B
  // Outputs
  output logic  [RAM_WIDTH-1:0]          o_dout_a,      // Data output for port A
  output logic  [RAM_WIDTH-1:0]          o_dout_b       // Data output for port B
);

  // Memory declaration
  logic [RAM_WIDTH-1:0] ram [RAM_DEPTH-1:0] = '{default: '0};

  // Port A: Read/Write, write-through
  always_ff @(posedge CLK_a) begin
    if (i_we_a) begin
      ram[i_addr_a] <= i_din_a;
    end
    o_dout_a <= i_we_a ? i_din_a : ram[i_addr_a];  // Write-through
  end

  // Port B: Read/Write, write-through
  always_ff @(posedge CLK_b) begin
    if (i_we_b) begin
      ram[i_addr_b] <= i_din_b;
    end
    o_dout_b <= i_we_b ? i_din_b : ram[i_addr_b];  // Write-through
  end

endmodule

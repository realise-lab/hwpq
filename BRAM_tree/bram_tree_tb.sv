module bram_tree_tb;

  // Parameters
  parameter TREE_DEPTH = 4;
  parameter DATA_WIDTH = 32;

  // Signals
  logic clk;
  logic rst;
  logic replace;
  logic [DATA_WIDTH-1:0] new_item;
  logic [DATA_WIDTH-1:0] top_item;

  // Instantiate the Unit Under Test (UUT)
  bram_tree #(
      .TREE_DEPTH(TREE_DEPTH),
      .DATA_WIDTH(DATA_WIDTH)
  ) uut (
      .clk(clk),
      .rst(rst),
      .replace(replace),
      .new_item(new_item),
      .top_item(top_item)
  );

  // Clock generation
  always #5 clk <= ~clk;  // 100 MHz

  // Test procedure
  initial begin
    // Initialize signals
    clk = 0;
    rst = 0;
    replace = 0;
    new_item = 0;

    // Apply reset for a few clock cycles
    rst = 1;
    repeat (4) @(posedge clk);
    rst = 0;

    // Initial Sorting
    repeat (80) @(posedge clk);

    // Perform 5 replace operations with random numbers
    for (int i = 0; i < 10; i++) begin
      replace  = 1;
      new_item = $urandom_range(1, 250);  // Random number between 1 and 1000
      @(posedge clk);
      replace = 0;
      repeat (10) @(posedge clk);  // Wait for the replace operation to complete
    end

    // Wait for couple of clock cycles
    repeat (40) @(posedge clk);

    // End simulation
    $finish;
  end

  // Monitor outputs
  always @(posedge clk) begin
    $display("Time %0t: Valid output - %0d", $time, top_item);
  end

endmodule

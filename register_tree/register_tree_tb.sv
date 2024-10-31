module register_tree_tb;
  parameter TREE_DEPTH = 4;
  parameter DATA_WIDTH = 32;

  reg clk;
  reg rst;
  reg replace;
  reg [DATA_WIDTH-1:0] new_item;
  wire [DATA_WIDTH-1:0] top_item;

  // Reference model: array to hold the items
  reg [DATA_WIDTH-1:0] ref_items[(1 << TREE_DEPTH) - 1];
  int ref_count;
  reg [DATA_WIDTH-1:0] expected_top_item;

  register_tree #(
      .TREE_DEPTH(TREE_DEPTH),
      .DATA_WIDTH(DATA_WIDTH)
  ) dut (
      .clk(clk),
      .rst(rst),
      .replace(replace),
      .new_item(new_item),
      .top_item(top_item)
  );

  // Clock generation
  always #5 clk <= ~clk;

  // Function to find the expected top item from the reference model
  function [DATA_WIDTH-1:0] get_expected_top_item;
    integer i;
    reg [DATA_WIDTH-1:0] max_value;
    begin
      if (ref_count == 0) begin
        get_expected_top_item = '0;  // If no items, return zero
      end else begin
        max_value = ref_items[0];
        for (i = 1; i < ref_count; i = i + 1) begin
          if (ref_items[i] > max_value) begin
            max_value = ref_items[i];
          end
        end
        get_expected_top_item = max_value;
      end
    end
  endfunction

  // Test Simulation
  initial begin
    // Initialize signals
    clk = 0;
    rst = 1;
    replace = 0;
    new_item = 0;

    // Initialize reference model with the same values as the DUT
    ref_count = (1 << TREE_DEPTH) - 1;  //? Very weird, why is this not (1 << TREE_DEPTH) - 1?
    for (int j = 0; j < ref_count; j++) begin
      ref_items[j] = (j + 1) * 10;
    end

    // Finish reset
    repeat (2) @(posedge clk);
    rst = 0;
    repeat (4) @(posedge clk);

    // Initial assertion to check the top item after reset
    expected_top_item = get_expected_top_item();
    repeat (2) @(posedge clk);
    // Assert the top item matches expected after reset
    assert (top_item == expected_top_item)
    else
      $error(
          "Assertion failed after reset: Expected top_item = %0d, got %0d",
          expected_top_item,
          top_item
      );

    // Test case: Replace items with random values
    for (int i = 0; i < 10; i++) begin
      replace  = 1;
      new_item = $urandom_range(1, 100);
      @(posedge clk);
      replace = 0;
      @(posedge clk);

      // Update reference model
      // Replace the top item in the reference model with the new item
      for (int k = 0; k < ref_count; k++) begin
        if (ref_items[k] == expected_top_item) begin
          ref_items[k] = new_item;
          break;
        end
      end

      // Get expected top item from reference model
      expected_top_item = get_expected_top_item();
      repeat (2) @(posedge clk);
      // Assert the top item matches expected
      assert (top_item == expected_top_item)
      else
        $error(
            "Assertion failed at iteration %0d: Expected top_item = %0d, got %0d",
            i,
            expected_top_item,
            top_item
        );
      repeat (2) @(posedge clk);
    end

    // Finish simulation
    repeat (2) @(posedge clk);
    $finish;
  end

  // Monitor top item
  always @(posedge clk) begin
    if (replace) begin
      $display("Replaced top item with %0d, New top item is %0d", new_item, top_item);
    end
  end
endmodule

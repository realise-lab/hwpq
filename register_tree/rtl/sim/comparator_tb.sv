module comparator_tb;

  // Parameters
  localparam int DATA_WIDTH = 32;

  // Testbench signals
  logic [DataWidth-1:0] parent;
  logic [DataWidth-1:0] left_child;
  logic [DataWidth-1:0] right_child;
  logic [DataWidth-1:0] new_parent;
  logic [DataWidth-1:0] new_left_child;
  logic [DataWidth-1:0] new_right_child;

  // Instantiate the comparator module
  comparator #(
      .DATA_WIDTH(DataWidth)
  ) u_Comparator (
      .parent(parent),
      .left_child(left_child),
      .right_child(right_child),
      .new_parent(new_parent),
      .new_left_child(new_left_child),
      .new_right_child(new_right_child)
  );

  // Test procedure
  initial begin
    // Test case 1
    parent = 32'h00000010;
    left_child = 32'h00000020;
    right_child = 32'h00000030;
    #10;
    $display("Test case 1: parent=%h, left_child=%h, right_child=%h -> ",
             "new_parent=%h, new_left_child=%h, new_right_child=%h", parent, left_child,
             right_child, new_parent, new_left_child, new_right_child);

    // Test case 2
    parent = 32'h00000040;
    left_child = 32'h00000020;
    right_child = 32'h00000030;
    #10;
    $display("Test case 2: parent=%h, left_child=%h, right_child=%h -> ",
             "new_parent=%h, new_left_child=%h, new_right_child=%h", parent, left_child,
             right_child, new_parent, new_left_child, new_right_child);

    // Test case 3
    parent = 32'h00000010;
    left_child = 32'h00000005;
    right_child = 32'h00000008;
    #10;
    $display("Test case 3: parent=%h, left_child=%h, right_child=%h -> ",
             "new_parent=%h, new_left_child=%h, new_right_child=%h", parent, left_child,
             right_child, new_parent, new_left_child, new_right_child);

    // Test case 4
    parent = 32'h00000010;
    left_child = 32'h00000010;
    right_child = 32'h00000010;
    #10;
    $display("Test case 4: parent=%h, left_child=%h, right_child=%h -> ",
             "new_parent=%h, new_left_child=%h, new_right_child=%h", parent, left_child,
             right_child, new_parent, new_left_child, new_right_child);

    // Finish simulation
    $finish;
  end

endmodule

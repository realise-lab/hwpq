`default_nettype none

module comparator #(
    parameter int DATA_WIDTH = 32
) (
    // Inputs
    input var logic [DATA_WIDTH-1:0] i_parent,
    input var logic [DATA_WIDTH-1:0] i_left_child,
    input var logic [DATA_WIDTH-1:0] i_right_child,
    // Outputs
    output var logic [DATA_WIDTH-1:0] o_parent,
    output var logic [DATA_WIDTH-1:0] o_left_child,
    output var logic [DATA_WIDTH-1:0] o_right_child
);

  //----------------------------------------------------------------------
  // Internal Registers and Wires
  //----------------------------------------------------------------------
  logic left_greater_than_right;
  logic parent_less_than_left;
  logic parent_less_than_right;

  //----------------------------------------------------------------------
  // Signals assignments
  //----------------------------------------------------------------------
  // Perform the three simultaneous comparisons
  assign left_greater_than_right = (i_left_child > i_right_child);
  assign parent_less_than_left   = (i_parent < i_left_child);
  assign parent_less_than_right  = (i_parent < i_right_child);

  //----------------------------------------------------------------------
  // Output o_parent
  //----------------------------------------------------------------------
  always_comb begin
    if (left_greater_than_right && parent_less_than_left) o_parent = i_left_child;
    else if (!left_greater_than_right && parent_less_than_right) o_parent = i_right_child;
    else o_parent = i_parent;
  end

  //----------------------------------------------------------------------
  // Output o_left_child
  //----------------------------------------------------------------------
  always_comb begin
    if (left_greater_than_right && parent_less_than_left) o_left_child = i_parent;
    else o_left_child = i_left_child;
  end

  //----------------------------------------------------------------------
  // Output o_right_child
  //----------------------------------------------------------------------
  always_comb begin
    if (!left_greater_than_right && parent_less_than_right) o_right_child = i_parent;
    else o_right_child = i_right_child;
  end

endmodule

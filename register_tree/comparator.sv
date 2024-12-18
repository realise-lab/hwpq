module comparator #(
  parameter DATA_WIDTH = 32
) (
  // Inputs
  input logic [DATA_WIDTH-1:0] i_parent,
  input logic [DATA_WIDTH-1:0] i_left_child,
  input logic [DATA_WIDTH-1:0] i_right_child,
  // Outputs
  output logic [DATA_WIDTH-1:0] o_parent,
  output logic [DATA_WIDTH-1:0] o_left_child,
  output logic [DATA_WIDTH-1:0] o_right_child
);

  logic left_greater_than_right;
  logic parent_less_than_left;
  logic parent_less_than_right;

  always @(*) begin
    if (left_greater_than_right) begin
      if (parent_less_than_left) begin
        // Swap parent with left child
        o_parent = i_left_child;
        o_left_child = i_parent;
        o_right_child = i_right_child;
      end else begin
        // No swap needed
        o_parent = i_parent;
        o_left_child = i_left_child;
        o_right_child = i_right_child;
      end
    end else begin
      if (parent_less_than_right) begin
        // Swap parent with right child
        o_parent = i_right_child;
        o_left_child = i_left_child;
        o_right_child = i_parent;
      end else begin
        // No swap needed
        o_parent = i_parent;
        o_left_child = i_left_child;
        o_right_child = i_right_child;
      end
    end
  end

  // Perform the three simultaneous comparisons
  assign left_greater_than_right = (i_left_child > i_right_child);
  assign parent_less_than_left = (i_parent < i_left_child);
  assign parent_less_than_right = (i_parent < i_right_child);

endmodule

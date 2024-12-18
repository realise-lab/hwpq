/*
  This module compares the parent and the two children 
  to find the minimum value and put it in the parent.
*/
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

  always_comb begin
    if (i_left_child < i_right_child) begin
      if (i_parent > i_left_child) begin
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
      if (i_parent > i_right_child) begin
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

endmodule

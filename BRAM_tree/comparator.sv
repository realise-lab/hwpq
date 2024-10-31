module comparator #(
    parameter DATA_WIDTH = 32
) (
    input  wire [DATA_WIDTH-1:0] parent,
    input  wire [DATA_WIDTH-1:0] left_child,
    input  wire [DATA_WIDTH-1:0] right_child,
    output reg  [DATA_WIDTH-1:0] new_parent,
    output reg  [DATA_WIDTH-1:0] new_left_child,
    output reg  [DATA_WIDTH-1:0] new_right_child
);

  always_comb begin
    if (left_child >= right_child) begin
      if (parent < left_child) begin
        // Swap parent with left child
        new_parent = left_child;
        new_left_child = parent;
        new_right_child = right_child;
      end else begin
        // No swap needed
        new_parent = parent;
        new_left_child = left_child;
        new_right_child = right_child;
      end
    end else begin
      if (parent <= right_child) begin
        // Swap parent with right child
        new_parent = right_child;
        new_left_child = left_child;
        new_right_child = parent;
      end else begin
        // No swap needed
        new_parent = parent;
        new_left_child = left_child;
        new_right_child = right_child;
      end
    end
  end

endmodule

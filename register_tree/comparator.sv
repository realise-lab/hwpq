module comparator #(
    parameter DATA_WIDTH = 32
)(
    input wire [DATA_WIDTH-1:0] parent,
    input wire [DATA_WIDTH-1:0] left_child,
    input wire [DATA_WIDTH-1:0] right_child,
    output reg [DATA_WIDTH-1:0] new_parent,
    output reg [DATA_WIDTH-1:0] new_left_child,
    output reg [DATA_WIDTH-1:0] new_right_child
);
    wire left_greater_than_right;
    wire parent_less_than_left;
    wire parent_less_than_right;

    // Perform the three simultaneous comparisons
    assign left_greater_than_right = (left_child > right_child);
    assign parent_less_than_left = (parent < left_child);
    assign parent_less_than_right = (parent < right_child);

    always @(*) begin
        if (left_greater_than_right) begin
            if (parent_less_than_left) begin
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
            if (parent_less_than_right) begin
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

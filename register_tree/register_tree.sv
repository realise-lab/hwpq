module register_tree #(
    parameter TREE_DEPTH = 4,
    parameter DATA_WIDTH = 32
) (
    input wire clk,
    input wire rst,
    input wire replace,
    input wire [DATA_WIDTH-1:0] new_item,    // New item for replacing the top
    output reg [DATA_WIDTH-1:0] top_item     // Output the top item
);

  // Number of nodes in the tree
  localparam NUM_NODES = (1 << TREE_DEPTH) - 1;

  // Register array to store the tree nodes
  reg  [DATA_WIDTH-1:0] tree                [    0:NUM_NODES - 1];

  // Wires to connect the comparator units
  wire [DATA_WIDTH-1:0] new_parent          [0:NUM_NODES / 2 - 1];
  wire [DATA_WIDTH-1:0] new_left_child      [0:NUM_NODES / 2 - 1];
  wire [DATA_WIDTH-1:0] new_right_child     [0:NUM_NODES / 2 - 1];

  // Register to indicate even or odd level
  reg                   level_indicator = 0;

  // Instantiate comparator units for each applicable node
  genvar i;
  generate
    for (i = 0; i < NUM_NODES / 2; i = i + 1) begin : comparator_units
      comparator #(
          .DATA_WIDTH(DATA_WIDTH)
      ) comparator_inst (
          .parent(tree[i]),
          .left_child(tree[2*i+1]),
          .right_child(tree[2*i+2]),
          .new_parent(new_parent[i]),
          .new_left_child(new_left_child[i]),
          .new_right_child(new_right_child[i])
      );
    end
  endgenerate

  // State machine control
  always @(posedge clk) begin
    if (rst) begin
      level_indicator <= 0;
      for (int j = 0; j < NUM_NODES; j++) begin
        tree[j] <= (j + 1) * 10;  // Initialize tree entries to some values
      end
    end else begin
      if (level_indicator == 0) begin
        // Always update the root node
        tree[0] <= new_parent[0];
        tree[1] <= new_left_child[0];
        tree[2] <= new_right_child[0];
        // Replace the top item if replace signal is high
        if (replace) begin
          tree[0] <= new_item;
        end
        // Update the tree for even levels
        for (integer k = 2; k < TREE_DEPTH; k = k + 2) begin
          for (integer j = 2 ** k - 1; j <= 2 ** (k + 1) - 2; j = j + 1) begin
            tree[j]     <= new_parent[j];
            tree[2*j+1] <= new_left_child[j];
            tree[2*j+2] <= new_right_child[j];
          end
        end
        level_indicator <= 1;
      end
      // Handle odd levels
      if (level_indicator == 1) begin
        for (integer m = 1; m < TREE_DEPTH - 1; m = m + 2) begin
          for (integer n = 2 ** m - 1; n <= 2 ** (m + 1) - 2; n = n + 1) begin
            tree[n]     <= new_parent[n];
            tree[2*n+1] <= new_left_child[n];
            tree[2*n+2] <= new_right_child[n];
          end
        end
        level_indicator <= 0;
      end
    end
  end

  // Output the top item
  assign top_item = tree[0];

endmodule


module bram_tree #(
    parameter TREE_DEPTH = 4,
    parameter DATA_WIDTH = 32
) (
    input logic CLK,
    input logic RSTn,
    // Inputs
    input logic i_write,
    input logic i_read,
    input logic i_replace,
    input logic [DATA_WIDTH-1:0] i_new_item,
    // Outputs
    output logic o_full,
    output logic o_empty,
    output logic [DATA_WIDTH-1:0] o_top_item
);  
  // Local parameters
  localparam MAX_RAM_DEPTH = 1 << (TREE_DEPTH - 1);
  localparam COMP_NUM = (1 << (TREE_DEPTH - 1)) - 1;

  // BRAM interface signals
  logic i_mem_write [0:TREE_DEPTH-1];
  logic i_mem_read [0:TREE_DEPTH-1];
  logic [MAX_RAM_DEPTH-1:0] i_mem_wrt_addr [0:TREE_DEPTH-1];
  logic [MAX_RAM_DEPTH-1:0] i_mem_read_addr [0:TREE_DEPTH-1];
  logic [DATA_WIDTH-1:0] i_mem_data [0:TREE_DEPTH-1];
  logic [DATA_WIDTH-1:0] o_mem_data [0:TREE_DEPTH-1];

  // Comparator signals
  logic [DATA_WIDTH-1:0] parent[0:COMP_NUM-1];
  logic [DATA_WIDTH-1:0] left_child[0:COMP_NUM-1];
  logic [DATA_WIDTH-1:0] right_child[0:COMP_NUM-1];
  logic [DATA_WIDTH-1:0] new_parent[0:COMP_NUM-1];
  logic [DATA_WIDTH-1:0] new_left_child[0:COMP_NUM-1];
  logic [DATA_WIDTH-1:0] new_right_child[0:COMP_NUM-1];

  // Generate BRAMs for each level of the tree
  genvar i;
  generate
    for (i = 0; i < TREE_DEPTH; i++) begin : BRAM_gen
      bram #(
        .DATA_WIDTH(DATA_WIDTH),
        .RAM_DEPTH(MAX_RAM_DEPTH)
      ) bram_inst (
        .CLK(CLK),
        .RSTn(RSTn),
        .i_write(i_mem_write[i]),
        .i_read(i_mem_read[i]), 
        .i_wrt_addr(i_mem_wrt_addr[i]),
        .i_read_addr(i_mem_read_addr[i]),
        .i_data(i_mem_data[i]),
        .o_data(o_mem_data[i])
      );
    end
  endgenerate

  generate
    for (i = 0; i < COMP_NUM; i++) begin : comparator_gen
      comparator #(
          .DATA_WIDTH(DATA_WIDTH)
      ) comparator (
          .parent(parent[i]),
          .left_child(left_child[i]),
          .right_child(right_child[i]),
          .new_parent(new_parent[i]),
          .new_left_child(new_left_child[i]),
          .new_right_child(new_right_child[i])
      );
    end
  endgenerate

endmodule

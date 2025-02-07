module bram_tree #(
    parameter int QUEUE_SIZE = 8,
    parameter int DATA_WIDTH = 32
) (
    input logic CLK,
    input logic RSTn,
    // Inputs
    input logic i_wrt,
    input logic i_read,
    input logic [DATA_WIDTH-1:0] i_data,
    // Outputs
    output logic [DATA_WIDTH-1:0] o_data
);
  // Local parameters
  localparam int TreeDepth = $clog2(QUEUE_SIZE + 1);  // if QUEUE_SIZE = 8, TREE_DEPTH = 4
  localparam int MaxRamDepth = 2 ** (TreeDepth - 1);  // if TREE_DEPTH = 4, MAX_RAM_DEPTH = 8
  localparam int NodesNeeded = 2 ** TreeDepth - 1;  // if TREE_DEPTH = 4, NODES_NEEDED = 15
  localparam int CompCount = NodesNeeded / 2;  // if NODES_NEEDED = 15, COMP_COUNT = 7

  // BRAM interface signals
  // Port A
  logic                           mem_we_a_lvl         [TreeDepth];
  logic [        MaxRamDepth-1:0] mem_addr_a_lvl       [TreeDepth];
  logic [         DATA_WIDTH-1:0] mem_din_a_lvl        [TreeDepth];
  logic [         DATA_WIDTH-1:0] mem_dout_a_lvl       [TreeDepth];
  // Port B
  logic                           mem_we_b_lvl         [TreeDepth];
  logic [        MaxRamDepth-1:0] mem_addr_b_lvl       [TreeDepth];
  logic [         DATA_WIDTH-1:0] mem_din_b_lvl        [TreeDepth];
  logic [         DATA_WIDTH-1:0] mem_dout_b_lvl       [TreeDepth];
  // BRAM access control signals
  logic [  $clog2(TreeDepth)-1:0] mem_current_level;
  logic [$clog2(MaxRamDepth)-1:0] mem_current_addr;

  // Comparator signals
  logic [         DATA_WIDTH-1:0] parent_value         [CompCount];
  logic [         DATA_WIDTH-1:0] left_child_value     [CompCount];
  logic [         DATA_WIDTH-1:0] right_child_value    [CompCount];

  logic [         DATA_WIDTH-1:0] new_parent_value     [CompCount];
  logic [         DATA_WIDTH-1:0] new_left_child_value [CompCount];
  logic [         DATA_WIDTH-1:0] new_right_child_value[CompCount];

  integer j, k, m, n;

  // Generate BRAMs for each level of the tree
  genvar i;
  generate
    for (i = 0; i < TreeDepth; i++) begin : gen_BRAM
      dual_port_bram #(
          .BRAM_WIDTH(DATA_WIDTH),
          .BRAM_DEPTH(MaxRamDepth)
      ) bram_inst (
          .CLK_a(CLK),
          .CLK_b(CLK),
          .i_we_a(mem_we_a_lvl[i]),
          .i_addr_a(mem_addr_a_lvl[i]),
          .i_din_a(mem_din_a_lvl[i]),
          .i_we_b(mem_we_b_lvl[i]),
          .i_addr_b(mem_addr_b_lvl[i]),
          .i_din_b(mem_din_b_lvl[i]),
          .o_dout_a(mem_dout_a_lvl[i]),
          .o_dout_b(mem_dout_b_lvl[i])
      );
    end
  endgenerate

  // Generate all comparators needed for the tree
  generate
    for (i = 0; i < CompCount; i++) begin : gen_comparator
      comparator #(
          .DATA_WIDTH(DATA_WIDTH)
      ) comparator_inst (
          .i_parent(parent_value[i]),
          .i_left_child(left_child_value[i]),
          .i_right_child(right_child_value[i]),
          .o_parent(new_parent_value[i]),
          .o_left_child(new_left_child_value[i]),
          .o_right_child(new_right_child_value[i])
      );
    end
  endgenerate

  // Four states, read, write, even_compare, and odd_compare
  typedef enum logic [1:0] {
    IDLE             = 2'b00,
    COMPARE_AND_SWAP = 2'b01,
    REPLACE          = 2'b10
  } state_t;
  state_t state;

  // State register
  always_ff @(posedge CLK or negedge RSTn) begin
    if (!RSTn) begin
      mem_we_a_lvl          <= '{default: 0};
      mem_addr_a_lvl        <= '{default: 0};
      mem_din_a_lvl         <= '{default: 0};
      mem_we_b_lvl          <= '{default: 0};
      mem_addr_b_lvl        <= '{default: 0};
      mem_din_b_lvl         <= '{default: 0};
      parent_value          <= '{default: 0};
      left_child_value      <= '{default: 0};
      right_child_value     <= '{default: 0};
      new_parent_value      <= '{default: 0};
      new_left_child_value  <= '{default: 0};
      new_right_child_value <= '{default: 0};
      mem_current_level     <= 0;
      mem_current_addr      <= 0;
      state                 <= IDLE;
    end else begin
      case (state)
        IDLE: begin
          // change state based on input
          if (i_wrt && i_read) begin
            state <= REPLACE;
          end else begin
            state <= COMPARE_AND_SWAP;
          end
        end

        COMPARE_AND_SWAP: begin
          // Write the new root comparator's results to the BRAM
          mem_we_a_lvl[0]   <= 1;
          mem_addr_a_lvl[0] <= 0;
          mem_din_a_lvl[0]  <= new_parent_value[0];
          mem_we_a_lvl[1]   <= 1;
          mem_addr_a_lvl[1] <= 0;
          mem_din_a_lvl[1]  <= new_left_child_value[0];
          mem_we_b_lvl[1]   <= 1;
          mem_addr_b_lvl[1] <= 1;
          mem_din_b_lvl[1]  <= new_right_child_value[0];
          // change state based on input
          if (i_wrt && i_read) begin
            state <= REPLACE;
          end else begin
            state <= COMPARE_AND_SWAP;
          end
        end

        REPLACE: begin
          // Replace the root of the tree with the new value
          mem_we_a_lvl[0]    <= 1;
          mem_addr_a_lvl[0]  <= 0;
          mem_din_a_lvl[0]   <= i_data;
          state <= COMPARE_AND_SWAP;
        end

        default: begin  // stay in current state
          state <= IDLE;
        end
      endcase
    end
  end

  always_comb begin
    case (state)
      IDLE: begin
      end

      COMPARE_AND_SWAP: begin
        // Read the data from the BRAM in to parent_value, left_child_value, and right_child_value
        for (j = 0; j < TREE_DEPTH; j++) begin  // j means the level of the tree
          mem_we_a_lvl[j] = 0;
          mem_we_b_lvl[j] = 0;
          if (j == TREE_DEPTH - 1) begin  // no comparators on the last level
            break;
          end else begin
            for (
                k = 0; k < MAX_RAM_DEPTH; k++
            ) begin  // k means the address of a data slot in this BRAM (One BRAM for each level)
              mem_addr_a_lvl[j]           = k;
              mem_addr_a_lvl[j+1]         = 2 * k;
              mem_addr_b_lvl[j+1]         = 2 * k + 1;
              parent_value[2**j-1+k]      = mem_dout_a_lvl[j];
              left_child_value[2**j-1+k]  = mem_dout_a_lvl[j+1];
              right_child_value[2**j-1+k] = mem_dout_b_lvl[j+1];
            end
          end
        end
        // iterate through even levels of the tree
        for (k = 2; k < TREE_DEPTH; k = k + 2) begin  // k means the level of the tree (even)
          if (k == TREE_DEPTH - 1) begin  // no comparators on the last level
            break;
          end else begin
            for (
                j = 0; j < MAX_RAM_DEPTH; j++
            ) begin  // j means the address of a data slot in this BRAM (One BRAM for each level)
              mem_we_a_lvl[k]     = 1;
              mem_addr_a_lvl[k]   = j;
              mem_din_a_lvl[k]    = new_parent_value[2**k-1+j];
              mem_we_a_lvl[k+1]   = 1;
              mem_addr_a_lvl[k+1] = 2 * j;
              mem_din_a_lvl[k+1]  = new_left_child_value[2**k-1+j];
              mem_we_b_lvl[k+1]   = 1;
              mem_addr_b_lvl[k+1] = 2 * j + 1;
              mem_din_b_lvl[k+1]  = new_right_child_value[2**k-1+j];
            end
          end
        end
        // iterate through odd levels of the tree
        for (m = 1; m < TREE_DEPTH; m = m + 2) begin  // m means the level of the tree (odd)
          if (m == TREE_DEPTH - 1) begin  // no comparators on the last level
            break;
          end else begin
            for (
                n = 0; n < MAX_RAM_DEPTH; n++
            ) begin  // n means the address of a data slot in this BRAM (One BRAM for each level)
              mem_we_a_lvl[m]     = 1;
              mem_addr_a_lvl[m]   = n;
              mem_din_a_lvl[m]    = new_parent_value[2**m-1+n];
              mem_we_a_lvl[m+1]   = 1;
              mem_addr_a_lvl[m+1] = 2 * n;
              mem_din_a_lvl[m+1]  = new_left_child_value[2**m-1+n];
              mem_we_b_lvl[m+1]   = 1;
              mem_addr_b_lvl[m+1] = 2 * n + 1;
              mem_din_b_lvl[m+1]  = new_right_child_value[2**m-1+n];
            end
          end
        end
      end

      REPLACE: begin
      end

      default: begin
      end
    endcase
  end

  assign o_data = mem_dout_a_lvl[0];

endmodule

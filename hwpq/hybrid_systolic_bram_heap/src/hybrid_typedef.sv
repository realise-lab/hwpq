package bram_tree_pkg;
  localparam integer SYSTOLIC_QUEUE_SIZE = 16;
  localparam integer TREE_COUNT = 11;

  localparam integer BRAM_TREE_QUEUE_SIZE = 2047;
  localparam integer QUEUE_SIZE = 15;
  localparam integer DATA_WIDTH = 16;
  localparam integer TREE_DEPTH    = $clog2(BRAM_TREE_QUEUE_SIZE + 1);
  localparam integer NODES_NEEDED  = (1 << TREE_DEPTH) - 1; 
  localparam integer ADDRESS_WIDTH = $clog2(NODES_NEEDED);
  // Wide enough to hold 0..BRAM_TREE_QUEUE_SIZE inclusive
  localparam integer QUEUE_COUNT_WIDTH = $clog2(BRAM_TREE_QUEUE_SIZE + 1);

  // Max-heap: a node is just its value, and 0 is the "empty" sentinel
  // (it is the lowest possible priority, so empties naturally sink to the bottom).
  localparam logic [DATA_WIDTH-1:0] EMPTY_VAL = '0;

  // Pessimistic "root not known yet" bound for a max-heap: the best possible priority, so reads
  // stall until the heap settles. (Mirror of the min-heap's 0, which is its best possible priority.)
  localparam logic [DATA_WIDTH-1:0] UNKNOWN_VAL = '1;

  // Keep track if the node is active, it's value and how much available nodes are under it
  typedef struct packed {
    logic active;
    logic [DATA_WIDTH-1:0] value;
    logic [ADDRESS_WIDTH-1:0]  capacity;
  } bram_tree_mem_t;

  // Keep track of the current node's value and position
  typedef struct packed {
    logic [DATA_WIDTH-1:0] value;
    logic [ADDRESS_WIDTH-1:0] position;
    logic [ADDRESS_WIDTH-1:0] capacity;
  } bram_tree_curr_t;

  // One-hot index of the LARGEST of 6 values. Ties go to the lowest index.
  // (This is the body of the old argmin6_oh, which as written selected the max.)
  function automatic logic [5:0] argmax6_oh(input logic [5:0][DATA_WIDTH-1:0] v);
    logic [5:0][5:0] ge;     // ge[a][b] (a<b) : v[a] >= v[b]
    logic [5:0]      win;
    ge = '0;
    for (int a = 0; a < 6; a++)
      for (int b = a+1; b < 6; b++)
        ge[a][b] = (v[a] >= v[b]);
    for (int i = 0; i < 6; i++) begin
      win[i] = 1'b1;
      for (int j = 0; j < 6; j++) begin
        if      (j > i) win[i] = win[i] &  ge[i][j];   // i beats later entries on ties
        else if (j < i) win[i] = win[i] & ~ge[j][i];   // strictly greater than earlier entries
      end
    end
    return win;
  endfunction

  function automatic logic [DATA_WIDTH-1:0] oh6_select(
      input logic [5:0][DATA_WIDTH-1:0] v, input logic [5:0] oh);
    logic [DATA_WIDTH-1:0] r;
    r = '0;
    for (int i = 0; i < 6; i++) r = r | (v[i] & {DATA_WIDTH{oh[i]}});
    return r;
  endfunction

endpackage
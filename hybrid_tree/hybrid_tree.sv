module hybrid_tree #(
    parameter integer DATA_WIDTH = 12,
    parameter integer ARRAY_SIZE = 4,
    parameter integer QUEUE_SIZE = 28
) (
    input  logic                  CLK,
    input  logic                  RSTn,
    // Inputs
    input  logic                  i_wrt,    // Write/insert command
    input  logic                  i_read,   // Read/pop command
    input  logic [DATA_WIDTH-1:0] i_data,   // Data to be inserted (or used for replace)
    // Outputs
    output logic                  o_full,   // High if the heap is full
    output logic                  o_empty,  // High if the heap is empty
    output logic [DATA_WIDTH-1:0] o_data    // Output data (popped value)
);

  //-------------------------------------------------------------------------
  // Local parameters
  //-------------------------------------------------------------------------
  localparam integer BRAM_COUNT = ARRAY_SIZE;
  localparam integer BRAM_SIZE = QUEUE_SIZE / BRAM_COUNT;
  localparam integer BRAM_DEPTH = $clog2(BRAM_SIZE + 1);

  //-------------------------------------------------------------------------
  // Internal used wires and registers
  //-------------------------------------------------------------------------
  // Level 0 register array data structure
  logic [DATA_WIDTH-1:0] level_0_data[ARRAY_SIZE-1:0];
  logic [DATA_WIDTH-1:0] next_level_0_data[ARRAY_SIZE-1:0];
  logic [$clog2(ARRAY_SIZE)-1:0] level_0_target[ARRAY_SIZE-1:0];
  logic [$clog2(ARRAY_SIZE)-1:0] next_level_0_target[ARRAY_SIZE-1:0];
  logic [(DATA_WIDTH + $clog2(ARRAY_SIZE))-1:0] level_0[ARRAY_SIZE-1:0];
  logic [(DATA_WIDTH + $clog2(ARRAY_SIZE))-1:0] next_level_0[ARRAY_SIZE-1:0];

  genvar lv_0_gen;
  generate
    for (lv_0_gen = 0; lv_0_gen < ARRAY_SIZE; lv_0_gen++) begin : gen_level_0_assignments
      assign level_0[lv_0_gen] = {level_0_target[lv_0_gen], level_0_data[lv_0_gen]};
      assign next_level_0[lv_0_gen] = {next_level_0_target[lv_0_gen], next_level_0_data[lv_0_gen]};
    end
  endgenerate

  // level 1 register array data structure
  logic [DATA_WIDTH-1:0] level_1_data[ARRAY_SIZE-1:0];
  logic [DATA_WIDTH-1:0] next_level_1_data[ARRAY_SIZE-1:0];
  logic level_1_valid[ARRAY_SIZE-1:0];
  logic next_level_1_valid[ARRAY_SIZE-1:0];
  logic [DATA_WIDTH:0] level_1[ARRAY_SIZE-1:0];
  logic [DATA_WIDTH:0] next_level_1[ARRAY_SIZE-1:0];

  genvar lv_1_gen;
  generate
    for (lv_1_gen = 0; lv_1_gen < ARRAY_SIZE; lv_1_gen++) begin : gen_level_1_assignments
      assign level_1[lv_1_gen] = {level_1_valid[lv_1_gen], level_1_data[lv_1_gen]};
      assign next_level_1[lv_1_gen] = {next_level_1_valid[lv_1_gen], next_level_1_data[lv_1_gen]};
    end
  endgenerate

  // input signals reroute
  logic enqueue, dequeue, replace;
  logic
      enqueue_done,
      dequeue_done,
      replace_done,
      next_enqueue_done,
      next_dequeue_done,
      next_replace_done;
  assign enqueue = i_wrt && !i_read;
  assign dequeue = !i_wrt && i_read;
  assign replace = i_wrt && i_read;

  // size tracker, full and empty flags
  logic [$clog2(QUEUE_SIZE)-1:0] size;
  logic [$clog2(QUEUE_SIZE)-1:0] next_size;
  logic empty, full;

  always_ff @(posedge CLK or negedge RSTn) begin : queue_size_seq
    if (!RSTn) begin
      size <= 0;
    end else begin
      size <= next_size;
    end
  end

  always_comb begin : size_comb
    next_size = size;
    if (i_wrt && !i_read) begin  // enqueue
      next_size = size + 1;
    end else if (!i_wrt && i_read) begin  // dequeue
      next_size = size - 1;
    end else if (i_wrt && i_read) begin  // replace
      next_size = size;
      if (size == 0 && i_data != 0) begin  // this would be a special case for replace
        next_size = size + 1;
      end
    end
  end

  // BRAM input & output signals
  logic bram_i_wrt[ARRAY_SIZE-1:0];
  logic bram_i_read[ARRAY_SIZE-1:0];
  logic [DATA_WIDTH-1:0] bram_i_data[ARRAY_SIZE-1:0];
  logic [DATA_WIDTH-1:0] next_bram_i_data[ARRAY_SIZE-1:0];
  logic bram_o_full[ARRAY_SIZE-1:0];
  logic bram_o_empty[ARRAY_SIZE-1:0];
  logic [DATA_WIDTH-1:0] bram_o_data[ARRAY_SIZE-1:0];
  logic bram_enqueue[ARRAY_SIZE-1:0];
  logic next_bram_enqueue[ARRAY_SIZE-1:0];
  logic bram_dequeue[ARRAY_SIZE-1:0];
  logic next_bram_dequeue[ARRAY_SIZE-1:0];
  logic bram_replace[ARRAY_SIZE-1:0];
  logic next_bram_replace[ARRAY_SIZE-1:0];

  always_comb begin : bram_signals_logic
    for (int i = 0; i < ARRAY_SIZE; i++) begin
      if (bram_enqueue[i]) begin
        bram_i_wrt[i]  = 1;
        bram_i_read[i] = 0;
      end else if (bram_dequeue[i]) begin
        bram_i_wrt[i]  = 0;
        bram_i_read[i] = 1;
      end else if (bram_replace[i]) begin
        bram_i_wrt[i]  = 1;
        bram_i_read[i] = 1;
      end else begin
        bram_i_wrt[i]  = 0;
        bram_i_read[i] = 0;
      end
    end
  end

  //-------------------------------------------------------------------------
  // Internal modules instantiation
  //-------------------------------------------------------------------------
  genvar bram_tree_gen;
  generate
    for (bram_tree_gen = 0; bram_tree_gen < ARRAY_SIZE; bram_tree_gen++) begin : gen_bram_tree
      pipelined_bram_tree #(
          .DATA_WIDTH(DATA_WIDTH),
          .QUEUE_SIZE(BRAM_SIZE)
      ) bram_tree_inst (
          .CLK(CLK),
          .RSTn(RSTn),
          .i_wrt(bram_i_wrt[bram_tree_gen]),
          .i_read(bram_i_read[bram_tree_gen]),
          .i_data(bram_i_data[bram_tree_gen]),
          .o_full(bram_o_full[bram_tree_gen]),
          .o_empty(bram_o_empty[bram_tree_gen]),
          .o_data(bram_o_data[bram_tree_gen])
      );
    end
  endgenerate

  //-------------------------------------------------------------------------
  // Regsiter Array Mamagement
  //-------------------------------------------------------------------------
  always_ff @(posedge CLK or negedge RSTn) begin : array_seq
    if (!RSTn) begin
      for (int i = 0; i < ARRAY_SIZE; i++) begin
        level_0_data[i]   <= '{default: 0};
        level_0_target[i] <= '{default: 0};
        level_1_data[i]   <= '{default: 0};
        level_1_valid[i]  <= '0;
        enqueue_done      <= '1;
        dequeue_done      <= '1;
        replace_done      <= '1;
        bram_enqueue[i]   <= '0;
        bram_dequeue[i]   <= '0;
        bram_replace[i]   <= '0;
        bram_i_data[i]    <= '{default: 0};
      end
    end else begin
      for (int i = 0; i < ARRAY_SIZE; i++) begin
        level_0_data[i]   <= next_level_0_data[i];
        level_0_target[i] <= next_level_0_target[i];
        level_1_data[i]   <= next_level_1_data[i];
        level_1_valid[i]  <= next_level_1_valid[i];
        enqueue_done      <= next_enqueue_done;
        dequeue_done      <= next_dequeue_done;
        replace_done      <= next_replace_done;
        bram_enqueue[i]   <= next_bram_enqueue[i];
        bram_dequeue[i]   <= next_bram_dequeue[i];
        bram_replace[i]   <= next_bram_replace[i];
        bram_i_data[i]    <= next_bram_i_data[i];
      end
    end
  end

  always_comb begin : array_comb
    for (int i = 0; i < ARRAY_SIZE; i++) begin
      next_level_0_data[i]   = level_0_data[i];
      next_level_0_target[i] = level_0_target[i];
      next_level_1_data[i]   = level_1_data[i];
      next_level_1_valid[i]  = level_1_valid[i];
      next_enqueue_done      = enqueue_done;
      next_dequeue_done      = dequeue_done;
      next_replace_done      = replace_done;
      next_bram_enqueue[i]   = '0;
      next_bram_dequeue[i]   = '0;
      next_bram_replace[i]   = '0;
      next_bram_i_data[i]    = bram_i_data[i];
    end

    for (int i = 0; i < ARRAY_SIZE; i++) begin
      next_level_1_data[i] = bram_o_data[i];
      if (bram_o_data[i] != 0) begin
        next_level_1_valid[i] = 1;
      end
    end

    // Handle Replace operation
    if (replace) begin
      next_level_0_data[0] = i_data;
      next_replace_done = 1'b0;
    end
    if (!replace_done) begin
      if (level_1_valid[level_0_target[0]]) begin // if level_1 data of the corresponding tree is valid
        if (i_data < level_1_data[level_0_target[0]]) begin // need to signal BRAM tree module to replace
          next_level_0_data[0] = level_1_data[level_0_target[0]];
          next_level_1_data[level_0_target[0]] = 0;
          next_level_1_valid[level_0_target[0]] = 0;
          next_bram_replace[level_0_target[0]] = 1;
          next_bram_i_data[level_0_target[0]] = i_data;
        end
        next_replace_done = 1'b1;
      end
    end

    // First phase (even-odd)
    for (int i = 0; i < ARRAY_SIZE - 1; i += 2) begin
      if (i + 1 < ARRAY_SIZE) begin
        if (level_0_data[i] < level_0_data[i+1]) begin
          next_level_0_data[i] = level_0_data[i+1];
          next_level_0_data[i+1] = level_0_data[i];
          next_level_0_target[i] = level_0_target[i+1];
          next_level_0_target[i+1] = level_0_target[i];
        end
      end
    end

    // Second phase (odd-even)
    for (int i = 1; i < ARRAY_SIZE - 1; i += 2) begin
      if (i + 1 < ARRAY_SIZE) begin
        if (level_0_data[i] < level_0_data[i+1]) begin
          next_level_0_data[i] = level_0_data[i+1];
          next_level_0_data[i+1] = level_0_data[i];
          next_level_0_target[i] = level_0_target[i+1];
          next_level_0_target[i+1] = level_0_target[i];
        end
      end
    end
  end

  always_comb begin : empty_check
    empty = 1'b1;
    for (int i = 0; i < ARRAY_SIZE; i++) begin
      empty = empty & bram_o_empty[i];  // AND operation to ensure all are empty
    end
  end

  always_comb begin : full_check
    full = 1'b1;
    for (int i = 0; i < ARRAY_SIZE; i++) begin
      full = full & bram_o_full[i];  // AND operation to ensure all are full
    end
  end

  assign o_empty = empty;
  assign o_full  = full;
  assign o_data  = level_0_data[0];

endmodule

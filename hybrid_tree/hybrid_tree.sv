module hybrid_tree #(
    parameter integer DATA_WIDTH = 16,
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
  assign enqueue = i_wrt && !i_read;
  assign dequeue = !i_wrt && i_read;
  assign replace = i_wrt && i_read;

  // size tracker
  logic [$clog2(QUEUE_SIZE)-1:0] queue_size;
  logic [$clog2(QUEUE_SIZE)-1:0] next_queue_size;
  logic empty, full;
  assign empty = (queue_size == 0);
  assign full  = (queue_size == QUEUE_SIZE);

  // iteration counter
  integer seq_itr, comb_itr;

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
      end 
      else if (bram_dequeue[i]) begin
        bram_i_wrt[i]  = 0;
        bram_i_read[i] = 1;
      end 
      else if (bram_replace[i]) begin
        bram_i_wrt[i]  = 1;
        bram_i_read[i] = 1;
      end 
      else begin
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
      for (seq_itr = 0; seq_itr < ARRAY_SIZE; seq_itr++) begin
        level_0_data[seq_itr]   <= '{default: 0};
        level_0_target[seq_itr] <= '{default: 0};
        level_1_data[seq_itr]   <= '{default: 0};
        level_1_valid[seq_itr]  <= '0;
        bram_enqueue[seq_itr]   <= '0;
        bram_dequeue[seq_itr]   <= '0;
        bram_replace[seq_itr]   <= '0;
        bram_i_data[seq_itr]    <= '{default: 0};
      end
    end else begin
      for (seq_itr = 0; seq_itr < ARRAY_SIZE; seq_itr++) begin
        level_0_data[seq_itr]   <= next_level_0_data[seq_itr];
        level_0_target[seq_itr] <= next_level_0_target[seq_itr];
        level_1_data[seq_itr]   <= next_level_1_data[seq_itr];
        level_1_valid[seq_itr]  <= next_level_1_valid[seq_itr];
        bram_enqueue[seq_itr]   <= next_bram_enqueue[seq_itr];
        bram_dequeue[seq_itr]   <= next_bram_dequeue[seq_itr];
        bram_replace[seq_itr]   <= next_bram_replace[seq_itr];
        bram_i_data[seq_itr]    <= next_bram_i_data[seq_itr];
      end
    end
  end

  always_comb begin : array_comb
    for (comb_itr = 0; comb_itr < ARRAY_SIZE; comb_itr++) begin
      next_level_0_data[comb_itr]   = level_0_data[comb_itr];
      next_level_0_target[comb_itr] = level_0_target[comb_itr];
      next_level_1_data[comb_itr]   = level_1_data[comb_itr];
      next_level_1_valid[comb_itr]  = level_1_valid[comb_itr];
      next_bram_enqueue[comb_itr]   = '0;
      next_bram_dequeue[comb_itr]   = '0;
      next_bram_replace[comb_itr]   = '0;
      next_bram_i_data[comb_itr]    = bram_i_data[comb_itr];
    end

    // Handle Replace operation
    if (replace) begin
      if (empty) begin
        // If empty, just insert the new item to the most left node
        if (i_data != 0) begin
          next_level_0_data[0] = i_data;
        end
      end 
      else begin
        // Replace the root with new value and do pulsation
        next_level_0_data[0] = i_data;

        // Check if the target level 1 node is valid
        if (level_1_valid[level_0_target[0]]) begin
          // Compare with the level 1 node
          if (i_data < level_1_data[level_0_target[0]]) begin
            // New item is smaller, swap with level 1 node
            next_level_0_data[0] = level_1_data[level_0_target[0]];
            next_level_1_data[level_0_target[0]] = i_data;
            // This is where we need to send signals to corresponding BRAM
            next_bram_replace[level_0_target[0]] = 1;
            next_bram_i_data[level_0_target[0]] = i_data;
          end
          // If new item is larger or equal, it stays in level_0_data[0]
        end
        // If level 1 node is invalid, new item stays in level_0_data[0]

        // First phase (even-odd)
        for (int i = 0; i < ARRAY_SIZE - 1; i += 2) begin
          if (i + 1 < ARRAY_SIZE) begin
            if (next_level_0_data[i] < next_level_0_data[i+1]) begin
              // Swap data and tree tags
              next_level_0[i] ^= next_level_0[i+1];
              next_level_0[i+1] ^= next_level_0[i];
              next_level_0[i] ^= next_level_0[i+1];
            end
          end
        end

        // Second phase (odd-even)
        for (int i = 1; i < ARRAY_SIZE - 1; i += 2) begin
          if (i + 1 < ARRAY_SIZE) begin
            if (next_level_0_data[i] < next_level_0_data[i+1]) begin
              // Swap data and tree tags
              next_level_0[i] ^= next_level_0[i+1];
              next_level_0[i+1] ^= next_level_0[i];
              next_level_0[i] ^= next_level_0[i+1];
            end
          end
        end
      end
    end
  end

  //-------------------------------------------------------------------------
  // Queue size counter
  //-------------------------------------------------------------------------
  always_ff @(posedge CLK or negedge RSTn) begin : queue_size_seq
    if (!RSTn) begin
      queue_size <= 0;
    end else begin
      queue_size <= next_queue_size;
    end
  end

  always_comb begin : queue_size_comb
    next_queue_size = queue_size;
    if (i_wrt && !i_read) begin  // enqueue
      next_queue_size = queue_size + 1;
    end else if (!i_wrt && i_read) begin  // dequeue
      next_queue_size = queue_size - 1;
    end else if (i_wrt && i_read) begin  // replace
      next_queue_size = queue_size;
      if (queue_size == 0 && i_data != 0) begin  // this would be a special case for replace
        next_queue_size = queue_size + 1;
      end
    end
  end

  //-------------------------------------------------------------------------
  // Assignments for status and output.
  //-------------------------------------------------------------------------
  assign o_empty = empty;
  assign o_full  = full;
  assign o_data  = level_0_data[0];

endmodule

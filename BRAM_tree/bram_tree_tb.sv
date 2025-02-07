module bram_tree_tb;
  // Parameters
  localparam int unsigned QueueSize = 8;
  localparam int unsigned DataWidth = 32;
  localparam int unsigned TreeDepth = $clog2(QueueSize + 1);
  localparam int unsigned NodesNeeded = 2 ** TreeDepth - 1;
  localparam int unsigned CompCount = NodesNeeded / 2;

  // Signals
  logic CLK;
  logic RSTn;
  logic i_wrt;
  logic i_read;
  logic [DataWidth-1:0] i_data;
  logic [DataWidth-1:0] o_data;

  // Reference array for verification
  logic [DataWidth-1:0] ref_queue[NodesNeeded];

  // Clock generation
  always #5 CLK <= ~CLK;

  // DUT instantiation
  bram_tree #(
      .QueueSize(QueueSize),
      .DataWidth(DataWidth)
  ) dut (
      .CLK(CLK),
      .RSTn(RSTn),
      .i_wrt(i_wrt),
      .i_read(i_read),
      .i_data(i_data),
      .o_data(o_data)
  );

  // Initialize BRAM with values through backdoor access
  initial begin
    // Initialize the bottom level of the tree (level 3 for QUEUE_SIZE=8)
    dut.BRAM_gen[3].bram_inst.bram[0] = 32'd8;
    ref_queue.push_back(32'd8);
    dut.BRAM_gen[3].bram_inst.bram[1] = 32'd6;
    ref_queue.push_back(32'd6);
    dut.BRAM_gen[3].bram_inst.bram[2] = 32'd4;
    ref_queue.push_back(32'd4);
    dut.BRAM_gen[3].bram_inst.bram[3] = 32'd2;
    ref_queue.push_back(32'd2);
    dut.BRAM_gen[3].bram_inst.bram[4] = 32'd9;
    ref_queue.push_back(32'd9);
    dut.BRAM_gen[3].bram_inst.bram[5] = 32'd5;
    ref_queue.push_back(32'd5);
    dut.BRAM_gen[3].bram_inst.bram[6] = 32'd3;
    ref_queue.push_back(32'd3);
    dut.BRAM_gen[3].bram_inst.bram[7] = 32'd1;
    ref_queue.push_back(32'd1);

    // Initialize level 2
    dut.BRAM_gen[2].bram_inst.bram[0] = 32'd6;
    ref_queue.push_back(32'd6);
    dut.BRAM_gen[2].bram_inst.bram[1] = 32'd2;
    ref_queue.push_back(32'd2);
    dut.BRAM_gen[2].bram_inst.bram[2] = 32'd5;
    ref_queue.push_back(32'd5);
    dut.BRAM_gen[2].bram_inst.bram[3] = 32'd1;
    ref_queue.push_back(32'd1);

    // Initialize level 1
    dut.BRAM_gen[1].bram_inst.bram[0] = 32'd2;
    ref_queue.push_back(32'd2);
    dut.BRAM_gen[1].bram_inst.bram[1] = 32'd1;
    ref_queue.push_back(32'd1);

    // Initialize root (level 0)
    dut.BRAM_gen[0].bram_inst.bram[0] = 32'd1;
    ref_queue.push_back(32'd1);

    // Sort the reference queue
    ref_queue.rsort();
  end

  // Test variables
  integer i;
  logic [DATA_WIDTH-1:0] random_value;

  initial begin
    // Initialize signals
    CLK = 0;
    RSTn = 0;
    i_wrt = 0;
    i_read = 0;
    i_data = 0;

    // Reset the module
    @(posedge CLK);
    RSTn = 1;
    repeat (3) @(posedge CLK);

    // Test Case 1: Verify initial state
    $display("\nTest Case 1: Initial State Test");
    assert (o_data == ref_queue[0])
    else $error("Initial top_item mismatch: expected %d, got %d", ref_queue[0], o_data);

    // Test Case 2: Replace top item with random values
    $display("\nTest Case 2: Replace Test");
    for (i = 0; i < QUEUE_SIZE; i++) begin
      random_value = $urandom_range(1, 256);
      replace(random_value);
      assert (o_data == ref_queue[0])
      else $error("Replace top_item mismatch: expected %d, got %d", ref_queue[0], o_data);
    end

    repeat (4) @(posedge CLK);  // Wait for tree to stabilize
    assert (o_data == ref_queue[0])
    else $error("Rapid replace top_item mismatch: expected %d, got %d", ref_queue[0], o_data);

    $display("\nTestbench completed");
    $finish;
  end

  // Task to replace top item
  task automatic replace(input logic [DataWidth-1:0] value);
    begin
      i_wrt  = 1;
      i_read = 1;
      i_data = value;
      ref_queue.pop_front();
      ref_queue.push_back(value);
      ref_queue.rsort();
      @(posedge CLK);
      i_wrt  = 0;
      i_read = 0;
      repeat (3) @(posedge CLK);
    end
  endtask

endmodule

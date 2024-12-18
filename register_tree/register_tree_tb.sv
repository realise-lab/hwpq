module register_tree_tb;
  // Parameters matching the module under test
  parameter QUEUE_SIZE = 8;
  parameter DATA_WIDTH = 32;
  parameter TREE_DEPTH = $clog2(QUEUE_SIZE+1);
  parameter NODES_NEEDED = 2**TREE_DEPTH - 1;
  parameter COMP_COUNT = NODES_NEEDED/2;

  // Clock and reset signals
  logic CLK;
  logic RSTn;
  
  // Input signals
  logic i_replace;
  logic [DATA_WIDTH-1:0] i_data;
  
  // Output signals
  logic [DATA_WIDTH-1:0] o_data;

  // Reference array for verification
  logic [DATA_WIDTH-1:0] ref_queue [$:NODES_NEEDED-1];
  
  // Instantiate the register_tree module
  register_tree #(
    .QUEUE_SIZE(QUEUE_SIZE),
    .DATA_WIDTH(DATA_WIDTH)
  ) uut (
    .CLK(CLK),
    .RSTn(RSTn),
    .i_replace(i_replace),
    .i_data(i_data),
    .o_data(o_data)
  );

  // Clock generation: 10ns period
  always #5 CLK <= ~CLK;

  // Test variables
  integer i;
  logic [DATA_WIDTH-1:0] random_value;

  initial begin
    // Initialize signals
    CLK = 0;
    RSTn = 0;
    i_replace = 0;
    i_data = 0;
    
    // Reset the module
    @(posedge CLK);
    RSTn = 1;
    repeat (3) @(posedge CLK);

    // Test Case 1: Verify initial state
    $display("\nTest Case 1: Initial State Test");
    for (i = NODES_NEEDED-1; i >= 0; i--) begin 
        if (i > QUEUE_SIZE) begin
          ref_queue.push_back(0);
        end else begin
          ref_queue.push_back((QUEUE_SIZE - i) * 10);
        end
      end
    ref_queue.rsort();
    assert (o_data == ref_queue[0])
    else $error("Initial top_item mismatch: expected %d, got %d", ref_queue[0], o_data);

    // Test Case 2: Replace top item with random values
    $display("\nTest Case 2: Replace Test");
    for(i = 0; i < QUEUE_SIZE; i++) begin
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
  task replace(input logic [DATA_WIDTH-1:0] value);
    begin
      i_replace = 1;
      i_data = value;
      ref_queue.pop_front();
      ref_queue.push_back(value);
      ref_queue.rsort();
      @(posedge CLK);
      i_replace = 0;
      repeat (3) @(posedge CLK);
    end
  endtask

endmodule

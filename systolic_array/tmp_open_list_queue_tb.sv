module tmp_open_list_queue_tb;
  // Parameters matching the module under test
  parameter QUEUE_SIZE = 4;
  parameter DATA_WIDTH = 32;

  // Clock and reset signals
  logic                  CLK;
  logic                  RSTn;

  // Input signals to the module
  logic                  i_wrt;  // Enqueue signal
  logic                  i_read;  // Dequeue signal
  logic [DATA_WIDTH-1:0] i_node_f;  // Node data input

  // Output signals from the module
  logic                  o_full;  // Queue is full
  logic                  o_empty;  // Queue is empty
  logic [DATA_WIDTH-1:0] o_node_f;  // Node data output

  // Reference array for sorted nodes
  logic [DATA_WIDTH-1:0] ref_queue  [$:2*QUEUE_SIZE-1];

  // Random number generator and random operations
  logic [DATA_WIDTH-1:0] random_node_f;
  logic [1:0]            random_operation;

  // Instantiate the tmp_open_list_queue module
  tmp_open_list_queue #(
      .QUEUE_SIZE(QUEUE_SIZE),
      .DATA_WIDTH(DATA_WIDTH)
  ) uut (
      .CLK(CLK),
      .RSTn(RSTn),
      .i_wrt(i_wrt),
      .i_read(i_read),
      .i_node_f(i_node_f),
      .o_full(o_full),
      .o_empty(o_empty),
      .o_node_f(o_node_f)
  );

  // Clock generation: 10ns period (100MHz)
  always #5 CLK <= ~CLK;

  // Test variables
  integer i;

  initial begin
    // Initialize signals
    CLK      = 0;
    RSTn     = 0;
    i_wrt    = 0;
    i_read   = 0;
    i_node_f = 0;

    // Reset the module
    @(posedge CLK);
    RSTn = 1;
    @(posedge CLK);

    // Test Case 1: Enqueue nodes
    // Enqueue nodes with random values
    $display("\nTest Case 1: Enqueue Test");
    while (!o_full) begin
      random_node_f = $urandom_range(0, 1024);
      enqueue_node(random_node_f);
      assert (o_node_f == ref_queue[0]) else $error("Node f value mismatch: expected %d, got %d", ref_queue[0], o_node_f);
    end

    // repeat (5) @(posedge CLK);

    // Test Case 2: Dequeue nodes
    // Dequeue all nodes
    $display("\nTest Case 2: Dequeue Test");
    while (!o_empty) begin
      dequeue_node();
      assert (o_node_f == ref_queue[0]) else $error("Node f value mismatch: expected %d, got %d", ref_queue[0], o_node_f);
    end
    
    // repeat (5) @(posedge CLK);

    // Test Case 3: Replace nodes
    // Enqueue some nodes and then replace them
    $display("\nTest Case 3: Replace Test");
    for (i = 0; i < 5; i++) begin
      random_node_f = $urandom_range(0, 1024);
      enqueue_node(random_node_f);
      assert (o_node_f == ref_queue[0]) else $error("Node f value mismatch: expected %d, got %d", ref_queue[0], o_node_f);
    end
    for (i = 0; i < 5; i++) begin
      random_node_f = $urandom_range(0, 1024);
      replace_node(random_node_f);
      assert (o_node_f == ref_queue[0]) else $error("Node f value mismatch: expected %d, got %d", ref_queue[0], o_node_f);
    end

    // dequeue all nodes until empty
    while (!o_empty) begin
      dequeue_node();
      assert (o_node_f == ref_queue[0]) else $error("Node f value mismatch: expected %d, got %d", ref_queue[0], o_node_f);
    end

    // stress test, mix operations
    $display("\nTest Case 4: Stress Test");
    for (i = 0; i < 100; i++) begin
      random_node_f = $urandom_range(0, 1024);
      random_operation = $urandom_range(0, 2);
      if (random_operation == 0) begin
        enqueue_node(random_node_f);
        assert (o_node_f == ref_queue[0]) else $error("Node f value mismatch: expected %d, got %d", ref_queue[0], o_node_f);
      end else if (random_operation == 1) begin
        dequeue_node();
        assert (o_node_f == ref_queue[0]) else $error("Node f value mismatch: expected %d, got %d", ref_queue[0], o_node_f);
      end else begin
        replace_node(random_node_f);
        assert (o_node_f == ref_queue[0]) else $error("Node f value mismatch: expected %d, got %d", ref_queue[0], o_node_f);
      end
    end

    // repeat (4) @(posedge CLK);
    $finish;
  end

  // ? This concurrent assertion is not working, so I am still using immediate assertions
  // Modified assertion for better Vivado compatibility
  // sequence queue_op_seq;
  //   (i_wrt || i_read) ##3 ($stable(o_node_f) && o_node_f == ref_queue[0]);
  // endsequence
  
  // queue_validation: assert property(@(posedge CLK) disable iff (!RSTn) queue_op_seq)
  //   else $error("Node f value mismatch at time %0t: expected %0d, got %0d", $time, ref_queue[0], o_node_f);

  // Task to perform an enqueue operation
  task enqueue_node(input logic [DATA_WIDTH-1:0] node_f);
    begin
      i_wrt = 1;
      i_node_f = node_f;
      ref_queue.push_back(node_f);
      ref_queue.sort();
      @(posedge CLK);
      i_wrt = 0;
      repeat (3) @(posedge CLK);
    end
  endtask

  // Task to perform a dequeue operation
  task dequeue_node();
    begin
      i_read = 1;
      ref_queue.pop_front();
      ref_queue.sort();
      @(posedge CLK);
      i_read = 0;
      repeat (3) @(posedge CLK);
    end
  endtask

  // Task to perform a replace operation
  task replace_node(input logic [DATA_WIDTH-1:0] node_f);
    begin
      i_wrt = 1;
      i_node_f = node_f;
      i_read = 1;
      ref_queue.pop_front();
      ref_queue.push_back(node_f);
      ref_queue.sort();
      @(posedge CLK);
      i_wrt = 0;
      i_read = 0;
      repeat (3) @(posedge CLK);
    end
  endtask

endmodule

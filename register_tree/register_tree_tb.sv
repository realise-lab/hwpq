module register_tree_tb;
  // Parameters matching the module under test
  parameter int QUEUE_SIZE = 16;
  parameter int DATA_WIDTH = 16;

  // parameter int TREE_DEPTH = $clog2(QUEUE_SIZE);
  // parameter int NODES_NEEDED = 2 ** (TREE_DEPTH + 1) - 1;
  // parameter int COMP_COUNT = NODES_NEEDED / 2;

  // Clock and reset signals
  logic                  CLK;
  logic                  RSTn;

  // Input signals
  logic                  i_wrt;
  logic                  i_read;
  logic [DATA_WIDTH-1:0] i_data;

  // Output signals
  logic                  o_full;
  logic                  o_empty;
  logic [DATA_WIDTH-1:0] o_data;

  // Reference array for verification
  logic [DATA_WIDTH-1:0] ref_queue        [$:QUEUE_SIZE-1];

  // Test variables
  int                    i;
  logic [DATA_WIDTH-1:0] random_value;
  int                    random_operation;
  int                    size;

  typedef enum logic [1:0] {
    ENQUEUE = 2'b00,
    DEQUEUE = 2'b01,
    REPLACE = 2'b10
  } operation_t;

  // Instantiate the register_tree module
  register_tree #(
      .QUEUE_SIZE(QUEUE_SIZE),
      .DATA_WIDTH(DATA_WIDTH)
  ) uut (
      .CLK(CLK),
      .RSTn(RSTn),
      .i_wrt(i_wrt),
      .i_read(i_read),
      .i_data(i_data),
      .o_full(o_full),
      .o_empty(o_empty),
      .o_data(o_data)
  );

  // Clock generation: 10ns period
  always #5 CLK <= ~CLK;

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
    size = 0;
    repeat (5) @(posedge CLK);

    // Initialize the queue, fill it up to QUEUE_SIZE with random values
    for (i = 0; i < QUEUE_SIZE; i++) begin
      random_value = $urandom_range(0, 1024);
      enqueue(random_value);
    end
    repeat (10) @(posedge CLK);  // wait for the queue to stabilize

    // Test Case 1: Dequeue nodes
    // Dequeue nodes for QUEUE_SIZE / 2 times
    $display("\nTest Case 1: Dequeue Test");
    for (i = 0; i < QUEUE_SIZE / 2; i++) begin
      dequeue();
      assert (o_data == ref_queue[0])
      else $error("Dequeue: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
    end

    // Test Case 2: Enqueue nodes
    // Enqueue random values for QUEUE_SIZE / 2 times
    $display("\nTest Case 2: Enqueue Test");
    for (i = 0; i < QUEUE_SIZE / 2; i++) begin
      random_value = $urandom_range(0, 1024);
      enqueue(random_value);
      assert (o_data == ref_queue[0])
      else $error("Enqueue: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
    end

    // Test Case 3: Replace nodes
    // Replace root node for QUEUE_SIZE / 2 times
    $display("\nTest Case 3: Replace Test");
    for (i = 0; i < QUEUE_SIZE / 2; i++) begin
      random_value = $urandom_range(0, 1024);
      replace(random_value);
      assert (o_data == ref_queue[0])
      else $error("Replace: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
    end

    // Test Case 4: Stress Test
    // stress test, mix operations
    $display("\nTest Case 4: Stress Test");
    for (i = 0; i < 100; i++) begin
      random_value = $urandom_range(0, 1024);
      random_operation = $urandom_range(0, 2);
      case (random_operation)
        ENQUEUE: begin
          enqueue(random_value);
          assert (o_data == ref_queue[0])
          else
            $error("Enqueue: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
        end

        DEQUEUE: begin
          dequeue();
          assert (o_data == ref_queue[0])
          else
            $error("Dequeue: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
        end

        REPLACE: begin
          replace(random_value);
          assert (o_data == ref_queue[0])
          else
            $error("Replace: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
        end

        default: begin
          $display("Invalid operation: %d", random_operation);
        end
      endcase
    end

    $display("\nTest completed!");
    $finish;
  end

  // Task to write to of the queue
  task automatic enqueue(input logic [DATA_WIDTH-1:0] value);
    begin
      if (!o_full) begin
        i_wrt  = 1;
        i_read = 0;
        i_data = value;
        ref_queue.push_back(value);
        ref_queue.rsort();
      end else begin
        $display("Enqueue: Queue full, skipping enqueue");
      end
      @(posedge CLK);
      i_wrt  = 0;
      i_read = 0;
      repeat ($clog2(QUEUE_SIZE) + 3) @(posedge CLK);
    end
  endtask

  // Task to read root node
  task automatic dequeue();
    begin
      if (!o_empty) begin
        i_wrt  = 0;
        i_read = 1;
        ref_queue.pop_front();
        ref_queue.rsort();
      end else begin
        $display("Dequeue: Queue empty, skipping dequeue");
      end
      @(posedge CLK);
      i_wrt  = 0;
      i_read = 0;
      repeat (3) @(posedge CLK);
    end
  endtask

  // Task to replace root node
  task automatic replace(input logic [DATA_WIDTH-1:0] value);
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

`default_nettype none

module SystolicArray_tb;
  // Parameters matching the module under test
  parameter int QUEUE_SIZE = 8;
  parameter int DATA_WIDTH = 16;

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
  logic [DATA_WIDTH-1:0] random_value;

  typedef enum int {
    ENQUEUE = 1,
    DEQUEUE = 2,
    REPLACE = 3
  } t_operation;
  t_operation random_operation;

  // Instantiate the register_tree module
  SystolicArray #(
      .QUEUE_SIZE(QUEUE_SIZE),
      .DATA_WIDTH(DATA_WIDTH)
  ) u_SystolicArray (
      .i_CLK(CLK),
      .i_RSTn(RSTn),
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
    @(posedge CLK);

    // Initialize the queue, fill it up to QUEUE_SIZE with random values
    for (int i = 0; i < QUEUE_SIZE; i++) begin
      random_value = $urandom_range(0, 1024);
      enqueue(random_value);
      repeat (5) @(posedge CLK);  // to make sure that the queue is correctly initialized
    end
    repeat (5) @(posedge CLK);  // wait for the queue to stabilize

    // Test Case 1: Dequeue nodes
    // Dequeue nodes for QUEUE_SIZE times
    $display("\nTest Case 1: Dequeue Test");
    for (int i = 0; i < QUEUE_SIZE; i++) begin
      dequeue();
      if (!o_empty) begin
        assert (o_data == ref_queue[0])
        else $error("Dequeue: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
      end else begin
        assert (o_data == '0)
        else $error("Dequeue: Node f value mismatch -> expected %d, got %d", '0, o_data);
      end
    end

    // Test Case 2: Enqueue nodes
    // Enqueue random values for QUEUE_SIZE times
    $display("\nTest Case 2: Enqueue Test");
    for (int i = 0; i < QUEUE_SIZE; i++) begin
      random_value = $urandom_range(0, 1024);
      enqueue(random_value);
      assert (o_data == ref_queue[0])
      else $error("Enqueue: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
    end

    // Test Case 3: Replace nodes
    // Replace root node for QUEUE_SIZE times
    $display("\nTest Case 3: Replace Test");
    for (int i = 0; i < QUEUE_SIZE; i++) begin
      random_value = $urandom_range(0, 1024);
      replace(random_value);
      assert (o_data == ref_queue[0])
      else $error("Replace: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
    end

    // Test Case 4: Stress Test
    // stress test, mix operations
    $display("\nTest Case 4: Stress Test");
    for (int i = 0; i < 100; i++) begin
      random_value = $urandom_range(0, 1024);
      random_operation = $urandom_range(1,3);
      case (random_operation)
        ENQUEUE: begin
          enqueue(random_value);
          assert (o_data == ref_queue[0])
          else
            $error("Enqueue: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
        end

        DEQUEUE: begin
          dequeue();
          if (!o_empty) begin
            assert (o_data == ref_queue[0])
            else
              $error("Dequeue: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
          end else begin
            assert (o_data == '0)
            else $error("Dequeue: Node f value mismatch -> expected %d, got %d", '0, o_data);
          end
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

    $display("\nTest completed! ");
    $finish;
  end

  // Task to write to the end of the queue
  task automatic enqueue(input logic [DATA_WIDTH-1:0] value);
    begin
      if (!o_full) begin
        i_wrt  = 1;
        i_read = 0;
        i_data = value;
        ref_queue.push_back(value);
        ref_queue.sort() with (item > item);
      end else begin
        $display("Enqueue: Queue full, skipping enqueue");
      end
      @(posedge CLK);
      i_wrt  = 0;
      i_read = 0;
      repeat (2) @(posedge CLK);
    end
  endtask

  // Task to read root node
  task automatic dequeue();
    begin
      if (!o_empty) begin
        i_wrt  = 0;
        i_read = 1;
        ref_queue.pop_front();
        ref_queue.sort() with (item > item);
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
      ref_queue.sort() with (item > item);
      @(posedge CLK);
      i_wrt  = 0;
      i_read = 0;
      repeat (2) @(posedge CLK);
    end
  endtask

endmodule

`default_nettype none

module RegisterTree_tb;
  // Parameters matching the module under test
  localparam int QUEUE_SIZE = 15;
  localparam int DATA_WIDTH = 16;

  // Clock and reset signals
  logic                  i_CLK;
  logic                  i_RSTn;

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
  int                    random_operation;

  typedef enum integer {
    ENQUEUE = 0,
    DEQUEUE = 1,
    REPLACE = 2
  } operation_t;

  // Instantiate the register_tree module
  RegisterTree #(
      .QUEUE_SIZE(QUEUE_SIZE),
      .DATA_WIDTH(DATA_WIDTH)
  ) u_RegisterTree (
      .i_CLK  (i_CLK),
      .i_RSTn (i_RSTn),
      .i_wrt  (i_wrt),
      .i_read (i_read),
      .i_data (i_data),
      .o_full (o_full),
      .o_empty(o_empty),
      .o_data (o_data)
  );

  // Clock generation: 10ns period
  always #5 i_CLK <= ~i_CLK;

  initial begin
    // Initialize signals
    i_CLK  = 0;
    i_RSTn = 0;
    i_wrt  = 0;
    i_read = 0;
    i_data = 0;

    // Reset the module
    @(posedge i_CLK);
    i_RSTn = 1;
    @(posedge i_CLK);

    // Initialize the queue, fill it up to QUEUE_SIZE with random values
    for (int i = 0; i < QUEUE_SIZE; i++) begin
      random_value = DATA_WIDTH'(($urandom & ((1 << DATA_WIDTH) - 1)) % 1025);
      enqueue(random_value);
      repeat (5) @(posedge i_CLK);
    end
    repeat (5) @(posedge i_CLK);  // to make sure that the queue is correctly initialized

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

    // Test Case 2: enqueue nodes
    // Enqueue random values for QUEUE_SIZE times
    $display("\nTest Case 2: Enqueue Test");
    for (int i = 0; i < QUEUE_SIZE; i++) begin
      random_value = DATA_WIDTH'(($urandom & ((1 << DATA_WIDTH) - 1)) % 1025);
      enqueue(random_value);
      assert (o_data == ref_queue[0])
      else $error("Enqueue: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
    end

    // Test Case 3: Replace nodes
    // Replace root node for QUEUE_SIZE times
    $display("\nTest Case 3: Replace Test");
    for (int i = 0; i < QUEUE_SIZE; i++) begin
      random_value = DATA_WIDTH'(($urandom & ((1 << DATA_WIDTH) - 1)) % 1025);
      replace(random_value);
      assert (o_data == ref_queue[0])
      else $error("Replace: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
    end

    // Test Case 4: Stress Test
    // stress test, mix operations
    $display("\nTest Case 4: Stress Test");
    for (int i = 0; i < 100; i++) begin
      random_value = DATA_WIDTH'(($urandom & ((1 << DATA_WIDTH) - 1)) % 1025);
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
        ref_queue.rsort();
      end else begin
        $display("Enqueue: Queue full, skipping enqueue");
      end
      @(posedge i_CLK);
      i_wrt  = 0;
      i_read = 0;
      repeat ($clog2(QUEUE_SIZE)) @(posedge i_CLK);
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
      @(posedge i_CLK);
      i_wrt  = 0;
      i_read = 0;
      repeat (2) @(posedge i_CLK);
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
      @(posedge i_CLK);
      i_wrt  = 0;
      i_read = 0;
      repeat (2) @(posedge i_CLK);
    end
  endtask

endmodule

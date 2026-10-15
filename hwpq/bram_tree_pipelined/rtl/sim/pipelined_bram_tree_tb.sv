module bram_tree_pipelined_tb;
  // Parameters matching the module under test
  localparam integer QueueSize = 15;
  localparam integer DataWidth = 16;

  // Clock and reset signals
  logic                   i_CLK;
  logic                   i_RSTn;

  // Input signals
  logic                   i_wrt;
  logic                   i_read;
  logic   [DataWidth-1:0] i_data;

  // Output signals
  logic                   o_write_ready;
  logic                   o_read_ready;
  logic   [DataWidth-1:0] o_data;

  // Reference array for verification
  logic   [DataWidth-1:0] ref_queue        [$:QueueSize-1];
  int                     ref_queue_size = 0;

  // Test variables
  integer                 i;
  logic   [DataWidth-1:0] random_value;
  integer                 random_operation;

  typedef enum integer {
    ENQUEUE = 0,
    DEQUEUE = 1,
    REPLACE = 2
  } operation_t;

  // Instantiate the register_tree module
  bram_tree_pipelined #(
      .QUEUE_SIZE(QueueSize),
      .DATA_WIDTH(DataWidth)
  ) uut (
      .i_CLK(i_CLK),
      .i_RSTn(i_RSTn),
      .i_wrt(i_wrt),
      .i_read(i_read),
      .i_data(i_data),
      .o_write_ready(o_write_ready),
      .o_read_ready(o_read_ready),
      .o_data(o_data)
  );

  // Clock generation: 10ns period
  always #5 i_CLK <= ~i_CLK;

  int error_count = 0;

  initial begin
    // Initialize signals
    i_CLK = 0;
    i_RSTn = 0;
    i_wrt = 0;
    i_read = 0;
    i_data = 0;

    // Reset the module
    @(posedge i_CLK);
    i_RSTn = 1;
    repeat (2) @(posedge i_CLK);

    // Initialize the reference queue, sort the reference queue, and write to the queue
    for (i = 0; i < QueueSize; i++) begin
      random_value = DataWidth'(($urandom & ((1 << DataWidth) - 1)) % 1025);
      ref_queue.push_back(random_value);
      ref_queue_size++;
      replace_init(random_value);
    end
    rsort();

    repeat (16) @(posedge i_CLK);

    // Test Case 1: Dequeue nodes
    // Dequeue nodes for QUEUE_SIZE times
    $display("\nTest Case 1: Dequeue Test");
    for (i = 0; i < QueueSize/2; i++) begin
      dequeue();
      if (o_read_ready) begin
        assert (o_data == ref_queue[0])
        else begin error_count++; $error("Dequeue: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data); end;
      end else begin
        assert (o_data == '0)
        else begin error_count++; $error("Dequeue: Node f value mismatch -> expected %d, got %d", '0, o_data); end;
      end
    end

    /*// Reset the module
    @(posedge i_CLK);
    i_RSTn = 1;
    repeat (2) @(posedge i_CLK);

    for (i = 0; i < QueueSize; i++) begin
      random_value = DataWidth'(($urandom & ((1 << DataWidth) - 1)) % 1025);
      ref_queue.push_back(random_value);
      replace_init(random_value);
    end
    ref_queue.rsort();*/
    
    repeat (16) @(posedge i_CLK);

    // Test Case 2: Replace nodes
    // Replace root node for QUEUE_SIZE times
    $display("\nTest Case 2: Replace Test");
    for (i = 0; i < QueueSize/2; i++) begin
      random_value = DataWidth'(($urandom & ((1 << DataWidth) - 1)) % 1025);
      replace(random_value);
      assert (o_data == ref_queue[0])
      else begin error_count++; $error("Replace: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data); end;
    end

    // Test Case 3: Stress Test
    // stress test, mix operations
    $display("\nTest Case 3: Stress Test");
    for (i = 0; i < 100; i++) begin
      random_value = DataWidth'(($urandom & ((1 << DataWidth) - 1)) % 1025);
      random_operation = $urandom_range(1, 2);
      case (random_operation)
        DEQUEUE: begin
          dequeue();
          if (o_read_ready) begin
            assert (o_data == ref_queue[0])
            else
              begin error_count++; $error("Dequeue: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data); end;
          end else begin
            assert (o_data == '0)
            else begin error_count++; $error("Dequeue: Node f value mismatch -> expected %d, got %d", '0, o_data); end;
          end
        end

        REPLACE: begin
          replace(random_value);
          assert (o_data == ref_queue[0])
          else
            begin error_count++; $error("Replace: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data); end;
        end

        default: begin
          $display("Invalid operation: %d", random_operation);
        end
      endcase
    end

    if (error_count == 0) begin
      $display("\nTest completed!");
      $finish;
    end else begin
      $display("\n%0d error(s) detected during simulation.", error_count);
      $fatal(1, "Test FAILED with %0d error(s).", error_count);
    end
  end

  // Task to read root node
  task automatic dequeue();
    begin
      if (o_read_ready) begin
        i_wrt  = 0;
        i_read = 1;
        for (int i = 0; i < ref_queue_size - 1; i++) begin
          ref_queue[i] = ref_queue[i+1];
        end
        ref_queue[ref_queue_size-1] = '0; 
        ref_queue_size--;
      end else begin
        $display("Dequeue: Queue empty, skipping dequeue");
      end
      @(posedge i_CLK);
      i_wrt  = 0;
      i_read = 0;
      repeat (24) @(posedge i_CLK);
    end
  endtask

  // Task to replace root node
  task automatic replace(input logic [DataWidth-1:0] value);
    begin
      i_wrt  = 1;
      i_read = 1;
      i_data = value;
      if (!o_read_ready) begin
        ref_queue[ref_queue_size] = value;
        ref_queue_size++;
        rsort();
      end else begin
        ref_queue[0] = value;
        rsort();
      end
      @(posedge i_CLK);
      i_wrt  = 0;
      i_read = 0;
      repeat (24) @(posedge i_CLK);
    end
  endtask

  task automatic replace_init(input logic [DataWidth-1:0] value);
    begin
      i_wrt  = 1;
      i_read = 1;
      i_data = value;
      repeat (1) @(posedge i_CLK);
      i_wrt  = 0;
      i_read = 0;
      repeat (24) @(posedge i_CLK);
    end
  endtask

  task automatic rsort();
    logic [DataWidth-1:0] temp_val;
    for (int i = 0; i < ref_queue_size; i++) begin
      for (int j = i + 1; j < ref_queue_size; j++) begin
        if (ref_queue[i] < ref_queue[j]) begin
          temp_val           = ref_queue[i];
          ref_queue[i] = ref_queue[j];
          ref_queue[j] = temp_val;
        end
      end
    end
  endtask

endmodule
import bram_tree_pkg::*;

module bram_tree_tb;
  // Clock and reset signals
  logic                   i_CLK;
  logic                   i_RSTn;

  // Input signals
  logic                   i_wrt;
  logic                   i_read;
  logic   [DATA_WIDTH-1:0] i_data;

  // Output signals
  logic                   o_write_ready;
  logic                   o_read_ready;
  logic   [DATA_WIDTH-1:0] o_data;

  // Reference array for verification
  logic [DATA_WIDTH-1:0] ref_queue        [$:QUEUE_SIZE-1];
  int                    ref_size = 0;

  // Test variables
  integer                 i;
  logic   [DATA_WIDTH-1:0] random_value;

  typedef enum integer {
    ENQUEUE = 0,
    DEQUEUE = 1,
    REPLACE = 2
  } operation_t;
	operation_t random_operation;

  // Instantiate the register_tree module
  bram_tree uut (
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
    for (i = 0; i < QUEUE_SIZE*5; i++) begin
      random_value = $urandom_range(0, 1024);
      enqueue(random_value);
    end

    // Test Case 1: Dequeue nodes
    // Dequeue nodes for QUEUE_SIZE times
    $display("\nTest Case 1: Dequeue Test");
    for (i = 0; i < QUEUE_SIZE*5; i++) begin
      dequeue();
    end
    
    // Test Case 2: Enqueue nodes
    // Enqueue random values for QUEUE_SIZE times
    $display("\nTest Case 2: Enqueue Test");
    for (i = 0; i < QUEUE_SIZE*3; i++) begin
      random_value = $urandom_range(0, 1024);
      enqueue(random_value);
    end
    
    // Test Case 3: Replace nodes
    // Replace root node for QUEUE_SIZE times
    $display("\nTest Case 3: Replace Test");
    for (i = 0; i < QUEUE_SIZE*3; i++) begin
      random_value = $urandom_range(0, 1024);
      replace(random_value);
    end

    
    // Test Case 3: Stress Test
    // stress test, mix operations
    $display("\nTest Case 4: Stress Test");
    for (i = 0; i < 1000; i++) begin
      random_value = $urandom_range(0, 1024);
      random_operation = operation_t'($urandom_range(0,2));
      case (random_operation)
				ENQUEUE: begin
          enqueue(random_value);
        end

        DEQUEUE: begin
          dequeue();
        end

        REPLACE: begin
          replace(random_value);
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

  // Task to write to the end of the queue
  task automatic enqueue(input logic [DATA_WIDTH-1:0] value);
    logic [DATA_WIDTH-1:0] tmp;
    begin
      if (o_write_ready) begin
        i_wrt  = 1;
        i_read = 0;
        i_data = value;
        
        ref_queue[ref_size] = value;
        ref_size++;
        
        for (int i = 0; i < ref_size; i++) begin
          for (int j = i + 1; j < ref_size; j++) begin
            if (ref_queue[i] < ref_queue[j]) begin
              tmp = ref_queue[i];
              ref_queue[i] = ref_queue[j];
              ref_queue[j] = tmp;
            end
          end
        end
      end else begin
        i_wrt  = 0;
        i_read = 0;
      end
      @(posedge i_CLK);
    end
  endtask

  // Task to read root node
  task automatic dequeue();
    begin
      if (o_read_ready) begin
        assert (o_data == ref_queue[0])
        else
          begin error_count++; $error("Replace: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data); end;
        i_wrt  = 0;
        i_read = 1;
        for (int i = 0; i < ref_size - 1; i++) begin
          ref_queue[i] = ref_queue[i+1];
        end
        ref_queue[ref_size-1] = '0; 
        ref_size--;
        
      end else begin
        i_wrt  = 0;
        i_read = 0;
      end
      @(posedge i_CLK);
    end
  endtask

  // Task to replace root node
  task automatic replace(input logic [DATA_WIDTH-1:0] value);
    logic [DATA_WIDTH-1:0] tmp;
    begin
      if (o_read_ready) begin
        assert (o_data == ref_queue[0])
        else
          begin error_count++; $error("Replace: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data); end;
        i_wrt  = 1;
        i_read = 1;
        i_data = value;
        ref_queue[0] = value;
        for (int i = 0; i < ref_size; i++) begin
          for (int j = i + 1; j < ref_size; j++) begin
            if (ref_queue[i] < ref_queue[j]) begin
              tmp = ref_queue[i];
              ref_queue[i] = ref_queue[j];
              ref_queue[j] = tmp;
            end
          end
        end
      end else begin
        i_wrt  = 0;
        i_read = 0;
      end
      @(posedge i_CLK);
    end
  endtask

endmodule

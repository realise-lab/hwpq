`default_nettype none

module register_array_tb;
  // Parameters matching the module under test
  localparam int QUEUE_SIZE = 128;
  localparam int DATA_WIDTH = 16;

  // Clock and reset signals
  logic                 i_CLK;
  logic                 i_RSTn;

  // Input signals - for ENQ_ENA enabled
  logic                  i_wrt_ena;
  logic                  i_read_ena;
  logic [DATA_WIDTH-1:0] i_data_ena;

  // Input signals - for ENQ_ENA disabled
  logic                  i_wrt_dis;
  logic                  i_read_dis;
  logic [DATA_WIDTH-1:0] i_data_dis;

  // Output signals - for ENQ_ENA enabled
  logic                  o_write_ready_ena;
  logic                  o_read_ready_ena;
  logic [DATA_WIDTH-1:0] o_data_ena;
  
  // Output signals - for ENQ_ENA disabled
  logic                  o_write_ready_dis;
  logic                  o_read_ready_dis;
  logic [DATA_WIDTH-1:0] o_data_dis;
  
  // Current active outputs for testing
  logic                  o_write_ready;
  logic                  o_read_ready;
  logic [DATA_WIDTH-1:0] o_data;
  logic [DATA_WIDTH-1:0] o_data_prev;
  
  // Enum to track which instance we're currently testing
  typedef enum bit {ENABLED, DISABLED} enq_mode_t;
  enq_mode_t current_mode;

  // Reference array for verification
  logic [DATA_WIDTH-1:0] ref_queue_enq_1 [$:QUEUE_SIZE-1];
  int                    ref_queue_enq_1_size = 0;

  logic [DATA_WIDTH-1:0] ref_queue_enq_0 [$:QUEUE_SIZE-1];
  int                    ref_queue_enq_0_size = 0;

  logic [DATA_WIDTH-1:0] ref_queue_prev  [$:QUEUE_SIZE-1];
  int                    ref_queue_prev_size = 0;

  // Test variables
  logic [DATA_WIDTH-1:0] random_value;
  int                    random_operation;

  typedef enum int {
    ENQUEUE = 1,
    DEQUEUE = 2,
    REPLACE = 3
  } operation_t;

  // Instantiate RegisterArray with ENQ_ENA enabled
  register_array #(
      .ENQ_ENA(1'b1),
      .QUEUE_SIZE(QUEUE_SIZE),
      .DATA_WIDTH(DATA_WIDTH)
  ) u_RegisterArray_ena (
      .i_CLK(i_CLK),
      .i_RSTn(i_RSTn),
      .i_wrt(i_wrt_ena),
      .i_read(i_read_ena),
      .i_data(i_data_ena),
      .o_write_ready(o_write_ready_ena),
      .o_read_ready(o_read_ready_ena),
      .o_data(o_data_ena)
  );
  
  // Instantiate RegisterArray with ENQ_ENA disabled
  register_array #(
      .ENQ_ENA(1'b0),
      .QUEUE_SIZE(QUEUE_SIZE),
      .DATA_WIDTH(DATA_WIDTH)
  ) u_RegisterArray_dis (
      .i_CLK(i_CLK),
      .i_RSTn(i_RSTn),
      .i_wrt(i_wrt_dis),
      .i_read(i_read_dis),
      .i_data(i_data_dis),
      .o_write_ready(o_write_ready_dis),
      .o_read_ready(o_read_ready_dis),
      .o_data(o_data_dis)
  );

  always_comb begin : output_signal_switch
    case (current_mode)
      ENABLED : begin
        o_write_ready = o_write_ready_ena;
        o_read_ready = o_read_ready_ena;
        o_data = o_data_ena;
      end
      DISABLED : begin
        o_write_ready = o_write_ready_dis;
        o_read_ready = o_read_ready_dis;
        o_data = o_data_dis;
      end
      default : begin
        o_write_ready = o_write_ready_dis;
        o_read_ready = o_read_ready_dis;
        o_data = o_data_dis;
      end
    endcase
  end

  // Clock generation: 10ns period
  always #5 i_CLK <= ~i_CLK;

  int error_count = 0;

  initial begin
    // Initialize signals
    i_CLK = 0;
    i_wrt_ena = 0;
    i_read_ena = 0;
    i_data_ena = 0;
    i_wrt_dis = 0;
    i_read_dis = 0;
    i_data_dis = 0;
    current_mode = ENABLED;
    ref_queue_enq_1 = {};
    ref_queue_enq_0 = {};
    ref_queue_prev = {};

    // Reset the modules
    i_RSTn = 0;
    @(posedge i_CLK);
    i_RSTn = 1;
    @(posedge i_CLK);

    // Test with ENQ_ENA enabled
    $display("\n=== Testing with ENQ_ENA enabled ===");
    
    // Initialize the queue, empty all, then fill it up to QUEUE_SIZE with random values

    $display("\nInitializing enqueue enabled module by enqueue into it");
    for (int i = 0; i < QUEUE_SIZE; i++) begin
      random_value = $urandom_range(1, 1023);
      enqueue(random_value);
    end
    assert (!o_write_ready) else begin error_count++; $error("The queue should be filled by the intialization!"); end;

    // Test Case 1: Dequeue nodes with ENQ_ENA enabled
    $display("\nTest Case 1: Dequeue Test (ENQ_ENA enabled)");
    for (int i = 0; i < QUEUE_SIZE / 2; i++) begin
      dequeue();
      if (o_read_ready) begin
        assert (o_data == ref_queue_enq_1[0]) else begin error_count++; $error("Dequeue: Node value mismatch -> expected %d, got %d", ref_queue_enq_1[0], o_data); end;
      end else begin
        assert (o_data == '0) else begin error_count++; $error("Dequeue: Node value mismatch -> expected %d, got %d", '0, o_data); end;
      end
    end

    // Test Case 2: Enqueue nodes with ENQ_ENA enabled
    $display("\nTest Case 2: Enqueue Test (ENQ_ENA enabled)");
    for (int i = 0; i < QUEUE_SIZE / 2; i++) begin
      random_value = $urandom_range(1, 1023);
      enqueue(random_value);
      assert (o_data == ref_queue_enq_1[0]) else begin error_count++; $error("Enqueue: Node value mismatch -> expected %d, got %d", ref_queue_enq_1[0], o_data); end;
    end
    assert (!o_write_ready) else begin error_count++; $error("The queue should be filled after enqueue!"); end;

    // Test Case 3: Replace nodes with ENQ_ENA enabled
    $display("\nTest Case 3: Replace Test (ENQ_ENA enabled)");
    for (int i = 0; i < QUEUE_SIZE / 2; i++) begin
      random_value = $urandom_range(1, 1023);
      replace(random_value);
      assert (o_data == ref_queue_enq_1[0]) else begin error_count++; $error("Replace: Node value mismatch -> expected %d, got %d", ref_queue_enq_1[0], o_data); end;
    end
    
    // Test case 4: Random opertaion for 50 times
    $display("\nTest Case 4: Stress Test (ENQ_ENA enabled)");
    for (int i = 0; i < 100; i++) begin
      random_operation = $urandom_range(1, 3);
      case (random_operation)
        ENQUEUE: begin
          random_value = $urandom_range(1, 1023);
          enqueue(random_value);
          assert (o_data == ref_queue_enq_1[0]) else begin error_count++; $error("Random Enqueue: Node value mismatch -> expected %d, got %d", ref_queue_enq_1[0], o_data); end;
        end
        DEQUEUE: begin
          dequeue();
          if (o_read_ready) begin
            assert (o_data == ref_queue_enq_1[0]) else begin error_count++; $error("Random Dequeue: Node value mismatch -> expected %d, got %d", ref_queue_enq_1[0], o_data); end;
          end else begin
            assert (o_data == '0) else begin error_count++; $error("Random Dequeue: Node value mismatch -> expected %d, got %d", '0, o_data); end;
          end
        end
        REPLACE: begin
          random_value = $urandom_range(1, 1023);
          replace(random_value);
          assert (o_data == ref_queue_enq_1[0]) else begin error_count++; $error("Random Replace: Node value mismatch -> expected %d, got %d", ref_queue_enq_1[0], o_data); end;
        end
      endcase
    end

    // Now test with ENQ_ENA disabled
    $display("\n=== Testing with ENQ_ENA disabled ===");
    current_mode = DISABLED;

    // Reset the modules
    i_RSTn = 0;
    @(posedge i_CLK);
    i_RSTn = 1;
    @(posedge i_CLK);
    
    // Initialize queue inside enqueue disabled module
    $display("\nInitializing enqueue disabled module by replacing into it");
    for (int i = 0; i < QUEUE_SIZE; i++) begin
      random_value = $urandom_range(1, 1023);
      ref_queue_enq_0.push_back(random_value);
      ref_queue_enq_0_size++;
      replace_init(random_value);
    end
    rsort_dis();



    repeat (2) @(posedge i_CLK);


    // Test Case 5: Dequeue Test with ENQ_ENA disabled
    $display("\nTest Case 5: Dequeue Test (ENQ_ENA disabled)");
    assert (!o_write_ready) else begin error_count++; $error("The queue should be filled by the intialization!"); end;
    for (int i = 0; i < QUEUE_SIZE / 2; i++) begin
      dequeue();
      if (o_read_ready) begin
        assert (o_data == ref_queue_enq_0[0]) else begin error_count++; $error("Dequeue: Node value mismatch -> expected %d, got %d", ref_queue_enq_0[0], o_data); end;
      end else begin
        assert (o_data == 'd0) else begin error_count++; $error("Dequeue: Node value mismatch -> expected %d, got %d", 'd0, o_data); end;
      end
    end
    
    // Test Case 6: Try to Enqueue nodes with ENQ_ENA disabled
    $display("\nTest Case 6: Enqueue Test (ENQ_ENA disabled)");
    o_data_prev = o_data;
    ref_queue_prev = ref_queue_enq_0;
    for (int i = 0; i < QUEUE_SIZE / 2; i++) begin
      random_value = $urandom_range(1, 1023);
      enqueue(random_value);
      assert (o_data == ref_queue_enq_0[0]) else begin error_count++; $error("Enqueue: Node value mismatch -> expected %d, got %d", ref_queue_enq_0[0], o_data); end;
    end
    assert (o_data == o_data_prev) else begin error_count++; $error("The queue should not have change!"); end;
    begin
      bit queues_match;
      bit error_flag;
      queues_match = 1;
      error_flag = 0;
      if (ref_queue_enq_0_size != ref_queue_prev_size) begin
        queues_match = 0;
      end else begin
        for (int i = 0; i < ref_queue_enq_0_size; i++) begin
          if (ref_queue_enq_0[i] != ref_queue_prev[i]) begin
            queues_match = 0;
            error_flag = 1;
          end
        end
      end
      assert (!error_flag) else begin error_count++; $error("The queue should not have change!"); end;
    end
    assert (o_write_ready && o_read_ready) else begin error_count++; $error("The queue should not do anything!"); end;

    // Test Case 7: Test Replace operation with ENQ_ENA disabled
    $display("\nTest Case 7: Replace Test (ENQ_ENA disabled)");
    for (int i = 0; i < QUEUE_SIZE / 2; i++) begin
      random_value = $urandom_range(1, 1023);
      replace(random_value);
      assert (o_data == ref_queue_enq_0[0]) else begin error_count++; $error("Replace: Node value mismatch -> expected %d, got %d", ref_queue_enq_0[0], o_data); end;
    end
    
    // Test case 8: Random opertaion for 50 times
    $display("\nTest Case 8: Stress Test (ENQ_ENA disabled)");
    for (int i = 0; i < 100; i++) begin
      random_operation = $urandom_range(2, 3);
      case (random_operation)
        DEQUEUE: begin
          dequeue();
          if (o_read_ready) begin
            assert (o_data == ref_queue_enq_0[0]) else begin error_count++; $error("Random Dequeue: Node value mismatch -> expected %d, got %d", ref_queue_enq_0[0], o_data); end;
          end else begin
            assert (o_data == '0) else begin error_count++; $error("Random Dequeue: Node value mismatch -> expected %d, got %d", '0, o_data); end;
          end
        end
        REPLACE: begin
          random_value = $urandom_range(1, 1023);
          replace(random_value);
          assert (o_data == ref_queue_enq_0[0]) else begin error_count++; $error("Random Replace: Node value mismatch -> expected %d, got %d", ref_queue_enq_0[0], o_data); end;
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

  task automatic enqueue(input logic [DATA_WIDTH-1:0] value);
    begin
      if (o_write_ready) begin
        case (current_mode)
          ENABLED: begin
            i_wrt_ena = 1;
            i_read_ena = 0;
            i_data_ena = value;

            ref_queue_enq_1[ref_queue_enq_1_size] = value;
            ref_queue_enq_1_size++;

            rsort_ena();
          end
          DISABLED: begin
            i_wrt_dis = 1;
            i_read_dis = 0;
            i_data_dis = value;
//            $display("Enqueue attempt with ENQ_ENA disabled - should have no effect");
          end
          default: begin
            $display("Enqueue: Invalid mode, skipping enqueue");
          end
        endcase
      end else begin
        $display("Enqueue: Queue full, skipping enqueue");
      end
      @(posedge i_CLK);
      i_wrt_ena  = 0;
      i_read_ena = 0;
      i_wrt_dis  = 0;
      i_read_dis = 0;
      repeat (2) @(posedge i_CLK);
    end
  endtask

  task automatic dequeue();
    begin
      if (o_read_ready) begin
        case (current_mode)
          ENABLED: begin
            i_wrt_ena  = 0;
            i_read_ena = 1;
            i_data_ena = 0;

            for (int i = 0; i < ref_queue_enq_1_size - 1; i++) begin
              ref_queue_enq_1[i] = ref_queue_enq_1[i+1];
            end
            ref_queue_enq_1[ref_queue_enq_1_size-1] = '0;
            ref_queue_enq_1_size--;
          end
          DISABLED: begin
            i_wrt_dis  = 0;
            i_read_dis = 1;
            i_data_dis = 0;

            for (int i = 0; i < ref_queue_enq_0_size - 1; i++) begin
              ref_queue_enq_0[i] = ref_queue_enq_0[i+1];
            end
            ref_queue_enq_0[ref_queue_enq_0_size-1] = '0;
            ref_queue_enq_0_size--;
          end
          default: begin
            $display("Dequeue: Invalid mode, skipping dequeue");
          end
        endcase
      end else begin
        $display("Dequeue: Queue empty, skipping dequeue");
      end
      @(posedge i_CLK);
      i_wrt_ena  = 0;
      i_read_ena = 0;
      i_wrt_dis  = 0;
      i_read_dis = 0;

      repeat (2) @(posedge i_CLK);
    end
  endtask

  task automatic replace(input logic [DATA_WIDTH-1:0] value);
    begin
      case (current_mode)
        ENABLED: begin
          i_wrt_ena  = 1;
          i_read_ena = 1;
          i_data_ena = value;
          if (!o_read_ready) begin
            ref_queue_enq_1[ref_queue_enq_1_size] = value;
            ref_queue_enq_1_size++;
            rsort_ena();
          end else begin
            ref_queue_enq_1[0] = value;
            rsort_ena();
          end
        end
        DISABLED: begin
          i_wrt_dis  = 1;
          i_read_dis = 1;
          i_data_dis = value;
          if (!o_read_ready) begin
            ref_queue_enq_0[ref_queue_enq_0_size] = value;
            ref_queue_enq_0_size++;
            rsort_dis();
          end else begin
            ref_queue_enq_0[0] = value;
            rsort_dis();
          end
        end
        default: begin
          $display("Replace: Invalid mode, skipping replace");
        end
      endcase
      @(posedge i_CLK);
      i_wrt_ena  = 0;
      i_read_ena = 0;
      i_wrt_dis  = 0;
      i_read_dis = 0;

      repeat (2) @(posedge i_CLK);
    end
  endtask

  task automatic replace_init(input logic [DATA_WIDTH-1:0] value);
    begin
      case (current_mode)
        ENABLED: begin
          i_wrt_ena  = 1;
          i_read_ena = 1;
          i_data_ena = value;
        end
        DISABLED: begin
          i_wrt_dis  = 1;
          i_read_dis = 1;
          i_data_dis = value;
        end
        default: begin
          $display("Replace: Invalid mode, skipping replace");
        end
      endcase
      @(posedge i_CLK);
      i_wrt_ena  = 0;
      i_read_ena = 0;
      i_wrt_dis  = 0;
      i_read_dis = 0;

      repeat (2) @(posedge i_CLK);
    end
  endtask

  task automatic rsort_ena();
    logic [DATA_WIDTH-1:0] temp_val;
    for (int i = 0; i < ref_queue_enq_1_size; i++) begin
      for (int j = i + 1; j < ref_queue_enq_1_size; j++) begin
        if (ref_queue_enq_1[i] < ref_queue_enq_1[j]) begin
          temp_val           = ref_queue_enq_1[i];
          ref_queue_enq_1[i] = ref_queue_enq_1[j];
          ref_queue_enq_1[j] = temp_val;
        end
      end
    end
  endtask

  task automatic rsort_dis();
    logic [DATA_WIDTH-1:0] temp_val;
    for (int i = 0; i < ref_queue_enq_0_size; i++) begin
      for (int j = i + 1; j < ref_queue_enq_0_size; j++) begin
        if (ref_queue_enq_0[i] < ref_queue_enq_0[j]) begin
          temp_val           = ref_queue_enq_0[i];
          ref_queue_enq_0[i] = ref_queue_enq_0[j];
          ref_queue_enq_0[j] = temp_val;
        end
      end
    end
  endtask

endmodule

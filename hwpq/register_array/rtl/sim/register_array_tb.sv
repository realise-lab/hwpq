`default_nettype none

module register_array_tb;
  // Parameters matching the module under test
  localparam int QUEUE_SIZE = 128;
  localparam int DATA_WIDTH = 16;

  // Clock and reset signals
  logic                 CLK;
  logic                 RSTn;

  // Input signals - for ENQ_ENA enabled
  logic                  i_wrt_ena;
  logic                  i_read_ena;
  logic [DATA_WIDTH-1:0] i_data_ena;

  // Input signals - for ENQ_ENA disabled
  logic                  i_wrt_dis;
  logic                  i_read_dis;
  logic [DATA_WIDTH-1:0] i_data_dis;

  // Output signals - for ENQ_ENA enabled
  logic                  o_full_ena;
  logic                  o_empty_ena;
  logic [DATA_WIDTH-1:0] o_data_ena;
  
  // Output signals - for ENQ_ENA disabled
  logic                  o_full_dis;
  logic                  o_empty_dis;
  logic [DATA_WIDTH-1:0] o_data_dis;
  
  // Current active outputs for testing
  logic                  o_full;
  logic                  o_empty;
  logic [DATA_WIDTH-1:0] o_data;
  logic [DATA_WIDTH-1:0] o_data_prev;
  
  // Enum to track which instance we're currently testing
  typedef enum bit {ENABLED, DISABLED} enq_mode_t;
  enq_mode_t current_mode;

  // Reference array for verification
  logic [DATA_WIDTH-1:0] ref_queue_enq_1 [$:QUEUE_SIZE-1];
  logic [DATA_WIDTH-1:0] ref_queue_enq_0 [$:QUEUE_SIZE-1];
  logic [DATA_WIDTH-1:0] ref_queue_prev  [$:QUEUE_SIZE-1];
  logic [DATA_WIDTH-1:0] saved_ref_queue [$:QUEUE_SIZE-1];

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
      .i_CLK(CLK),
      .i_RSTn(RSTn),
      .i_wrt(i_wrt_ena),
      .i_read(i_read_ena),
      .i_data(i_data_ena),
      .o_full(o_full_ena),
      .o_empty(o_empty_ena),
      .o_data(o_data_ena)
  );
  
  // Instantiate RegisterArray with ENQ_ENA disabled
  register_array #(
      .ENQ_ENA(1'b0),
      .QUEUE_SIZE(QUEUE_SIZE),
      .DATA_WIDTH(DATA_WIDTH)
  ) u_RegisterArray_dis (
      .i_CLK(CLK),
      .i_RSTn(RSTn),
      .i_wrt(i_wrt_dis),
      .i_read(i_read_dis),
      .i_data(i_data_dis),
      .o_full(o_full_dis),
      .o_empty(o_empty_dis),
      .o_data(o_data_dis)
  );

  always_comb begin : output_signal_switch
    case (current_mode)
      ENABLED : begin
        o_full = o_full_ena;
        o_empty = o_empty_ena;
        o_data = o_data_ena;
      end
      DISABLED : begin
        o_full = o_full_dis;
        o_empty = o_empty_dis;
        o_data = o_data_dis;
      end
      default : begin
        o_full = o_full_dis;
        o_empty = o_empty_dis;
        o_data = o_data_dis;
      end
    endcase
  end

  // Clock generation: 10ns period
  always #5 CLK <= ~CLK;

  initial begin
    // Initialize signals
    CLK = 0;
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
    RSTn = 0;
    @(posedge CLK);
    RSTn = 1;
    @(posedge CLK);

    // Test with ENQ_ENA enabled
    $display("\n=== Testing with ENQ_ENA enabled ===");
    
    // Initialize the queue, fill it up to QUEUE_SIZE with random values
    $display("\nInitializing enqueue enabled module by enqueue into it");
    for (int i = 0; i < QUEUE_SIZE; i++) begin
      random_value = DATA_WIDTH'(($urandom & ((1 << DATA_WIDTH) - 1)) % 1025);
      enqueue(random_value);
    end
    assert (o_full) else $error("The queue should be filled by the intialization!");

    // Test Case 1: Dequeue nodes with ENQ_ENA enabled
    $display("\nTest Case 1: Dequeue Test (ENQ_ENA enabled)");
    for (int i = 0; i < QUEUE_SIZE / 2; i++) begin
      dequeue();
      if (!o_empty) begin
        assert (o_data == ref_queue_enq_1[0]) else $error("Dequeue: Node value mismatch -> expected %d, got %d", ref_queue_enq_1[0], o_data);
      end else begin
        assert (o_data == '0) else $error("Dequeue: Node value mismatch -> expected %d, got %d", '0, o_data);
      end
    end

    // Test Case 2: Enqueue nodes with ENQ_ENA enabled
    $display("\nTest Case 2: Enqueue Test (ENQ_ENA enabled)");
    for (int i = 0; i < QUEUE_SIZE / 2; i++) begin
      random_value = DATA_WIDTH'(($urandom & ((1 << DATA_WIDTH) - 1)) % 1025);
      enqueue(random_value);
      assert (o_data == ref_queue_enq_1[0]) else $error("Enqueue: Node value mismatch -> expected %d, got %d", ref_queue_enq_1[0], o_data);
    end
    assert (o_full) else $error("The queue should be filled after enqueue!");

    // Test Case 3: Replace nodes with ENQ_ENA enabled
    $display("\nTest Case 3: Replace Test (ENQ_ENA enabled)");
    for (int i = 0; i < QUEUE_SIZE / 2; i++) begin
      random_value = DATA_WIDTH'(($urandom & ((1 << DATA_WIDTH) - 1)) % 1025);
      replace(random_value);
      assert (o_data == ref_queue_enq_1[0]) else $error("Replace: Node value mismatch -> expected %d, got %d", ref_queue_enq_1[0], o_data);
    end
    
    // Test case 4: Random opertaion for 50 times
    $display("\nTest Case 4: Stress Test (ENQ_ENA enabled)");
    for (int i = 0; i < 100; i++) begin
      random_operation = $urandom_range(1, 3);
      case (random_operation)
        ENQUEUE: begin
          random_value = DATA_WIDTH'(($urandom & ((1 << DATA_WIDTH) - 1)) % 1025);
          enqueue(random_value);
          assert (o_data == ref_queue_enq_1[0]) else $error("Random Enqueue: Node value mismatch -> expected %d, got %d", ref_queue_enq_1[0], o_data);
        end
        DEQUEUE: begin
          dequeue();
          if (!o_empty) begin
            assert (o_data == ref_queue_enq_1[0]) else $error("Random Dequeue: Node value mismatch -> expected %d, got %d", ref_queue_enq_1[0], o_data);
          end else begin
            assert (o_data == '0) else $error("Random Dequeue: Node value mismatch -> expected %d, got %d", '0, o_data);
          end
        end
        REPLACE: begin
          random_value = DATA_WIDTH'(($urandom & ((1 << DATA_WIDTH) - 1)) % 1025);
          replace(random_value);
          assert (o_data == ref_queue_enq_1[0]) else $error("Random Replace: Node value mismatch -> expected %d, got %d", ref_queue_enq_1[0], o_data);
        end
      endcase
    end

    // Now test with ENQ_ENA disabled
    $display("\n=== Testing with ENQ_ENA disabled ===");
    current_mode = DISABLED;

    // Reset the modules
    RSTn = 0;
    @(posedge CLK);
    RSTn = 1;
    @(posedge CLK);
    
    // Initialize queue inside enqueue disabled module
    for (int i = 0; i < QUEUE_SIZE; i++) begin
      random_value = DATA_WIDTH'(($urandom & ((1 << DATA_WIDTH) - 1)) % 1025);
      ref_queue_enq_0.push_back(random_value);
    end
    ref_queue_enq_0.rsort();
    
//    $display("\nSorted queue contents:");
//    for (int i = 0; i < ref_queue_enq_0.size(); i++) begin
//      $display("ref_queue_enq_0[%0d] = %0d", i, ref_queue_enq_0[i]);
//    end
    
//    $display("\nInitializing enqueue disabled module by directly tap into it");
    for (int i = 0; i < QUEUE_SIZE; i++) begin
      u_RegisterArray_dis.next_queue[i] = ref_queue_enq_0[i];
    end
    u_RegisterArray_dis.next_size = QUEUE_SIZE;
    repeat (2) @(posedge CLK);
    
//    $display("\nRegisterArray_dis.queue contents after initialization:");
//    for (int i = 0; i < QUEUE_SIZE; i++) begin
//      $display("u_RegisterArray_dis.queue[%0d] = %0d", i, u_RegisterArray_dis.queue[i]);
//    end;

    // Test Case 5: Dequeue Test with ENQ_ENA disabled
    $display("\nTest Case 5: Dequeue Test (ENQ_ENA disabled)");
    assert (o_full) else $error("The queue should be filled by the intialization!");
    for (int i = 0; i < QUEUE_SIZE / 2; i++) begin
      dequeue();
      if (!o_empty) begin
        assert (o_data == ref_queue_enq_0[0]) else $error("Dequeue: Node value mismatch -> expected %d, got %d", ref_queue_enq_0[0], o_data);
      end else begin
        assert (o_data == 'd0) else $error("Dequeue: Node value mismatch -> expected %d, got %d", 'd0, o_data);
      end
    end
    
    // Test Case 6: Try to Enqueue nodes with ENQ_ENA disabled
    $display("\nTest Case 6: Enqueue Test (ENQ_ENA disabled)");
    o_data_prev = o_data;
    ref_queue_prev = ref_queue_enq_0;
    for (int i = 0; i < QUEUE_SIZE / 2; i++) begin
      random_value = DATA_WIDTH'(($urandom & ((1 << DATA_WIDTH) - 1)) % 1025);
      enqueue(random_value);
      assert (o_data == ref_queue_enq_0[0]) else $error("Enqueue: Node value mismatch -> expected %d, got %d", ref_queue_enq_0[0], o_data);
    end
    assert (o_data == o_data_prev) else $error("The queue should not have change!");
    assert (ref_queue_enq_0 == ref_queue_prev) else $error("The queue should not have change!");
    assert (!o_full && !o_empty) else $error("The queue should not do anything!");

    // Test Case 7: Test Replace operation with ENQ_ENA disabled
    $display("\nTest Case 7: Replace Test (ENQ_ENA disabled)");
    for (int i = 0; i < QUEUE_SIZE / 2; i++) begin
      random_value = DATA_WIDTH'(($urandom & ((1 << DATA_WIDTH) - 1)) % 1025);
      replace(random_value);
      assert (o_data == ref_queue_enq_0[0]) else $error("Replace: Node value mismatch -> expected %d, got %d", ref_queue_enq_0[0], o_data);
    end
    
    // Test case 8: Random opertaion for 50 times
    $display("\nTest Case 8: Stress Test (ENQ_ENA disabled)");
    for (int i = 0; i < 100; i++) begin
      random_operation = $urandom_range(2, 3);
      case (random_operation)
        DEQUEUE: begin
          dequeue();
          if (!o_empty) begin
            assert (o_data == ref_queue_enq_0[0]) else $error("Random Dequeue: Node value mismatch -> expected %d, got %d", ref_queue_enq_0[0], o_data);
          end else begin
            assert (o_data == '0) else $error("Random Dequeue: Node value mismatch -> expected %d, got %d", '0, o_data);
          end
        end
        REPLACE: begin
          random_value = DATA_WIDTH'(($urandom & ((1 << DATA_WIDTH) - 1)) % 1025);
          replace(random_value);
          assert (o_data == ref_queue_enq_0[0]) else $error("Random Replace: Node value mismatch -> expected %d, got %d", ref_queue_enq_0[0], o_data);
        end
      endcase
    end

    $display("\nTest completed!");
    $finish;
  end

  task automatic enqueue(input logic [DATA_WIDTH-1:0] value);
    begin
      if (!o_full) begin
        if (current_mode == ENABLED) begin
          i_wrt_ena = 1;
          i_read_ena = 0;
          i_data_ena = value;
          ref_queue_enq_1.push_back(value);
          ref_queue_enq_1.rsort();
        end else if (current_mode == DISABLED) begin
          i_wrt_dis = 1;
          i_read_dis = 0;
          i_data_dis = value;
//          $display("Enqueue attempt with ENQ_ENA disabled - should have no effect");
        end
      end else begin
        $display("Enqueue: Queue full, skipping enqueue");
      end
      @(posedge CLK);
      i_wrt_ena  = 0;
      i_read_ena = 0;
      i_wrt_dis  = 0;
      i_read_dis = 0;
      if (current_mode == ENABLED) @(posedge CLK);
      else if (current_mode == DISABLED) @(posedge CLK); // should have no effects
    end
  endtask

  task automatic dequeue();
    begin
      if (!o_empty) begin
        if (current_mode == ENABLED) begin
          i_wrt_ena  = 0;
          i_read_ena = 1;
          i_data_ena = 0;
          ref_queue_enq_1.pop_front();
          ref_queue_enq_1.rsort();
        end else if (current_mode == DISABLED) begin
          i_wrt_dis  = 0;
          i_read_dis = 1;
          i_data_dis = 0;
          ref_queue_enq_0.pop_front();
          ref_queue_enq_0.rsort();
        end
      end else begin
        $display("Dequeue: Queue empty, skipping dequeue");
      end
      @(posedge CLK);
      i_wrt_ena  = 0;
      i_read_ena = 0;
      i_wrt_dis  = 0;
      i_read_dis = 0;
      if (current_mode == ENABLED) @(posedge CLK);
      else if (current_mode == DISABLED) @(posedge CLK);
    end
  endtask

  task automatic replace(input logic [DATA_WIDTH-1:0] value);
    begin
      if (current_mode == ENABLED) begin
        i_wrt_ena  = 1;
        i_read_ena = 1;
        i_data_ena = value;
        if (o_empty) begin
          ref_queue_enq_1.push_back(value);
        end else begin
          ref_queue_enq_1.pop_front();
          ref_queue_enq_1.push_back(value);
        end
        ref_queue_enq_1.rsort();
      end else if (current_mode == DISABLED) begin
        i_wrt_dis  = 1;
        i_read_dis = 1;
        i_data_dis = value;
        if (o_empty) begin
          ref_queue_enq_0.push_back(value);
        end else begin
          ref_queue_enq_0.pop_front();
          ref_queue_enq_0.push_back(value);
        end
        ref_queue_enq_0.rsort();
      end
      @(posedge CLK);
      i_wrt_ena  = 0;
      i_read_ena = 0;
      i_wrt_dis  = 0;
      i_read_dis = 0;
      if (current_mode == ENABLED) @(posedge CLK);
      else if (current_mode == DISABLED) @(posedge CLK);
    end
  endtask

endmodule

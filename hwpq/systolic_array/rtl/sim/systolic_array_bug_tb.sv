module systolic_array_tb;
  // Parameters matching the module under test
  parameter int QUEUE_SIZE = 8;
  parameter int DATA_WIDTH = 16;

  // Clock and reset signals
  logic                  i_CLK;
  logic                  i_RSTn;

  // Input signals
  logic                  i_wrt;
  logic                  i_read;
  logic [DATA_WIDTH-1:0] i_data;

  // Output signals
  logic                  o_write_ready;
  logic                  o_read_ready;
  logic [DATA_WIDTH-1:0] o_data;

  // Reference array for verification
  logic [DATA_WIDTH-1:0] ref_queue        [$:QUEUE_SIZE-1];
  int                    ref_size = 0;
  logic [DATA_WIDTH-1:0] tmp;

  // Instantiate the register_tree module
  systolic_array #(
      .QUEUE_SIZE(QUEUE_SIZE),
      .DATA_WIDTH(DATA_WIDTH)
  ) u_SystolicArray (
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
    @(posedge i_CLK);

    // Test Case 1: Successive decreasing numbers in IB
    $display("\nTest Case 1: Successive decreasing numbers in IB");
    ref_queue.delete();

    /* Icarus Verilog (12.0) cannot force an unpacked array, so the DUT buffers are seeded
      one element at a time with plain hierarchical assignments instead of
        `force u_SystolicArray.IB = '{16'd1, 16'd6, 16'd4, 16'd2};`
      which fails with "Assignment to an entire array or to an array slice is not yet supported".
      Forcing a single word fails too with "cannot force to the word of a variable array". 
      The same applies to the other test cases below. */
    
    force u_SystolicArray.IB = '{16'd0, 16'd6, 16'd4, 16'd2};
    force u_SystolicArray.OB = '{16'd12, 16'd11, 16'd10, 16'd0}; 
    force u_SystolicArray.size = 4'd6;

    @(posedge i_CLK);

    release u_SystolicArray.IB;
    release u_SystolicArray.OB;
    release u_SystolicArray.size;

    ref_queue.push_back(16'd6);
    ref_queue.push_back(16'd4);
    ref_queue.push_back(16'd2);
    ref_queue.push_back(16'd12);
    ref_queue.push_back(16'd11);
    ref_queue.push_back(16'd10);
    ref_size = 6;
    for (int i = 0; i < ref_size; i++) begin
      for (int j = i + 1; j < ref_size; j++) begin
        if (ref_queue[i] < ref_queue[j]) begin
          tmp = ref_queue[i];
          ref_queue[i] = ref_queue[j];
          ref_queue[j] = tmp;
        end
      end
    end
    repeat (10) @(posedge i_CLK);

    for (int i = 0; i < QUEUE_SIZE*2; i++) begin
      dequeue();
    end

    // Test Case 2: Successive decreasing numbers from IB to OB+1
    $display("\nTest Case 2: Successive decreasing numbers from IB to OB+1");
    ref_queue.delete();
    force u_SystolicArray.IB = '{16'd0, 16'd0, 16'd11, 16'd10};
    force u_SystolicArray.OB = '{16'd17, 16'd16, 16'd15, 16'd9}; 
    force u_SystolicArray.size = 4'd6;

    @(posedge i_CLK);

    release u_SystolicArray.IB;
    release u_SystolicArray.OB;
    release u_SystolicArray.size;

    ref_queue.push_back(16'd11);
    ref_queue.push_back(16'd10);
    ref_queue.push_back(16'd17);
    ref_queue.push_back(16'd16);
    ref_queue.push_back(16'd15);
    ref_queue.push_back(16'd9);
    ref_size = 6;
    for (int i = 0; i < ref_size; i++) begin
      for (int j = i + 1; j < ref_size; j++) begin
        if (ref_queue[i] < ref_queue[j]) begin
          tmp = ref_queue[i];
          ref_queue[i] = ref_queue[j];
          ref_queue[j] = tmp;
        end
      end
    end
    repeat (10) @(posedge i_CLK);

    for (int i = 0; i < QUEUE_SIZE*2; i++) begin
      dequeue();
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
        assert (o_data == ref_queue[0])
        else
          begin error_count++; $error("Dequeue: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data); end;
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

endmodule
`default_nettype none

module systolic_array_tb;
  // Parameters matching the module under test
  parameter int QUEUE_SIZE = 16;
  parameter int DATA_WIDTH = 16;

  // Clock and reset signals
  logic                  CLK;
  logic                  RSTn;

  // Input signals
  logic                  i_wrt;
  logic                  i_read;
  logic [DATA_WIDTH-1:0] i_data;

  // Output signals
  logic [DATA_WIDTH-1:0] o_data;
  logic                  o_write_ready;
  logic                  o_read_ready;

  // Reference array for verification
  logic [DATA_WIDTH-1:0] ref_queue        [$:QUEUE_SIZE-1];

  int total_cycles;
  int write_stall_cycles;
  int read_stall_cycles;
  int stall_timeout      = 2000;
  int error_count        = 0;

  // File descriptor for write logging
  int write_log_file;

  // Test variables
  logic [DATA_WIDTH-1:0] random_value;

  typedef enum int {
    ENQUEUE = 1,
    DEQUEUE = 2,
    REPLACE = 3
  } t_operation;
  t_operation random_operation;

  // Instantiate the register_tree module
  systolic_array #(
      .QUEUE_SIZE(QUEUE_SIZE),
      .DATA_WIDTH(DATA_WIDTH)
  ) u_SystolicArray (
      .i_CLK(CLK),
      .i_RSTn(RSTn),
      .i_wrt(i_wrt),
      .i_read(i_read),
      .i_data(i_data),
      .o_data(o_data),
      .o_write_ready(o_write_ready),
      .o_read_ready(o_read_ready)
  );

  // Clock generation: 10ns period
  always #5 CLK <= ~CLK;

  always_ff @(posedge CLK or negedge RSTn) begin
    if (!RSTn) begin
      total_cycles <= 0;
      write_stall_cycles <= 0;
      read_stall_cycles <= 0;
    end else begin
      total_cycles <= total_cycles + 1;

      if (ref_queue.size() > 0 && !o_read_ready) begin
        read_stall_cycles <= read_stall_cycles + 1;
        if (read_stall_cycles >= stall_timeout) begin
          $fatal(1, "Read stall timeout: queue still has %0d entries but o_read_ready stayed low for %0d cycles.", ref_queue.size(), stall_timeout);
        end
      end else begin
        read_stall_cycles <= 0;
      end

      if (!o_write_ready) begin
        write_stall_cycles <= write_stall_cycles + 1;
        if (write_stall_cycles >= stall_timeout) begin
          $fatal(1, "Write stall timeout: o_write_ready stayed low for %0d cycles while size=%0d.", stall_timeout, u_SystolicArray.size);
        end
      end else begin
        write_stall_cycles <= 0;
      end
    end
  end

`ifndef __ICARUS__
  // Each live IB value is next seen in IB or OB at an adjacent index. iverilog lacks SVA.
  genvar g_i;
  generate
    // Loop up to HALF_SIZE (u_SystolicArray.HALF_SIZE), not QUEUE_SIZE
    for (g_i = 0; g_i < u_SystolicArray.HALF_SIZE; g_i++) begin : g_data_conservation_check
      property p_value_preserved;
        @(posedge CLK) disable iff (!RSTn)
        (u_SystolicArray.IB[g_i] != '0) |=> (
          (u_SystolicArray.IB[g_i] == $past(u_SystolicArray.IB[g_i])) ||
          (g_i < u_SystolicArray.HALF_SIZE-1 && u_SystolicArray.IB[g_i+1] == $past(u_SystolicArray.IB[g_i])) ||
          (u_SystolicArray.OB[g_i] == $past(u_SystolicArray.IB[g_i])) ||
          (g_i < u_SystolicArray.HALF_SIZE-1 && u_SystolicArray.OB[g_i+1] == $past(u_SystolicArray.IB[g_i])) ||
          (g_i > 0 && u_SystolicArray.IB[g_i-1] == $past(u_SystolicArray.IB[g_i]))
        );
      endproperty

      a_value_preserved: assert property (p_value_preserved)
        else begin
          error_count++;
          $error("[Data Lost] Time %0t: Value %0d at IB index %0d disappeared!",
                 $time, $past(u_SystolicArray.IB[g_i]), g_i);
        end
    end
  endgenerate
`endif

  // Each element occupies one nonzero IB/OB slot, so the occupied count tracks size.
  // Reports each change in the mismatch once: a loss drops the count, a duplicate raises it.
  int drift = 0;
  always @(negedge CLK) if (RSTn) begin : occupancy
    int occupied;
    occupied = 0;
    for (int i = 0; i < QUEUE_SIZE/2; i++)
      occupied += (u_SystolicArray.IB[i] != '0) + (u_SystolicArray.OB[i] != '0);
    if (occupied - u_SystolicArray.size != drift) begin
      error_count++;
      $error("[Occupancy] Time %0t: %0d nonzero IB/OB slots, size is %0d",
             $time, occupied, u_SystolicArray.size);
      drift = occupied - u_SystolicArray.size;
    end
  end

  initial begin
    // Open log file for recording writes
    write_log_file = $fopen("build/systolic_writes.txt", "w");
    if (write_log_file == 0) begin
      $fatal(1, "Failed to open file: build/systolic_writes.txt");
    end

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
      random_value = i+1;
      enqueue(random_value);
    end

    // Test Case 1: Dequeue nodes
    // Dequeue nodes for QUEUE_SIZE*2 times since it takes 2 cycles to dequeue
    $display("\nTest Case 1: Dequeue Test");
    for (int i = 0; i < QUEUE_SIZE*2; i++) begin
      dequeue();
    end

    // Test Case 2: Enqueue nodes
    // Enqueue random values for QUEUE_SIZE times
    $display("\nTest Case 2: Enqueue Test");
    for (int i = 0; i < QUEUE_SIZE; i++) begin
      random_value = $urandom_range(1, 1024);
      enqueue(random_value);
    end

    // Test Case 3: Replace nodes
    // Replace root node for QUEUE_SIZE times
    $display("\nTest Case 3: Replace Test");
    for (int i = 0; i < QUEUE_SIZE; i++) begin
      random_value = $urandom_range(1, 1024);
      replace(random_value);
    end

    // Test Case 4: Stress Test
    // stress test, mix operations
    $display("\nTest Case 4: Stress Test");
    for (int i = 0; i < 100000; i++) begin
      random_value = $urandom_range(1, 1024);
      random_operation = t_operation'($urandom_range(1,3));
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

    $display("\n================ PERFORMANCE METRICS ================");
    $display("Total Simulated Cycles : %d", total_cycles);
    $display("Write Stall Cycles     : %d  (%.2f%%)", write_stall_cycles, (real'(write_stall_cycles) / total_cycles) * 100.0);
    $display("Read Stall Cycles      : %d  (%.2f%%)", read_stall_cycles,  (real'(read_stall_cycles) / total_cycles) * 100.0);
    $display("=====================================================");

    $fclose(write_log_file);
    if (error_count != 0) $fatal(1, "Test FAILED with %0d error(s).", error_count);
    $display("\nTest completed! ");
    $finish;
  end

  task automatic enqueue(input logic [DATA_WIDTH-1:0] value);
    begin
      #1;  // sample after this edge's updates land, not the previous cycle's ready
      if (o_write_ready) begin
        i_wrt  = 1;
        i_read = 0;
        i_data = value;
        ref_queue.push_back(value);
        ref_queue.rsort();
        $fdisplay(write_log_file, "Time: %0t | Value: %0d", $time, value);
      end else begin
        i_wrt  = 0;
        i_read = 0;
      end
      @(posedge CLK);
    end
  endtask

  // Task to read root node
  task automatic dequeue();
    begin
      #1;
      if (o_read_ready) begin
        assert (o_data == ref_queue[0])
        else begin
          error_count++;
          $error("Dequeue: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
        end
        i_wrt  = 0;
        i_read = 1;
        ref_queue.rsort();
        ref_queue.pop_front();
      end else begin
        i_wrt  = 0;
        i_read = 0;
      end
      @(posedge CLK);
    end
  endtask

  // Task to replace root node
  task automatic replace(input logic [DATA_WIDTH-1:0] value);
    begin
      #1;
      if (o_read_ready) begin
        assert (o_data == ref_queue[0])
        else begin
          error_count++;
          $error("Replace: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
        end
        i_wrt  = 1;
        i_read = 1;
        i_data = value;
        ref_queue.pop_front();
        ref_queue.push_back(value);
        ref_queue.rsort();
        $fdisplay(write_log_file, "Time: %0t | Value: %0d", $time, value);
      end else begin
        i_wrt  = 0;
        i_read = 0;
      end
      @(posedge CLK);
    end
  endtask

endmodule
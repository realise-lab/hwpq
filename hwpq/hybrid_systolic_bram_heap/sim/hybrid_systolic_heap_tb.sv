`default_nettype none
import bram_tree_pkg::*;

// vcs -sverilog -full64 hwpq/hwpq/hybrid_systolic_bram_heap/src/hybrid_typedef.sv hwpq/hwpq/hybrid_systolic_bram_heap/sim/hybrid_systolic_heap_tb.sv hwpq/hwpq/hybrid_systolic_bram_heap/src/rams_tdp_rf_rf.sv hwpq/hwpq/hybrid_systolic_bram_heap/src/bram_tree.sv hwpq/hwpq/hybrid_systolic_bram_heap/src/hybrid_systolic_heap.sv -o simv

// vcs -sverilog -full64 hwpq/hwpq/hybrid_systolic_bram_heap/src/hybrid_typedef.sv hwpq/hwpq/bram_tree/rtl/sim/bram_tree_tb.sv hwpq/hwpq/hybrid_systolic_bram_heap/src/rams_tdp_rf_rf.sv hwpq/hwpq/hybrid_systolic_bram_heap/src/bram_tree.sv 

module systolic_array_tb;
  // Parameters matching the module under test
  parameter int QUEUE_SIZE = SYSTOLIC_QUEUE_SIZE + BRAM_TREE_QUEUE_SIZE*TREE_COUNT;
  parameter int THRESHOLD = 1000;

  // Clock and reset signals
  logic                  CLK;
  logic                  RSTn;

  // Input signals
  logic                  i_wrt;
  logic                  i_read;
  logic [DATA_WIDTH-1:0] i_data;

  // Output signals
  logic                  o_write_ready;
  logic                  o_read_ready;
  logic [DATA_WIDTH-1:0] o_data;

  // Reference array for verification
  logic [DATA_WIDTH-1:0] ref_queue        [$:QUEUE_SIZE*2];

  int total_cycles       = 0;
  int write_stall_cycles = 0;
  int read_stall_cycles  = 0;

  // Test variables
  logic [DATA_WIDTH-1:0] random_value;
  int timeout_counter = 0;

  typedef enum int {
    ENQUEUE = 1,
    DEQUEUE = 2,
    REPLACE = 3
  } t_operation;
  t_operation random_operation;

  // Instantiate the register_tree module
  hybrid_systolic_heap uut (
      .i_CLK(CLK),
      .i_RSTn(RSTn),
      .i_wrt(i_wrt),
      .i_read(i_read),
      .i_data(i_data),
      .o_write_ready(o_write_ready),
      .o_read_ready(o_read_ready),
      .o_data(o_data)
  );

  // Clock generation: 10ns period
  always #5 CLK <= ~CLK;

  always @(posedge CLK) begin
    if (RSTn) begin
      total_cycles += 1;
    end
  end

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
    for (int i = 0; i < QUEUE_SIZE/2; i++) begin
      random_value = $urandom_range(1,3000);
      enqueue(random_value);
    end
    
    // Test Case 1: Dequeue nodes
    $display("DEBUG fill ref=%0d m=%0d h=%0d ob=%0d ib=%0d", ref_queue.size(), uut.m_empt, uut.h_empt, uut.OB[0], uut.IB[0]);
    // Dequeue nodes for QUEUE_SIZE times
    $display("\nTest Case 1: Dequeue Test");
    for (int i = 0; i < QUEUE_SIZE/2; i++) begin
      dequeue();
    end
    
    
    // Test Case 2: Enqueue nodes
    // Enqueue random values for QUEUE_SIZE times
    $display("\nTest Case 2: Enqueue Test");
    for (int i = 0; i < QUEUE_SIZE/2; i++) begin
      random_value = $urandom_range(1,3000);
      enqueue(random_value);
    end
    
    
    // Test Case 3: Replace nodes
    // Replace root node for QUEUE_SIZE times
    
    $display("\nTest Case 3: Replace Test");
    for (int i = 0; i < QUEUE_SIZE/2; i++) begin
      random_value = $urandom_range(1,3000);
      replace(random_value);
    end
    
    // Test Case 4: Stress Test
    // stress test, mix operations
    
    $display("\nTest Case 4: Stress Test");
    for (int i = 0; i < 100000; i++) begin
      random_value = $urandom_range(1,3000);
      random_operation = $urandom_range(1,3);
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

    $display("\nTest completed! ");
    $finish;
  end

  // Task to write to the end of the queue
  task automatic enqueue(input logic [DATA_WIDTH-1:0] value);
    begin
      if (o_write_ready) begin
        i_wrt  = 1;
        i_read = 0;
        i_data = value;
        ref_queue.push_back(value);
          ref_queue.rsort();
        timeout_counter = 0;
      end else begin
        i_wrt  = 0;
        i_read = 0;
        timeout_counter += 1;
        if (timeout_counter >= THRESHOLD) begin
          $error("ERROR: TIMEOUT");
          $finish;
        end
      end
      @(posedge CLK);
    end
  endtask

  // Task to read root node
  task automatic dequeue();
    begin
      if (o_read_ready) begin
        assert (o_data == ref_queue[0])
        else
          $error("Dequeue: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
        i_wrt  = 0;
        i_read = 1;
          ref_queue.rsort();
        ref_queue.pop_front();
        timeout_counter = 0;
      end else begin
        i_wrt  = 0;
        i_read = 0;
          timeout_counter += 1;
          if (timeout_counter >= THRESHOLD) begin
          $error("ERROR: TIMEOUT");
          $finish;
        end
      end
      @(posedge CLK);
    end
  endtask

  // Task to replace root node
  task automatic replace(input logic [DATA_WIDTH-1:0] value);
    begin
      if (o_read_ready && o_write_ready) begin
        assert (o_data == ref_queue[0])
        else
          $error("Replace: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
        i_wrt  = 1;
        i_read = 1;
        i_data = value;
        ref_queue.pop_front();
        ref_queue.push_back(value);
        ref_queue.rsort();
        timeout_counter = 0;
      end else begin
        i_wrt  = 0;
        i_read = 0;
        timeout_counter += 1;
        if (timeout_counter >= THRESHOLD) begin
          $error("ERROR: TIMEOUT");
          $finish;
        end
      end
      @(posedge CLK);
    end
  endtask

endmodule

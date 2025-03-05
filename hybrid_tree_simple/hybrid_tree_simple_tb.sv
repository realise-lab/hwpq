module bram_tree_tb;
  // Parameters matching the module under test
  localparam integer QueueSize = 15;
  localparam integer DataWidth = 16;

  // Clock and reset signals
  logic                   CLK;
  logic                   RSTn;

  // Input signals
  logic                   i_wrt;
  logic                   i_read;
  logic   [DataWidth-1:0] i_data;

  // Output signals
  logic                   o_full;
  logic                   o_empty;
  logic   [DataWidth-1:0] o_data;

  // Reference array for verification
  logic   [DataWidth-1:0] ref_queue        [$:QueueSize-1];

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
  bram_tree #(
      .QUEUE_SIZE(QueueSize),
      .DATA_WIDTH(DataWidth)
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
    repeat (2) @(posedge CLK);

    // Initialize the reference queue, sort the reference queue, and write to the queue
    for (i = 0; i < QueueSize; i++) begin
      random_value = DataWidth'(($urandom & ((1 << DataWidth) - 1)) % 1025);
      ref_queue.push_back(random_value);
    end
    ref_queue.rsort();
    for (i = 0; i < QueueSize; i++) begin
      if (i == 0) begin
        uut.next_level_0 = ref_queue[0];
      end else if (i == 1) begin
        uut.next_level_1[0] = ref_queue[1];
      end else if (i == 2) begin
        uut.next_level_1[1] = ref_queue[2];
      end else begin
        if ($clog2(i + 1) - (((i + 1) & i) ? 1 : 0) == 2) begin
          if (i - 3 == 0) begin
            uut.gen_bram[2].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[i-3] = ref_queue[3];
          end else if (i - 3 == 1) begin
            uut.gen_bram[2].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[i-3] = ref_queue[4];
          end else if (i - 3 == 2) begin
            uut.gen_bram[2].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[i-3] = ref_queue[5];
          end else if (i - 3 == 3) begin
            uut.gen_bram[2].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[i-3] = ref_queue[6];
          end
        end else if ($clog2(i + 1) - (((i + 1) & i) ? 1 : 0) == 3) begin
          if (i - 7 == 0) begin
            uut.gen_bram[3].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[i-7] = ref_queue[7];
          end else if (i - 7 == 1) begin
            uut.gen_bram[3].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[i-7] = ref_queue[8];
          end else if (i - 7 == 2) begin
            uut.gen_bram[3].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[i-7] = ref_queue[9];
          end else if (i - 7 == 3) begin
            uut.gen_bram[3].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[i-7] = ref_queue[10];
          end else if (i - 7 == 4) begin
            uut.gen_bram[3].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[i-7] = ref_queue[11];
          end else if (i - 7 == 5) begin
            uut.gen_bram[3].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[i-7] = ref_queue[12];
          end else if (i - 7 == 6) begin
            uut.gen_bram[3].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[i-7] = ref_queue[13];
          end else if (i - 7 == 7) begin
            uut.gen_bram[3].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[i-7] = ref_queue[14];
          end
        end
      end
    end
    uut.next_queue_size = QueueSize;
    uut.next_state = 0;

    repeat (16) @(posedge CLK);

    // Test Case 1: Dequeue nodes
    // Dequeue nodes for QUEUE_SIZE times
    $display("\nTest Case 1: Dequeue Test");
    for (i = 0; i < QueueSize; i++) begin
      dequeue();
      if (!o_empty) begin
        assert (o_data == ref_queue[0])
        else $error("Dequeue: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
      end else begin
        assert (o_data == '0)
        else $error("Dequeue: Node f value mismatch -> expected %d, got %d", '0, o_data);
      end
    end

    for (i = 0; i < QueueSize; i++) begin
      random_value = DataWidth'(($urandom & ((1 << DataWidth) - 1)) % 1025);
      ref_queue.push_back(random_value);
    end
    ref_queue.rsort();
    for (i = 0; i < QueueSize; i++) begin
      if (i == 0) begin
        uut.next_level_0 = ref_queue[0];
      end else if (i == 1) begin
        uut.next_level_1[0] = ref_queue[1];
      end else if (i == 2) begin
        uut.next_level_1[1] = ref_queue[2];
      end else begin
        for (i = 0; i < QueueSize; i++) begin
          if (i == 0) begin
            uut.next_level_0 = ref_queue[0];
          end else if (i == 1) begin
            uut.next_level_1[0] = ref_queue[1];
          end else if (i == 2) begin
            uut.next_level_1[1] = ref_queue[2];
          end else begin
            if ($clog2(i + 1) - (((i + 1) & i) ? 1 : 0) == 2) begin
              if (i - 3 == 0) begin
                uut.gen_bram[2].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[0] = ref_queue[3];
              end else if (i - 3 == 1) begin
                uut.gen_bram[2].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[1] = ref_queue[4];
              end else if (i - 3 == 2) begin
                uut.gen_bram[2].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[2] = ref_queue[5];
              end else if (i - 3 == 3) begin
                uut.gen_bram[2].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[3] = ref_queue[6];
              end
            end else if ($clog2(i + 1) - (((i + 1) & i) ? 1 : 0) == 3) begin
              if (i - 7 == 0) begin
                uut.gen_bram[3].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[0] = ref_queue[7];
              end else if (i - 7 == 1) begin
                uut.gen_bram[3].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[1] = ref_queue[8];
              end else if (i - 7 == 2) begin
                uut.gen_bram[3].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[2] = ref_queue[9];
              end else if (i - 7 == 3) begin
                uut.gen_bram[3].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[3] = ref_queue[10];
              end else if (i - 7 == 4) begin
                uut.gen_bram[3].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[4] = ref_queue[11];
              end else if (i - 7 == 5) begin
                uut.gen_bram[3].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[5] = ref_queue[12];
              end else if (i - 7 == 6) begin
                uut.gen_bram[3].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[6] = ref_queue[13];
              end else if (i - 7 == 7) begin
                uut.gen_bram[3].bram_inst.inst.native_mem_module.blk_mem_gen_v8_4_8_inst.memory[7] = ref_queue[14];
              end
            end
          end
        end
      end
    end
    uut.next_queue_size = QueueSize;
    uut.next_state = 0;

    repeat (16) @(posedge CLK);

    // Test Case 2: Replace nodes
    // Replace root node for QUEUE_SIZE times
    $display("\nTest Case 2: Replace Test");
    for (i = 0; i < QueueSize; i++) begin
      random_value = DataWidth'(($urandom & ((1 << DataWidth) - 1)) % 1025);
      replace(random_value);
      assert (o_data == ref_queue[0])
      else $error("Replace: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
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
          if (!o_empty) begin
            assert (o_data == ref_queue[0])
            else $error("Dequeue: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
          end else begin
            assert (o_data == '0)
            else $error("Dequeue: Node f value mismatch -> expected %d, got %d", '0, o_data);
          end
        end

        REPLACE: begin
          replace(random_value);
          assert (o_data == ref_queue[0])
          else $error("Replace: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
        end

        default: begin
          $display("Invalid operation: %d", random_operation);
        end
      endcase
    end

    $display("\nTest completed! ");
    $finish;
  end

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
      repeat (24) @(posedge CLK);
    end
  endtask

  // Task to replace root node
  task automatic replace(input logic [DataWidth-1:0] value);
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
      repeat (24) @(posedge CLK);
    end
  endtask

endmodule

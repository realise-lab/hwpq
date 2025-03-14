module tb_pipelined_bram_tree;
  // Parameters matching the module under test
  localparam integer QueueSize = 31;
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
  logic   [DataWidth-1:0] random_value;
  integer                 random_operation;

  typedef enum integer {
    ENQUEUE = 0,
    DEQUEUE = 1,
    REPLACE = 2
  } operation_t;

  // Instantiate the register_tree module
  pipelined_bram_tree #(
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
    @(posedge CLK);

    // Initialize the reference queue, sort the reference queue, and write to the queue
    for (int i = 0; i < QueueSize; i++) begin
      random_value = DataWidth'(($urandom & ((1 << DataWidth) - 1)) % 1025);
      ref_queue.push_back(random_value);
    end
    ref_queue.rsort();
    for (int i = 0; i < QueueSize; i++) begin
      if ($clog2(i + 1) - (((i + 1) & i) ? 1 : 0) == 0) begin
        if (i == 0) begin
          uut.gen_bram[0].bram_inst.ram[0] = ref_queue[0];
        end
      end
      else if ($clog2(i + 1) - (((i + 1) & i) ? 1 : 0) == 1) begin
        if (i == 1) begin
          uut.gen_bram[1].bram_inst.ram[0] = ref_queue[1];
        end
        else if (i == 2) begin
          uut.gen_bram[1].bram_inst.ram[1] = ref_queue[2];
        end
      end
      else if ($clog2(i + 1) - (((i + 1) & i) ? 1 : 0) == 2) begin
        if (i - 3 == 0) begin
          uut.gen_bram[2].bram_inst.ram[0] = ref_queue[3];
        end else if (i - 3 == 1) begin
          uut.gen_bram[2].bram_inst.ram[1] = ref_queue[4];
        end else if (i - 3 == 2) begin
          uut.gen_bram[2].bram_inst.ram[2] = ref_queue[5];
        end else if (i - 3 == 3) begin
          uut.gen_bram[2].bram_inst.ram[3] = ref_queue[6];
        end
      end 
      else if ($clog2(i + 1) - (((i + 1) & i) ? 1 : 0) == 3) begin
        if (i - 7 == 0) begin
          uut.gen_bram[3].bram_inst.ram[0] = ref_queue[7];
        end else if (i - 7 == 1) begin
          uut.gen_bram[3].bram_inst.ram[1] = ref_queue[8];
        end else if (i - 7 == 2) begin
          uut.gen_bram[3].bram_inst.ram[2] = ref_queue[9];
        end else if (i - 7 == 3) begin
          uut.gen_bram[3].bram_inst.ram[3] = ref_queue[10];
        end else if (i - 7 == 4) begin
          uut.gen_bram[3].bram_inst.ram[4] = ref_queue[11];
        end else if (i - 7 == 5) begin
          uut.gen_bram[3].bram_inst.ram[5] = ref_queue[12];
        end else if (i - 7 == 6) begin
          uut.gen_bram[3].bram_inst.ram[6] = ref_queue[13];
        end else if (i - 7 == 7) begin
          uut.gen_bram[3].bram_inst.ram[7] = ref_queue[14];
        end
      end 
      else if ($clog2(i + 1) - (((i + 1) & i) ? 1 : 0) == 4) begin
        if (i - 15 == 0) begin
          uut.gen_bram[4].bram_inst.ram[0] = ref_queue[15];
        end else if (i - 15 == 1) begin
          uut.gen_bram[4].bram_inst.ram[1] = ref_queue[16];
        end else if (i - 15 == 2) begin
          uut.gen_bram[4].bram_inst.ram[2] = ref_queue[17];
        end else if (i - 15 == 3) begin
          uut.gen_bram[4].bram_inst.ram[3] = ref_queue[18];
        end else if (i - 15 == 4) begin
          uut.gen_bram[4].bram_inst.ram[4] = ref_queue[19];
        end else if (i - 15 == 5) begin
          uut.gen_bram[4].bram_inst.ram[5] = ref_queue[20];
        end else if (i - 15 == 6) begin
          uut.gen_bram[4].bram_inst.ram[6] = ref_queue[21];
        end else if (i - 15 == 7) begin
          uut.gen_bram[4].bram_inst.ram[7] = ref_queue[22];
        end else if (i - 15 == 8) begin
          uut.gen_bram[4].bram_inst.ram[8] = ref_queue[23];
        end else if (i - 15 == 9) begin
          uut.gen_bram[4].bram_inst.ram[9] = ref_queue[24];
        end else if (i - 15 == 10) begin
          uut.gen_bram[4].bram_inst.ram[10] = ref_queue[25];
        end else if (i - 15 == 11) begin
          uut.gen_bram[4].bram_inst.ram[11] = ref_queue[26];
        end else if (i - 15 == 12) begin
          uut.gen_bram[4].bram_inst.ram[12] = ref_queue[27];
        end else if (i - 15 == 13) begin
          uut.gen_bram[4].bram_inst.ram[13] = ref_queue[28];
        end else if (i - 15 == 14) begin
          uut.gen_bram[4].bram_inst.ram[14] = ref_queue[29];
        end else if (i - 15 == 15) begin
          uut.gen_bram[4].bram_inst.ram[15] = ref_queue[30];
        end
      end
    end
    uut.next_queue_size = QueueSize;
    uut.next_state = 0;

    repeat (16) @(posedge CLK);

    // Test Case 1: Dequeue nodes
    // Dequeue nodes for QUEUE_SIZE times
    $display("\nTest Case 1: Dequeue Test");
    for (int i = 0; i < QueueSize; i++) begin
      dequeue();
      if (!o_empty) begin
        assert (o_data == ref_queue[0])
        else $error("Dequeue: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
      end else begin
        assert (o_data == '0)
        else $error("Dequeue: Node f value mismatch -> expected %d, got %d", '0, o_data);
      end
    end

    for (int i = 0; i < QueueSize; i++) begin
      random_value = DataWidth'(($urandom & ((1 << DataWidth) - 1)) % 1025);
      ref_queue.push_back(random_value);
    end
    ref_queue.rsort();
    for (int i = 0; i < QueueSize; i++) begin
      if ($clog2(i + 1) - (((i + 1) & i) ? 1 : 0) == 0) begin
        if (i == 0) begin
          uut.gen_bram[0].bram_inst.ram[0] = ref_queue[0];
        end
      end
      else if ($clog2(i + 1) - (((i + 1) & i) ? 1 : 0) == 1) begin
        if (i == 1) begin
          uut.gen_bram[1].bram_inst.ram[0] = ref_queue[1];
        end
        else if (i == 2) begin
          uut.gen_bram[1].bram_inst.ram[1] = ref_queue[2];
        end
      end
      else if ($clog2(i + 1) - (((i + 1) & i) ? 1 : 0) == 2) begin
        if (i - 3 == 0) begin
          uut.gen_bram[2].bram_inst.ram[0] = ref_queue[3];
        end else if (i - 3 == 1) begin
          uut.gen_bram[2].bram_inst.ram[1] = ref_queue[4];
        end else if (i - 3 == 2) begin
          uut.gen_bram[2].bram_inst.ram[2] = ref_queue[5];
        end else if (i - 3 == 3) begin
          uut.gen_bram[2].bram_inst.ram[3] = ref_queue[6];
        end
      end 
      else if ($clog2(i + 1) - (((i + 1) & i) ? 1 : 0) == 3) begin
        if (i - 7 == 0) begin
          uut.gen_bram[3].bram_inst.ram[0] = ref_queue[7];
        end else if (i - 7 == 1) begin
          uut.gen_bram[3].bram_inst.ram[1] = ref_queue[8];
        end else if (i - 7 == 2) begin
          uut.gen_bram[3].bram_inst.ram[2] = ref_queue[9];
        end else if (i - 7 == 3) begin
          uut.gen_bram[3].bram_inst.ram[3] = ref_queue[10];
        end else if (i - 7 == 4) begin
          uut.gen_bram[3].bram_inst.ram[4] = ref_queue[11];
        end else if (i - 7 == 5) begin
          uut.gen_bram[3].bram_inst.ram[5] = ref_queue[12];
        end else if (i - 7 == 6) begin
          uut.gen_bram[3].bram_inst.ram[6] = ref_queue[13];
        end else if (i - 7 == 7) begin
          uut.gen_bram[3].bram_inst.ram[7] = ref_queue[14];
        end
      end 
      else if ($clog2(i + 1) - (((i + 1) & i) ? 1 : 0) == 4) begin
        if (i - 15 == 0) begin
          uut.gen_bram[4].bram_inst.ram[0] = ref_queue[15];
        end else if (i - 15 == 1) begin
          uut.gen_bram[4].bram_inst.ram[1] = ref_queue[16];
        end else if (i - 15 == 2) begin
          uut.gen_bram[4].bram_inst.ram[2] = ref_queue[17];
        end else if (i - 15 == 3) begin
          uut.gen_bram[4].bram_inst.ram[3] = ref_queue[18];
        end else if (i - 15 == 4) begin
          uut.gen_bram[4].bram_inst.ram[4] = ref_queue[19];
        end else if (i - 15 == 5) begin
          uut.gen_bram[4].bram_inst.ram[5] = ref_queue[20];
        end else if (i - 15 == 6) begin
          uut.gen_bram[4].bram_inst.ram[6] = ref_queue[21];
        end else if (i - 15 == 7) begin
          uut.gen_bram[4].bram_inst.ram[7] = ref_queue[22];
        end else if (i - 15 == 8) begin
          uut.gen_bram[4].bram_inst.ram[8] = ref_queue[23];
        end else if (i - 15 == 9) begin
          uut.gen_bram[4].bram_inst.ram[9] = ref_queue[24];
        end else if (i - 15 == 10) begin
          uut.gen_bram[4].bram_inst.ram[10] = ref_queue[25];
        end else if (i - 15 == 11) begin
          uut.gen_bram[4].bram_inst.ram[11] = ref_queue[26];
        end else if (i - 15 == 12) begin
          uut.gen_bram[4].bram_inst.ram[12] = ref_queue[27];
        end else if (i - 15 == 13) begin
          uut.gen_bram[4].bram_inst.ram[13] = ref_queue[28];
        end else if (i - 15 == 14) begin
          uut.gen_bram[4].bram_inst.ram[14] = ref_queue[29];
        end else if (i - 15 == 15) begin
          uut.gen_bram[4].bram_inst.ram[15] = ref_queue[30];
        end
      end
    end
    uut.next_queue_size = QueueSize;
    uut.next_state = 0;

    repeat (16) @(posedge CLK);

    // Test Case 2: Replace nodes
    // Replace root node for QUEUE_SIZE times
    $display("\nTest Case 2: Replace Test");
    for (int i = 0; i < QueueSize; i++) begin
      random_value = DataWidth'(($urandom & ((1 << DataWidth) - 1)) % 1025);
      replace(random_value);
      assert (o_data == ref_queue[0])
      else $error("Replace: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
    end

    // Test Case 3: Stress Test
    // stress test, mix operations
    $display("\nTest Case 3: Stress Test");
    for (int i = 0; i < 100; i++) begin
      random_value = DataWidth'(($urandom & ((1 << DataWidth) - 1)) % 1025);
      random_operation = $urandom_range(1, 2);
      case (random_operation)
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

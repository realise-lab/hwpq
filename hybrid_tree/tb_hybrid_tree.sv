module tb_hybrid_tree;
  // Parameters matching the module under test
  localparam integer QueueSize = 12;
  localparam integer DataWidth = 16;
  localparam integer ArraySize = 4;

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
  hybrid_tree #(
      .DATA_WIDTH(DataWidth),
      .QUEUE_SIZE(QueueSize),
      .ARRAY_SIZE(ArraySize)
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
    for (int i = 0; i < QueueSize; i++) begin
      random_value = DataWidth'(($urandom & ((1 << DataWidth) - 1)) % 1025);
      ref_queue.push_back(random_value);
    end
    ref_queue.rsort();

    uut.gen_bram_tree[0].bram_tree_inst.gen_bram[0].bram_inst.ram[0] = ref_queue[0];
    uut.gen_bram_tree[0].bram_tree_inst.gen_bram[1].bram_inst.ram[0] = ref_queue[4];
    uut.gen_bram_tree[0].bram_tree_inst.gen_bram[1].bram_inst.ram[1] = ref_queue[5];
    uut.gen_bram_tree[1].bram_tree_inst.gen_bram[0].bram_inst.ram[0] = ref_queue[1];
    uut.gen_bram_tree[1].bram_tree_inst.gen_bram[1].bram_inst.ram[0] = ref_queue[6];
    uut.gen_bram_tree[1].bram_tree_inst.gen_bram[1].bram_inst.ram[1] = ref_queue[7];
    uut.gen_bram_tree[2].bram_tree_inst.gen_bram[0].bram_inst.ram[0] = ref_queue[2];
    uut.gen_bram_tree[2].bram_tree_inst.gen_bram[1].bram_inst.ram[0] = ref_queue[8];
    uut.gen_bram_tree[2].bram_tree_inst.gen_bram[1].bram_inst.ram[1] = ref_queue[9];
    uut.gen_bram_tree[3].bram_tree_inst.gen_bram[0].bram_inst.ram[0] = ref_queue[3];
    uut.gen_bram_tree[3].bram_tree_inst.gen_bram[1].bram_inst.ram[0] = ref_queue[10];
    uut.gen_bram_tree[3].bram_tree_inst.gen_bram[1].bram_inst.ram[1] = ref_queue[11];

    repeat (16) @(posedge CLK);

    // Test Case: Replace nodes
    $display("\nReplace Test");
    for (int i = 0; i < 20; i++) begin
      random_value = DataWidth'(($urandom & ((1 << DataWidth) - 1)) % 1025);
      replace(random_value);
      assert (o_data == ref_queue[0])
      else $error("Replace: Node f value mismatch -> expected %d, got %d", ref_queue[0], o_data);
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

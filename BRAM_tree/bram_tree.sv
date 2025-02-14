module bram_tree #(
    parameter integer QUEUE_SIZE = 31,
    parameter integer DATA_WIDTH = 16
) (
    input  logic                  CLK,
    input  logic                  RSTn,
    // Inputs
    input  logic                  i_wrt,    // Write/insert command
    input  logic                  i_read,   // Read/pop command
    input  logic [DATA_WIDTH-1:0] i_data,   // Data to be inserted (or used for replace)
    // Outputs
    output logic                  o_full,   // High if the heap is full
    output logic                  o_empty,  // High if the heap is empty
    output logic [DATA_WIDTH-1:0] o_data    // Output data (popped value)
);

  //-------------------------------------------------------------------------
  // Local parameters
  //-------------------------------------------------------------------------
  localparam integer TREE_DEPTH = $clog2(QUEUE_SIZE + 1); // depth of the tree calculated from the queue size
                                                      // = how many BRAMs are needed
  localparam integer BRAM_WIDTH = 18; // width of the BRAMs, as Xilinx BRAMs are only supported for width of
                                      // 0, 1, 2, 4, 9, 18, 36, 72
  localparam integer BRAM_DEPTH = 1024;  // depth of the BRAMs, 18 Kb = 18 * 1024 bits
  localparam integer NODES_NEEDED = (1 << (TREE_DEPTH + 1)) - 1; // number of actual slots needed for the queue
                                                                 // to store the heap, need to caculate this so
                                                                 // that we could take any arbitrary queue size
  localparam integer COMPARATORS_NEEDED = TREE_DEPTH / 2; // number of comparators needed for the heap
  localparam integer ADDRESS_WIDTH = $clog2(BRAM_DEPTH);  // width for the address/index of the BRAMs
  localparam integer COUNTER_WIDTH = $clog2(NODES_NEEDED);  // width for the counter of the queue size

  //-------------------------------------------------------------------------
  // Internal used wires and registers
  //-------------------------------------------------------------------------

  // Memory used wires and registers
  logic [     ADDRESS_WIDTH-1:0] addr_a            [        TREE_DEPTH];
  logic [     ADDRESS_WIDTH-1:0] addr_b            [        TREE_DEPTH];
  logic [        DATA_WIDTH-1:0] dout_a            [        TREE_DEPTH];
  logic [        DATA_WIDTH-1:0] dout_b            [        TREE_DEPTH];
  logic [        DATA_WIDTH-1:0] din_a             [        TREE_DEPTH];
  logic [        DATA_WIDTH-1:0] din_b             [        TREE_DEPTH];
  logic [$clog2(DATA_WIDTH)-1:0] we_a              [        TREE_DEPTH];
  logic [$clog2(DATA_WIDTH)-1:0] we_b              [        TREE_DEPTH];
  logic                          en_a              [        TREE_DEPTH];
  logic                          en_b              [        TREE_DEPTH];

  logic [     ADDRESS_WIDTH-1:0] next_addr_a       [        TREE_DEPTH];
  logic [     ADDRESS_WIDTH-1:0] next_addr_b       [        TREE_DEPTH];
  logic [        DATA_WIDTH-1:0] next_dout_a       [        TREE_DEPTH];
  logic [        DATA_WIDTH-1:0] next_dout_b       [        TREE_DEPTH];
  logic [        DATA_WIDTH-1:0] next_din_a        [        TREE_DEPTH];
  logic [        DATA_WIDTH-1:0] next_din_b        [        TREE_DEPTH];
  logic [$clog2(DATA_WIDTH)-1:0] next_we_a         [        TREE_DEPTH];
  logic [$clog2(DATA_WIDTH)-1:0] next_we_b         [        TREE_DEPTH];
  logic                          next_en_a         [        TREE_DEPTH];
  logic                          next_en_b         [        TREE_DEPTH];

  // Comparator used wires and registers
  logic [        DATA_WIDTH-1:0] old_parent        [COMPARATORS_NEEDED];
  logic [        DATA_WIDTH-1:0] old_left_child    [COMPARATORS_NEEDED];
  logic [        DATA_WIDTH-1:0] old_right_child   [COMPARATORS_NEEDED];
  logic [        DATA_WIDTH-1:0] new_parent        [COMPARATORS_NEEDED];
  logic [        DATA_WIDTH-1:0] new_left_child    [COMPARATORS_NEEDED];
  logic [        DATA_WIDTH-1:0] new_right_child   [COMPARATORS_NEEDED];

  // Size counter to keep track of the number of nodes in the queue
  logic [     COUNTER_WIDTH-1:0] queue_size;
  logic [     COUNTER_WIDTH-1:0] next_queue_size;

  // Level tracker
  logic [ADDRESS_WIDTH-1:0] current_level     [COMPARATORS_NEEDED];
  logic [ADDRESS_WIDTH-1:0] next_level        [COMPARATORS_NEEDED];
  logic                          current_even_flag;
  logic                          next_even_flag;

  // integers for iteration
  integer lvl, itr;

  //-------------------------------------------------------------------------
  // FSM state declaration
  //-------------------------------------------------------------------------
  typedef enum logic [3:0] {
    IDLE             = 4'd0,
    PROCESS_EVEN     = 4'd1,
    PROCESS_ODD      = 4'd2,
    READ_MEM         = 4'd3,
    COMPARE_AND_SWAP = 4'd4,
    WRITE_MEM        = 4'd5,
    ENQUEUE          = 4'd6,
    DEQUEUE          = 4'd7,
    REPLACE          = 4'd8
  } state_t;
  state_t current_state, next_state;

  //-------------------------------------------------------------------------
  // Memory declaration and initialization
  //-------------------------------------------------------------------------
  genvar i;
  generate
    for (i = 0; i < TREE_DEPTH; i++) begin : gen_bram
      RAMB18E2 #(
          // DOA_REG, DOB_REG: Optional output register (0, 1)
          .DOA_REG(0),
          .DOB_REG(0),
          // READ_WIDTH_A/B: Read width per port
          .READ_WIDTH_A(BRAM_WIDTH),
          .READ_WIDTH_B(BRAM_WIDTH),
          // WRITE_WIDTH_A/B: Write width per port
          .WRITE_WIDTH_A(BRAM_WIDTH),
          .WRITE_WIDTH_B(BRAM_WIDTH)
      ) RAMB18E2_inst (
          // Port A Address/Control Signals inputs: Port A address and control signals
          .ADDRARDADDR  (addr_a[i]),  // 14-bit input: A/Read port address
          .ADDRENA      (1'b1),       // 1-bit input: Active-High A/Read port address enable
          .CLKARDCLK    (CLK),        // 1-bit input: A/Read port clock
          .ENARDEN      (en_a[i]),    // 1-bit input: Port A enable/Read enable
          .WEA          (we_a[i]),    // 2-bit input: Port A write enable
          // Port A Data inputs: Port A data
          .DINADIN      (din_a[i]),   // 16-bit input: Port A data/LSB data
          .DINPADINP    (2'b0),
          // Port A Data outputs: Port A data
          .DOUTADOUT    (dout_a[i]),  // 16-bit output: Port A data/LSB data
          .DOUTPADOUTP  (2'b0),
          // Port B Address/Control Signals inputs: Port B address and control signals
          .ADDRBWRADDR  (addr_b[i]),  // 14-bit input: B/Write port address
          .ADDRENB      (1'b1),       // 1-bit input: Active-High B/Write port address enable
          .CLKBWRCLK    (CLK),        // 1-bit input: B/Write port clock
          .ENBWREN      (en_b[i]),    // 1-bit input: Port B enable/Write enable
          .WEBWE        (we_b[i]),    // 4-bit input: Port B write enable/Write enable
          // Port B Data inputs: Port B data
          .DINBDIN      (din_b[i]),   // 16-bit input: Port B data/MSB data
          .DINPBDINP    (2'b0),
          // Port B Data outputs: Port B data
          .DOUTBDOUT    (dout_b[i]),  // 16-bit output: Port B data/MSB data
          .DOUTPBDOUTP  (2'b0),
          // Unused ports (tied to default values)
          .REGCEAREGCE  (1'b0),       // Disable output register for Port A
          .REGCEB       (1'b0),       // Disable output register for Port B
          .RSTRAMARSTRAM(1'b0),       // No reset for Port A
          .RSTRAMB      (1'b0),       // No reset for Port B
          .RSTREGARSTREG(1'b0),       // No reset for Port A register
          .RSTREGB      (1'b0),       // No reset for Port B register
          .SLEEP        (1'b0),       // Disable sleep mode

          // Cascade ports
          .CASDINA        (16'b0),  // Tie to 0
          .CASDINB        (16'b0),  // Tie to 0
          .CASDINPA       (2'b0),   // Tie to 0
          .CASDINPB       (2'b0),   // Tie to 0
          .CASDOUTA       (),       // Leave unconnected
          .CASDOUTB       (),       // Leave unconnected
          .CASDOUTPA      (),       // Leave unconnected
          .CASDOUTPB      (),       // Leave unconnected
          .CASDIMUXA      (1'b0),   // Disable cascade input mux for Port A
          .CASDIMUXB      (1'b0),   // Disable cascade input mux for Port B
          .CASDOMUXA      (1'b0),   // Disable cascade output mux for Port A
          .CASDOMUXB      (1'b0),   // Disable cascade output mux for Port B
          .CASOREGIMUXA   (1'b0),   // Disable cascade registered output mux for Port A
          .CASOREGIMUXB   (1'b0),   // Disable cascade registered output mux for Port B
          .CASDOMUXEN_A   (1'b0),   // Disable cascade output mux enable for Port A
          .CASDOMUXEN_B   (1'b0),   // Disable cascade output mux enable for Port B
          .CASOREGIMUXEN_A(1'b0),   // Disable cascade registered output mux enable for Port A
          .CASOREGIMUXEN_B(1'b0)    // Disable cascade registered output mux enable for Port B
      );
    end
  endgenerate

  //-------------------------------------------------------------------------
  // Comparator instantiation
  //-------------------------------------------------------------------------
  genvar j;
  generate
    for (j = 0; j < COMPARATORS_NEEDED; j++) begin : gen_comparator
      comparator #(
          .DATA_WIDTH(DATA_WIDTH)
      ) comparator_inst (
          .i_parent(old_parent[j]),
          .i_left_child(old_left_child[j]),
          .i_right_child(old_right_child[j]),
          .o_parent(new_parent[j]),
          .o_left_child(new_left_child[j]),
          .o_right_child(new_right_child[j])
      );
    end
  endgenerate

  //-------------------------------------------------------------------------
  // Assignments for status and output.
  //-------------------------------------------------------------------------
  assign o_full  = (queue_size == QUEUE_SIZE);
  assign o_empty = (queue_size == 0);
  assign o_data  = dout_a[0];

  //-------------------------------------------------------------------------
  // FSM
  //-------------------------------------------------------------------------
  always_ff @(posedge CLK or negedge RSTn) begin : fsm_seq
    if (!RSTn) begin
      current_state <= IDLE;
      current_even_flag <= 1'b1;
    end else begin
      current_state <= next_state;
      current_even_flag <= next_even_flag;
    end
  end

  always_comb begin : fsm_comb
    next_state = IDLE;  // default next state, latch preventing
    next_even_flag = current_even_flag;
    case (current_state)
      IDLE: begin
        next_state = PROCESS_EVEN;
        if (i_wrt && !i_read) begin  // enqueue
          next_state = ENQUEUE;
        end else if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      PROCESS_EVEN: begin
        next_state = READ_MEM;
        if (i_wrt && !i_read) begin  // enqueue
          next_state = ENQUEUE;
        end else if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      PROCESS_ODD: begin
        next_state = READ_MEM;
        if (i_wrt && !i_read) begin  // enqueue
          next_state = ENQUEUE;
        end else if (!i_wrt && i_read) begin  // dequeue
          next_state = DEQUEUE;
        end else if (i_wrt && i_read) begin  // replace
          next_state = REPLACE;
        end
      end

      READ_MEM: begin
        next_state = COMPARE_AND_SWAP;
      end

      COMPARE_AND_SWAP: begin
        next_state = WRITE_MEM;
      end

      WRITE_MEM: begin
        if (current_even_flag) begin
          next_state = PROCESS_ODD;
          next_even_flag = 1'b0;
        end else begin
          next_state = PROCESS_EVEN;
          next_even_flag = 1'b1;
        end
      end

      ENQUEUE: begin
        next_state = PROCESS_EVEN;
      end

      DEQUEUE: begin
        next_state = PROCESS_EVEN;
      end

      REPLACE: begin
        next_state = PROCESS_EVEN;
      end

      default: begin
        next_state = IDLE;
      end
    endcase
  end

  //-------------------------------------------------------------------------
  // Queue size counter
  //-------------------------------------------------------------------------
  always_ff @(posedge CLK or negedge RSTn) begin : queue_size_seq
    if (!RSTn) begin
      queue_size <= 0;
    end else begin
      queue_size <= next_queue_size;
    end
  end

  always_comb begin : queue_size_counter_comb
    next_queue_size = queue_size;
    if (i_wrt && !i_read) begin
      next_queue_size = queue_size + 1;
    end else if (!i_wrt && i_read) begin
      next_queue_size = queue_size - 1;
    end
  end

  //-------------------------------------------------------------------------
  // BRAM read&write, heap management
  //-------------------------------------------------------------------------
  always_ff @(posedge CLK or negedge RSTn) begin : bram_seq
    if (!RSTn) begin
      for (int i = 0; i < TREE_DEPTH; i++) begin
        addr_a[i] <= 0;
        addr_b[i] <= 0;
        din_a[i]  <= 0;
        din_b[i]  <= 0;
        we_a[i]   <= 0;
        we_b[i]   <= 0;
        en_a[i]   <= 0;
        en_b[i]   <= 0;
      end
    end else begin
      for (int i = 0; i < TREE_DEPTH; i++) begin
        addr_a[i] <= next_addr_a[i];
        addr_b[i] <= next_addr_b[i];
        dout_a[i] <= next_dout_a[i];
        dout_b[i] <= next_dout_b[i];
        din_a[i]  <= next_din_a[i];
        din_b[i]  <= next_din_b[i];
        we_a[i]   <= next_we_a[i];
        we_b[i]   <= next_we_b[i];
        en_a[i]   <= next_en_a[i];
        en_b[i]   <= next_en_b[i];
      end
    end
  end

  always_comb begin : bram_comb
    for (int i = 0; i < TREE_DEPTH; i++) begin : bram_comb_default  // latch preventation
      next_addr_a[i] = addr_a[i];
      next_addr_b[i] = addr_b[i];
      next_dout_a[i] = dout_a[i];
      next_dout_b[i] = dout_b[i];
      next_din_a[i]  = din_a[i];
      next_din_b[i]  = din_b[i];
      next_we_a[i]   = we_a[i];
      next_we_b[i]   = we_b[i];
      next_en_a[i]   = en_a[i];
      next_en_b[i]   = en_b[i];
    end
    case (current_state)
      IDLE: begin
      end

      PROCESS_EVEN: begin
        // Setup read addresses for even levels
        for (int i = 0; i < TREE_DEPTH; i += 2) begin
          next_addr_a[i] = current_level[i/2];  // Parent address
          next_addr_b[i] = (current_level[i/2] << 1) + 1;  // Left child address
          if (i + 1 < TREE_DEPTH) begin
            next_addr_a[i+1] = (current_level[i/2] << 1) + 2;  // Right child address
          end
          next_en_a[i] = 1'b1;
          next_en_b[i] = 1'b1;
          next_we_a[i] = '0;  // Read mode
          next_we_b[i] = '0;  // Read mode
        end
      end

      PROCESS_ODD: begin
        // Setup read addresses for odd levels
        for (int i = 1; i < TREE_DEPTH; i += 2) begin
          next_addr_a[i] = current_level[i/2];  // Parent address
          next_addr_b[i] = (current_level[i/2] << 1) + 1;  // Left child address
          if (i + 1 < TREE_DEPTH) begin
            next_addr_a[i+1] = (current_level[i/2] << 1) + 2;  // Right child address
          end
          next_en_a[i] = 1'b1;
          next_en_b[i] = 1'b1;
          next_we_a[i] = '0;  // Read mode
          next_we_b[i] = '0;  // Read mode
        end
      end

      READ_MEM: begin
        // Data will be available in dout_a and dout_b in the next cycle
        // Store the read values for comparison
        for (int i = 0; i < COMPARATORS_NEEDED; i++) begin
          if (current_even_flag) begin
            old_parent[i] = dout_a[i*2];
            old_left_child[i] = dout_b[i*2];
            old_right_child[i] = (i * 2 + 1 < TREE_DEPTH) ? dout_a[i*2+1] : '0;
          end else begin
            old_parent[i] = dout_a[i*2+1];
            old_left_child[i] = dout_b[i*2+1];
            old_right_child[i] = (i * 2 + 2 < TREE_DEPTH) ? dout_a[i*2+2] : '0;
          end
        end
      end

      COMPARE_AND_SWAP: begin
        // Comparator outputs are automatically connected through generate block
        // Prepare write enables and addresses for writing back results
        for (int i = 0; i < TREE_DEPTH; i++) begin
          if ((current_even_flag && (i % 2 == 0)) || (!current_even_flag && (i % 2 == 1))) begin
            next_addr_a[i] = addr_a[i];  // Keep the same addresses
            next_addr_b[i] = addr_b[i];
            next_we_a[i]   = '1;  // Enable writing
            next_we_b[i]   = '1;
            next_din_a[i]  = new_parent[i/2];
            next_din_b[i]  = new_left_child[i/2];
            if (i + 1 < TREE_DEPTH) begin
              next_din_a[i+1] = new_right_child[i/2];
            end
          end
        end
      end

      WRITE_MEM: begin
        // Reset write enables
        for (int i = 0; i < TREE_DEPTH; i++) begin
          next_we_a[i] = '0;
          next_we_b[i] = '0;
        end
        // Update level counters for next comparison
        for (int i = 0; i < COMPARATORS_NEEDED; i++) begin
          if (current_even_flag) begin
            next_level[i] = current_level[i] + 1;
          end else begin
            next_level[i] = current_level[i] + 1;
          end
        end
      end

      ENQUEUE: begin  // port a read from head, port b write into tail
        next_addr_a[0] = '0;  // top level bram port a read from head
        next_addr_b[TREE_DEPTH-1] = (1 << TREE_DEPTH) - 1; // bottom level bram port b write into tail
        next_din_a[0] = din_a[0];  // top level bram port a input data unchange
        next_din_b[TREE_DEPTH-1] = i_data;  // bottom level bram port b write input data
        next_we_a[0] = '0;  // top level bram port a write disable
        next_we_b[TREE_DEPTH-1] = '1;  // bottom level bram port b write enable
        next_en_a[0] = 1'b1;  // top level bram port a enable
        next_en_b[TREE_DEPTH-1] = 1'b1;  // bottom level bram port b enable
      end

      DEQUEUE: begin  // read from port a, write 0 into port b
        next_addr_a[0] = '0;  // port a read from head
        next_addr_b[0] = '0;  // port b write into head
        next_din_a[0]  = din_a[0];  // port a input data unchange
        next_din_b[0]  = '0;  // port b input data unchange
        next_we_a[0]   = '0;  // port a write disable
        next_we_b[0]   = '1;  // port b write enable
        next_en_a[0]   = 1'b1;  // port a enable
        next_en_b[0]   = 1'b1;  // port b enable
      end

      REPLACE: begin  // read from port a, write input data into port b
        next_addr_a[0] = '0;  // port a read from head
        next_addr_b[0] = '0;  // port b write into head
        next_din_a[0]  = din_a[0];  // port a input data unchange
        next_din_b[0]  = i_data;  // port b input data replace
        next_we_a[0]   = '0;  // port a write disable
        next_we_b[0]   = '1;  // port b write enable
        next_en_a[0]   = 1'b1;  // port a enable
        next_en_b[0]   = 1'b1;  // port b enable
      end

      default: begin
      end
    endcase
  end

endmodule

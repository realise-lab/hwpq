module bram_tree #(
    parameter TREE_DEPTH = 4,
    parameter DATA_WIDTH = 32
) (
    input logic clk,
    input logic rst,
    input logic replace,
    input logic [DATA_WIDTH-1:0] new_item,
    output logic [DATA_WIDTH-1:0] top_item
);

  // BRAM interface signals
  logic [DATA_WIDTH-1:0] bram_addr_a[0:TREE_DEPTH-1];
  logic [DATA_WIDTH-1:0] bram_addr_b[0:TREE_DEPTH-1];
  logic [DATA_WIDTH-1:0] bram_din_a[0:TREE_DEPTH-1];
  logic [DATA_WIDTH-1:0] bram_din_b[0:TREE_DEPTH-1];
  logic bram_we_a[0:TREE_DEPTH-1];
  logic bram_we_b[0:TREE_DEPTH-1];
  logic [DATA_WIDTH-1:0] bram_dout_a[0:TREE_DEPTH-1];
  logic [DATA_WIDTH-1:0] bram_dout_b[0:TREE_DEPTH-1];

  // Comparator signals
  logic [DATA_WIDTH-1:0] parent[0:(1 << (TREE_DEPTH - 1)) - 2];
  logic [DATA_WIDTH-1:0] left_child[0:(1 << (TREE_DEPTH - 1)) - 2];
  logic [DATA_WIDTH-1:0] right_child[0:(1 << (TREE_DEPTH - 1)) - 2];
  logic [DATA_WIDTH-1:0] new_parent[0:(1 << (TREE_DEPTH - 1)) - 2];
  logic [DATA_WIDTH-1:0] new_left_child[0:(1 << (TREE_DEPTH - 1)) - 2];
  logic [DATA_WIDTH-1:0] new_right_child[0:(1 << (TREE_DEPTH - 1)) - 2];

  // Generate BRAMs for each level of the tree
  genvar i;
  generate
    for (i = 0; i < TREE_DEPTH; i++) begin : BRAM_gen
      xilinx_true_dual_port_read_first_1_clock_ram #(
          .RAM_WIDTH(DATA_WIDTH),
          .RAM_DEPTH(2 ** i),
          .RAM_PERFORMANCE("LOW_LATENCY"),
          .INIT_FILE("")
      ) bram (
          .addra(bram_addr_a[i]),  // Port A address bus, width determined from RAM_DEPTH
          .addrb(bram_addr_b[i]),  // Port B address bus, width determined from RAM_DEPTH
          .dina(bram_din_a[i]),  // Port A RAM input data, width determined from RAM_WIDTH
          .dinb(bram_din_b[i]),  // Port B RAM input data, width determined from RAM_WIDTH
          .clka(clk),  // Clock
          .wea(bram_we_a[i]),  // Port A write enable
          .web(bram_we_b[i]),  // Port B write enable
          .ena(1'b1),       // Port A RAM Enable, for additional power savings, disable port when not in use
          .enb(1'b1),       // Port B RAM Enable, for additional power savings, disable port when not in use
          .rsta(rst),  // Port A output reset (does not affect memory contents)
          .rstb(rst),  // Port B output reset (does not affect memory contents)
          .regcea(1'b0),  // Port A output register enable
          .regceb(1'b0),  // Port B output register enable
          .douta(bram_dout_a[i]),  // Port A RAM output data, width determined from RAM_WIDTH
          .doutb(bram_dout_b[i])  // Port B RAM output data, width determined from RAM_WIDTH
      );
    end
  endgenerate

  generate
    for (i = 0; i < (1 << (TREE_DEPTH - 1)) - 1; i++) begin : comparator_gen
      comparator #(
          .DATA_WIDTH(DATA_WIDTH)
      ) comparator (
          .parent(parent[i]),
          .left_child(left_child[i]),
          .right_child(right_child[i]),
          .new_parent(new_parent[i]),
          .new_left_child(new_left_child[i]),
          .new_right_child(new_right_child[i])
      );
    end
  endgenerate

  enum logic [2:0] {
    IDLE = 3'b000,
    REPLACE = 3'b001,
    EVEN = 3'b010,
    ODD = 3'b011,
    READ = 3'b100,
    WRITE = 3'b101
  } STATE;

  logic even, odd;
  integer level, addr;

  // Synchronized Finite State Machine
  always_ff @(posedge clk) begin
    if (rst) begin
      for (int j = 0; j < (1 << TREE_DEPTH); j++) begin
        bram_addr_a[j] <= '0;
        bram_addr_b[j] <= '0;
        bram_we_a[j]   <= '0;
        bram_din_a[j]  <= '0;
        bram_we_b[j]   <= '0;
        bram_din_b[j]  <= '0;
      end
      for (int k = 0; k < (1 << (TREE_DEPTH - 1)) - 1; k++) begin
        parent[k]          <= '0;
        left_child[k]      <= '0;
        right_child[k]     <= '0;
        new_parent[k]      <= '0;
        new_left_child[k]  <= '0;
        new_right_child[k] <= '0;
      end
      level <= 0;
      addr  <= 0;
      even  <= 0;
      odd   <= 0;
      STATE <= IDLE;
    end else begin
      case (STATE)
        IDLE: begin
          if (replace) begin
            STATE <= REPLACE;
          end else begin
            STATE <= EVEN;
          end
        end

        REPLACE: begin
          addr  <= 0;
          level <= 0;
          even  <= 0;
          odd   <= 0;
          STATE <= EVEN;  //? Maybe should go to EVEN state
        end

        EVEN: begin
          if (replace) begin
            STATE <= REPLACE;
          end else begin
            even  <= 1;
            odd   <= 0;
            STATE <= READ;
          end
        end

        ODD: begin
          if (replace) begin
            STATE <= REPLACE;
          end else begin
            even  <= 0;
            odd   <= 1;
            STATE <= READ;
          end
        end

        READ: begin
          if (replace) begin
            STATE <= REPLACE;
          end else begin
            STATE <= WRITE;
          end
        end

        WRITE: begin
          if (replace) begin
            STATE <= REPLACE;
          end else if (even == 1) begin
            if (level == 2 && addr == 3) begin
              level <= 1;
              addr  <= 0;
              STATE <= ODD;
            end else if (addr == (1 << level) - 1) begin
              level <= level + 2;
              addr  <= 0;
              STATE <= EVEN;
            end else begin
              addr  <= addr + 1;
              STATE <= EVEN;
            end
          end else if (odd == 1) begin
            if (level == 1 && addr == 1) begin
              level <= 0;
              addr  <= 0;
              STATE <= EVEN;
            end else if (addr == (1 << level) - 1) begin
              level <= level + 2;
              addr  <= 0;
              STATE <= ODD;
            end else begin
              addr  <= addr + 1;
              STATE <= ODD;
            end
          end
        end

        default: begin
        end
      endcase
    end
  end

  always_latch begin
    case (STATE)
      IDLE: begin
      end

      REPLACE: begin
        bram_addr_b[0] = '0;
        bram_din_b[0]  = new_item;
        bram_we_b[0]   = '1;
      end

      EVEN: begin
        // close all wea ports just in case 
        for (int k = 0; k < TREE_DEPTH; k++) begin
          bram_we_a[k] = '0;
          bram_we_b[k] = '0;
        end
        // Giving address to BRAMs
        if (level < TREE_DEPTH) begin
          if (level != TREE_DEPTH - 1) begin  //* not equal to second last level, for scaling purpose in future
            if (addr < (1 << level)) begin
              bram_addr_b[level]   = addr;
              bram_addr_a[level+1] = (addr << 1);
              bram_addr_b[level+1] = (addr << 1) + 1;
            end
          end
        end
      end

      ODD: begin
        // close all wea ports just in case 
        for (int k = 0; k < TREE_DEPTH; k++) begin
          bram_we_a[k] = '0;
          bram_we_b[k] = '0;
        end
        // Giving address to BRAMs
        if (level < TREE_DEPTH) begin
          if (level != TREE_DEPTH - 1) begin  //* not equal to second last level, for scaling purpose in future
            if (addr < (1 << level)) begin
              bram_addr_b[level]   = addr;
              bram_addr_a[level+1] = (addr << 1);
              bram_addr_b[level+1] = (addr << 1) + 1;
            end
          end
        end
      end

      READ: begin
        // read from BRAMs
        parent[(1<<level)-1+addr]      = bram_dout_b[level];
        left_child[(1<<level)-1+addr]  = bram_dout_a[level+1];
        right_child[(1<<level)-1+addr] = bram_dout_b[level+1];
        // get results from comparators
        bram_din_b[level]              = new_parent[(1<<level)-1+addr];
        bram_din_a[level+1]            = new_left_child[(1<<level)-1+addr];
        bram_din_b[level+1]            = new_right_child[(1<<level)-1+addr];
      end

      WRITE: begin
        // write into BRAMS
        bram_we_b[level]   = '1;
        bram_we_a[level+1] = '1;
        bram_we_b[level+1] = '1;
      end

      default: begin
      end
    endcase
  end

  // Reserve port A on BRAM 0 to read continously
  assign bram_addr_a[0] = '0;
  assign top_item = bram_dout_a[0];

endmodule

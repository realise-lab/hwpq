module top_tb;
  // Parameters
  localparam CLK_PERIOD = 10;

  // Signals
  logic clk;
  logic [3:0] sw;
  logic [1:0] led;

  // Clock generation
  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  // DUT instantiation
  top dut (
    .CLK(clk),
    .i_sw(sw),
    .o_led(led)
  );

  // Test stimulus
  initial begin
    // Initialize inputs
    sw = 4'b0000;

    // Wait 100ns for initialization
    repeat (10) @(posedge clk);

    // Test Case 1: Write to Port A (sw[0] = 1)
    sw = 4'b1000;
    repeat (10) @(posedge clk);

    // Test Case 2: Read from Port A (sw[1] = 1)
    sw = 4'b0100;
    repeat (10) @(posedge clk);

    // Test Case 3: Write to Port B (sw[2] = 1)
    sw = 4'b0010;
    repeat (10) @(posedge clk);

    // Test Case 4: Read from Port B (sw[3] = 1)
    sw = 4'b0001;
    repeat (10) @(posedge clk);

    // Test Case 5: Simultaneous write to both ports
    sw = 4'b1010;
    repeat (10) @(posedge clk);

    // Test Case 6: Simultaneous read from both ports
    sw = 4'b0101;
    repeat (10) @(posedge clk);

    $display("Simulation completed");
    $finish;
  end

  // Monitor changes
  initial begin
    $monitor("Time=%0t sw=%b led=%b", $time, sw, led);
  end

  // Optional: Dump waveforms
  initial begin
    $dumpfile("top_tb.vcd");
    $dumpvars(0, top_tb);
  end

  // Helper task to display counter values
  task display_counter_values;
    $display("Counter A - Data: %h, Addr: %h", 
            dut.i_data_a, dut.i_addr_a);
    $display("Counter B - Data: %h, Addr: %h", 
            dut.i_data_b, dut.i_addr_b);
  endtask

  // Periodically display counter values
  initial begin
    forever begin
      repeat (10) @(posedge clk);
      display_counter_values();
    end
  end

endmodule 
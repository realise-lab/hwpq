# Define the range of queue sizes to test
# Use the first list for any array-liked architectures
# Use the second list for any tree-liked architectures

# set queue_sizes {4 8 16 32 64 128 256 512 1024 2048 4096 8192 16384}
set queue_sizes {3 7 15 31 63 127 255 511 1023 2047 4095 8191 16383}

set enq_flags {0 1}

set running_device "xcvp1902-vsva6865-2MP-e-L"

# NOTE: Specify the sv file path accordingly, this is the file that will be modified
set sv_file_path "../register_tree/rtl/src/register_tree_cycled.sv"

# NOTE: Set the log file path accordingly, this is the directory that will store the results
set log_file_path "../register_tree/vivado_analysis_results_16bit_cycled"

# Create the directory if it doesn't exist
if {![file exists $log_file_path]} {
    file mkdir $log_file_path
}

foreach enq_flag $enq_flags {
  foreach queue_size $queue_sizes {
    for {set freq 100} {$freq <= 800} {incr freq 50} {
      # Calculate clock period in ns from frequency in MHz
      set clock_period [expr {1000.0 / $freq}]
      
      # Set the clock period constraint
      create_clock -period $clock_period -name clk [get_ports i_CLK]
    }
  }
}
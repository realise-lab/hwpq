set running_device xcvu19p-fsva3824-1-e

# NOTE Specify the sv file path accordingly, this is the file that will be modified
set sv_file_path ./register_tree/rtl/src/register_tree_cycled.sv

# NOTE Set the log file path accordingly, this is the directory that will store the results
set log_file_path ./register_tree/vivado_analysis_results_16bit_cycled_nonproject_parameter_changed

# Create the directory if it doesn't exist
if {![file exists $log_file_path]} {
    file mkdir $log_file_path
}

# Close any open projects
close_project -quiet -delete

# Import the design
read_verilog -sv $sv_file_path

# Run synthesis
synth_design -top register_tree_cycled -part $running_device -generic ENQ_ENA=0 -generic QUEUE_SIZE=511 -flatten_hierarchy full
report_timing_summary -file $log_file_path/post_synth_timing_summary_parameter_changed.rpt
report_utilization -file $log_file_path/post_synth_utilization_parameter_changed.rpt
report_power -file $log_file_path/post_synth_power_parameter_changed.rpt

# Create a system clock
create_clock -period 10 [get_ports i_CLK] -name sys_clk

# Run implementation
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -file $log_file_path/post_route_timing_summary_parameter_changed.rpt
report_utilization -file $log_file_path/post_route_utilization_parameter_changed.rpt
report_power -file $log_file_path/post_route_power_parameter_changed.rpt

# Close the project at the end
close_project

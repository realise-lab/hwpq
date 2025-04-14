set running_device xcvp1902-vsva6865-2MP-e-L

# NOTE Specify the sv file path accordingly, this is the file that will be modified
set sv_file_path ./register_tree/rtl/src/register_tree_cycled.sv

# NOTE Set the log file path accordingly, this is the directory that will store the results
set proj_file_path ./register_tree/vivado_projects/register_tree_cycled
set log_file_path ./register_tree/vivado_analysis_results_16bit_cycled/flow_test

# Create the directory if it doesn't exist
if {![file exists $proj_file_path]} {
    file mkdir $proj_file_path
}

# Create the directory if it doesn't exist
if {![file exists $log_file_path]} {
    file mkdir $log_file_path
}

# Close any open projects
close_project

# Create a new project
create_project -force register_tree_cycled $proj_file_path -part $running_device

# Add source files
add_files -norecurse $sv_file_path
update_compile_order -fileset sources_1

# Set project properties
# set_property generic {ENQ_ENA=0 QUEUE_SIZE=15} [current_fileset]
set_property top register_tree_cycled [current_fileset]

# Run synthesis
launch_runs synth_1
wait_on_run -timeout 30 synth_1

# Generate synthesis reports
open_run synth_1
report_timing_summary -file $log_file_path/post_synth_timing_summary.rpt
report_utilization -file $log_file_path/post_synth_utilization.rpt
report_power -file $log_file_path/post_synth_power.rpt

# Run implementation
launch_runs impl_1 -to_step route_design
wait_on_run -timeout 30 impl_1

# Generate implementation reports
open_run impl_1
report_timing_summary -file $log_file_path/post_route_timing_summary.rpt
report_utilization -file $log_file_path/post_route_utilization.rpt
report_power -file $log_file_path/post_route_power.rpt

close_project

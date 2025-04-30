# Script for running a single parameter configuration in parallel
# This script accepts command line arguments: enq_ena queue_size
# Example: vivado -mode batch -source synth_design_param_sweep_parallel.tcl -tclargs 0 16 1023

# Get parameters from command line arguments
if {$argc < 4} {
  puts "Error: This script requires four arguments: Architecture name, ENQ_ENA, DATA_WIDTH, and QUEUE_SIZE"
  puts "Usage: vivado -mode batch -source synth_design_param_sweep_parallel.tcl -tclargs <ARCHITECTURE_NAME> <ENQ_ENA> <DATA_WIDTH> <QUEUE_SIZE>"
  exit 1
}

set architecture_name [lindex $argv 0]
set enq_ena [lindex $argv 1]
set data_width [lindex $argv 2]
set queue_size [lindex $argv 3]

# NOTE - Set the device to use
# set running_device xcvu19p-fsva3824-1-e
set running_device xcau25p-ffvb676-1-e

# NOTE - Set the number of threads to use
set_param general.maxThreads 16

# NOTE - File paths - change accordingly for design under test - use absolute path
# Get the current script directory and navigate to project root
set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir ".."]]
set sv_file_path [file join $project_root "hwpq" $architecture_name "rtl" "src" "${architecture_name}.sv"]
set base_log_path [file join $project_root "hwpq" $architecture_name "vivado_analysis_results_16bit_xcau25p"]

# Clock frequency values
set clock_freq_values {100 150 200 250 300 350 400 450 500 550 600 650 700 750 800}

# Create log directories
if {![file exists $base_log_path]} {
  file mkdir $base_log_path
}

set log_dir "${base_log_path}/enqueue_${enq_ena}"
if {![file exists $log_dir]} {
  file mkdir $log_dir
}

# Close any open projects that may be caused by the previous run
close_project -quiet -delete

# Read the sv file
read_verilog -sv $sv_file_path

# Set the log directory
set log_dir "${base_log_path}/enqueue_${enq_ena}"

# Create log file for this queue size
set log_file "${log_dir}/vivado_analysis_on_queue_size_${queue_size}.txt"

# Initialize or clear log file
set fileId [open $log_file "w"]
puts $fileId "Analysis for QUEUE_SIZE = ${queue_size}, ENQ_ENA = ${enq_ena}\n"
close $fileId

# Now iterate through clock frequencies for this specific ENQ_ENA and QUEUE_SIZE combination
foreach clock_freq $clock_freq_values {
  # Calculate the clock period in ns
  set clock_period [expr {1000.0 / $clock_freq}]

  puts "\n=========================================================="
  puts "Running synthesis with parameters:"
  puts "  ENQ_ENA = $enq_ena"
  puts "  QUEUE_SIZE = $queue_size"
  puts "  Clock Frequency = ${clock_freq} MHz (period = ${clock_period} ns)"
  puts "==========================================================\n"

  # Record start time for synthesis
  set synth_start_time [clock seconds]

  # NOTE - Run synthesis - Adjust the top module name accordingly
  synth_design -top $architecture_name -part $running_device -generic ENQ_ENA=$enq_ena -generic DATA_WIDTH=$data_width -generic QUEUE_SIZE=$queue_size -flatten_hierarchy full

  # Record end time for synthesis
  set synth_end_time [clock seconds]

  # Calculate the synthesis duration
  set synth_duration [expr $synth_end_time - $synth_start_time]
  if {$synth_duration > 60} {
    set minutes [expr int($synth_duration / 60)]
    set seconds [expr $synth_duration % 60]
    set synth_duration_str "${minutes}m ${seconds}s"
  } else {
    set synth_duration_str "${synth_duration}s"
  }

  # Create a system clock with the specified frequency
  create_clock -period $clock_period [get_ports i_CLK] -name sys_clk

  # Record start time for implementation
  set impl_start_time [clock seconds]

  # Run implementation with explicit directives to improve stability
  opt_design
  place_design
  phys_opt_design
  route_design

  # Record end time for implementation
  set impl_end_time [clock seconds]

  # Calculate the implementation duration
  set impl_duration [expr $impl_end_time - $impl_start_time]
  if {$impl_duration > 60} {
    set minutes [expr int($impl_duration / 60)]
    set seconds [expr $impl_duration % 60]
    set impl_duration_str "${minutes}m ${seconds}s"
  } else {
    set impl_duration_str "${impl_duration}s"
  }

  # Extract utilization data
  set utilization_report [report_utilization -return_string]

  # Extract CLB LUTs and Registers usage
  set in_section_1 0
  foreach line [split $utilization_report "\n"] {
    if {[regexp {^1\. CLB Logic} $line]} {
      set in_section_1 1
    } elseif {[regexp {^\d+\.} $line]} {
      set in_section_1 0
    }

    if {$in_section_1} {
      if {[regexp {\|\s*CLB LUTs\s*\|\s*([0-9]+)\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*([<0-9\.]+)\s*\|} $line match luts_used luts_util]} {
        set clb_luts_used $luts_used
        set clb_luts_util $luts_util
      }
      if {[regexp {\|\s*CLB Registers\s*\|\s*([0-9]+)\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*([<0-9\.]+)\s*\|} $line match registers_used registers_util]} {
        set clb_registers_used $registers_used
        set clb_registers_util $registers_util
      }
    }
  }

  # Extract BRAM usage
  set in_section_3 0
  foreach line [split $utilization_report "\n"] {
    if {[regexp {^3\. BLOCKRAM} $line]} {
      set in_section_3 1
    } elseif {[regexp {^\d+\.} $line]} {
      set in_section_3 0
    }

    if {$in_section_3} {
      if {[regexp {\|\s*Block RAM Tile\s*\|\s*([0-9]+\.?[0-9]*)\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*([<0-9\.]+)\s*\|} $line match bram_used bram_util_percent]} {
        set bram_used $bram_used
        set bram_util_percentage $bram_util_percent
      }
    }
  }

  # Extract power data
  set power_report [report_power -return_string]
  set match [regexp {\|\s*Total On-Chip Power \(W\)\s*\|\s*([0-9\.]+)\s*\|} $power_report full_match total_on_chip_power]

  # Get timing information
  set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]

  # Calculate achieved frequency
  set achieved_frequency [format "%.3f" [expr {1000.0 / ($clock_period - $wns)}]]

  # Append results to the log file
  set fileId [open $log_file "a+"]

  # Print the results in the same format as vivado_analysis_cycled.tcl
  puts $fileId "Frequency: ${clock_freq} MHz -> Synthesis: ${synth_duration_str} -> ${synth_duration}s"
  puts $fileId "Frequency: ${clock_freq} MHz -> Implementation: ${impl_duration_str} -> ${impl_duration}s"
  if {$match} {
    puts $fileId "Frequency: ${clock_freq} MHz -> Power: ${total_on_chip_power} W"
  } else {
    puts $fileId "Frequency: ${clock_freq} MHz -> Power: No power report"
  }
  puts $fileId "Frequency: ${clock_freq} MHz -> CLB LUTs Used: ${clb_luts_used}"
  puts $fileId "Frequency: ${clock_freq} MHz -> CLB LUTs Util%: ${clb_luts_util} %"
  puts $fileId "Frequency: ${clock_freq} MHz -> CLB Registers Used: ${clb_registers_used}"
  puts $fileId "Frequency: ${clock_freq} MHz -> CLB Registers Util%: ${clb_registers_util} %"
  if {[info exists bram_used]} {
    puts $fileId "Frequency: ${clock_freq} MHz -> BRAM Util: ${bram_used}"
    puts $fileId "Frequency: ${clock_freq} MHz -> BRAM Util%: ${bram_util_percentage} %"
  } else {
    puts $fileId "Frequency: ${clock_freq} MHz -> BRAM Util: 0"
    puts $fileId "Frequency: ${clock_freq} MHz -> BRAM Util%: 0 %"
  }
  puts $fileId "Frequency: ${clock_freq} MHz -> WNS: ${wns} ns"
  puts $fileId "Frequency: ${clock_freq} MHz -> Achieved Frequency: ${achieved_frequency} MHz"
  puts $fileId "\n"

  # Break the frequency loop if WNS is less than -1 ns
  if {$wns < -1.0} {
    puts $fileId "WNS exceeded -1 ns, finished\n"
    close $fileId
    break
  }

  close $fileId
  close_design -quiet
}

# Close the project to clean up
close_project -delete -quiet

puts "\nAnalysis completed for ENQ_ENA=${enq_ena}, QUEUE_SIZE=${queue_size}"
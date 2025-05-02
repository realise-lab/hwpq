# NOTE - Set the device to use
# set running_device xcvu19p-fsva3824-1-e
set running_device xcau25p-ffvb676-1-e

# NOTE - Set the number of threads to use
set_param general.maxThreads 16

# NOTE - Specify the sv file path accordingly, this is the file that will be modified
set sv_file_path <path_to_your_workspace>/hwpq/hwpq/<architecture_name>/rtl/src/<architecture_name>.sv

# NOTE Set the base log file path accordingly, this is the directory that will store the results
set base_log_path <path_to_your_workspace>/hwpq/hwpq/<architecture_name>/vivado_analysis_results_16bit_cycled

# Define the parameter sweep values
set enq_ena_values {0 1}

# NOTE - Set the queue size values to sweep, odd numbers for tree, even numbers for array
set queue_size_values {3 7 15 31 63 127 255 511 1023 2047}
# set queue_size_values {4 8 16 32 64 128 256 512 1024 2048}

set clock_freq_values {100 150 200 250 300 350 400 450 500 550 600 650 700 750 800}

# Create log directories for each ENQ_ENA value
if {![file exists $base_log_path]} {
  file mkdir $base_log_path
}

# Create log directories for each ENQ_ENA value
foreach enq_ena $enq_ena_values {
  set log_dir "${base_log_path}/enqueue_${enq_ena}"
  if {![file exists $log_dir]} {
    file mkdir $log_dir
  }
}

# Close any open projects that may caused by the previous run
close_project -quiet -delete

# Read the sv file
read_verilog -sv $sv_file_path

# Iterate through all parameter combinations
foreach enq_ena $enq_ena_values {
  # Set the log directory
  set log_dir "${base_log_path}/enqueue_${enq_ena}"
  
  foreach queue_size $queue_size_values {
    # Create log file for this queue size
    set log_file "${log_dir}/vivado_analysis_on_queue_size_${queue_size}.txt"
    
    # Initialize or clear log file
    set fileId [open $log_file "w"]
    puts $fileId "Analysis for QUEUE_SIZE = ${queue_size}, ENQ_ENA = ${enq_ena}\n"
    close $fileId
    
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
      
      # Run synthesis
      synth_design -top <architecture_name> -part $running_device -generic ENQ_ENA=$enq_ena -generic QUEUE_SIZE=$queue_size -flatten_hierarchy full
      
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
      
      # Save synthesis reports
      # report_timing_summary -file ${log_dir}/post_synth_timing_summary_qs${queue_size}_clk${clock_freq}.rpt
      # report_utilization -file ${log_dir}/post_synth_utilization_qs${queue_size}_clk${clock_freq}.rpt
      # report_power -file ${log_dir}/post_synth_power_qs${queue_size}_clk${clock_freq}.rpt
      
      # Create a system clock with the specified frequency
      create_clock -period $clock_period [get_ports i_CLK] -name sys_clk
      
      # Record start time for implementation
      set impl_start_time [clock seconds]
      
      # Run implementation
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
      
      # Save implementation reports
      # report_timing_summary -file ${log_dir}/post_route_timing_summary_qs${queue_size}_clk${clock_freq}.rpt
      # report_utilization -file ${log_dir}/post_route_utilization_qs${queue_size}_clk${clock_freq}.rpt
      # report_power -file ${log_dir}/post_route_power_qs${queue_size}_clk${clock_freq}.rpt
      
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
      
      # Break the frequency loop if WNS is less than -1 ns (same as in vivado_analysis_cycled.tcl)
      if {$wns < -1.0} {
        puts $fileId "WNS exceeded -1 ns, finished\n"
        close $fileId
        break
      }
      
      close $fileId
      
      # Save a brief summary to a central results file
      # set results_log [open "${base_log_path}/all_results_summary.csv" "a+"]
      # if {[file size "${base_log_path}/all_results_summary.csv"] == 0} {
      #   puts $results_log "ENQ_ENA,QUEUE_SIZE,CLOCK_FREQ_MHZ,WNS,TIMING_MET,ACHIEVED_FREQ,CLB_LUTS,CLB_REGS,BRAM,POWER_W"
      # }
      
      # Write the data to the CSV
      # puts $results_log "$enq_ena,$queue_size,$clock_freq,$wns,[expr {$wns >= 0 ? "YES" : "NO"}],$achieved_frequency,$clb_luts_used,$clb_registers_used,[expr {[info exists bram_used] ? $bram_used : 0}],[expr {[info exists total_on_chip_power] ? $total_on_chip_power : 0}]"
      # close $results_log
    }
  }
}

# Close the project
close_project -quiet -delete

# Some indication that we have reached the end
puts "\nParameter sweep completed. Results saved to $base_log_path" 
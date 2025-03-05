# Define the range of TREE_DEPTH and clock frequencies to test
set queue_sizes {7 15 31 63 127 255 511 1023 2047 4095 8191 16383 32767 65535}

# Create the results directory if it doesn't exist
file mkdir ./vivado_hybrid_tree_simple_analysis_results_16bit

# Loop through each QUEUE_SIZE
foreach queue_size $queue_sizes {

    # Open the register_tree.sv file
    set file_id [open "./bram_tree.sv" r+]

    # Read the file content
    set file_content [read $file_id]

    # Replace the parameter QUEUE_SIZE value
    set updated_content [regsub {parameter integer QUEUE_SIZE = \d+} $file_content "parameter integer QUEUE_SIZE = $queue_size"]

    # Rewind the file pointer to the beginning
    seek $file_id 0

    # Write the updated content back to the file
    puts -nonewline $file_id $updated_content

    # Close the file
    close $file_id

    set log_file "./vivado_hybrid_tree_simple_analysis_results_16bit/vivado_analysis_on_queue_size_${queue_size}.txt"

    # Loop through each frequency
    for {set freq 100} {$freq <= 800} {incr freq 50} {

        open_project ./vivado_BRAM_tree/vivado_BRAM_tree.xpr

        # Set the clock period (in nanoseconds)
        set period_ns [expr {1000.0 / $freq}]

        # Reset the previous synthesis result
        reset_run synth_1

        # Start a new synthesis and time how long it takes
        set synth_start_time [clock seconds]
        launch_runs synth_1
        wait_on_run synth_1
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

        # Open the synthesis result
        open_run synth_1

        # Create a timing constraint
        create_clock -name sys_clk -period $period_ns [get_ports CLK]

        # Reset the previous implementation result
        reset_run impl_1

        # Start a new implementation run and time how long it takes
        set impl_start_time [clock seconds]
        launch_runs impl_1
        wait_on_run impl_1
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

        # Open the implementation result
        open_run impl_1

        # Extract the utilization report content
        set utilization_report [report_utilization -return_string]

        # Extract the Util% of CLB LUTs and CLB Registers from the report
        set in_section_1 0
        foreach line [split $utilization_report "\n"] {
            if {[regexp {^1\. CLB Logic} $line]} {
                set in_section_1 1
            } elseif {[regexp {^\d+\.} $line]} {
                set in_section_1 0
            }

            if {$in_section_1} {
                if {[regexp {\|\s*CLB LUTs\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*([0-9]+\.[0-9]+)\s*\|} $line match luts_util]} {
                    set clb_luts_util $luts_util
                }
            }
        }

        # Extract the Util% of Block RAMs from the report
        set in_section_2 0
        foreach line [split $utilization_report "\n"] {
            if {[regexp {^3\. BLOCKRAM} $line]} {
                set in_section_2 1
            } elseif {[regexp {^\d+\.} $line]} {
                set in_section_2 0
            }

            if {$in_section_2} {
                if {[regexp {\|\s*Block RAM Tile\s*\|\s*([0-9]+\.?[0-9]*)\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*([0-9]+\.[0-9]+)\s*\|} $line match bram_util bram_util_percent]} {
                    set bram_util_number $bram_util
                    set bram_util_percentage $bram_util_percent
                }
            }
        }

        # Report power summary and get the total on-chip power
        set power_report [report_power -return_string]
        set match [regexp {\|\s*Total On-Chip Power \(W\)\s*\|\s*([0-9\.]+)\s*\|} $power_report full_match total_on_chip_power]

        # Report timing summary and get the Worst Negative Slack (WNS)
        set timing_report [report_timing_summary -delay_type max -significant_digits 3]

        # Extract WNS from the timing summary
        set wns [get_property SLACK [get_timing_paths]]

        # Calculate the achieved frequency using WNS and target frequency with 3 significant digits
        set achieved_frequency [format "%.3f" [expr {1000.0 / ($period_ns - $wns)}]]

        set fileId [open $log_file "a+"]

        # Print the results to the log file
        puts $fileId "Frequency: ${freq} MHz -> Synthesis: ${synth_duration_str} -> ${synth_duration}s"
        puts $fileId "Frequency: ${freq} MHz -> Implementation: ${impl_duration_str} -> ${impl_duration}s"
        if ($match) {
            puts $fileId "Frequency: ${freq} MHz -> Power: ${total_on_chip_power} W"
        } else {
            puts $fileId "Frequency: ${freq} MHz -> Power: No power report"
        }
        puts $fileId "Frequency: ${freq} MHz -> LUTs Util%: ${clb_luts_util} %"
        puts $fileId "Frequency: ${freq} MHz -> BRAM Util%: ${bram_util_percentage} %"
        puts $fileId "Frequency: ${freq} MHz -> BRAM Util: ${bram_util_number}"
        puts $fileId "Frequency: ${freq} MHz -> WNS: ${wns} ns"
        puts $fileId "Frequency: ${freq} MHz -> Achieved Frequency: ${achieved_frequency} MHz"
        puts $fileId "\n"

        # Break the frequency loop if WNS is less than -1 ns
        if {$wns < -1.0} {
            puts $fileId "WNS exceeded -1 ns, finished"
            close $fileId
            close_project
            break
        }

        close $fileId
        close_project
    }
}

# Open the register_tree.sv file
set file_id [open "./bram_tree.sv" r+]

# Read the file content
set file_content [read $file_id]

# Replace the parameter TREE_DEPTH value
set updated_content [regsub {parameter integer QUEUE_SIZE = \d+} $file_content "parameter integer QUEUE_SIZE = 7"]

# Rewind the file pointer to the beginning
seek $file_id 0

# Write the updated content back to the file
puts -nonewline $file_id $updated_content

# Close the file
close $file_id

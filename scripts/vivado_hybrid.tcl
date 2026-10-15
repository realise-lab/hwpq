# Synthesise hybrid_systolic_heap once, implement it at rising clock targets, and log each point
# in the library sweep format that py-scripts/analysis_py parses.
# Usage: vivado -mode batch -nojournal -nolog -source scripts/vivado_hybrid.tcl \
#          -tclargs <data_width> <tree_queue_size> <result_dir> <work_dir> [tree_count]
# <work_dir> receives the checkpoints and, for the first violating target, the path reports.
# Ports carry no I/O delays, matching the library sweeps: paths to and from pins are untimed.

lassign $argv data_width tree_qs result_dir work_dir tree_count
if {$work_dir eq ""} {
  puts "Usage: -tclargs <data_width> <tree_queue_size> <result_dir> <work_dir> \[tree_count\]"
  exit 1
}
if {$tree_count eq ""} { set tree_count 11 }

set part xcau25p-ffvb676-1-e
set_param general.maxThreads 8

set root [file normalize [file join [file dirname [info script]] ..]]
set src  [file join $root hwpq hybrid_systolic_bram_heap src]

# Capacity as the shared testbench counts it: full trees plus both systolic buffers at threshold.
set systolic_qs 16
set queue_size [expr {$tree_count * $tree_qs + 2 * ($systolic_qs - 2)}]

# A target that misses by more than 1 ns ends the sweep, as in the library sweep.
set clock_freq_values {50 75 100 125 150 175 200 250 300 350 400}

file mkdir $result_dir $work_dir
set log_file [file join $result_dir "vivado_analysis_on_queue_size_${queue_size}.txt"]
set fh [open $log_file w]
puts $fh "Analysis for QUEUE_SIZE = ${queue_size}, DATA_WIDTH = ${data_width}, TREE_QUEUE_SIZE = ${tree_qs}, TREE_COUNT = ${tree_count}\n"
close $fh

proc duration_str {s} {
  if {$s > 60} { return "[expr {$s / 60}]m [expr {$s % 60}]s" }
  return "${s}s"
}

# Worst setup slack between each pair of design regions; regions are matched by cell name.
proc report_region_slack {file} {
  set seq [get_cells -hier -filter {IS_SEQUENTIAL || PRIMITIVE_GROUP == BLOCKRAM}]
  set regions [dict create \
    tree     [filter $seq {NAME =~ g_trees*}] \
    reset    [filter $seq {NAME =~ tree_reset/*}] \
    main_buf [filter $seq {NAME =~ IB_reg* || NAME =~ OB_reg*}] \
    heap_buf [filter $seq {NAME =~ heap_IB_reg* || NAME =~ heap_OB_reg*}]]
  dict set regions glue [filter $seq {NAME !~ g_trees* && NAME !~ tree_reset/* &&
    NAME !~ IB_reg* && NAME !~ OB_reg* && NAME !~ heap_IB_reg* && NAME !~ heap_OB_reg*}]

  set fh [open $file w]
  puts $fh [format "%-10s %-10s %10s %7s  %s" from to slack_ns levels endpoint]
  dict for {from fcells} $regions {
    dict for {to tcells} $regions {
      if {[llength $fcells] == 0 || [llength $tcells] == 0} continue
      set p [get_timing_paths -setup -from $fcells -to $tcells -max_paths 1 -nworst 1 -quiet]
      if {$p eq ""} continue
      puts $fh [format "%-10s %-10s %10.3f %7d  %s" $from $to [get_property SLACK $p] \
        [get_property LOGIC_LEVELS $p] [get_property ENDPOINT_PIN $p]]
    }
  }
  close $fh
}

# Package first: the other files import it.
read_verilog -sv [file join $src hybrid_typedef.sv]
foreach f {rams_tdp_rf_rf.sv bram_tree.sv hybrid_systolic_heap.sv} {
  read_verilog -sv [file join $src $f]
}

set t0 [clock seconds]
synth_design -top hybrid_systolic_heap -part $part -flatten_hierarchy full \
  -verilog_define HYBRID_DATA_WIDTH=$data_width \
  -verilog_define HYBRID_BRAM_TREE_QUEUE_SIZE=$tree_qs \
  -verilog_define HYBRID_TREE_COUNT=$tree_count
set synth_duration [expr {[clock seconds] - $t0}]
set synth_dcp [file join $work_dir synth.dcp]
write_checkpoint -force $synth_dcp
close_design

set detailed 0
foreach clock_freq $clock_freq_values {
  set clock_period [expr {1000.0 / $clock_freq}]
  open_checkpoint $synth_dcp
  create_clock -period $clock_period [get_ports i_CLK] -name sys_clk

  set t0 [clock seconds]
  opt_design
  place_design
  phys_opt_design
  route_design
  set impl_duration [expr {[clock seconds] - $t0}]

  set util [report_utilization -return_string]
  regexp {\|\s*CLB LUTs\s*\|\s*([0-9]+)\s*\|[^|]*\|[^|]*\|[^|]*\|\s*([<0-9.]+)\s*\|} $util -> luts luts_pct
  regexp {\|\s*CLB Registers\s*\|\s*([0-9]+)\s*\|[^|]*\|[^|]*\|[^|]*\|\s*([<0-9.]+)\s*\|} $util -> regs regs_pct
  set bram 0; set bram_pct 0
  regexp {\|\s*Block RAM Tile\s*\|\s*([0-9.]+)\s*\|[^|]*\|[^|]*\|[^|]*\|\s*([<0-9.]+)\s*\|} $util -> bram bram_pct
  set power "No power report"
  if {[regexp {\|\s*Total On-Chip Power \(W\)\s*\|\s*([0-9.]+)\s*\|} [report_power -return_string] -> p]} {
    set power "$p W"
  }
  set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
  set achieved [format "%.3f" [expr {1000.0 / ($clock_period - $wns)}]]

  set fh [open $log_file a]
  set tag "Frequency: ${clock_freq} MHz ->"
  puts $fh "$tag Synthesis: [duration_str $synth_duration] -> ${synth_duration}s"
  puts $fh "$tag Implementation: [duration_str $impl_duration] -> ${impl_duration}s"
  puts $fh "$tag Power: $power"
  puts $fh "$tag CLB LUTs Used: $luts"
  puts $fh "$tag CLB LUTs Util%: $luts_pct %"
  puts $fh "$tag CLB Registers Used: $regs"
  puts $fh "$tag CLB Registers Util%: $regs_pct %"
  puts $fh "$tag BRAM Util: $bram"
  puts $fh "$tag BRAM Util%: $bram_pct %"
  puts $fh "$tag WNS: $wns ns"
  puts $fh "$tag Achieved Frequency: $achieved MHz"
  puts $fh "\n"
  close $fh

  # The first violating target is the one whose critical paths limit Fmax.
  if {$wns < 0 && !$detailed} {
    set detailed 1
    set out [file join $work_dir "${clock_freq}MHz"]
    write_checkpoint -force $out.dcp
    report_timing_summary -max_paths 10 -file $out.summary
    report_timing -max_paths 3 -input_pins -file $out.worst3
    report_timing -max_paths 50 -nworst 1 -unique_pins -file $out.top50
    report_design_analysis -logic_level_distribution -logic_level_dist_paths 2000 -file $out.levels
    report_utilization -file $out.util
    report_region_slack $out.regions
  }

  close_design
  if {$wns < -1.0} {
    set fh [open $log_file a]
    puts $fh "WNS exceeded -1 ns, finished\n"
    close $fh
    break
  }
}

puts "\nAnalysis completed for DATA_WIDTH=${data_width}, QUEUE_SIZE=${queue_size}"

# formal/drive.tcl - read a .cfg, build the model, hand off to verdict.tcl.
#
# Run from the REPO ROOT; every path in a .cfg is repo-relative. formal/run.sh
# sets the environment below and invokes this through the selected backend.
#
#   HWPQ_CFG            path to the config to run                     REQUIRED
#   FORMAL_BACKEND      backend name                                  REQUIRED
#   FORMAL_BACKEND_DIR  where <name>.tcl lives           Default formal/backend
#   HWPQ_SELFTEST       1 = compile the deliberately-broken property  Default 0
#   HWPQ_UNGATED        1 = drop the workaround assumptions           Default 0
#
# The mode plumbing lives here rather than in each config because it is
# identical everywhere: the old per-module scripts repeated it fifteen times.

proc hwpq_env {name default} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return $default
}

set HWPQ_CFG      [hwpq_env HWPQ_CFG ""]
set HWPQ_SELFTEST [hwpq_env HWPQ_SELFTEST 0]
set HWPQ_UNGATED  [hwpq_env HWPQ_UNGATED 0]
set backend_name  [hwpq_env FORMAL_BACKEND ""]
set backend_dir   [hwpq_env FORMAL_BACKEND_DIR [file join formal backend]]

if {$HWPQ_CFG eq ""} {
    puts "FORMAL ERROR: HWPQ_CFG is not set."
    exit 2
}
if {![file exists $HWPQ_CFG]} {
    puts "FORMAL ERROR: no such config: $HWPQ_CFG"
    exit 2
}
if {$backend_name eq ""} {
    puts "FORMAL ERROR: FORMAL_BACKEND is not set."
    exit 2
}

set backend_file [file join $backend_dir "${backend_name}.tcl"]
if {![file exists $backend_file]} {
    puts "FORMAL ERROR: no such backend: $backend_file"
    puts "              see formal/backend/README.md for the contract."
    exit 2
}
source $backend_file

# ---- parse the config -------------------------------------------------------
# Every key may appear at most once except `source` and `param`. An unknown key
# is a hard error: a typo must not silently drop a parameter and quietly change
# what is proven.
set cfg_sources {}
set cfg_params  {}
set cfg(top)                 ""
set cfg(clock)               ""
set cfg(reset)               ""
set cfg(module)              ""
set cfg(allow_bounded)       0
set cfg(expect_cex)          {}
set cfg(expect_cex_ungated)  {}
set cfg(expect_cex_selftest) {}

set fh [open $HWPQ_CFG r]
set lineno 0
array set seen {}
foreach line [split [read $fh] "\n"] {
    incr lineno
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} { continue }
    set key [lindex $line 0]
    set val [string trim [string range $line [string length $key] end]]
    switch -exact -- $key {
        source  { lappend cfg_sources $val }
        param   { lappend cfg_params [lindex $val 0] [lindex $val 1] }
        top - clock - reset - module - allow_bounded -
        expect_cex - expect_cex_ungated - expect_cex_selftest {
            if {[info exists seen($key)]} {
                puts "FORMAL ERROR: ${HWPQ_CFG}:${lineno}: '$key' given twice\
                      (first at line $seen($key)); a silent overwrite would change\
                      what is proved"
                exit 2
            }
            set seen($key) $lineno
            set cfg($key) $val
        }
        default {
            puts "FORMAL ERROR: ${HWPQ_CFG}:${lineno}: unknown key '$key'"
            exit 2
        }
    }
}
close $fh

foreach need {module top clock reset} {
    if {$cfg($need) eq ""} {
        puts "FORMAL ERROR: $HWPQ_CFG has no '$need'"
        exit 2
    }
}
if {[llength $cfg_sources] == 0} {
    puts "FORMAL ERROR: $HWPQ_CFG lists no sources"
    exit 2
}

# ---- verdict settings -------------------------------------------------------
# Loaded BEFORE the build so the elaboration gate is available between steps.
set HWPQ_MODULE        $cfg(module)
set HWPQ_ALLOW_BOUNDED $cfg(allow_bounded)
if {$HWPQ_UNGATED} {
    set HWPQ_EXPECT_CEX $cfg(expect_cex_ungated)
} elseif {$HWPQ_SELFTEST && $cfg(expect_cex_selftest) ne ""} {
    set HWPQ_EXPECT_CEX $cfg(expect_cex_selftest)
} else {
    set HWPQ_EXPECT_CEX $cfg(expect_cex)
}
source formal/verdict.tcl

# ---- modes ------------------------------------------------------------------
set defines {}
if {$HWPQ_SELFTEST} {
    puts "### SELF-TEST MODE: the self-test property is deliberately unprovable."
    lappend defines HWPQ_SELFTEST
}
if {$HWPQ_UNGATED} {
    puts "### UNGATED MODE: workaround assumptions dropped; the recorded"
    puts "###               shortcomings are expected to reproduce."
    lappend defines HWPQ_UNGATED
}

# ---- build ------------------------------------------------------------------
# Gate after each step that can fail. A design that did not elaborate has no
# clock or reset to declare, and the tool's error from trying would end the run
# before the gate could report the real cause.
backend::clear
backend::analyze $cfg_sources $defines
hwpq_elab_gate
backend::elaborate $cfg(top) $cfg_params
hwpq_elab_gate
backend::clock $cfg(clock)
backend::reset $cfg(reset)

hwpq_prove_and_exit

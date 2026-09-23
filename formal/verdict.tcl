# formal/verdict.tcl - shared prove / classify / report / exit tail.
#
# Sourced by formal/drive.tcl after the design is analyzed, elaborated, clocked
# and reset. This file only knows how to prove, classify the result, and decide
# pass/fail. Every tool-specific operation goes through the backend:: contract
#
# CALLER CONTRACT:
#   HWPQ_MODULE          module name, used in the verdict banner.        REQUIRED
#   HWPQ_OUTDIR (env)    where run.sh wants artifacts; defaults to formal/
#   HWPQ_ALLOW_BOUNDED   1 = accept bounded_proven asserts.            Default 0
#   HWPQ_EXPECT_CEX      list of assert leaf-names that are SUPPOSED to fail.
#                        A listed property that proves is a FAILURE; one that
#                        produces a cex is a PASS.                     Default {}
#
# VERSION SENSITIVITY:
#   Property-table filter syntax and status spellings shift between tool
#   releases. That variation is the backend's problem, not this file's: every
#   query here goes through backend::property_list, and a failure to QUERY is a
#   hard error (exit 2), never "nothing found". If a query errors, the backend
#   is the thing to fix.

if {![info exists HWPQ_MODULE]} {
    puts "FORMAL ERROR: caller did not set HWPQ_MODULE before sourcing verdict.tcl"
    exit 2
}
if {![info exists HWPQ_ALLOW_BOUNDED]} { set HWPQ_ALLOW_BOUNDED 0 }
if {![info exists HWPQ_EXPECT_CEX]}    { set HWPQ_EXPECT_CEX    {} }


# hwpq_plist - query the property table, hard-failing on a query error.
proc hwpq_plist {type statuses} {
    if {[catch {set res [backend::property_list $type $statuses]} err]} {
        puts "FORMAL ERROR: backend::property_list failed for type {$type} status {$statuses}"
        puts "FORMAL ERROR: $err"
        puts "FORMAL ERROR: see VERSION SENSITIVITY in formal/verdict.tcl"
        exit 2
    }
    return $res
}

# hwpq_leaf - the bare property name out of a full property path.
#
# Properties are reported as <task>::<module>.<inst>.<generate>.<name>, which is
# DOT-separated. `file tail` splits on "/" and so returns the whole string
# untouched, so an HWPQ_EXPECT_CEX entry could then never match anything.
proc hwpq_leaf {p} {
    return [lindex [split $p .] end]
}

# hwpq_multiple_driven_gate - refuse to prove against a multiply-driven design.
#
# A variable driven from two `always` blocks is a lint nit in simulation: the
# two write ports touch different addresses and the non-blocking assignments
# land on different elements, so nothing is ever observed to go wrong. In formal
# it means the TOOL resolves the drivers, and what it resolves to is not what
# the design computes. Writes stop being reliably observable - a write to
# address 0 need not be there on the next cycle - and every memory-dependent
# property is then decided against contents the tool was free to invent.
#
# The gate runs BEFORE proving. A run against a resolved-driver model does not
# produce a usable result.
proc hwpq_multiple_driven_gate {} {
    puts "\n=== multiple-driver check ======================================"
    if {[catch {set md [backend::design_info multiple_driven]} err]} {
        puts "FORMAL ERROR: backend::design_info multiple_driven failed"
        puts "FORMAL ERROR: $err"
        puts "FORMAL ERROR: see VERSION SENSITIVITY in formal/verdict.tcl"
        exit 2
    }
    if {[llength $md] == 0} {
        puts "    none - every signal has a single driver."
        return
    }
    puts "    MULTIPLY-DRIVEN SIGNALS ([llength $md]):"
    foreach sig $md { puts "        $sig" }
    puts ""
    puts "    The tool resolves these drivers itself, so their values are NOT"
    puts "    the ones the RTL computes. Any property that reads them is decided"
    puts "    against contents the tool chose. Do not prove, do not report, and"
    puts "    do NOT treat a counterexample from such a run as a design defect."
    puts ""
    puts "    Search the elaboration log above for the multiple-driver warnings"
    puts "    to see both drivers and the bit count. The usual cause is a vendor"
    puts "    RAM template with one always block per port; merging them into a"
    puts "    single process is sound wherever both ports share a clock."
    puts "    See the multiply-driven RAM section of formal/docs/results.md."
    puts ""
    puts "    RESULT: FAIL"
    puts ""
    exit 1
}

# hwpq_elab_gate - stop if a build step failed.
#
# drive.tcl calls this after analyze and after elaborate, not only from
# hwpq_prove_and_exit: a design that did not elaborate has no clock or reset to
# declare, and the tool's own error from trying would end the run before this
# could say why.
#
# The "ELABORATION FAILED:" line is what regress.sh keys an elaboration-failure
# row on, in place of the tool's own diagnostic. It counts failed BUILD STEPS,
# not bad source sites: sites are the tool's to report and are not portably
# countable, so a source-error count and a build-step count can legitimately
# disagree.
proc hwpq_elab_gate {} {
    if {[catch {set n [backend::elab_errors]} err]} {
        puts "FORMAL ERROR: backend::elab_errors failed: $err"
        exit 2
    }
    if {$n > 0} {
        puts "\n=== elaboration ================================================"
        puts "    ELABORATION FAILED: $n build step(s) reported errors."
        puts "    The model was not built, so there is nothing to prove. The"
        puts "    tool's own diagnostics are in the log above."
        puts "\n    RESULT: FAIL\n"
        exit 1
    }
}

proc hwpq_group {label items} {
    if {[llength $items] == 0} { return }
    puts "    $label ([llength $items]):"
    foreach p $items { puts "        $p" }
}

# hwpq_prove_and_exit - prove everything, print a verdict, exit 0/1/2.
#
#   0  every assert proven (or an expected cex fired); every cover reachable
#   1  a real proof failure - unexpected cex, missing expected cex,
#      undetermined, unreachable cover, bounded-only with ALLOW_BOUNDED=0, an
#      elaboration error, or a multiply-driven design (both checked BEFORE
#      proving)
#   2  the script itself could not run

proc hwpq_prove_and_exit {} {
    global HWPQ_MODULE HWPQ_ALLOW_BOUNDED HWPQ_EXPECT_CEX

    # Model sanity BEFORE proof effort: a multiply-driven design cannot be
    # proved against, only proved something about. Exits 1 on its own if dirty.
    hwpq_elab_gate
    hwpq_multiple_driven_gate

    # assumption sanity
    puts "\n=== assumption check ==========================================="
    if {[catch {backend::assumption_status} err]} {
        puts "    NOTE: assumption conflict check unavailable here ($err)"
        puts "    NOTE: falling back on the cover set to detect vacuity."
    }

    # prove
    puts "\n=== prove ======================================================"
    backend::prove_all

    # classify
    # Each query passes several spellings so one rename cannot silently drop a
    # whole failure category.
    set a_cex     [hwpq_plist assert {cex}]
    set a_undet   [hwpq_plist assert {undetermined unknown error}]
    set a_bounded [hwpq_plist assert {bounded_proven bounded}]
    set a_proven  [hwpq_plist assert {proven}]
    set c_unreach [hwpq_plist cover  {unreachable}]
    set c_undet   [hwpq_plist cover  {undetermined unknown}]
    set c_ok      [hwpq_plist cover  {covered proven}]

    # expected-cex bookkeeping
    set unexpected_cex {}
    set missing_cex    {}
    foreach p $a_cex {
        if {[lsearch -exact $HWPQ_EXPECT_CEX [hwpq_leaf $p]] < 0} {
            lappend unexpected_cex $p
        }
    }
    foreach want $HWPQ_EXPECT_CEX {
        set hit 0
        foreach p $a_cex { if {[hwpq_leaf $p] eq $want} { set hit 1 } }
        if {!$hit} { lappend missing_cex $want }
    }

    # verdict
    puts "\n=== $HWPQ_MODULE verdict ======================================="
    puts "    asserts: [llength $a_proven] proven, [llength $a_cex] cex,\
[llength $a_bounded] bounded, [llength $a_undet] undetermined"
    puts "    covers : [llength $c_ok] reachable, [llength $c_unreach] UNREACHABLE,\
[llength $c_undet] undetermined"
    if {[llength $HWPQ_EXPECT_CEX] > 0} {
        puts "    expecting cex from: $HWPQ_EXPECT_CEX"
    }

    hwpq_group "unexpected counterexamples"       $unexpected_cex
    hwpq_group "expected cex that did NOT fire"   $missing_cex
    hwpq_group "undetermined asserts"             $a_undet
    hwpq_group "bounded-only asserts"             $a_bounded
    hwpq_group "UNREACHABLE covers"               $c_unreach
    hwpq_group "undetermined covers"              $c_undet

    if {[llength $c_unreach] > 0} {
        puts ""
        puts "    An unreachable cover means an assumption has strangled the"
        puts "    design. Every 'proven' above it is vacuous. Fix the assume"
        puts "    set FIRST - do not raise effort, and do not report this run."
    }

    set fail 0
    if {[llength $unexpected_cex] > 0} { set fail 1 }
    if {[llength $missing_cex]    > 0} { set fail 1 }
    if {[llength $a_undet]        > 0} { set fail 1 }
    if {[llength $c_unreach]      > 0} { set fail 1 }
    if {[llength $c_undet]        > 0} { set fail 1 }
    if {[llength $a_bounded] > 0 && !$HWPQ_ALLOW_BOUNDED} { set fail 1 }

    # An empty assert table means the bind never attached: green by vacuum.
    if {[llength $a_proven] == 0 && [llength $a_cex] == 0 &&
        [llength $a_bounded] == 0 && [llength $a_undet] == 0} {
        puts ""
        puts "    NO ASSERTS FOUND. The bind almost certainly did not attach."
        puts "    Check the module name in formal/bind/<module>_bind.sv and"
        puts "    that the bind file was listed as a source in the .cfg."
        set fail 1
    }

    # artifacts
    # run.sh passes the run's output directory, so the summary lands beside the
    # log and the tool scratch for the same run rather than in a parallel naming
    # scheme of its own. Falling back keeps a hand-invoked run working outside
    # run.sh.
    set outdir "formal"
    set sname  "${HWPQ_MODULE}_summary.txt"
    if {[info exists ::env(HWPQ_OUTDIR)] && $::env(HWPQ_OUTDIR) ne ""} {
        set outdir $::env(HWPQ_OUTDIR)
        set sname  "summary.txt"
    }
    catch { backend::report $outdir $sname }

    if {$fail} { puts "\n    RESULT: FAIL\n" ; exit 1 }
    puts "\n    RESULT: PASS\n"
    exit 0
}

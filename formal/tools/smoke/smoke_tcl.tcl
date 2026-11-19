# Exercises formal/verdict.tcl's decisions against the licence-free `stub`
# backend, so the pass/fail/exit-code logic is validated anywhere. Invoked by
# formal/tools/smoke.sh.
#
# What this does NOT validate: the real property-table filter syntax and status
# spellings, which vary by release and can only be confirmed against the tool.
# That is the backend's half of the contract; see formal/backend/README.md.

set repo [lindex $argv 0]

# Each case runs in a child tclsh so we can observe the exit code. The child
# loads the same stub backend a real run would load, then the real verdict.tcl:
# only the STUB_* globals differ between cases.
#   must  optional regexp the output must also match (-line mode). An exit code
#         alone cannot tell a gate that fired from a run that died for some
#         other reason with the same code.
proc run_case {name expect_rc setup {must ""}} {
    global repo
    set f [file join [file dirname [info script]] "_case.tcl"]
    set fh [open $f w]
    puts $fh "set repo {$repo}"
    puts $fh {source [file join $repo formal backend stub.tcl]}
    puts $fh $setup
    puts $fh {source [file join $repo formal verdict.tcl]}
    puts $fh {hwpq_prove_and_exit}
    close $fh
    catch {exec tclsh $f} out opts
    set rc [dict get $opts -code]
    if {$rc == 0} { set rc 0 } else { set rc [lindex [dict get $opts -errorcode] 2] }
    file delete $f
    if {$rc != $expect_rc} {
        puts "        BAD   $name: expected exit $expect_rc, got $rc"
        return 0
    }
    if {$must ne "" && ![regexp -line -- $must $out]} {
        puts "        BAD   $name: exit $rc as expected, but output lacks /$must/"
        return 0
    }
    puts "        ok    $name (exit $rc)"
    return 1
}

set common {
    set HWPQ_MODULE      smoke
    set HWPQ_EXPECT_CEX  {}
}

set all_ok 1

# 1. everything proven, covers reachable -> 0
set all_ok [expr {$all_ok & [run_case "clean run" 0 "
    set STUB_TABLE \[dict create \
        {type {assert} status {proven}} {a1 a2} \
        {type {cover} status {covered proven}} {c1}\]
    $common"]}]

# 2. an unexpected counterexample -> 1
set all_ok [expr {$all_ok & [run_case "unexpected cex" 1 "
    set STUB_TABLE \[dict create \
        {type {assert} status {cex}} {a_plumbing} \
        {type {cover} status {covered proven}} {c1}\]
    $common"]}]

# 3. an EXPECTED counterexample -> 0 (bug-reproduction mode)
#    Uses a FULLY QUALIFIED property name on purpose. Backends report dotted
#    paths (see formal/backend/README.md), so a short name here would let a
#    broken leaf-extraction pass.
set all_ok [expr {$all_ok & [run_case "expected cex fires" 0 "
    set STUB_TABLE \[dict create \
        {type {assert} status {cex}} {<task>::dut.u_spec.g_x.a_plumbing} \
        {type {cover} status {covered proven}} {c1}\]
    set HWPQ_MODULE smoke
    set HWPQ_EXPECT_CEX {a_plumbing}"]}]

# 4. an expected counterexample that does NOT fire -> 1
set all_ok [expr {$all_ok & [run_case "expected cex missing" 1 "
    set STUB_TABLE \[dict create \
        {type {assert} status {proven}} {<task>::dut.u_spec.g_x.a_plumbing} \
        {type {cover} status {covered proven}} {c1}\]
    set HWPQ_MODULE smoke
    set HWPQ_EXPECT_CEX {a_plumbing}"]}]

# 5. an unreachable cover means vacuity -> 1
set all_ok [expr {$all_ok & [run_case "unreachable cover" 1 "
    set STUB_TABLE \[dict create \
        {type {assert} status {proven}} {a1} \
        {type {cover} status {unreachable}} {c_plumbing_alive}\]
    $common"]}]

# 6. no asserts at all means the bind never attached -> 1
set all_ok [expr {$all_ok & [run_case "no asserts (bind missed)" 1 "
    set STUB_TABLE \[dict create \
        {type {cover} status {covered proven}} {c1}\]
    $common"]}]

# 7. bounded-only, not allowed -> 1
set all_ok [expr {$all_ok & [run_case "bounded-only rejected" 1 "
    set STUB_TABLE \[dict create \
        {type {assert} status {bounded_proven bounded}} {a1} \
        {type {cover} status {covered proven}} {c1}\]
    $common"]}]

# 8. a multiply-driven design -> 1, WITHOUT proving.
#    The property table below is a clean sweep, so anything other than exit 1
#    means the gate did not run or did not stop the run.
set all_ok [expr {$all_ok & [run_case "multiply-driven design rejected" 1 "
    set STUB_MD {bram_inst.ram\[0\] bram_inst.ram\[1\]}
    set STUB_TABLE \[dict create \
        {type {assert} status {proven}} {a1 a2} \
        {type {cover} status {covered proven}} {c1}\]
    $common"]}]

# 9. the gate must not fire on a clean design, and must not swallow a real
#    failure either: an empty driver list with a cex still exits 1 for the cex.
set all_ok [expr {$all_ok & [run_case "clean drivers, real cex still fails" 1 "
    set STUB_MD {}
    set STUB_TABLE \[dict create \
        {type {assert} status {cex}} {a_plumbing} \
        {type {cover} status {covered proven}} {c1}\]
    $common"]}]

# 10. a FAILING driver query is exit 2, not exit 0: never let an unanswerable
#     question read as "clean". This is also the contract in
#     formal/backend/README.md under test: a
#     backend that cannot answer must raise, not return {}.
set all_ok [expr {$all_ok & [run_case "driver query error is a hard error" 2 "
    set STUB_TABLE \[dict create \
        {type {assert} status {proven}} {a1} \
        {type {cover} status {covered proven}} {c1}\]
    $common
    proc backend::design_info {kind} { error {query rejected} }"]}]

# 11. a failed build stops the run BEFORE any property query, and says so on the
#     line regress.sh keys an elaboration-failure row on. property_list is
#     rigged to raise, so a gate that did not stop the run first would exit 2
#     here, not 1.
set all_ok [expr {$all_ok & [run_case "elaboration failure stops the run" 1 "
    set STUB_ELAB_ERRORS 1
    $common
    proc backend::property_list {type statuses} { error {queried a model that was never built} }" {^\s*ELABORATION FAILED:}]}]

exit [expr {$all_ok ? 0 : 1}]

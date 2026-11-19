# formal/backend/stub.tcl - a backend that needs no licence.
#
# Implements the contract in formal/backend/README.md against globals instead of
# a tool, so formal/tools/smoke.sh can exercise verdict.tcl's pass/fail/exit-code
# decisions anywhere. It proves nothing about a design.
#
# Driven by:
#   STUB_TABLE         dict: "type {t} status {s}" -> list of property names
#   STUB_MD            list returned by design_info multiple_driven   Default {}
#   STUB_ELAB_ERRORS   integer returned by elab_errors                Default 0
#
# What this does NOT validate: the real filter syntax and status spellings,
# which vary by release and can only be confirmed against the tool.

namespace eval backend {

    proc clear {} {}

    proc analyze {files defines} {}

    proc elaborate {top params} {}

    proc clock {expr} {}

    proc reset {expr} {}

    proc elab_errors {} {
        global STUB_ELAB_ERRORS
        if {[info exists STUB_ELAB_ERRORS]} { return $STUB_ELAB_ERRORS }
        return 0
    }

    proc prove_all {} {}

    proc property_list {type statuses} {
        global STUB_TABLE
        set filter "type \{$type\} status \{$statuses\}"
        if {[info exists STUB_TABLE] && [dict exists $STUB_TABLE $filter]} {
            return [dict get $STUB_TABLE $filter]
        }
        return {}
    }

    proc design_info {kind} {
        global STUB_MD
        if {[info exists STUB_MD]} { return $STUB_MD }
        return {}
    }

    proc assumption_status {} {}

    proc report {outdir name} {}
}

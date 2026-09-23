# formal/backend/dryrun.tcl - print the build a config would perform, prove nothing.
#
# Exists to show that a .cfg drives the same build its old per-module script
# did: run it over every config and diff the transcripts. Needs no licence.
#
# It stops at the point where proving would begin, so the transcript covers
# exactly the part a config controls.

namespace eval backend {

    proc clear {} { puts "clear" }

    proc analyze {files defines} {
        puts "analyze defines={$defines}"
        foreach f [lsort $files] { puts "    source $f" }
    }

    proc elaborate {top params} {
        puts "elaborate top=$top"
        foreach {n v} $params { puts "    param $n=$v" }
    }

    proc clock {expr} { puts "clock $expr" }

    proc reset {expr} { puts "reset $expr" }

    proc elab_errors {} { return 0 }

    proc prove_all {} {
        puts "prove (stopping here: dryrun)"
        exit 0
    }

    proc property_list {type statuses} { return {} }

    proc design_info {kind} { return {} }

    proc assumption_status {} {}

    proc report {outdir name} {}
}

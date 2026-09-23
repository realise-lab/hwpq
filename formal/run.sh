#!/usr/bin/env bash
#
# Driver for the HWPQ formal suite.
#
#   formal/run.sh <module>              prove it; expect exit 0
#   formal/run.sh --selftest <module>   break one property on purpose;
#                                       expect exit 1
#   formal/run.sh --ungated <module>    drop the workaround assumptions and
#                                       reproduce the recorded shortcomings;
#                                       expect exit 0 (see below)
#   formal/run.sh --all                 every module with a config
#   formal/run.sh --timeout <secs> ...  wall-clock ceiling per configuration
#                                       (default 1800; a run that exceeds it is
#                                       mis-sized, not merely slow)
#
# GATED vs UNGATED
#
# Some proofs hold only under an assumption that papers over a known, recorded
# defect. ASSUME_FILL_FIRST is the one such assumption in this suite. The default
# (gated) run applies it, so work on everything else can continue; --ungated
# drops it and reproduces the defect.
#
# Ungated does not mean "expect failure". Each config lists which properties are
# supposed to break (expect_cex_ungated), so the run exits 0 if and only if
# precisely those fail. Fixing a defect therefore fails the ungated run with
# "expected cex that did not fire", which is the prompt to retire the
# assumption. That makes each shortcoming a regression test rather than a
# footnote.
#
# Everything a run generates - tool scratch, console log, property summary -
# goes to formal/fv_proj/<module>[_selftest][_ungated]/ and nowhere else, so
# the whole lot is one gitignored tree and one directory to delete.
#
# Runs from any working directory: paths resolve against the repo root.
#
# BACKEND
#
# Most formal tools should be compatible with this driver. FORMAL_BACKEND selects
# one of formal/backend/<name>.sh; see formal/backend/README.md. 
# The licence-free stub and dryrun backends ship with the repo, so --all is runnable anywhere.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${REPO_ROOT}"

SELFTEST=0
UNGATED=0
MODULES=()

# Wall-clock ceiling per configuration, seconds. A proof that has not finished by
# now is not going to: these runs are dominated by finding cover witnesses, and a
# cover whose witness is hundreds of cycles deep does not converge at all rather
# than converging slowly. Override with --timeout <seconds>.
TIMEOUT="${HWPQ_TIMEOUT:-1800}"

while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) SELFTEST=1 ;;
    --ungated)  UNGATED=1 ;;
    --timeout)  shift; TIMEOUT="$1" ;;
    --all)      for f in formal/config/*.cfg; do
                  MODULES+=("$(basename "$f" .cfg)")
                done ;;
    -h|--help)  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         echo "unknown option: $1" >&2; exit 2 ;;
    *)          MODULES+=("$1") ;;
  esac
  shift
done

if [ "${#MODULES[@]}" -eq 0 ]; then
  echo "usage: formal/run.sh [--selftest] <module> | --all" >&2
  exit 2
fi

# A real backend is local-only (formal/backend/README.md), so it is absent
# from every git worktree regress.sh builds. FORMAL_BACKEND_DIR lets it live
# anywhere, exported so drive.tcl sources the Tcl half from the same place.
want_dir="${FORMAL_BACKEND_DIR:-${REPO_ROOT}/formal/backend}"
if ! FORMAL_BACKEND_DIR="$(cd "$want_dir" 2>/dev/null && pwd)"; then
  echo "ERROR: FORMAL_BACKEND_DIR does not exist: ${want_dir}" >&2
  exit 2
fi
export FORMAL_BACKEND_DIR

backend_names() {
  ls "${FORMAL_BACKEND_DIR}"/*.sh 2>/dev/null | while read -r f; do basename "$f" .sh; done
}

# Source one backend and report whether it can actually run here.
pick_backend() {
  [ -f "${FORMAL_BACKEND_DIR}/$1.sh" ] || return 1
  # shellcheck source=/dev/null
  . "${FORMAL_BACKEND_DIR}/$1.sh"
  backend_available
}

BACKEND="${FORMAL_BACKEND:-}"
if [ -z "$BACKEND" ]; then
  # Autodetect among REAL tools only. stub and dryrun prove nothing, and picking
  # one silently turns "no tool here" into a green run, which is how a self-test
  # once passed against an empty property table. They run only when named.
  for cand in $(backend_names | grep -vxE 'stub|dryrun'); do
    if pick_backend "$cand"; then BACKEND="$cand"; break; fi
  done
  if [ -z "$BACKEND" ]; then
    echo "ERROR: no runnable formal tool backend in ${FORMAL_BACKEND_DIR}." >&2
    echo "       Load the tool's environment first, or name a licence-free backend:" >&2
    echo "       FORMAL_BACKEND=stub (plumbing) or FORMAL_BACKEND=dryrun (print the" >&2
    echo "       build). Neither proves anything about the design." >&2
    exit 2
  fi
else
  if [ ! -f "${FORMAL_BACKEND_DIR}/${BACKEND}.sh" ]; then
    echo "ERROR: no such backend: ${FORMAL_BACKEND_DIR}/${BACKEND}.sh" >&2
    echo "       available: $(backend_names | tr '\n' ' ')" >&2
    exit 2
  fi
  if ! pick_backend "$BACKEND"; then
    echo "ERROR: backend '${BACKEND}' is not runnable here." >&2
    echo "       Load the tool's environment first." >&2
    exit 2
  fi
fi
case "$BACKEND" in
  stub|dryrun) echo "backend: ${BACKEND}   (licence-free: PROVES NOTHING about the design)" ;;
  *)           echo "backend: ${BACKEND}" ;;
esac

# The modes travel to drive.tcl in the environment rather than on a command
# line, because a tool's option for pre-running Tcl is spelled differently
# across releases while $::env() is the same everywhere.
export HWPQ_SELFTEST="$SELFTEST"
export HWPQ_UNGATED="$UNGATED"

overall=0
for m in "${MODULES[@]}"; do
  cfg="formal/config/${m}.cfg"
  if [ ! -f "$cfg" ]; then
    echo "ERROR: no such config: $cfg" >&2
    overall=2; continue
  fi

  # Everything a run generates lands in ONE directory: the tool's scratch, the
  # console log, and the property summary. The suffix keeps the modes apart -
  # before it existed a --selftest run overwrote the real run's log, so the
  # artifact on disk belonged to whichever happened to run last.
  sfx=""
  [ "$SELFTEST" -eq 1 ] && sfx="${sfx}_selftest"
  [ "$UNGATED"  -eq 1 ] && sfx="${sfx}_ungated"
  outdir="formal/fv_proj/${m}${sfx}"
  mkdir -p "$outdir"
  log="${outdir}/run.log"
  echo "############################################################"
  if [ "$SELFTEST" -eq 1 ]; then
    echo "# SELF-TEST: ${m}   (a broken property MUST make this exit 1)"
  elif [ "$UNGATED" -eq 1 ]; then
    echo "# UNGATED: ${m}   (workaround assumptions dropped; the recorded"
    echo "#                  shortcomings MUST reproduce, and nothing else)"
  else
    echo "# PROVE: ${m}"
  fi
  echo "############################################################"

  # The scratch directory is per-run so parallel runs cannot clobber each
  # other's state, and per-mode because the two configurations elaborate
  # differently. Whatever cleanup that costs is the backend's business --
  # stale-lock handling, for instance, is specific to the tool that left it.
  backend_prepare "$outdir"

  # The backend owns the invocation, including the timeout: it is the only thing
  # that knows the tool's command line. $TIMEOUT is in scope because the backend
  # was sourced into this shell.
  backend_launch "$cfg" "$outdir" "$log"
  rc=$?

  # 124 is timeout(1) reporting that it had to kill the run.
  if [ "$rc" -eq 124 ]; then
    echo "==> ${m}: TIMEOUT after ${TIMEOUT}s: the proof did not converge." >&2
    echo "    This is a sizing problem, not a proof failure. Check the cover set" >&2
    echo "    for a witness that is hundreds of cycles deep, and shrink" >&2
    echo "    QUEUE_SIZE before raising --timeout." >&2
    overall=1
    continue
  fi

  if [ "$SELFTEST" -eq 1 ]; then
    # Exit 1 alone is not a pass: an empty property table, a failed build and a
    # backend that proves nothing all exit 1 too. The self-test property itself
    # must come back as a counterexample.
    st_verdict="$(sed -n '/verdict =====/,/RESULT:/p' "$log")"
    if [ "$rc" -eq 1 ] && grep -q 'unexpected counterexamples' <<<"$st_verdict" \
       && grep -qE '(^|[.[:space:]])a_selftest_must_fail\b' <<<"$st_verdict"; then
      echo "==> ${m}: self-test PASSED (a_selftest_must_fail reported as a counterexample)"
    else
      if [ "$rc" -ne 1 ]; then
        why="expected exit 1, got ${rc}"
      elif [ -z "$st_verdict" ]; then
        why="exit 1, but no property table: the run failed before proving"
      else
        why="exit 1, but a_selftest_must_fail is not among the counterexamples"
      fi
      echo "==> ${m}: self-test FAILED: ${why}." >&2
      echo "    The harness has not shown it can report a failure. Do not trust any" >&2
      echo "    green run until this is fixed. Read ${log}" >&2
      overall=1
    fi
  else
    case "$rc" in
      0) if [ "$UNGATED" -eq 1 ]; then
           echo "==> ${m}: PASS (ungated: recorded shortcomings reproduced exactly)"
         else
           echo "==> ${m}: PASS"
         fi ;;
      1) if [ "$UNGATED" -eq 1 ]; then
           echo "==> ${m}: FAIL (ungated: the set of failures changed; either a" >&2
           echo "    defect was fixed and its assumption should be retired, or a" >&2
           echo "    new one appeared. Read ${log})" >&2
         else
           echo "==> ${m}: FAIL (proof failure: read ${log})"
         fi
         overall=1 ;;
      *) echo "==> ${m}: SCRIPT ERROR (exit ${rc}: read ${log})"; overall=2 ;;
    esac
  fi
  echo
done

exit "${overall}"

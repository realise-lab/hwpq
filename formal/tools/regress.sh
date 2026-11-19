#!/usr/bin/env bash
#
# Mutation regression driver: does the suite still catch each fix's defect?
#
#   formal/tools/regress.sh <finding>    one row, keyed by SWEEP.tsv (see --list)
#   formal/tools/regress.sh --all        every row in mutations/SWEEP.tsv
#   formal/tools/regress.sh --list       show the manifest
#   formal/tools/regress.sh --replay ... build each worktree from the HEAD each
#                                        row was RECORDED at, not current HEAD
#
# For each row: detached worktree, reintroduce the defect (git revert, or
# mutations/<finding>.patch), run the module, and require the recorded outcome.
#
# TWO INVERSIONS make this different from run.sh, and both matter:
#
#   1. run.sh FAILING is success here. A defect that reddens nothing is the bug.
#      Never trust run.sh's exit code; parse the verdict block.
#
#   2. The CONTROL is checked first. A property that is already red at unmutated
#      HEAD proves nothing when it is red under mutation, for a reason unrelated
#      to the mutated defect. --all verifies the unmutated tree is clean before
#      it trusts a single row.
#
#      NOTE ON THE WORD: this is the CONTROL run, not the "baseline". In this
#      project `baseline` means the pre-verification RTL; see
#      formal/tools/baseline/MANIFEST.tsv, which is a different measurement entirely.
#
# TWO MANIFEST COLUMNS THIS SCRIPT ACTS ON:
#
#   class     rtl | harness. Most rows mutate the DESIGN and ask whether the
#             instrument still sees the defect. A harness row mutates the
#             INSTRUMENT and asks whether it is load-bearing at all. The script
#             does not branch on this: it reports it, because those are
#             different questions and a manifest that cannot tell them apart
#             cannot say which it answered.
#
#   head      the HEAD each row's outcome was MEASURED at. NOT the "baseline" --
#             that word is taken: formal/tools/baseline/MANIFEST.tsv records the
#             pre-verification RTL, a different measurement.
#
#             The sweep runs at current HEAD by design: "does the suite STILL
#             catch this" is a question about the code as it stands, not a
#             historical replay. So when HEAD has moved past a row's recorded
#             one this script WARNS and still runs: a changed outcome is then
#             a result to investigate rather than drift silently attributed to
#             the mutation. --replay rebuilds at the recorded HEAD instead,
#             which is what makes the numbers reproducible rather than dated.
#
# Requires FORMAL_BACKEND naming a real tool's backend (formal/backend/README.md).
# stub and dryrun are refused: every row would "pass" against nothing. One run per
# module directory at a time: concurrent runs on the same formal/fv_proj/<module>
# collide on the tool's scratch.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
MANIFEST="${SCRIPT_DIR}/mutations/SWEEP.tsv"
cd "${REPO_ROOT}"

# Every row runs in a fresh worktree, and a real tool's backend is never
# committed, so no worktree contains one. Point every row back at the backend in
# THIS checkout, unless FORMAL_BACKEND_DIR already says otherwise.
export FORMAL_BACKEND_DIR="${FORMAL_BACKEND_DIR:-${REPO_ROOT}/formal/backend}"

[ -f "${MANIFEST}" ] || { echo "no manifest at ${MANIFEST}" >&2; exit 2; }

rows() { grep -v '^#' "${MANIFEST}" | grep -v '^[[:space:]]*$'; }

# --replay is a modifier, not a mode: strip it and dispatch on what is left.
REPLAY=0
BASELINE=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --replay)   REPLAY=1 ;;
    --baseline) BASELINE=1 ;;
    *)             ARGS+=("$a") ;;
  esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}

# --baseline selects the OTHER manifest. Everything downstream (dispatch, control
# runs, drift warning, verdict parsing, exit code) is shared. The two manifests
# align their column positions precisely so this stays a selector and never grows
# into a second slightly-different driver.
if [ "$BASELINE" -eq 1 ]; then
  MANIFEST="${SCRIPT_DIR}/baseline/MANIFEST.tsv"
  [ -f "${MANIFEST}" ] || { echo "no baseline manifest at ${MANIFEST}" >&2; exit 2; }
fi

HEAD_SHA="$(git rev-parse --short HEAD)"

# Comment-only commits sit between each fix and current HEAD, so a fix's own
# revert or patch does not apply against the trimmed lines. Reverting these
# first, in every non-baseline worktree, restores the state each row was written
# against. Baseline mode pins its checkout to the baseline commit directly and
# never touches HEAD's comment trim, so it is unaffected.
COMMENT_ONLY_IDS=""
if [ "$BASELINE" -eq 0 ]; then
  COMMENT_ONLY_IDS="$(grep -m1 '^#comment-only ' "${MANIFEST}" | cut -d' ' -f2-)"
fi

# A conflict here means the trim commit and the row's own mutation touch the
# same lines; report it distinctly rather than let it read as a failure of
# defect detection.
revert_comment_only() {
  local wt="$1" label="$2"
  [ -z "$COMMENT_ONLY_IDS" ] && return 0
  ( cd "$wt" && git revert --no-commit $COMMENT_ONLY_IDS ) >/dev/null 2>&1 \
    || { echo "  ${label}: comment-only revert conflicts"; return 2; }
  return 0
}

if [ "${1:-}" = "--list" ]; then
  if [ "$BASELINE" -eq 1 ]; then
    printf '%-30s %-38s %-9s %-24s %s\n' ROW CONFIG BASELINE ENABLING EXPECT
    rows | while IFS=$'\t' read -r r cfg base enab harness wb expect notes; do
      printf '%-30s %-38s %-9s %-24s %s\n' "$r" "$cfg" "$base" "$enab" "$expect"
    done
    exit 0
  fi
  printf '%-8s %-9s %-22s %-8s %-9s %-7s %s\n' FINDING FIX MODULE CLASS HEAD METHOD EXPECT
  rows | while IFS=$'\t' read -r f fix mod cls head_at method expect notes; do
    printf '%-8s %-9s %-22s %-8s %-9s %-7s %s\n' "$f" "$fix" "$mod" "$cls" "$head_at" "$method" "$expect"
  done
  exit 0
fi

# ---- backend --------------------------------------------------------------------
# A licence-free backend would judge every row against an empty property table.
# Refuse before a single worktree is built, rather than report a sweep of noise.
case "${FORMAL_BACKEND:-}" in
  "")          echo "regress: FORMAL_BACKEND is not set: name a real tool's backend." >&2; exit 2 ;;
  stub|dryrun) echo "regress: FORMAL_BACKEND=${FORMAL_BACKEND} proves nothing; refusing." >&2; exit 2 ;;
esac
if [ ! -f "${FORMAL_BACKEND_DIR}/${FORMAL_BACKEND}.sh" ] \
   || ! ( . "${FORMAL_BACKEND_DIR}/${FORMAL_BACKEND}.sh" && backend_available ); then
  echo "regress: backend '${FORMAL_BACKEND}' in ${FORMAL_BACKEND_DIR} is missing or not runnable here." >&2
  exit 2
fi

# ---- head drift ---------------------------------------------------------------
# Printed once, not per row. Each row records the HEAD it was measured at; if
# HEAD has moved the row still runs, which is the point of a regression driver,
# but its recorded outcome no longer describes the current code.
warn_head_drift() {
  local stale
  stale="$(rows | awk -F'\t' -v h="${HEAD_SHA}" '$5 != h {print $5}' | sort -u | tr '\n' ' ')"
  [ -n "${stale// /}" ] || return 0
  if [ "$REPLAY" -eq 1 ]; then
    echo "== replaying at each row's recorded HEAD (${stale%% }); current HEAD is ${HEAD_SHA} =="
  else
    echo "== NOTE: HEAD is ${HEAD_SHA}; rows were measured at ${stale%% }=="
    echo "   Rows still run at HEAD: that is the regression question. But a changed"
    echo "   outcome below may be the code moving rather than the mutation. Use"
    echo "   --replay to replay a row where its numbers were recorded."
  fi
  echo
}

# ---- control: the unmutated tree must be clean, or no row below means anything -
check_control() {
  local mod="$1" ref="$2" wt out
  wt="$(mktemp -d)"
  git worktree add "$wt" --detach "$ref" >/dev/null 2>&1 || return 2
  revert_comment_only "$wt" "$mod" || { git worktree remove --force "$wt" >/dev/null 2>&1; return 2; }
  out="$( cd "$wt" && formal/run.sh "$mod" 2>&1 )"
  git worktree remove --force "$wt" >/dev/null 2>&1
  # Kept for the same reason as each row's log: "control not clean" with nothing
  # left to read is a verdict whose evidence was destroyed.
  mkdir -p "${REPO_ROOT}/formal/fv_proj/regress"
  printf '%s\n' "$out" > "${REPO_ROOT}/formal/fv_proj/regress/control-${mod//\//_}.log"
  grep -qE '^[[:space:]]*RESULT: PASS' <<<"$out"
}

# ---- a run that dies BEFORE the property table --------------------------------
#
# Two expectations share this shape and differ only in the signature: one class
# stops at the multiple-driver gate, another at the elaboration gate. The tell in
# both is the gate's line in the FULL output plus an EMPTY verdict block; sed's range
# never opens, so there is no "asserts:" line to find. That absence is the
# discriminator, not an accident: a run that reached the property table failed
# some other way and must not read as CAUGHT.
#
# Both signatures are verdict.tcl's own output, never a tool diagnostic, so the
# rows survive a change of tool. Match them CASE-SENSITIVELY and anchored at line
# start. A tool that echoes the Tcl it runs puts the source of those puts
# statements, and any prose mentioning the condition, into the log: measured on a
# clean bram_tree log, "7 multiply-driven signals" appears in echoed prose. The
# empty verdict block is the second conjunct, because one is not enough to hang a
# row on.
#
# Reads $out, $verdict and $finding from the calling run_row (bash locals are
# visible to callees).
#
#   $1 signature regex   $2 human label
check_elab_fail() {
  local sig="$1" label="$2"
  if ! grep -qE "$sig" <<<"$out"; then
    echo "  ${finding}: *** NOT CAUGHT *** expected ${label}"; return 1
  fi
  if grep -q 'asserts:' <<<"$verdict"; then
    echo "  ${finding}: *** NOT CAUGHT *** ${label} matched, but a property table WAS produced"
    return 1
  fi
  echo "  ${finding}: CAUGHT (${label}, no property table)"
  return 0
}

# ---- one row ------------------------------------------------------------------
run_row() {
  local finding="$1" fix="$2" mod="$3" cls="$4" head_at="$5" method="$6" expect="$7"
  local wt out verdict ref ceiling rc=0

  ref="$HEAD_SHA"
  [ "$REPLAY" -eq 1 ] && ref="$head_at"

  wt="$(mktemp -d)"

  if [ "$BASELINE" -eq 1 ]; then
    # BASELINE MODE. Field meanings differ: fix=config, mod=baseline commit,
    # cls=enabling list. The CHECKOUT IS PINNED to the baseline commit and only the
    # formal/ OVERLAY follows $ref. If the checkout ever follows $ref instead, the
    # row measures TODAY's RTL while claiming the pre-verification design: it
    # runs, it looks plausible, and it is silently wrong.
    local base_commit="$mod" enabling="$cls" config="$fix" got_sha
    git worktree add "$wt" --detach "$base_commit" >/dev/null 2>&1 \
      || { echo "  ${finding}: worktree at ${base_commit} failed"; return 2; }
    got_sha="$(git -C "$wt" rev-parse --short HEAD)"
    if [ "$got_sha" != "$base_commit" ]; then
      echo "  ${finding}: *** REFUSING TO RUN *** worktree is at ${got_sha}, expected ${base_commit}"
      git worktree remove --force "$wt" >/dev/null 2>&1; return 2
    fi
    git -C "$wt" checkout "$ref" -- formal/ >/dev/null 2>&1 \
      || { echo "  ${finding}: could not overlay formal/ from ${ref}"; git worktree remove --force "$wt" >/dev/null 2>&1; return 2; }
    if [ "$enabling" != "-" ]; then
      local c
      for c in ${enabling//,/ }; do
        ( cd "$wt" && git cherry-pick --no-commit "$c" ) >/dev/null 2>&1 \
          || { echo "  ${finding}: enabling commit ${c} failed to apply"; git worktree remove --force "$wt" >/dev/null 2>&1; return 2; }
      done
    fi
    mod="$config"
  else
  git worktree add "$wt" --detach "$ref" >/dev/null 2>&1 || { echo "worktree failed"; return 2; }

  revert_comment_only "$wt" "$finding" || { git worktree remove --force "$wt" >/dev/null 2>&1; return 2; }

  if [ "$method" = "revert" ]; then
    ( cd "$wt" && git revert --no-commit "$fix" ) >/dev/null 2>&1 \
      || { echo "  ${finding}: REVERT CONFLICTS, needs a patch"; git worktree remove --force "$wt" >/dev/null 2>&1; return 2; }
  else
    ( cd "$wt" && git apply "${SCRIPT_DIR}/mutations/${finding}.patch" ) 2>/dev/null \
      || { echo "  ${finding}: patch failed to apply"; git worktree remove --force "$wt" >/dev/null 2>&1; return 2; }
  fi
  fi

  # A `timeout:<secs>` row overrides run.sh's ceiling. Only a row whose EXPECTED
  # outcome is non-convergence may do this: shortening the ceiling on a row that
  # is supposed to converge manufactures a false timeout. The trade is evidential
  # strength -- "did not converge in 600 s" is a weaker claim than the same at
  # 1800 s -- so the ceiling must stay well clear of the control run's slowest
  # property (174 s at f667f74) or the result reads as slowness, not divergence.
  ceiling=""
  case "$expect" in timeout:*) ceiling="${expect#timeout:}" ;; esac
  if [ -n "$ceiling" ]; then
    out="$( cd "$wt" && HWPQ_TIMEOUT="$ceiling" formal/run.sh "$mod" 2>&1 )"
  else
    out="$( cd "$wt" && formal/run.sh "$mod" 2>&1 )"
  fi
  # KEEP THE EVIDENCE. The run happens in a worktree that is deleted below, so
  # without this the sweep produces a verdict line and destroys everything that
  # justifies it, and a reproduction ledger whose own results are uncheckable
  # is the thing this effort exists to avoid. One log per row, overwritten each
  # sweep, beside the ordinary run artifacts.
  mkdir -p "${REPO_ROOT}/formal/fv_proj/regress"
  printf '%s\n' "$out" > "${REPO_ROOT}/formal/fv_proj/regress/${finding}.log"
  verdict="$(sed -n '/verdict =====/,/RESULT:/p' <<<"$out")"

  case "$expect" in
    cex:*)
      # A COMMA LIST REQUIRES EVERY NAMED LEAF, not "at least one". A baseline
      # row's whole value is the BREADTH of what the harness still sees: pinning
      # one leaf would let systolic_array drop from five counterexamples to one
      # and still report CAUGHT, which is the weakened-spec case this exists to
      # catch. Counts are deliberately NOT pinned: a spec that got weaker loses
      # a NAMED property, and count drift alone is noise.
      local leaf missing="" want_list="${expect#cex:}"
      for leaf in ${want_list//,/ }; do
        grep -q "\.${leaf}\b" <<<"$verdict" || missing="${missing} ${leaf}"
      done
      if [ -z "$missing" ] && grep -qE 'unexpected counterexamples' <<<"$verdict"; then
        echo "  ${finding}: CAUGHT (${want_list})"
      else
        echo "  ${finding}: *** NOT CAUGHT *** missing:${missing:-" (no counterexample block at all)"}"; rc=1
      fi ;;
    clean)
      # A verdict block MUST exist. Without that check "clean" is satisfied by a
      # run that died before producing a table: a silently-not-running row is
      # indistinguishable from a passing one, and the clean rows are the most
      # valuable in the baseline table precisely because they are the canaries.
      if ! grep -qE 'asserts:' <<<"$verdict"; then
        echo "  ${finding}: *** NO VERDICT BLOCK *** the run produced no property table"; rc=1
      elif grep -qE '0 cex' <<<"$verdict" && grep -qE '0 UNREACHABLE' <<<"$verdict"; then
        echo "  ${finding}: clean, as recorded"
      else
        echo "  ${finding}: *** CHANGED *** expected clean, got: $(grep -E 'asserts:|covers :' <<<"$verdict" | tr -s ' ' | tr '\n' ' ')"; rc=1
      fi ;;
    cover-unreachable|cover-unreachable:*)
      local got_n want_cnt="${expect#cover-unreachable}"; want_cnt="${want_cnt#:}"
      got_n="$(grep -oE '[0-9]+ UNREACHABLE' <<<"$verdict" | head -1 | cut -d' ' -f1)"
      if [ -z "$got_n" ] || [ "$got_n" -eq 0 ] 2>/dev/null; then
        echo "  ${finding}: *** NOT CAUGHT *** expected unreachable covers"; rc=1
      elif [ -n "$want_cnt" ] && [ "$got_n" != "$want_cnt" ]; then
        echo "  ${finding}: *** COUNT CHANGED *** expected ${want_cnt} unreachable, got ${got_n}"; rc=1
      else
        echo "  ${finding}: CAUGHT (vacuity: ${got_n} unreachable)"
      fi ;;
    elab-fail)
      # Keyed on verdict.tcl's own gate line, never on the tool's diagnostic, so
      # the row survives a change of tool. Anchored at line start: if the tool
      # echoes the Tcl it runs, the echoed source reads `puts "    ELABORATION
      # FAILED...` and the anchor does not match it.
      check_elab_fail '^[[:space:]]*ELABORATION FAILED:' 'elaboration failure' || rc=1 ;;
    harness-gate)
      check_elab_fail '^[[:space:]]*MULTIPLY-DRIVEN SIGNALS \(' 'multiply-driven harness gate' || rc=1 ;;
    timeout|timeout:*)
      if grep -q 'TIMEOUT' <<<"$out"; then
        echo "  ${finding}: CAUGHT (non-convergence at ${ceiling:-1800}s, weakest form, names no property)"
      else
        echo "  ${finding}: *** NOT CAUGHT *** expected a timeout"; rc=1
      fi ;;
    none)
      if grep -qE '^[[:space:]]*RESULT: PASS' <<<"$out"; then
        echo "  ${finding}: green, as recorded (not detectable, see manifest notes)"
      else
        echo "  ${finding}: *** CHANGED *** recorded as undetectable but something fired"; rc=1
      fi ;;
    *) echo "  ${finding}: unknown expectation '${expect}'"; rc=2 ;;
  esac

  [ "$cls" = "harness" ] && echo "      (harness-class row: the RTL is untouched; this tests the instrument)"

  git worktree remove --force "$wt" >/dev/null 2>&1
  return $rc
}

# ---- dispatch -----------------------------------------------------------------
fail=0
if [ "${1:-}" = "--all" ]; then
  warn_head_drift
  echo "== control: the unmutated tree must be clean before any row is trusted =="
  # Unique module+head pairs: with --replay different rows can check out
  # different commits, and a clean run at one says nothing about the other.
  while IFS=$'\t' read -r mod head_at; do
    ref="$HEAD_SHA"; [ "$REPLAY" -eq 1 ] && ref="$head_at"
    if check_control "$mod" "$ref"; then
      echo "  $mod @ $ref: clean"
    else
      echo "  $mod @ $ref: *** CONTROL NOT CLEAN: rows for this module prove nothing ***"; fail=1
    fi
  done < <(rows | awk -F'\t' -v b="$BASELINE" 'BEGIN{OFS="\t"} {print (b==1 ? $2 : $3), $5}' | sort -u)
  [ "$fail" -eq 0 ] || { echo; echo "REGRESS: aborted, control run dirty"; exit 1; }
  echo; echo "== mutations =="
  while IFS=$'\t' read -r f fix mod cls head_at method expect notes; do
    run_row "$f" "$fix" "$mod" "$cls" "$head_at" "$method" "$expect" || fail=1
  done < <(rows)
else
  want="${1:?usage: regress.sh [--replay] <finding>|--all|--list}"
  line="$(rows | awk -F'\t' -v w="$want" '$1==w')"
  [ -n "$line" ] || { echo "no row for '${want}'" >&2; exit 2; }
  IFS=$'\t' read -r f fix mod cls head_at method expect notes <<<"$line"
  warn_head_drift
  ref="$HEAD_SHA"; [ "$REPLAY" -eq 1 ] && ref="$head_at"
  # In baseline mode the control target is the CONFIG (field 2); the run.sh
  # argument for a BRAM row is baseline/<config>, not the module name.
  ctl="$mod"; [ "$BASELINE" -eq 1 ] && ctl="$fix"
  check_control "$ctl" "$ref" && echo "  $ctl @ $ref control: clean" || { echo "  $ctl: *** CONTROL NOT CLEAN ***"; exit 1; }
  run_row "$f" "$fix" "$mod" "$cls" "$head_at" "$method" "$expect" || fail=1
fi

echo
[ "$fail" -eq 0 ] && echo "REGRESS: all rows behaved as recorded" || echo "REGRESS: a row did not behave as recorded"
exit $fail

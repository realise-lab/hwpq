#!/usr/bin/env bash
#
# Local validation. Runs everything that can be checked WITHOUT the formal
# tool's license, so a broken spec is caught in seconds instead of after an
# SSH round trip.
#
# Four checks:
#   1. lint:      the spec and bind elaborate together under Verilator
#   2. polarity+: normal build: the plumbing property must NOT fire
#   3. polarity-: HWPQ_SELFTEST build: the self-test property MUST fire
#   4. verdict:   verdict.tcl parses, and its decisions return the right
#                   exit codes for clean / cex / unreachable-cover /
#                   no-asserts / expected-cex cases
#
# Check 3 is the important one. A harness that cannot report failure is worse
# than no harness, and this is how we know it can before trusting a green run.
#
# What this CANNOT do: prove anything. Simulation samples; only the formal tool
# decides. Passing smoke.sh means "worth a real proof run", not "correct".
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
cd "${REPO_ROOT}"

WORK="${TMPDIR:-/tmp}/hwpq_smoke.$$"
mkdir -p "${WORK}"
trap 'rm -rf "${WORK}"' EXIT

RTL="hwpq/register_array/src/register_array.sv"
SPEC="formal/spec/hwpq_spec.sv"
BIND="formal/bind/register_array_bind.sv"
TB="${SCRIPT_DIR}/smoke/hwpq_smoke_tb.sv"

pass=0; fail=0
ok()   { echo "  PASS  $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL  $1"; fail=$((fail+1)); }

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: $1 not on PATH" >&2; exit 2; }; }
need verilator
need tclsh

echo "=== 1. lint: spec + bind elaborate against the DUT ==="
# Waivers, each deliberate:
#   UNUSEDSIGNAL  some interface ports are wired for future properties
#                 before anything reads them.
#   SYNCASYNCNET  inherent to `disable iff (!i_RSTn)` on an async-reset design:
#                 the RTL flops i_RSTn asynchronously, the property samples it
#                 synchronously. That is exactly what `disable iff` is for, and
#                 it is how the formal tool's `reset ~i_RSTn` works too. Not a
#                 defect.
#   GENUNNAMED /  pre-existing warnings in the RTL itself, not introduced here.
#   WIDTHEXPAND   Left waived so this check only ever fails on OUR code.
#   DECLFILENAME  hwpq_spec.sv holds a module of the same name; harmless.
if verilator --lint-only --timing --assert -sv -Wall \
     -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-GENUNNAMED -Wno-WIDTHEXPAND \
     -Wno-SYNCASYNCNET \
     --top-module register_array \
     -GQUEUE_SIZE=4 -GDATA_WIDTH=3 -GENQ_ENA=1 \
     "$RTL" "$SPEC" "$BIND" > "${WORK}/lint.log" 2>&1; then
  ok "lint clean"
else
  bad "lint"; sed 's/^/        /' "${WORK}/lint.log" | head -20
fi

build_and_run () {  # $1 = tag, $2... = extra verilator args
  local tag="$1"; shift
  verilator --binary --timing --assert -sv -Wno-fatal \
    --top-module hwpq_smoke_tb -Mdir "${WORK}/obj_${tag}" \
    -o "sim_${tag}" "$@" "$RTL" "$SPEC" "$BIND" "$TB" \
    > "${WORK}/build_${tag}.log" 2>&1 || return 99
  "${WORK}/obj_${tag}/sim_${tag}" > "${WORK}/run_${tag}.log" 2>&1
  return $?
}

echo
echo "=== 2. polarity+: the plumbing property must NOT fire ==="
if build_and_run good; then
  ok "normal build ran clean"
else
  rc=$?
  if [ "$rc" -eq 99 ]; then bad "normal build did not compile"; sed 's/^/        /' "${WORK}/build_good.log" | tail -15
  else bad "plumbing property fired on a correct DUT (exit $rc)"; sed 's/^/        /' "${WORK}/run_good.log" | tail -10; fi
fi

echo
echo "=== 3. polarity-: the self-test property MUST fire ==="
if build_and_run bad +define+HWPQ_SELFTEST; then
  bad "self-test build did NOT fire: the harness cannot report failures"
else
  rc=$?
  if [ "$rc" -eq 99 ]; then bad "self-test build did not compile"; sed 's/^/        /' "${WORK}/build_bad.log" | tail -15
  else ok "inverted property fired as required (exit $rc)"; fi
fi

echo
echo "=== 4. verdict: verdict.tcl parses and its decisions are correct ==="
tclsh "${SCRIPT_DIR}/smoke/smoke_tcl.tcl" "${REPO_ROOT}" && ok "verdict logic" || bad "verdict logic"

echo
echo "============================================================"
echo "  ${pass} passed, ${fail} failed"
echo "============================================================"
[ "$fail" -eq 0 ] || exit 1

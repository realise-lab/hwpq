#!/usr/bin/env bash
#
# Compile and run a single module's testbench with Icarus Verilog.
#
# Usage: scripts/run_sim.sh <module_dir> <testbench_file> <top_module> [<iverilog_flags>]
#   <module_dir>      name under hwpq/ (e.g. register_tree)
#   <testbench_file>  path to the testbench .sv (e.g. hwpq/register_tree/rtl/sim/register_tree_tb.sv)
#   <top_module>      top-level module name declared in the testbench (e.g. register_tree_tb)
#   <iverilog_flags>  optional extra compile flags, word-split (e.g. "-DHYBRID_TREE_COUNT=2")
#
set -eu

MODULE="$1"
TB="$2"
TOP="$3"
FLAGS="${4:-}"

SRC_DIR="hwpq/${MODULE}/rtl/src"
[ -d "${SRC_DIR}" ] || SRC_DIR="hwpq/${MODULE}/src"
# sharing build/${MODULE} would let the runs clobber each other's sim.vvp/sim.log.
BUILD="build/${TOP}"
LOG="${BUILD}/sim.log"
mkdir -p "${BUILD}"

shopt -s nullglob
PKGS=()
REST=()

ALL_FILES=("${SRC_DIR}"/*.sv)

for f in "${ALL_FILES[@]}"; do
  if grep -qE '^[[:space:]]*package[[:space:]]' "$f"; then
    PKGS+=("$f")
  else
    REST+=("$f")
  fi
done

echo "==> Compiling ${MODULE} (top: ${TOP})"
# shellcheck disable=SC2086
iverilog -g2012 -Wall -I hwpq/common/tb ${FLAGS} -s "${TOP}" -o "${BUILD}/sim.vvp" "${PKGS[@]}" "${REST[@]}" "${TB}"

echo "==> Running ${MODULE}"
vvp "${BUILD}/sim.vvp" | tee "${LOG}"
status="${PIPESTATUS[0]}"

echo "==> Checking results for ${MODULE}"

if [ "${status}" -ne 0 ]; then
  echo "::error::${MODULE}: testbench exited with status ${status}"
fi

if ! grep -qiE 'test[[:space:]]+completed' "${LOG}"; then
  echo "::error::${MODULE}: simulation did not reach the 'Test completed' marker"
  status=1
fi

if [ "${status}" -eq 0 ]; then
  echo "PASS: ${MODULE}"
else
  echo "FAIL: ${MODULE}"
fi
exit "${status}"
#!/usr/bin/env bash
#
# Compile and run a single module's testbench with Icarus Verilog.
#
# Usage: scripts/run_sim.sh <module_dir> <testbench_file> <top_module>
#   <module_dir>      name under hwpq/ (e.g. register_tree)
#   <testbench_file>  path to the testbench .sv (e.g. hwpq/register_tree/rtl/sim/register_tree_tb.sv)
#   <top_module>      top-level module name declared in the testbench (e.g. register_tree_tb)
#
set -eu

MODULE="$1"
TB="$2"
TOP="$3"

SRC_DIR="hwpq/${MODULE}/rtl/src"
BUILD="build/${MODULE}"
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
iverilog -g2012 -Wall -s "${TOP}" -o "${BUILD}/sim.vvp" "${PKGS[@]}" "${REST[@]}" "${TB}"

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
#!/usr/bin/env bash
#
# Compile and run a single module's testbench with Icarus Verilog.
#
# Usage: test/run_sim.sh <module_dir> <testbench_file> <top_module>
#   <module_dir>      name under hwpq/ (e.g. register_tree)
#   <testbench_file>  path to the testbench .sv, relative to the repo root
#                     (e.g. hwpq/register_tree/test/register_tree_tb.sv)
#   <top_module>      top-level module name declared in the testbench (e.g. register_tree_tb)
#
# Runs from any working directory: paths are resolved against the repo root, not $PWD.
#
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(dirname "${SCRIPT_DIR}")"

MODULE="$1"
TB="$2"
TOP="$3"

SRC_DIR="hwpq/${MODULE}/src"
# sharing build/${MODULE} would let the runs clobber each other's sim.vvp/sim.log.
BUILD="build/${TOP}"
LOG="${BUILD}/sim.log"
mkdir -p "${BUILD}"

shopt -s nullglob
PKGS=()
REST=()

ALL_FILES=("${SRC_DIR}"/*.sv)

if [ "${#ALL_FILES[@]}" -eq 0 ]; then
  echo "::error::${MODULE}: no .sv sources found in ${SRC_DIR}"
  exit 1
fi

for f in "${ALL_FILES[@]}"; do
  if grep -qE '^[[:space:]]*package[[:space:]]' "$f"; then
    PKGS+=("$f")
  else
    REST+=("$f")
  fi
done

echo "==> Compiling ${MODULE} (top: ${TOP})"
iverilog -g2012 -Wall -I "${SCRIPT_DIR}/common" -s "${TOP}" -o "${BUILD}/sim.vvp" "${PKGS[@]}" "${REST[@]}" "${TB}"

echo "==> Running ${MODULE}"
vvp "${BUILD}/sim.vvp" | tee "${LOG}"
status="${PIPESTATUS[0]}"

echo "==> Checking results for ${MODULE}"

if [ "${status}" -ne 0 ]; then
  echo "::error::${MODULE}: testbench exited with status ${status}"
  status=1
fi

if [ "${status}" -eq 0 ]; then
  echo "PASS: ${MODULE}"
else
  echo "FAIL: ${MODULE}"
fi
exit "${status}"

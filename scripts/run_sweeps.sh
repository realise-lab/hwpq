#!/usr/bin/env bash
#
# Measure what the figures plot, for each architecture: cycles per op (test/perf/cycle_profile.sh)
# and Fmax and resources (vivado-runtime/run_param_sweep_parallel.sh), the two side by side.
#
# Usage: scripts/run_sweeps.sh [arch ...]     default: every architecture below
#   PROFILE=0 / SYNTH=0 skips that half. SIM and the other cycle_profile.sh settings pass through.
# Needs on PATH: vivado, and the simulator SIM names (iverilog by default).
# Logs: build/sweeps/<cycles|synth>_<arch>.log. Results: where each script writes them; then
#   python3 py-scripts/analysis_py/src/plotter.py
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHS="${*:-register_array register_array_pipelined register_tree register_tree_pipelined
              systolic_array bram_tree bram_tree_pipelined bram_tree_pair hybrid_systolic_bram_heap}"
PROFILE=${PROFILE:-1}; SYNTH=${SYNTH:-1}
LOGS="${ROOT}/build/sweeps"
mkdir -p "${LOGS}"

if [ "${SYNTH}" = 1 ]; then command -v vivado >/dev/null || { echo "vivado not on PATH"; exit 1; }; fi
if [ "${PROFILE}" = 1 ]; then
  command -v "${SIM:-iverilog}" >/dev/null || { echo "${SIM:-iverilog} not on PATH"; exit 1; }
fi

pids=()
if [ "${PROFILE}" = 1 ]; then
  ( for a in ${ARCHS}; do
      "${ROOT}/test/perf/cycle_profile.sh" "${a}" > "${LOGS}/cycles_${a}.log" 2>&1 \
        && echo "cycles ${a}: done" || echo "cycles ${a}: FAILED (${LOGS}/cycles_${a}.log)"
    done ) &
  pids+=($!)
fi
if [ "${SYNTH}" = 1 ]; then
  # The synthesis driver keeps its job logs relative to its own directory.
  ( cd "${ROOT}/vivado-runtime"
    for a in ${ARCHS}; do
      ./run_param_sweep_parallel.sh "${a}" > "${LOGS}/synth_${a}.log" 2>&1 \
        && echo "synth ${a}: done" || echo "synth ${a}: FAILED (${LOGS}/synth_${a}.log)"
    done ) &
  pids+=($!)
fi
wait "${pids[@]}"

#!/usr/bin/env bash
#
# Sweep hybrid_systolic_heap over data widths and tree sizes, one batch run per build.
#
# Usage: scripts/run_hybrid_sweep.sh [-j <parallel>] [-w "<widths>"] [-t "<tree_queue_sizes>"]
#   -j  concurrent builds (default 2); each uses up to 8 threads and a 128-bit build ~10 GB
#   -w  data widths (default "128")
#   -t  per-tree queue sizes, each 2^k - 1 (default "2047")
# Results:  hwpq/hybrid_systolic_bram_heap/vivado_analysis_results_<W>bit_xcau25p/
# Logs, checkpoints and path reports:  build/vivado_hybrid/<W>b_tree<T>/
# A build whose result file already ends in "Analysis completed" is skipped; delete it to rerun.
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TCL="${ROOT}/scripts/vivado_hybrid.tcl"
MODULE_DIR="${ROOT}/hwpq/hybrid_systolic_bram_heap"
TREE_COUNT=11
SYSTOLIC_QS=16

MAX_PARALLEL=2
WIDTHS="128"
TREE_SIZES="2047"
while getopts "j:w:t:" opt; do
  case "${opt}" in
    j) MAX_PARALLEL="${OPTARG}" ;;
    w) WIDTHS="${OPTARG}" ;;
    t) TREE_SIZES="${OPTARG}" ;;
    *) sed -n '3,11p' "$0"; exit 1 ;;
  esac
done

command -v vivado >/dev/null || { echo "vivado not on PATH"; exit 1; }

run_one() {
  local w="$1" t="$2"
  local qs=$(( TREE_COUNT * t + 2 * (SYSTOLIC_QS - 2) ))
  local result_dir="${MODULE_DIR}/vivado_analysis_results_${w}bit_xcau25p"
  local work_dir="${ROOT}/build/vivado_hybrid/${w}b_tree${t}"
  local result="${result_dir}/vivado_analysis_on_queue_size_${qs}.txt"

  if [ -f "${result}" ] && grep -q "Analysis completed" "${work_dir}/vivado.log" 2>/dev/null; then
    echo "skip  ${w}b tree=${t} (done)"
    return 0
  fi
  mkdir -p "${work_dir}"
  echo "start ${w}b tree=${t} -> ${work_dir}/vivado.log"
  local status=0
  (cd "${work_dir}" && vivado -mode batch -nojournal -log vivado.log -source "${TCL}" \
     -tclargs "${w}" "${t}" "${result_dir}" "${work_dir}" "${TREE_COUNT}" > /dev/null 2>&1) || status=$?
  if grep -q "Analysis completed" "${work_dir}/vivado.log"; then
    echo "done  ${w}b tree=${t}: best $(grep -o 'Achieved Frequency: [0-9.]*' "${result}" | awk '{print $3}' | sort -g | tail -1) MHz"
  else
    echo "FAIL  ${w}b tree=${t} (exit ${status}); see ${work_dir}/vivado.log"
  fi
}

for w in ${WIDTHS}; do
  for t in ${TREE_SIZES}; do
    while [ "$(jobs -rp | wc -l)" -ge "${MAX_PARALLEL}" ]; do wait -n || true; done
    run_one "${w}" "${t}" &
  done
done
wait

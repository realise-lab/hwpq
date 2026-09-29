#!/usr/bin/env bash
#
# Run every testbench in the suite
# Usage: test/run_all_sims.sh
#
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# module_dir | testbench_file | top_module
#
# Each entry is a thin shim that `includes test/common/hwpq_tb_common.svh, except the
# bug-reproduction tb, which is standalone. hybrid_tree is omitted: its RTL does not
# currently compile under iverilog.
TESTS=(
  # Enqueue-enabled runs
  "register_array|hwpq/register_array/test/register_array_tb.sv|register_array_tb"
  "register_array_pipelined|hwpq/register_array_pipelined/test/register_array_pipelined_tb.sv|register_array_pipelined_tb"
  "register_tree|hwpq/register_tree/test/register_tree_tb.sv|register_tree_tb"
  "register_tree_pipelined|hwpq/register_tree_pipelined/test/register_tree_pipelined_tb.sv|register_tree_pipelined_tb"
  "systolic_array|hwpq/systolic_array/test/systolic_array_tb.sv|systolic_array_tb"
  "bram_tree|hwpq/bram_tree/test/bram_tree_tb.sv|bram_tree_tb"
  # Replace-only (ENQ_ENA=0) runs: second sim of the same DUT
  "register_array|hwpq/register_array/test/register_array_enq0_tb.sv|register_array_enq0_tb"
  "register_array_pipelined|hwpq/register_array_pipelined/test/register_array_pipelined_enq0_tb.sv|register_array_pipelined_enq0_tb"
  "register_tree|hwpq/register_tree/test/register_tree_enq0_tb.sv|register_tree_enq0_tb"
  "register_tree_pipelined|hwpq/register_tree_pipelined/test/register_tree_pipelined_enq0_tb.sv|register_tree_pipelined_enq0_tb"
  # bram_tree_pipelined has no enqueue path -> replace-only only
  "bram_tree_pipelined|hwpq/bram_tree_pipelined/test/bram_tree_pipelined_tb.sv|bram_tree_pipelined_tb"
  # Bug-reproduction (kept separate from the shared harness)
  "systolic_array|hwpq/systolic_array/test/systolic_array_bug_tb.sv|systolic_array_bug_tb"
)

declare -a RESULTS=()
overall_status=0

for entry in "${TESTS[@]}"; do
  IFS='|' read -r module tb top <<< "$entry"
  echo "#############################################################"
  echo "# ${module}  (${tb})"
  echo "#############################################################"
  if "${SCRIPT_DIR}/run_sim.sh" "${module}" "${tb}" "${top}"; then
    RESULTS+=("PASS  ${module}  ${tb}")
  else
    RESULTS+=("FAIL  ${module}  ${tb}")
    overall_status=1
  fi
  echo
done

echo "============================================================"
echo "Summary"
echo "============================================================"
printf '%s\n' "${RESULTS[@]}"

exit "${overall_status}"

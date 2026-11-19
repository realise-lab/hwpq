#!/usr/bin/env bash
#
# Cycles per op of one architecture across queue sizes, measured by cycle_profile_tb.sv.
#
# Usage: test/perf/cycle_profile.sh <arch> [queue_size ...]
#   Sizes default to the synthesis sweep's: 2^k - 1 for trees, 2^k for arrays.
#   For hybrid_systolic_bram_heap a size is the node count of each tree.
# Settings, as environment variables:
#   SRC_ROOT  checkout holding hwpq/<arch>/src or hwpq/<arch>/rtl/src (this repository)
#   OUT       results root (hwpq), beside each architecture's synthesis results
#   RUNS      scratch root (build/cycle_profile); give concurrent calls on one arch their own
#   W (16), M (12000), STEP (3), SEEDS ("1"); TREES (16) and SYS (16) for the hybrid
#   SIM       iverilog (default), xrun or vcs; each must be on PATH with its licence
#   LOADS     loads to run ("mix stream"); stream dominates run time at large capacity
# Writes <OUT>/<arch>/cycle_profile_<W>bit/enqueue_<n>/cycle_profile_on_queue_size_<qs>.txt with
# a line per load (mix, stream) and value order: the mean over SEEDS of each cost, and the worst
# op as <name>_max.
set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../.." && pwd)"
ARCH="$1"; shift
SRC_ROOT="${SRC_ROOT:-${ROOT}}"
OUT="${OUT:-${ROOT}/hwpq}"
RUNS="${RUNS:-${ROOT}/build/cycle_profile}"
W=${W:-16}; M=${M:-12000}; STEP=${STEP:-3}; SEEDS=${SEEDS:-1}
TREES=${TREES:-16}; SYS=${SYS:-16}; SIM=${SIM:-iverilog}; LOADS=${LOADS:-mix stream}

SRC="${SRC_ROOT}/hwpq/${ARCH}/src"
[ -d "${SRC}" ] || SRC="${SRC_ROOT}/hwpq/${ARCH}/rtl/src"
shopt -s nullglob
FILES=("${SRC}"/*.sv)
[ ${#FILES[@]} -gt 0 ] || { echo "no sources for ${ARCH} under ${SRC_ROOT}"; exit 1; }
# Packages compile first.
SOURCES="$(grep -lE '^\s*package\s' "${FILES[@]}" || true) $(grep -LE '^\s*package\s' "${FILES[@]}" || true)"

case "${ARCH}" in
  *tree* | *heap*) SIZES="3 7 15 31 63 127 255 511 1023 2047" ;;
  systolic_array)  SIZES="8 16 32 64 128 256 512 1024 2048" ;;  # 4 deadlocks the shift network
  *)               SIZES="4 8 16 32 64 128 256 512 1024 2048" ;;
esac
[ $# -gt 0 ] && SIZES="$*"
ENQS=1; ENQ_PARAM=""
if grep -qE 'parameter[^;]*ENQ_ENA' "${FILES[@]}"; then ENQS="0 1"; ENQ_PARAM="DUT_ENQ_ENA"; fi
[ "${ARCH}" = bram_tree_pipelined ] && ENQS=0  # replace-only, with no ENQ_ENA parameter

ORDERS="uniform:0 nondecreasing:1 nonincreasing:-1"

# summary <log ...>: mean of each key over the RESULT lines; the max for keys ending in _max.
summary() {
  awk '$1 == "RESULT" {
      for (i = 2; i <= NF; i++) {
        split($i, kv, "="); k = kv[1]
        if (!(k in v)) keys[n++] = k
        if (k ~ /_max$/) { if (kv[2] > v[k]) v[k] = kv[2] } else { v[k] += kv[2]; runs[k]++ }
      }
    }
    END {
      for (i = 0; i < n; i++) {
        k = keys[i]
        if (k ~ /_max$/) printf " %s=%d", k, v[k]; else printf " %s=%.3f", k, v[k] / runs[k]
      }
    }' "$@"
}

for qs in ${SIZES}; do
  case "${ARCH}" in
    hybrid_systolic_bram_heap)
      CAP=$(( TREES * qs + 2 * (SYS - 2) ))
      DEFS="DUT=hybrid_systolic_heap DUT_NO_PARAMS HYBRID_TREE_COUNT=${TREES}
            HYBRID_BRAM_TREE_QUEUE_SIZE=${qs} HYBRID_SYSTOLIC_QUEUE_SIZE=${SYS}
            HYBRID_DATA_WIDTH=${W}" ;;
    systolic_array) CAP=$(( qs - 2 )); DEFS="DUT=${ARCH}" ;;  # shift-chain margin
    *)              CAP=${qs};         DEFS="DUT=${ARCH}" ;;
  esac
  DEFS="${DEFS} ${ENQ_PARAM}"

  for enq in ${ENQS}; do
    dir="${OUT}/${ARCH}/cycle_profile_${W}bit/enqueue_${enq}"
    runs="${RUNS}/${ARCH}/enqueue_${enq}"
    run="${runs}/qs${qs}"
    mkdir -p "${dir}" "${runs}"
    defs=(${DEFS})
    pars=(QS=${qs} W=${W} ENQ=${enq} CAP=${CAP} M=${M} STEP=${STEP})
    case "${SIM}" in
      iverilog)
        build=(iverilog -g2012 -o "${run}.vvp" -s cycle_profile_tb "${defs[@]/#/-D}"
               "${pars[@]/#/-Pcycle_profile_tb.}")
        sim=(vvp -n "${run}.vvp") ;;
      xrun)
        build=(xrun -q -sv -elaborate -nolog -timescale 1ns/1ps -top cycle_profile_tb
               -xmlibdirname "${run}.xcelium.d" "${defs[@]/#/+define+}")
        for p in "${pars[@]}"; do build+=(-defparam "cycle_profile_tb.${p}"); done
        sim=(xrun -q -R -nolog -xmlibdirname "${run}.xcelium.d") ;;
      vcs)
        build=(vcs -full64 -q -sverilog -timescale=1ns/1ps -top cycle_profile_tb
               -Mdir="${run}.csrc" -o "${run}.simv" "${defs[@]/#/+define+}"
               "${pars[@]/#/-pvalue+cycle_profile_tb.}")
        sim=("${run}.simv" -q) ;;
      *) echo "SIM must be iverilog, xrun or vcs"; exit 1 ;;
    esac
    (cd "${runs}" && "${build[@]}" ${SOURCES} "${HERE}/cycle_profile_tb.sv") \
      > "${run}.comp" 2>&1 || { cat "${run}.comp"; exit 1; }

    for load in ${LOADS}; do
      for order in ${ORDERS}; do
        for s in ${SEEDS}; do
          plus="+seed=${s} +mono=${order#*:}"
          [ "${load}" = stream ] && plus="${plus} +stream"
          (cd "${runs}" && "${sim[@]}" ${plus}) > "${run}_${load}_${order%:*}_${s}.log" 2>&1 &
        done
      done
    done
    wait
    for log in "${run}"_*.log; do
      grep -q '^RESULT' "${log}" || { echo "${log}:"; cat "${log}"; exit 1; }
    done

    result="${dir}/cycle_profile_on_queue_size_${qs}.txt"
    {
      echo "# ${ARCH} queue_size=${qs} capacity=${CAP} enqueue=${enq} data_width=${W}"
      for load in ${LOADS}; do
        for order in ${ORDERS}; do
          echo "${load} ${order%:*}$(summary "${run}_${load}_${order%:*}"_*.log)"
        done
      done
    } > "${result}"
    cat "${result}"
  done
done

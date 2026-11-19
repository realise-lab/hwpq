#!/usr/bin/env bash
#
# Instantiate the formal templates for a new architecture.
#
#   formal/tools/template/new_module.sh <module> [--aux] [--config <name>]
#
#   --aux            also create the white-box addendum and its bind
#   --config <name>  name the tcl config something other than <module>, for a
#                    second configuration of a module that already has one
#                    (e.g. an ENQ_ENA=0 build: --config <module>_enq0)
#
# Creates formal/bind/<module>_bind.sv and formal/config/<config>.cfg from
# formal/tools/template/, substituting the module name. Never overwrites.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

MODULE=""; CONFIG=""; AUX=0
while [ $# -gt 0 ]; do
  case "$1" in
    --aux)    AUX=1 ;;
    --config)
      shift
      [ $# -gt 0 ] && [ -n "$1" ] || { echo "--config needs a value" >&2; exit 2; }
      CONFIG="$1" ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *)  [ -z "$MODULE" ] && MODULE="$1" || { echo "unexpected argument: $1" >&2; exit 2; } ;;
  esac
  shift
done

[ -n "$MODULE" ] || { echo "usage: formal/tools/template/new_module.sh <module> [--aux] [--config <name>]" >&2; exit 2; }
[ -n "$CONFIG" ] || CONFIG="$MODULE"

SRC="hwpq/${MODULE}/src/${MODULE}.sv"
[ -f "$SRC" ] || { echo "no such module: ${SRC}" >&2; exit 1; }

emit() {  # emit <template> <destination>
  local tpl="${SCRIPT_DIR}/$1" dst="$2"
  [ -e "$dst" ] && { echo "  exists, left alone: $dst"; return 0; }
  sed "s/@MODULE@/${MODULE}/g" "$tpl" > "$dst"
  chmod 644 "$dst"
  echo "  created: $dst"
  created=1
}

created=0
emit MODULE_bind.sv "formal/bind/${MODULE}_bind.sv"
emit MODULE.cfg     "formal/config/${CONFIG}.cfg"
if [ "$AUX" -eq 1 ]; then
  emit MODULE_aux.sv      "formal/spec/hwpq_${MODULE}_aux.sv"
  emit MODULE_aux_bind.sv "formal/bind/${MODULE}_aux_bind.sv"
fi

[ "$created" -eq 1 ] || { echo "nothing to do."; exit 0; }

cat <<NEXT

Next, in order:

  1. Check the module against the uniform six-port interface before touching
     either file. A mismatch found there is much cheaper than a counterexample
     that turns out to be a spec premise.

  2. Answer the four questions marked ANSWER in
     formal/bind/${MODULE}_bind.sv.

  3. Set the geometry in formal/config/${CONFIG}.cfg. Small: these proofs are
     about protocol, not width.
NEXT
if [ "$AUX" -eq 1 ]; then
  cat <<NEXT
  4. Say what formal/spec/hwpq_${MODULE}_aux.sv is for, in prose, before
     writing a property in it. Add both new files to the cfg's source list.

  5. formal/run.sh ${CONFIG}
NEXT
else
  echo "  4. formal/run.sh ${CONFIG}"
fi
cat <<'NEXT'

Read the elaboration warnings BEFORE the property table. On a newly bound
module the harness is the newer, less exercised artifact.

If a run finds a defect and you fix it, add a row to formal/tools/mutations/SWEEP.tsv.
NEXT

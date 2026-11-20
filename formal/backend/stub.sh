# formal/backend/stub.sh - launcher for the licence-free stub backend.
# Sourced by formal/run.sh when FORMAL_BACKEND=stub.

backend_available() { command -v tclsh >/dev/null 2>&1; }

backend_prepare() { :; }

backend_launch() {
  cfg="$1"; outdir="$2"; log="$3"
  HWPQ_CFG="$cfg" HWPQ_OUTDIR="$outdir" FORMAL_BACKEND=stub \
    timeout --signal=TERM --kill-after=30 "${TIMEOUT:-1800}" \
    tclsh formal/drive.tcl 2>&1 | tee "$log"
  return "${PIPESTATUS[0]}"
}

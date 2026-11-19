import os

# Output settings
OUTPUT_DIR = "../vivado-analysis_plots"

# Cycle profiler results (test/perf/cycle_profile.sh): <dir>/<arch>/<name>/enqueue_<n>/, with the
# dir its OUT when not the default.
CYCLE_PROFILE_DIR = os.environ.get(
    "CYCLE_PROFILE_DIR",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "hwpq"),
)
CYCLE_PROFILE_NAME = "cycle_profile_16bit"
# Load whose per-op cost sets throughput.
PROFILE_LOAD = ("mix", "uniform")

# Plotted against total capacity, read from its result files, not the per-tree QUEUE_SIZE.
HYBRID_ARCH = "hybrid_systolic_bram_heap"

# Architectures built without ENQ_ENA: one variant, whichever enqueue_<n> directory holds it.
SINGLE_VARIANT = {"systolic_array", "bram_tree_pipelined", "bram_tree_pair", HYBRID_ARCH}
# Not plotted: its results predate the current RTL and it has no cycle profile.
EXCLUDED_ARCHS = {"hybrid_tree"}

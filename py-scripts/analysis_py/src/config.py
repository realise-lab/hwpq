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
# Load whose per-op cost sets throughput; an op it does not measure falls back to
# PERFORMANCE_FACTORS.
PROFILE_LOAD = ("mix", "uniform")

# Plotted against total capacity, read from its result files, not the per-tree QUEUE_SIZE.
HYBRID_ARCH = "hybrid_systolic_bram_heap"

# Architectures built without ENQ_ENA: one variant, whichever enqueue_<n> directory holds it.
SINGLE_VARIANT = {"systolic_array", "bram_tree", "bram_tree_pipelined", "bram_tree_pair", HYBRID_ARCH}

# Cycles-per-op fallbacks as throughput factors (ops per cycle), used where no profile exists.
PERFORMANCE_FACTORS = {
    "enqueue": {
        "register_array_enq_enabled": 1,
        "register_array_pipelined_enq_enabled": 1/2,
        # register_tree handled specially with log2 formula
        "systolic_array": 1,
        # bram_tree, pipelined_bram_tree and hybrid tree do not support enqueue operation
    },
    "dequeue": {
        "register_array_enq_disabled": 1,
        "register_array_enq_enabled": 1,
        "register_array_pipelined_enq_disabled": 1/2,
        "register_array_pipelined_enq_enabled": 1/2,
        "register_tree_enq_disabled": 1,
        "register_tree_enq_enabled": 1,
        "register_tree_pipelined_enq_disabled": 1/2,
        "register_tree_pipelined_enq_enabled": 1/2,
        "systolic_array": 1,
        "bram_tree": 1/8,
        "bram_tree_pipelined": 1/4,
        "hybrid_tree": 1,
    },
    "replace": {
        "register_array_enq_disabled": 1,
        "register_array_enq_enabled": 1,
        "register_array_pipelined_enq_disabled": 1/2,
        "register_array_pipelined_enq_enabled": 1/2,
        "register_tree_enq_disabled": 1,
        "register_tree_enq_enabled": 1,
        "register_tree_pipelined_enq_disabled": 1/2,
        "register_tree_pipelined_enq_enabled": 1/2,
        "systolic_array": 1,
        "bram_tree": 1/8,
        "bram_tree_pipelined": 1/4,
        "hybrid_tree": 1,
    },
}

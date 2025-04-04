# Output settings
OUTPUT_DIR = "vivado_analysis_results_plots"
OUTPUT_FILENAME = "analysis_plots.pdf"

# Performance factors for operations across architectures
PERFORMANCE_FACTORS = {
    "enqueue": {
        # "register_array": 1 / 2,
        # "register_array_enq_disabled": 0,
        "systolic_array": 1 / 2,
        # register_array with enqueue option enabled handled specifally during data processing with N/2
        # register_tree handled specially with log2 formula
        # bram_tree, pipelined_bram_tree and hybrid tree do not support enqueue operation
    },
    "dequeue": {
        # "register_array": 1 / 2,
        "register_array_enq_disabled": 1,
        "register_array_enq_enabled": 1,
        "systolic_array": 1 / 2,
        "register_tree": 1 / 2,
        "bram_tree": 1 / 8,
        "pipelined_bram_tree": 1 / 4,
        "hybrid_tree": 1 / 2,
    },
    "replace": {
        # "register_array": 1 / 2,
        "register_array_enq_disabled": 1,  # Same replace performance even when enqueue is disabled
        "register_array_enq_enabled": 1,  # Same replace performance when enqueue is enabled
        "systolic_array": 1 / 2,
        "register_tree": 1 / 2,
        "bram_tree": 1 / 8,
        "pipelined_bram_tree": 1 / 4,
        "hybrid_tree": 1 / 2,
    },
}

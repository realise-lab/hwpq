# Output settings
OUTPUT_DIR = "../vivado-analysis_plots"

# Performance factors for operations across architectures
PERFORMANCE_FACTORS = {
    "enqueue": {
        # register_array with enqueue option enabled handled specifally during data processing with N/2
        # register_tree handled specially with log2 formula
        "systolic_array": 1/2,
        # bram_tree, pipelined_bram_tree and hybrid tree do not support enqueue operation
    },
    "dequeue": {
        "register_array_enq_disabled": 1,
        "register_array_enq_enabled": 1,
        "register_array_cycled_enq_disabled": 1/2,
        "register_array_cycled_enq_enabled": 1/2,
        "register_tree_enq_disabled": 1,
        "register_tree_enq_enabled": 1,
        "register_tree_cycled_enq_disabled": 1/2,
        "register_tree_cycled_enq_enabled": 1/2,
        "systolic_array": 1/2,
        "bram_tree": 1/8,
        "pipelined_bram_tree": 1/4,
        "hybrid_tree": 1,
    },
    "replace": {
        "register_array_enq_disabled": 1,
        "register_array_enq_enabled": 1,
        "register_array_cycled_enq_disabled": 1/2,
        "register_array_cycled_enq_enabled": 1/2,
        "register_tree_enq_disabled": 1,
        "register_tree_enq_enabled": 1,
        "register_tree_cycled_enq_disabled": 1/2,
        "register_tree_cycled_enq_enabled": 1/2,
        "systolic_array": 1/2,
        "bram_tree": 1/8,
        "pipelined_bram_tree": 1/4,
        "hybrid_tree": 1,
    },
}

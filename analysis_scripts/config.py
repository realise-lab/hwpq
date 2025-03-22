"""Configuration settings for the HWPQ analysis."""

# Output settings
OUTPUT_DIR = "vivado_analysis_results_plots"
OUTPUT_FILENAME = "analysis_plots.pdf"

# Performance factors for operations across architectures
PERFORMANCE_FACTORS = {
    "enqueue": {
        "register_array": 1/2, 
        "systolic_array": 1/2,
        # register_tree handled specially with log2 formula
        # bram_tree and pipelined_bram_tree do not support enqueue operation
    },
    "dequeue": {
        "register_array": 1/2, 
        "systolic_array": 1/2, 
        "register_tree": 1/2, 
        "bram_tree": 1/8, 
        "pipelined_bram_tree": 1/4,
        "hybrid_tree": 1/2
    },
    "replace": {
        "register_array": 1/2, 
        "systolic_array": 1/2, 
        "register_tree": 1/2, 
        "bram_tree": 1/8, 
        "pipelined_bram_tree": 1/4,
        "hybrid_tree": 1/2
    }
}

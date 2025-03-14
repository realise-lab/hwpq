"""Configuration settings for the HWPQ analysis."""

# Directory paths
REGISTER_ARRAY_LOG_DIR = "register_array/vivado_analysis_results_16bit/"
REGISTER_TREE_LOG_DIR = "register_tree/vivado_analysis_results_16bit/"
SYSTOLIC_ARRAY_LOG_DIR = "systolic_array/vivado_analysis_results_16bit/"
BRAM_TREE_LOG_DIR = "bram_tree/vivado_analysis_results_16bit/"
PIPELINED_BRAM_TREE_LOG_DIR = "pipelined_bram_tree/vivado_analysis_results_16bit/"
HYBRID_TREE_LOG_DIR = "hybrid_tree/vivado_analysis_results_16bit/"

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
        "bram_tree": 1/7, 
        "pipelined_bram_tree": 1/4
    },
    "replace": {
        "register_array": 1/2, 
        "systolic_array": 1/2, 
        "register_tree": 1/2, 
        "bram_tree": 1/7, 
        "pipelined_bram_tree": 1/4
    }
}

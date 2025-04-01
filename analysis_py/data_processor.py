"""
Data processing functions for Vivado analysis results.
"""

import os
import numpy as np
from math import log2
import parsers
from config import PERFORMANCE_FACTORS


def sort_xy(x, y):
    """
    Sort x, y pairs based on x value.

    Args:
        x (list): X values
        y (list): Y values

    Returns:
        tuple: ([sorted x values], [corresponding y values])
    """
    # Use numpy to sort x and y arrays
    x = np.array(x)
    y = np.array(y)
    sort_idx = np.argsort(x)

    return x[sort_idx], y[sort_idx]


def get_max_achieved_frequency(data_dict):
    """
    For each queue size, get the maximum achieved frequency.

    Args:
        data_dict (dict): Data returned from parser.process_directory function

    Returns:
        tuple: ([queue sizes], [maximum achieved frequencies])
    """
    queue_sizes = []
    max_frequencies = []

    for queue_size, metrics in data_dict.items():
        # Extract the maximum achieved frequency
        if "max_achieved_frequency" in metrics:
            max_freq = metrics["max_achieved_frequency"]

            # Add to our lists
            queue_sizes.append(queue_size)
            max_frequencies.append(max_freq)

    # Sort by queue size for better visualization
    return sort_xy(queue_sizes, max_frequencies)


def get_lut_usage(data_dict):
    """
    For each queue size, get the number of LUTs used.

    Args:
        data_dict (dict): Data returned from parser.process_directory function

    Returns:
        tuple: ([queue sizes], [LUT usage counts])
    """
    queue_sizes = []
    lut_usage = []

    for queue_size, metrics in data_dict.items():
        # Extract the LUTs used
        if "luts_used" in metrics:
            luts = metrics["luts_used"]

            # Add to our lists
            queue_sizes.append(queue_size)
            lut_usage.append(luts)

    # Sort by queue size for better visualization
    return sort_xy(queue_sizes, lut_usage)


def get_lut_utilization(data_dict):
    """
    For each queue size, get the LUT utilization percentage.

    Args:
        data_dict (dict): Data returned from parser.process_directory function

    Returns:
        tuple: ([queue sizes], [LUT utilization percentages])
    """
    queue_sizes = []
    lut_util = []

    for queue_size, metrics in data_dict.items():
        # Extract the LUT utilization percentage
        if "luts_util_percent" in metrics:
            util = metrics["luts_util_percent"]

            # Add to our lists
            queue_sizes.append(queue_size)
            lut_util.append(util)

    # Sort by queue size for better visualization
    return sort_xy(queue_sizes, lut_util)


def get_register_usage(data_dict):
    """
    For each queue size, get the number of registers used.

    Args:
        data_dict (dict): Data returned from parser.process_directory function

    Returns:
        tuple: ([queue sizes], [register usage counts])
    """
    queue_sizes = []
    reg_usage = []

    for queue_size, metrics in data_dict.items():
        # Extract the registers used
        if "registers_used" in metrics:
            regs = metrics["registers_used"]

            # Add to our lists
            queue_sizes.append(queue_size)
            reg_usage.append(regs)

    # Sort by queue size for better visualization
    return sort_xy(queue_sizes, reg_usage)


def get_register_utilization(data_dict):
    """
    For each queue size, get the register utilization percentage.

    Args:
        data_dict (dict): Data returned from parser.process_directory function

    Returns:
        tuple: ([queue sizes], [register utilization percentages])
    """
    queue_sizes = []
    reg_util = []

    for queue_size, metrics in data_dict.items():
        # Extract the register utilization percentage
        if "registers_util_percent" in metrics:
            util = metrics["registers_util_percent"]

            # Add to our lists
            queue_sizes.append(queue_size)
            reg_util.append(util)

    # Sort by queue size for better visualization
    return sort_xy(queue_sizes, reg_util)


def get_bram_usage(data_dict):
    """
    For each queue size, get the number of BRAMs used.

    Args:
        data_dict (dict): Data returned from parser.process_directory function

    Returns:
        tuple: ([queue sizes], [BRAM usage counts])
    """
    queue_sizes = []
    bram_usage = []

    for queue_size, metrics in data_dict.items():
        # Extract the BRAMs used
        if "bram_used" in metrics:
            brams = metrics["bram_used"]

            # Add to our lists
            queue_sizes.append(queue_size)
            bram_usage.append(brams)

    # Sort by queue size for better visualization
    return sort_xy(queue_sizes, bram_usage)


def get_bram_utilization(data_dict):
    """
    For each queue size, get the BRAM utilization percentage.

    Args:
        data_dict (dict): Data returned from parser.process_directory function

    Returns:
        tuple: ([queue sizes], [BRAM utilization percentages])
    """
    queue_sizes = []
    bram_util = []

    for queue_size, metrics in data_dict.items():
        # Extract the BRAM utilization percentage
        if "bram_util_percent" in metrics:
            util = metrics["bram_util_percent"]

            # Add to our lists
            queue_sizes.append(queue_size)
            bram_util.append(util)

    # Sort by queue size for better visualization
    return sort_xy(queue_sizes, bram_util)


def compute_performance(data_dict, arch, operation):
    """
    For each queue size, compute raw performance as a function of achieved frequency
    and architecture-specific performance factors.

    Args:
        data_dict (dict): Data returned from parser.process_directory function
        arch (str): Architecture name
        operation (str): Operation type ('enqueue', 'dequeue', 'replace')

    Returns:
        tuple: ([queue sizes], [performance values])
    """
    queue_sizes = []
    performance_values = []

    for queue_size, metrics in data_dict.items():
        # Extract the maximum achieved frequency
        if "max_achieved_frequency" in metrics:
            max_freq = metrics["max_achieved_frequency"]

            # Calculate performance based on architecture and operation
            if arch == "register_tree" and operation == "enqueue":
                # Special case for register tree enqueue where performance scales with log2(queue_size)
                perf_factor = 1 / log2(queue_size) if queue_size > 1 else 1
            else:
                # For other architectures/operations, use predefined performance factors
                perf_factor = PERFORMANCE_FACTORS.get(operation, {}).get(arch, 1)

            performance = max_freq * perf_factor

            # Add to our lists
            queue_sizes.append(queue_size)
            performance_values.append(performance)

    # Sort by queue size for better visualization
    return sort_xy(queue_sizes, performance_values)


def compute_resource_utilization(data_dict):
    queue_sizes = []
    resource_utilization = []

    for queue_size, metrics in data_dict.items():
        if "max_achieved_frequency" in metrics:
            # max_freq = metrics["max_achieved_frequency"]
            lut_utilization = metrics["luts_util_percent"]
            reg_utilization = metrics["registers_util_percent"]
            bram_utilization = metrics["bram_util_percent"]

            resource = np.max([lut_utilization, reg_utilization, bram_utilization])

            # Add to our lists
            queue_sizes.append(queue_size)
            resource_utilization.append(resource)

    # Sort by queue size for better visualization
    return sort_xy(queue_sizes, resource_utilization)


def compute_resource_utilization_efficiency(data_dict, arch, operation):
    """
    Calculate area efficiency by dividing performance by area (LUT count, Register count and BRAM count)
    Lower values indicate better area efficiency.

    Args:
        data_dict (dict): Data returned from parser.process_directory function
        arch (str): Architecture name
        operation (str): Operation type ('enqueue', 'dequeue', 'replace')

    Returns:
        tuple: ([queue sizes], [area efficiency values])
    """
    queue_sizes = []
    efficiency_values = []

    for queue_size, metrics in data_dict.items():
        if "max_achieved_frequency" in metrics:
            max_freq = metrics["max_achieved_frequency"]
            lut_utilization = metrics["luts_util_percent"]
            reg_utilization = metrics["registers_util_percent"]
            bram_utilization = metrics["bram_util_percent"]

            resource = np.max([lut_utilization, reg_utilization, bram_utilization])

            # Calculate performance factor based on architecture and operation
            if arch == "register_tree" and operation == "enqueue":
                # Special case for register tree enqueue where performance scales with log2(queue_size)
                perf_factor = 1 / log2(queue_size) if queue_size > 1 else 1
            else:
                # For other architectures/operations, use predefined performance factors
                perf_factor = PERFORMANCE_FACTORS.get(operation, {}).get(arch, 1)

            # Calculate performance
            performance = max_freq * perf_factor

            # Calculate resource utilization efficiency (performance/resource)
            # Higher is better: more performance achieved with less resource
            efficiency = performance / resource if performance > 0 else float("inf")

            # Add to our lists
            queue_sizes.append(queue_size)
            efficiency_values.append(efficiency)

    # Sort by queue size for better visualization
    return sort_xy(queue_sizes, efficiency_values)


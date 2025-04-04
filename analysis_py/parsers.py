"""
Parsing functions for Vivado analysis log files/directories.
"""

import os
import re
import numpy as np


def parse_achieved_frequencies(file_path):
    """
    Parses a Vivado log file to extract target clock frequencies and their corresponding achieved frequencies.

    Args:
        file_path (str): Path to the Vivado implementation log file to parse.

    Returns:
        tuple: Two parallel lists (given_frequencies, achieved_frequencies) where:
            - given_frequencies (list[float]): Target clock frequencies in MHz.
            - achieved_frequencies (list[float]): Actually achieved frequencies in MHz after implementation.

    Note:
        Each index in both lists corresponds to the same implementation run.
    """
    given_frequencies = []
    achieved_frequencies = []

    with open(file_path, "r") as f:
        for line in f:
            line = line.strip()

            # Extract given frequency
            if "Frequency:" in line and "Achieved Frequency" in line:
                try:
                    # Extract given frequency
                    parts = line.split("Frequency:")
                    freq = float(parts[1].split("MHz")[0].strip())

                    # Extract achieved frequency
                    parts = line.split("Achieved Frequency:")
                    a_freq = float(parts[1].split("MHz")[0].strip())

                    given_frequencies.append(freq)
                    achieved_frequencies.append(a_freq)

                except (ValueError, IndexError):
                    continue

    return given_frequencies, achieved_frequencies


def parse_metrics(file_path):
    """
    Parses a Vivado log file to extract performance and resource utilization metrics
    for the implementation with the maximum achieved frequency.

    Args:
        file_path (str): Path to the Vivado log file.

    Returns:
        dict: Dictionary containing extracted metrics including:
            - queue_size: Size of the queue extracted from file name
            - max_achieved_frequency: Maximum achieved clock frequency in MHz
            - power: Power consumption in Watts (if available)
            - luts_used: Number of CLB LUTs used
            - luts_util_percent: CLB LUTs utilization percentage
            - registers_used: Number of CLB registers used
            - registers_util_percent: CLB registers utilization percentage
            - bram_used: BRAM blocks used
            - bram_util_percent: BRAM utilization percentage
    """
    metrics = {}

    # Find the maximum achieved freqency and the given frequency for that
    given_frequencies, achieved_frequencies = parse_achieved_frequencies(file_path)
    max_freq = np.max(achieved_frequencies)
    max_freq_index = achieved_frequencies.index(max_freq)
    max_freq_given = given_frequencies[max_freq_index]

    # Extract queue size from file name
    queue_size = None
    try:
        queue_size_match = re.search(r"queue_size_(\d+)", file_path)
        if queue_size_match:
            queue_size = int(queue_size_match.group(1))
        else:
            # Fallback to simpler extraction if regex fails
            file_name = file_path.split("/")[-1]
            parts = file_name.split("_")
            queue_size = int(parts[-1].split(".")[0])
    except (ValueError, IndexError):
        queue_size = 0  # Default value if extraction fails

    # Initialize metrics dictionary with queue size and max frequency
    metrics = {"queue_size": queue_size, "max_achieved_frequency": max_freq}

    # Get all metrics for this queue size when the frequency is the maximum
    with open(file_path, "r") as f:
        for line in f:
            line = line.strip()

            # Extract Power
            if "Frequency:" in line and "Power" in line:
                try:
                    # Extract the frequency from the line
                    parts = line.split("Frequency:")
                    freq = float(parts[1].split("MHz")[0].strip())

                    # Extract power
                    parts = line.split("Power:")
                    power = float(parts[1].split("W")[0].strip())

                    # If this frequency is equal to the max frequency, add to metrics
                    if (
                        abs(freq - max_freq_given) < 1e-6
                    ):  # Using small epsilon for float comparison
                        metrics["power"] = power

                except (ValueError, IndexError):
                    continue

            # Extract CLB LUTs Used
            if "Frequency:" in line and "CLB LUTs Used" in line:
                try:
                    # Extract the frequency from the line
                    parts = line.split("Frequency:")
                    freq = float(parts[1].split("MHz")[0].strip())

                    # Extract LUTs used
                    parts = line.split("CLB LUTs Used:")
                    luts_used = int(parts[1].strip())

                    # If this frequency is equal to the max frequency, add to metrics
                    if (
                        abs(freq - max_freq_given) < 1e-6
                    ):  # Using small epsilon for float comparison
                        metrics["luts_used"] = luts_used

                except (ValueError, IndexError):
                    continue

            # Extract CLB LUTs Utilization
            if "Frequency:" in line and "CLB LUTs Util%" in line:
                try:
                    # Extract the frequency from the line
                    parts = line.split("Frequency:")
                    freq = float(parts[1].split("MHz")[0].strip())

                    # Extract LUTs utilization
                    parts = line.split("CLB LUTs Util%:")
                    luts_util = float(parts[1].split("%")[0].strip())

                    # If this frequency is equal to the max frequency, add to metrics
                    if (
                        abs(freq - max_freq_given) < 1e-6
                    ):  # Using small epsilon for float comparison
                        metrics["luts_util_percent"] = luts_util

                except (ValueError, IndexError):
                    continue

            # Extract CLB Registers Used
            if "Frequency:" in line and "CLB Registers Used" in line:
                try:
                    # Extract the frequency from the line
                    parts = line.split("Frequency:")
                    freq = float(parts[1].split("MHz")[0].strip())

                    # Extract Registers used
                    parts = line.split("CLB Registers Used:")
                    regs_used = int(parts[1].strip())

                    # If this frequency is equal to the max frequency, add to metrics
                    if (
                        abs(freq - max_freq_given) < 1e-6
                    ):  # Using small epsilon for float comparison
                        metrics["registers_used"] = regs_used

                except (ValueError, IndexError):
                    continue

            # Extract CLB Registers Utilization Percentage
            if "Frequency:" in line and "CLB Registers Util%" in line:
                try:
                    # Extract the frequency from the line
                    parts = line.split("Frequency:")
                    freq = float(parts[1].split("MHz")[0].strip())

                    # Extract Registers utilization
                    parts = line.split("CLB Registers Util%:")
                    regs_util = float(parts[1].split("%")[0].strip())

                    # If this frequency is equal to the max frequency, add to metrics
                    if (
                        abs(freq - max_freq_given) < 1e-6
                    ):  # Using small epsilon for float comparison
                        metrics["registers_util_percent"] = regs_util

                except (ValueError, IndexError):
                    continue

            # Extract BRAM Used
            if "Frequency:" in line and "BRAM Util:" in line:
                try:
                    # Extract the frequency from the line
                    parts = line.split("Frequency:")
                    freq = float(parts[1].split("MHz")[0].strip())

                    # Extract BRAM used
                    parts = line.split("BRAM Util:")
                    bram_used = float(parts[1].strip())

                    # If this frequency is equal to the max frequency, add to metrics
                    if (
                        abs(freq - max_freq_given) < 1e-6
                    ):  # Using small epsilon for float comparison
                        metrics["bram_used"] = bram_used

                except (ValueError, IndexError):
                    continue

            # Extract BRAM Utilization Percentage
            if "Frequency:" in line and "BRAM Util%:" in line:
                try:
                    # Extract the frequency from the line
                    parts = line.split("Frequency:")
                    freq = float(parts[1].split("MHz")[0].strip())

                    # Extract BRAM utilization
                    parts = line.split("BRAM Util%:")
                    bram_util = float(parts[1].split("%")[0].strip())

                    # If this frequency is equal to the max frequency, add to metrics
                    if (
                        abs(freq - max_freq_given) < 1e-6
                    ):  # Using small epsilon for float comparison
                        metrics["bram_util_percent"] = bram_util

                except (ValueError, IndexError):
                    continue

    return metrics


def process_directory(log_dir):
    """
    Process Vivado analysis log files to extract performance metrics for various queue sizes.

    This function scans the specified directory for log files that match the pattern
    containing "vivado_analysis_on_queue_size" and extracts metrics for each queue size.
    It also supports nested directory structures with enqueue_0 and enqueue_1 subdirectories.

    Args:
        log_dir (str): Path to directory containing Vivado analysis log files.

    Returns:
        dict or tuple: If no subdirectories are found, returns a dictionary mapping 
                      queue sizes (int) to metrics dictionary. If subdirectories like
                      enqueue_0/enqueue_1 are found, returns a tuple with two 
                      dictionaries (enqueue_disabled_data, enqueue_enabled_data).

    Note:
        Files must follow the naming convention that includes "vivado_analysis_on_queue_size"
        and end with the queue size (e.g., "vivado_analysis_on_queue_size_64.txt").
    """
    # Check if this directory has enqueue_0/enqueue_1 subdirectories
    contents = os.listdir(log_dir)
    if "enqueue_0" in contents and "enqueue_1" in contents:
        # Process both subdirectories
        enqueue_disabled_data = _process_files(os.path.join(log_dir, "enqueue_0"))
        enqueue_enabled_data = _process_files(os.path.join(log_dir, "enqueue_1"))
        return (enqueue_disabled_data, enqueue_enabled_data)
    else:
        # Process files in the main directory
        return _process_files(log_dir)


def _process_files(log_dir):
    """
    Helper function to process files in a directory.
    
    Args:
        log_dir (str): Path to directory containing log files.
        
    Returns:
        dict: Dictionary mapping queue sizes to metrics.
    """
    data_dict = {}
    for file_name in os.listdir(log_dir):
        if file_name.endswith(".txt") and "vivado_analysis_on_queue_size" in file_name:
            file_path = os.path.join(log_dir, file_name)

            # Extract queue size from filename
            queue_size = int(file_name.split("_")[-1].split(".")[0])

            # Get other metrics
            metrics = parse_metrics(file_path)

            # Store metrics in dictionary
            data_dict[queue_size] = metrics

    return data_dict


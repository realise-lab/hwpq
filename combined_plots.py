import os
import matplotlib.pyplot as plt
import numpy as np
from math import log2

plt.rcParams.update({"font.size": 16})

TOTAL_LUTS = 141000

# ----- Parsing Functions -----

def parse_achieved_frequencies(file_path):
    """
    Parses a log file to extract frequencies and achieved frequencies.
    Expected line format: "Frequency: 150 MHz -> Achieved Frequency: 138.242 MHz"
    """
    frequencies = []
    achieved_frequencies = []
    with open(file_path, "r") as f:
        for line in f:
            if "Frequency" in line and "Achieved Frequency" in line:
                parts = line.split("->")
                # Extract frequency and achieved frequency
                freq_part = parts[0].strip().split(" ")[1]
                achieved_freq_part = parts[1].strip().split(" ")[2]
                frequencies.append(float(freq_part))
                achieved_frequencies.append(float(achieved_freq_part))
    return frequencies, achieved_frequencies


def extrapolate_final_achieved_frequency(achieved_frequencies):
    """Returns the maximum achieved frequency."""
    return np.max(achieved_frequencies)


def parse_area_utilization_dict(file_path):
    """
    Parses a log file to extract LUTs Util% as a dictionary keyed by frequency.
    Expected line format: "Frequency: 150 MHz -> LUTs Util%: 0.07 %"
    """
    utilization_data = {}
    with open(file_path, "r") as f:
        for line in f:
            if "Frequency" in line and "LUTs Util%" in line:
                parts = line.split("->")
                freq = float(parts[0].split(":")[1].strip().split(" ")[0])
                util = float(parts[1].strip().split(" ")[2])
                utilization_data[freq] = util
    return utilization_data


def parse_area_utilization_list(file_path):
    """
    Parses a log file to extract LUTs Util% as a list (order maintained as in file).
    """
    utilization_data = []
    with open(file_path, "r") as f:
        for line in f:
            if "Frequency" in line and "LUTs Util%" in line:
                parts = line.split("->")
                util = float(parts[1].strip().split(" ")[2])
                utilization_data.append(util)
    return utilization_data

def parse_bram_utilization_dict(file_path):
    """
    Parses a log file to extract LUTs Util% as a dictionary keyed by frequency.
    Expected line format: "Frequency: 150 MHz -> LUTs Util%: 0.07 %"
    """
    utilization_data = {}
    with open(file_path, "r") as f:
        for line in f:
            if "Frequency" in line and "BRAM Util" in line:
                parts = line.split("->")
                freq = float(parts[0].split(":")[1].strip().split(" ")[0])
                util = float(parts[1].strip().split(" ")[2])
                utilization_data[freq] = util
    return utilization_data

def parse_bram_utilization_list(file_path):
    """
    Parses a log file to extract LUTs Util% as a list (order maintained as in file).
    """
    utilization_data = []
    with open(file_path, "r") as f:
        for line in f:
            if "Frequency" in line and "BRAM Util" in line:
                parts = line.split("->")
                util = float(parts[1].strip().split(" ")[2])
                utilization_data.append(util)
    return utilization_data

# ----- Directory Processing Functions -----

def process_directory_achieved(log_dir):
    """
    Process log files to extract achieved frequency data.
    Returns a dictionary: key = queue_size, value = (frequencies, achieved_frequencies)
    """
    data = {}
    files = sorted(os.listdir(log_dir), key=lambda x: int(x.split("_")[-1].split(".")[0]))
    for file_name in files:
        if file_name.startswith("vivado_analysis_on_queue_size") and file_name.endswith(".txt"):
            queue_size = int(file_name.split("_")[-1].split(".")[0])
            file_path = os.path.join(log_dir, file_name)
            frequencies, achieved_frequencies = parse_achieved_frequencies(file_path)
            data[queue_size] = (frequencies, achieved_frequencies)
    return data


def process_directory_area_dict(log_dir):
    """
    Process log files to extract average LUT utilization (using dict parsing).
    Returns a dictionary: key = queue_size, value = average LUT count (converted from percentage).
    """
    data = {}
    files = sorted(os.listdir(log_dir), key=lambda x: int(x.split("_")[-1].split(".")[0]))
    for file_name in files:
        if file_name.startswith("vivado_analysis_on_queue_size") and file_name.endswith(".txt"):
            queue_size = int(file_name.split("_")[-1].split(".")[0])
            file_path = os.path.join(log_dir, file_name)
            util_dict = parse_area_utilization_dict(file_path)
            if util_dict:
                avg_util = sum(util_dict.values()) / len(util_dict)
                # Convert percentage to actual LUT count
                data[queue_size] = avg_util * 0.01 * TOTAL_LUTS
    return data

def process_directory_bram_dict(log_dir):
    """
    Process log files to extract average LUT utilization (using dict parsing).
    Returns a dictionary: key = queue_size, value = average LUT count (converted from percentage).
    """
    data = {}
    files = sorted(os.listdir(log_dir), key=lambda x: int(x.split("_")[-1].split(".")[0]))
    for file_name in files:
        if file_name.startswith("vivado_analysis_on_queue_size") and file_name.endswith(".txt"):
            queue_size = int(file_name.split("_")[-1].split(".")[0])
            file_path = os.path.join(log_dir, file_name)
            util_dict = parse_bram_utilization_dict(file_path)
            if util_dict:
                avg_util = sum(util_dict.values()) / len(util_dict)
                data[queue_size] = avg_util
    return data

def process_directory_all(log_dir):
    """
    Process log files to extract achieved frequencies and LUT/BRAM utilization (list version).
    Returns a dictionary: key = queue_size, value = (frequencies, achieved_frequencies, utilization_list, bram_list)
    For non-BRAM architectures, bram_list will be None
    """
    data = {}
    files = sorted(os.listdir(log_dir), key=lambda x: int(x.split("_")[-1].split(".")[0]))
    for file_name in files:
        if file_name.startswith("vivado_analysis_on_queue_size") and file_name.endswith(".txt"):
            queue_size = int(file_name.split("_")[-1].split(".")[0])
            file_path = os.path.join(log_dir, file_name)
            freqs, achieved_freqs = parse_achieved_frequencies(file_path)
            util_list = parse_area_utilization_list(file_path)
            # If parsing BRAM tree directory, include BRAM utilization
            if "BRAM_tree" in log_dir:
                bram_list = parse_bram_utilization_list(file_path)
            else:
                bram_list = None
            data[queue_size] = (freqs, achieved_freqs, util_list, bram_list)
    return data

# ----- Data Processing for Architectures -----

# Define log directories
register_array_log_dir = "register_array/vivado_register_array_analysis_results_16bit/"
register_tree_log_dir  = "register_tree/vivado_register_tree_analysis_results_16bit/"
systolic_array_log_dir = "systolic_array/vivado_systolic_array_analysis_results_16bit/"
bram_tree_log_dir = "BRAM_tree/vivado_BRAM_tree_analysis_results_16bit/"

# Process achieved frequency data
ra_achieved = process_directory_achieved(register_array_log_dir)
rt_achieved = process_directory_achieved(register_tree_log_dir)
sa_achieved = process_directory_achieved(systolic_array_log_dir)
bt_achieved = process_directory_achieved(bram_tree_log_dir)

# Process area utilization (using dict to compute average) data
ra_area = process_directory_area_dict(register_array_log_dir)
rt_area = process_directory_area_dict(register_tree_log_dir)
sa_area = process_directory_area_dict(systolic_array_log_dir)
bt_area = process_directory_area_dict(bram_tree_log_dir)

# Process BRAM utilization data
bt_bram = process_directory_bram_dict(bram_tree_log_dir)

# Process all data (for LUT utilization vs achieved frequency and area over frequency plots)
ra_all = process_directory_all(register_array_log_dir)
rt_all = process_directory_all(register_tree_log_dir)
sa_all = process_directory_all(systolic_array_log_dir)
bt_all = process_directory_all(bram_tree_log_dir)

# ----- Compute Derived Data -----

def compute_final_achieved(data):
    """
    For each queue size, compute the maximum achieved frequency.
    Returns a dict: key = queue_size, value = final achieved frequency.
    """
    final = {}
    for qs, (freqs, achieved) in data.items():
        final[qs] = np.max(achieved)
    return final

ra_final_freq = compute_final_achieved(ra_achieved)
rt_final_freq = compute_final_achieved(rt_achieved)
sa_final_freq = compute_final_achieved(sa_achieved)
bt_final_freq = compute_final_achieved(bt_achieved)

def compute_utilization_vs_freq(data_dict):
    """
    For each queue size, select the maximum achieved frequency and corresponding LUT utilization from list.
    Returns two lists: x (LUT utilization count) and y (achieved frequency).
    """
    x_vals = []
    y_vals = []
    for qs, (freqs, achieved, util_list, bram_list) in data_dict.items():
        if achieved:
            max_achieved = max(achieved)
            idx = achieved.index(max_achieved)
            util = util_list[idx]
            x_vals.append(util * 0.01 * TOTAL_LUTS)  # convert percentage to count
            y_vals.append(max_achieved)
    return x_vals, y_vals

ra_util_x, ra_util_y = compute_utilization_vs_freq(ra_all)
rt_util_x, rt_util_y = compute_utilization_vs_freq(rt_all)
sa_util_x, sa_util_y = compute_utilization_vs_freq(sa_all)
bt_util_x, bt_util_y = compute_utilization_vs_freq(bt_all)

def compute_raw_performance(data_dict, arch, operation):
    """
    For each queue size, compute: (LUT Utilization count) / (max achieved frequency * performance factor).
    For register_tree with operation 'enqueue', performance_factor = 1 / log2(queue_size).
    Returns two lists: x (queue size) and y (computed value).
    """
    x_vals = []
    y_vals = []
    for qs, (freqs, achieved, util_list, bram_list) in data_dict.items():
        if achieved:
            max_achieved = max(achieved)
            if arch == "register_tree" and operation == "enqueue":
                perf_factor = 1 / log2(qs)
            else:
                perf_factor = performances[operation][arch]
            value = max_achieved * perf_factor
            x_vals.append(qs)
            y_vals.append(value)
    return x_vals, y_vals


def compute_area_over_freq_perf(data_dict, arch, operation):
    """
    For each queue size, compute: 
    For BRAM tree: (BRAM utilization count) / (max achieved frequency * performance factor)
    For others: (LUT Utilization count) / (max achieved frequency * performance factor).
    For register_tree with operation 'enqueue', performance_factor = 1 / log2(queue_size).
    Returns two lists: x (queue size) and y (computed value).
    """
    x_vals = []
    y_vals = []
    for qs, (freqs, achieved, util_list, bram_list) in data_dict.items():
        if achieved:
            max_achieved = max(achieved)
            idx = achieved.index(max_achieved)
            
            if arch == "bram_tree":
                # For BRAM tree, use BRAM utilization
                util = bram_list[idx]
                area_count = util  # BRAM utilization is already a count
            else:
                # For other architectures, use LUT utilization
                util = util_list[idx]
                area_count = util * 0.01 * TOTAL_LUTS
                
            if arch == "register_tree" and operation == "enqueue":
                perf_factor = 1 / (log2(qs) + 1)
            else:
                perf_factor = performances[operation][arch]
                
            value = area_count / (max_achieved * perf_factor)
            x_vals.append(qs)
            y_vals.append(value)
    return x_vals, y_vals

# Performance factors for area over (achieved frequency * performance) plots
performances = {
    "enqueue": {"register_array": 1/2, "systolic_array": 1/2},
    "dequeue": {"register_array": 1/2, "systolic_array": 1/2, "register_tree": 1/2, "bram_tree":1/4},
    "replace": {"register_array": 1/2, "systolic_array": 1/2, "register_tree": 1/2, "bram_tree":1/4}
}

ra_raw_enq = compute_raw_performance(ra_all, "register_array", "enqueue")
sa_raw_enq = compute_raw_performance(sa_all, "systolic_array", "enqueue")
rt_raw_enq = compute_raw_performance(rt_all, "register_tree", "enqueue")

ra_raw_deq = compute_raw_performance(ra_all, "register_array", "dequeue")
sa_raw_deq = compute_raw_performance(sa_all, "systolic_array", "dequeue")
rt_raw_deq = compute_raw_performance(rt_all, "register_tree", "dequeue")
bt_raw_deq = compute_raw_performance(bt_all, "bram_tree", "dequeue")

ra_raw_rep = compute_raw_performance(ra_all, "register_array", "replace")
sa_raw_rep = compute_raw_performance(sa_all, "systolic_array", "replace")
rt_raw_rep = compute_raw_performance(rt_all, "register_tree", "replace")
bt_raw_rep = compute_raw_performance(bt_all, "bram_tree", "replace")

ra_area_enq = compute_area_over_freq_perf(ra_all, "register_array", "enqueue")
sa_area_enq = compute_area_over_freq_perf(sa_all, "systolic_array", "enqueue")
rt_area_enq = compute_area_over_freq_perf(rt_all, "register_tree", "enqueue")

ra_area_deq = compute_area_over_freq_perf(ra_all, "register_array", "dequeue")
sa_area_deq = compute_area_over_freq_perf(sa_all, "systolic_array", "dequeue")
rt_area_deq = compute_area_over_freq_perf(rt_all, "register_tree", "dequeue")
bt_bram_deq = compute_area_over_freq_perf(bt_all, "bram_tree", "dequeue")

ra_area_rep = compute_area_over_freq_perf(ra_all, "register_array", "replace")
sa_area_rep = compute_area_over_freq_perf(sa_all, "systolic_array", "replace")
rt_area_rep = compute_area_over_freq_perf(rt_all, "register_tree", "replace")
bt_bram_rep = compute_area_over_freq_perf(bt_all, "bram_tree", "replace")

# Utility function to sort x, y pairs based on x value

def sort_xy(x, y):
    sorted_pairs = sorted(zip(x, y), key=lambda pair: pair[0])
    return [p[0] for p in sorted_pairs], [p[1] for p in sorted_pairs]

# ----- Plotting -----

# Create a 3x3 grid of subplots
fig, axs = plt.subplots(4, 3, figsize=(32, 24))

# Subplot 1: Achieved Frequency vs Queue Size
ax = axs[0, 0]
ra_qs = sorted(ra_final_freq.keys())
ra_freqs = [ra_final_freq[q] for q in ra_qs]
rt_qs = sorted(rt_final_freq.keys())
rt_freqs = [rt_final_freq[q] for q in rt_qs]
sa_qs = sorted(sa_final_freq.keys())
sa_freqs = [sa_final_freq[q] for q in sa_qs]
bt_qs = sorted(bt_final_freq.keys())
bt_freqs = [bt_final_freq[q] for q in bt_qs]

ax.plot(ra_qs, ra_freqs, 'o-', label='Register Array')
ax.plot(sa_qs, sa_freqs, 'd-', label='Systolic Array')
ax.plot(rt_qs, rt_freqs, 'x-', label='Register Tree')
ax.plot(bt_qs, bt_freqs, 's-', label='BRAM Tree')
ax.set_xlabel('Queue Size')
ax.set_ylabel('Achieved Frequency (MHz)')
ax.set_title('Achieved Frequency vs Queue Size')
ax.set_xscale('log', base=2)
ax.grid(True)
ax.legend()

# Subplot 2: LUT Utilization vs Queue Size
ax = axs[0, 1]
ra_qs_area = sorted(ra_area.keys())
ra_area_vals = [ra_area[q] for q in ra_qs_area]
rt_qs_area = sorted(rt_area.keys())
rt_area_vals = [rt_area[q] for q in rt_qs_area]
sa_qs_area = sorted(sa_area.keys())
sa_area_vals = [sa_area[q] for q in sa_qs_area]
bt_qs_area = sorted(bt_area.keys())
bt_area_vals = [bt_area[q] for q in bt_qs_area]

ax.plot(ra_qs_area, ra_area_vals, 'o-', label='Register Array')
ax.plot(sa_qs_area, sa_area_vals, 'd-', label='Systolic Array')
ax.plot(rt_qs_area, rt_area_vals, 'x-', label='Register Tree')
ax.plot(bt_qs_area, bt_area_vals, 's-', label='BRAM Tree')
ax.set_xlabel('Queue Size')
ax.set_ylabel('LUT Utilization (Count)')
ax.set_title('LUT Utilization vs Queue Size')
ax.set_xscale('log', base=2)
ax.set_yscale('log')
ax.grid(True)
ax.legend()

# Subplot 3: LUT Utilization vs Queue Size
ax = axs[0, 2]
bt_qs_x = sorted(bt_bram.keys())
bt_qs_y = [bt_bram[q] for q in bt_qs_x]
ax.plot(bt_qs_x, bt_qs_y, 's-', label='BRAM Tree')
ax.set_xlabel('Queue Size')
ax.set_ylabel('BRAM Utilization (Count)')
ax.set_title('BRAM Utilization vs Queue Size')
ax.set_xscale('log', base=2)
ax.grid(True)
ax.legend()

# Subplot 4: Enqueue -> Raw Performance vs Queue Size
ax = axs[1, 0]
ra_x, ra_y = sort_xy(*ra_raw_enq)
rt_x, rt_y = sort_xy(*rt_raw_enq)
sa_x, sa_y = sort_xy(*sa_raw_enq)

ax.plot(ra_x, ra_y, 'o-', label='Register Array')
ax.plot(sa_x, sa_y, 'd-', label='Systolic Array')
ax.plot(rt_x, rt_y, 'x-', label='Register Tree')
ax.set_xlabel('Queue Size')
ax.set_ylabel('MHz*(ops/cycle)')
ax.set_title('Enqueue: Performance vs Queue Size')
ax.set_xscale('log', base=2)
ax.set_yscale('log')
ax.grid(True)
ax.legend()
ax.annotate('Better', xy=(0.9, 0.95), xycoords='axes fraction',
            xytext=(0.5, 0.95), textcoords='axes fraction',
            arrowprops=dict(facecolor='black', shrink=0.05, width=1, headwidth=5),
            horizontalalignment='left', verticalalignment='top')
ax.annotate('Better', xy=(0.95, 0.7), xycoords='axes fraction',
            xytext=(0.95, 0.3), textcoords='axes fraction',
            arrowprops=dict(facecolor='black', shrink=0.05, width=1, headwidth=5),
            horizontalalignment='left', verticalalignment='top')

# Subplot 5: Dequeue -> Raw Performance vs Queue Size
ax = axs[1, 1]
ra_x, ra_y = sort_xy(*ra_raw_deq)
rt_x, rt_y = sort_xy(*rt_raw_deq)
sa_x, sa_y = sort_xy(*sa_raw_deq)
bt_x, bt_y = sort_xy(*bt_raw_deq)

ax.plot(ra_x, ra_y, 'o-', label='Register Array')
ax.plot(sa_x, sa_y, 'd-', label='Systolic Array')
ax.plot(rt_x, rt_y, 'x-', label='Register Tree')
ax.plot(bt_x, bt_y, 's-', label='BRAM Tree')
ax.set_xlabel('Queue Size')
ax.set_ylabel('MHz*(ops/cycle)')
ax.set_title('Dequeue: Performance vs Queue Size')
ax.set_xscale('log', base=2)
ax.set_yscale('log')
ax.grid(True)
ax.legend()
ax.annotate('Better', xy=(0.9, 0.95), xycoords='axes fraction',
            xytext=(0.5, 0.95), textcoords='axes fraction',
            arrowprops=dict(facecolor='black', shrink=0.05, width=1, headwidth=5),
            horizontalalignment='left', verticalalignment='top')
ax.annotate('Better', xy=(0.95, 0.7), xycoords='axes fraction',
            xytext=(0.95, 0.3), textcoords='axes fraction',
            arrowprops=dict(facecolor='black', shrink=0.05, width=1, headwidth=5),
            horizontalalignment='left', verticalalignment='top')

# Subplot 6: Replace -> Raw Performance vs Queue Size
ax = axs[1, 2]
ra_x, ra_y = sort_xy(*ra_raw_rep)
rt_x, rt_y = sort_xy(*rt_raw_rep)
sa_x, sa_y = sort_xy(*sa_raw_rep)
bt_x, bt_y = sort_xy(*bt_raw_rep)

ax.plot(ra_x, ra_y, 'o-', label='Register Array')
ax.plot(sa_x, sa_y, 'd-', label='Systolic Array')
ax.plot(rt_x, rt_y, 'x-', label='Register Tree')
ax.plot(bt_x, bt_y, 's-', label='BRAM Tree')
ax.set_xlabel('Queue Size')
ax.set_ylabel('MHz*(ops/cycle)')
ax.set_title('Replace: Performance vs Queue Size')
ax.set_xscale('log', base=2)
ax.set_yscale('log')
ax.grid(True)
ax.legend()
ax.annotate('Better', xy=(0.9, 0.95), xycoords='axes fraction',
            xytext=(0.5, 0.95), textcoords='axes fraction',
            arrowprops=dict(facecolor='black', shrink=0.05, width=1, headwidth=5),
            horizontalalignment='left', verticalalignment='top')
ax.annotate('Better', xy=(0.95, 0.7), xycoords='axes fraction',
            xytext=(0.95, 0.3), textcoords='axes fraction',
            arrowprops=dict(facecolor='black', shrink=0.05, width=1, headwidth=5),
            horizontalalignment='left', verticalalignment='top')

# Subplot 7: Enqueue -> Area/(Achieved Frequency * Performance) vs Queue Size
ax = axs[2, 0]
ra_x, ra_y = sort_xy(*ra_area_enq)
rt_x, rt_y = sort_xy(*rt_area_enq)
sa_x, sa_y = sort_xy(*sa_area_enq)

ax.plot(ra_x, ra_y, 'o-', label='Register Array')
ax.plot(sa_x, sa_y, 'd-', label='Systolic Array')
ax.plot(rt_x, rt_y, 'x-', label='Register Tree')
ax.set_xlabel('Queue Size')
ax.set_ylabel('LUTs/(MHz*(ops/cycle))')
ax.set_title('Enqueue: LUT Area/Performance vs Queue Size')
ax.set_xscale('log', base=2)
ax.set_yscale('log')
ax.grid(True)
ax.legend()
ax.annotate('Better', xy=(0.9, 0.08), xycoords='axes fraction',
            xytext=(0.5, 0.08), textcoords='axes fraction',
            arrowprops=dict(facecolor='black', shrink=0.05, width=1, headwidth=5),
            horizontalalignment='left', verticalalignment='top')
ax.annotate('Better', xy=(0.95, 0.1), xycoords='axes fraction',
            xytext=(0.95, 0.5), textcoords='axes fraction',
            arrowprops=dict(facecolor='black', shrink=0.05, width=1, headwidth=5),
            horizontalalignment='left', verticalalignment='top')

# Subplot 8: Dequeue -> Area/(Achieved Frequency * Performance) vs Queue Size
ax = axs[2, 1]
ra_x, ra_y = sort_xy(*ra_area_deq)
rt_x, rt_y = sort_xy(*rt_area_deq)
sa_x, sa_y = sort_xy(*sa_area_deq)

ax.plot(ra_x, ra_y, 'o-', label='Register Array')
ax.plot(sa_x, sa_y, 'd-', label='Systolic Array')
ax.plot(rt_x, rt_y, 'x-', label='Register Tree')
ax.set_xlabel('Queue Size')
ax.set_ylabel('LUTs/(MHz*(ops/cycle))')
ax.set_title('Dequeue: LUT Area/Performance vs Queue Size')
ax.set_xscale('log', base=2)
ax.set_yscale('log')
ax.grid(True)
ax.legend()
ax.annotate('Better', xy=(0.9, 0.08), xycoords='axes fraction',
            xytext=(0.5, 0.08), textcoords='axes fraction',
            arrowprops=dict(facecolor='black', shrink=0.05, width=1, headwidth=5),
            horizontalalignment='left', verticalalignment='top')
ax.annotate('Better', xy=(0.95, 0.1), xycoords='axes fraction',
            xytext=(0.95, 0.5), textcoords='axes fraction',
            arrowprops=dict(facecolor='black', shrink=0.05, width=1, headwidth=5),
            horizontalalignment='left', verticalalignment='top')

# Subplot 9: Replace -> Area/(Achieved Frequency * Performance) vs Queue Size
ax = axs[2, 2]
ra_x, ra_y = sort_xy(*ra_area_rep)
rt_x, rt_y = sort_xy(*rt_area_rep)
sa_x, sa_y = sort_xy(*sa_area_rep)

ax.plot(ra_x, ra_y, 'o-', label='Register Array')
ax.plot(sa_x, sa_y, 'd-', label='Systolic Array')
ax.plot(rt_x, rt_y, 'x-', label='Register Tree')
ax.set_xlabel('Queue Size')
ax.set_ylabel('LUTs/(MHz*(ops/cycle))')
ax.set_title('Replace: LUT Area/Performance vs Queue Size')
ax.set_xscale('log', base=2)
ax.set_yscale('log')
ax.grid(True)
ax.legend()
ax.annotate('Better', xy=(0.9, 0.08), xycoords='axes fraction',
            xytext=(0.5, 0.08), textcoords='axes fraction',
            arrowprops=dict(facecolor='black', shrink=0.05, width=1, headwidth=5),
            horizontalalignment='left', verticalalignment='top')
ax.annotate('Better', xy=(0.95, 0.1), xycoords='axes fraction',
            xytext=(0.95, 0.5), textcoords='axes fraction',
            arrowprops=dict(facecolor='black', shrink=0.05, width=1, headwidth=5),
            horizontalalignment='left', verticalalignment='top')

# Subplot 10: Enqueue -> Area/(Achieved Frequency * Performance) vs Queue Size
# ax = axs[2, 0]
# ra_x, ra_y = sort_xy(*ra_area_enq)
# rt_x, rt_y = sort_xy(*rt_area_enq)
# sa_x, sa_y = sort_xy(*sa_area_enq)

# ax.plot(ra_x, ra_y, 'o-', label='Register Array')
# ax.plot(sa_x, sa_y, 'd-', label='Systolic Array')
# ax.plot(rt_x, rt_y, 'x-', label='Register Tree')
# ax.set_xlabel('Queue Size')
# ax.set_ylabel('LUTs/(MHz*(ops/cycle))')
# ax.set_title('Enqueue: LUT Area/Performance vs Queue Size')
# ax.set_xscale('log', base=2)
# ax.set_yscale('log')
# ax.grid(True)
# ax.legend()
# ax.annotate('Better', xy=(0.9, 0.05), xycoords='axes fraction',
#             xytext=(0.5, 0.05), textcoords='axes fraction',
#             arrowprops=dict(facecolor='black', shrink=0.05, width=1, headwidth=5),
#             horizontalalignment='left', verticalalignment='top')
# ax.annotate('Better', xy=(0.95, 0.1), xycoords='axes fraction',
#             xytext=(0.95, 0.5), textcoords='axes fraction',
#             arrowprops=dict(facecolor='black', shrink=0.05, width=1, headwidth=5),
#             horizontalalignment='left', verticalalignment='top')

# Subplot 11: Dequeue -> Area/(Achieved Frequency * Performance) vs Queue Size
ax = axs[3, 1]
bt_x, bt_y = sort_xy(*bt_bram_deq)

ax.plot(bt_x, bt_y, 's-', label='BRAM Tree')
ax.set_xlabel('Queue Size')
ax.set_ylabel('BRAMs/(MHz*(ops/cycle))')
ax.set_title('Dequeue: BRAM Utilization/Performance vs Queue Size')
ax.set_xscale('log', base=2)
ax.set_yscale('log')
ax.grid(True)
ax.legend()
ax.annotate('Better', xy=(0.9, 0.08), xycoords='axes fraction',
            xytext=(0.5, 0.08), textcoords='axes fraction',
            arrowprops=dict(facecolor='black', shrink=0.05, width=1, headwidth=5),
            horizontalalignment='left', verticalalignment='top')
ax.annotate('Better', xy=(0.95, 0.1), xycoords='axes fraction',
            xytext=(0.95, 0.5), textcoords='axes fraction',
            arrowprops=dict(facecolor='black', shrink=0.05, width=1, headwidth=5),
            horizontalalignment='left', verticalalignment='top')

# Subplot 12: Replace -> Area/(Achieved Frequency * Performance) vs Queue Size
ax = axs[3, 2]
bt_x, bt_y = sort_xy(*bt_bram_rep)

ax.plot(bt_x, bt_y, 's-', label='BRAM Tree')
ax.set_xlabel('Queue Size')
ax.set_ylabel('BRAMs/(MHz*(ops/cycle))')
ax.set_title('Dequeue: BRAM Utilization/Performance vs Queue Size')
ax.set_xscale('log', base=2)
ax.set_yscale('log')
ax.grid(True)
ax.legend()
ax.annotate('Better', xy=(0.9, 0.08), xycoords='axes fraction',
            xytext=(0.5, 0.08), textcoords='axes fraction',
            arrowprops=dict(facecolor='black', shrink=0.05, width=1, headwidth=5),
            horizontalalignment='left', verticalalignment='top')
ax.annotate('Better', xy=(0.95, 0.1), xycoords='axes fraction',
            xytext=(0.95, 0.5), textcoords='axes fraction',
            arrowprops=dict(facecolor='black', shrink=0.05, width=1, headwidth=5),
            horizontalalignment='left', verticalalignment='top')

plt.tight_layout()

# Save the combined figure
output_dir = "vivado_analysis_results_plots_16bit"
os.makedirs(output_dir, exist_ok=True)
output_path = os.path.join(output_dir, "combined_plots.pdf")
plt.savefig(output_path)
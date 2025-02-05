import os
import matplotlib.pyplot as plt
import numpy as np


plt.rcParams.update({"font.size": 16})


def parse_achieved_frequencies(file_path):
    """
    Parses a log file to extract frequencies and their corresponding achieved frequencies.

    Args:
        file_path (str): The path to the log file.

    Returns:
        tuple: Two lists, the first containing the frequencies and the second containing the achieved frequencies.

    Example:
        Given a log file with the following content:
            Frequency: 150 MHz -> Achieved Frequency: 138.242 MHz
            Frequency: 160 MHz -> Achieved Frequency: 143.205 MHz

        The function will return:
            ([150.0, 160.0], [138.242, 143.205])
    """
    frequencies = []
    achieved_frequencies = []

    with open(file_path, "r") as file:
        for line in file:
            if "Frequency" in line and "Achieved Frequency" in line:
                freq_part = line.split("->")[0].strip().split(" ")[1]
                achieved_freq_part = line.split("->")[1].strip().split(" ")[2]
                frequencies.append(float(freq_part))
                achieved_frequencies.append(float(achieved_freq_part))

    return frequencies, achieved_frequencies


def extrapolate_final_achieved_frequency(achieved_frequencies):
    """
    Extrapolates the final achieved frequency by finding the maximum frequency.

    Args:
        achieved_frequencies (list): A list of achieved frequencies.

    Returns:
        float: The extrapolated final achieved frequency.
    """
    return np.max(achieved_frequencies)


def parse_area_utilization(file_path):
    """
    Parses a log file to extract frequencies and their corresponding LUTs Utilization.

    Args:
        file_path (str): The path to the log file.

    Returns:
        dict: A dictionary where keys are frequencies and values are LUTs Utilization.

    Example:
        Given a log file with the following content:
            Frequency: 150 MHz -> LUTs Util%: 0.07 %
            Frequency: 160 MHz -> LUTs Util%: 0.08 %

        The function will return:
            [0.07, 0.08]
    """
    utilization_data = []

    with open(file_path, "r") as file:
        for line in file:
            if "Frequency" in line and "LUTs Util%" in line:
                parts = line.split("->")
                utilization = float(parts[1].strip().split(" ")[2])
                utilization_data.append(float(utilization))

    return utilization_data


def process_log_directory(log_dir):
    """
    Processes log files in the given directory and returns a dictionary of data.
    """
    data = {}
    for file_name in sorted(
        os.listdir(log_dir), key=lambda x: int(x.split("_")[-1].split(".")[0])
    ):
        if file_name.startswith("vivado_analysis_on_queue_size") and file_name.endswith(
            ".txt"
        ):
            queue_size = int(file_name.split("_")[-1].split(".")[0])
            file_path = os.path.join(log_dir, file_name)
            frequencies, achieved_frequencies = parse_achieved_frequencies(file_path)
            utilization_data = parse_area_utilization(file_path)
            data[queue_size] = (frequencies, achieved_frequencies, utilization_data)
    return data


def make_throughput_vs_queue_size_plot(data):
    """
    Converts data from process_log_directory into plot-ready x and y values.

    Args:
        data (dict): Dictionary from process_log_directory containing (frequencies, achieved_frequencies, utilization_data)

    Returns:
        tuple: (x_values, y_values) where:
            x_values (list): List of achieved frequencies for x-axis
            y_values (list): List of throughput counts for y-axis
    """
    x_values = []
    y_values = []

    for queue_size, (
        frequencies,
        achieved_frequencies,
        utilization_data,
    ) in data.items():
        # For each queue size, find the max achieved frequency and corresponding utilization
        max_achieved_freq = max(achieved_frequencies)
        max_utilization = utilization_data[
            achieved_frequencies.index(max_achieved_freq)
        ]
        x_values.append(queue_size)  # Use queue size for x-axis
        y_values.append(max_achieved_freq * 16)  # throughput

    return x_values, y_values


# Define log directories
register_array_log_dir = "register_array/vivado_register_array_analysis_results_16bit/"
register_tree_log_dir = "register_tree/vivado_register_tree_analysis_results_16bit/"
systolic_array_log_dir = "systolic_array/vivado_systolic_array_analysis_results_16bit/"

# Process data for all architectures
array_data = process_log_directory(register_array_log_dir)
tree_data = process_log_directory(register_tree_log_dir)
systolic_data = process_log_directory(systolic_array_log_dir)

# Create the plot
plt.figure(figsize=(10, 6))

# Plot data for each architecture
x_systolic, y_systolic = make_throughput_vs_queue_size_plot(systolic_data)
x_array, y_array = make_throughput_vs_queue_size_plot(array_data)
x_tree, y_tree = make_throughput_vs_queue_size_plot(tree_data)

plt.plot(x_systolic, y_systolic, "d-", label="Systolic Array")
plt.plot(x_array, y_array, "o-", label="Register Array")
plt.plot(x_tree, y_tree, "x-", label="Register Tree")

plt.xlabel("Queue Size", fontsize=20)
plt.ylabel("Throughput (Mbps)", fontsize=20)

plt.xscale("log", base=2)
plt.yscale('log')

plt.grid(True)
plt.legend()
plt.tight_layout()

# Save the plot
output_dir = "vivado_analysis_results_plots_16bit"
os.makedirs(output_dir, exist_ok=True)
plt.savefig(os.path.join(output_dir, "throughput_vs_queue_size.pdf"))

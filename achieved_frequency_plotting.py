import os
import matplotlib.pyplot as plt
from matplotlib.ticker import MultipleLocator
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


def extrapolate_final_achieved_frequency(achieved_frequencies, num_points=3):
    """
    Extrapolates the final achieved frequency by averaging the last few points.

    Args:
        achieved_frequencies (list): A list of achieved frequencies.
        num_points (int, optional): The number of points to consider for averaging. Defaults to 3.

    Returns:
        float: The extrapolated final achieved frequency.

    Example:
        Given achieved_frequencies = [138.242, 143.205, 134.132, 138.035, 138.290, 138.889]
        and num_points = 3, the function will return the average of the last 3 points:
            (138.035 + 138.290 + 138.889) / 3 = 138.40466666666667
    """
    if len(achieved_frequencies) < num_points:
        return np.mean(achieved_frequencies)
    return np.mean(achieved_frequencies[-num_points:])


# Function to process log files in a directory
def process_register_array_log_directory(log_dir):
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
            data[queue_size] = (frequencies, achieved_frequencies)
    return data


# Function to process log files in a directory
def process_register_tree_log_directory(log_dir):
    """
    Processes log files in the given directory and returns a dictionary of data.
    """
    data = {}
    for file_name in sorted(
        os.listdir(log_dir), key=lambda x: int(x.split("_")[-1].split(".")[0])
    ):
        if file_name.startswith("vivado_analysis_on_tree_depth") and file_name.endswith(
            ".txt"
        ):
            tree_depth = int(file_name.split("_")[-1].split(".")[0])
            queue_size = (1 << tree_depth) - 1  # Convert tree depth to queue size
            file_path = os.path.join(log_dir, file_name)
            frequencies, achieved_frequencies = parse_achieved_frequencies(file_path)
            data[queue_size] = (frequencies, achieved_frequencies)
    return data


# Function to process log files in a directory
def process_open_list_log_directory(log_dir):
    """
    Processes log files in the given directory and returns a dictionary of data.
    """
    data = {}
    for file_name in sorted(
        os.listdir(log_dir), key=lambda x: int(x.split("_")[-1].split(".")[0])
    ):
        if file_name.startswith("pq_analysis_") and file_name.endswith(".txt"):
            queue_size = file_name.split("_")[-1].split(".")[0]
            file_path = os.path.join(log_dir, file_name)
            frequencies, achieved_frequencies = parse_achieved_frequencies(file_path)
            data[queue_size] = (frequencies, achieved_frequencies)
    return data


# Define log directories for both register array and register tree
register_array_log_dir = "register_array/vivado_register_array_analysis_results/"
register_tree_log_dir = "register_tree/vivado_register_tree_analysis_results/"
open_list_log_dir = "../vivado_dir/zhou_2020_hwpq/zhou_2020_hwpq.logs/"

# Process log files for register array
all_data_array = process_register_array_log_directory(register_array_log_dir)

# Process log files for register tree
all_data_tree = process_register_tree_log_directory(register_tree_log_dir)

# Process log files for register tree
all_data_systolic = {
    k: v
    for k, v in process_open_list_log_directory(open_list_log_dir).items()
    if int(k) not in [4, 8]
}

# Calculate final achieved frequencies for register array
final_achieved_frequencies_array = {}
for queue_size, (frequencies, achieved_frequencies) in all_data_array.items():
    final_achieved_frequency = extrapolate_final_achieved_frequency(
        achieved_frequencies, num_points=1
    )
    final_achieved_frequencies_array[queue_size] = final_achieved_frequency

# Calculate final achieved frequencies for register tree
final_achieved_frequencies_tree = {}
for queue_size, (frequencies, achieved_frequencies) in all_data_tree.items():
    final_achieved_frequency = extrapolate_final_achieved_frequency(
        achieved_frequencies, num_points=1
    )
    final_achieved_frequencies_tree[queue_size] = final_achieved_frequency

# Calculate final achieved frequencies for systolic array
final_achieved_frequencies_systolic = {}
for queue_size, (frequencies, achieved_frequencies) in all_data_systolic.items():
    final_achieved_frequency = extrapolate_final_achieved_frequency(
        achieved_frequencies, num_points=1
    )
    final_achieved_frequencies_systolic[queue_size] = final_achieved_frequency

# Plot the final achieved frequencies for both register array and register tree together
plt.figure(figsize=(10, 6))

# Plot for OPEN List
queue_sizes_systolic = [
    int(size) for size in final_achieved_frequencies_systolic.keys()
]
final_frequencies_systolic = list(final_achieved_frequencies_systolic.values())
plt.plot(
    queue_sizes_systolic,
    final_frequencies_systolic,
    marker="d",
    label="Systolic Array",
)

# Plot for register array
queue_sizes_array = list(final_achieved_frequencies_array.keys())
final_frequencies_array = list(final_achieved_frequencies_array.values())
plt.plot(
    queue_sizes_array,
    final_frequencies_array,
    marker="o",
    label="Register Array",
)

# Plot for register tree
queue_sizes_tree = list(final_achieved_frequencies_tree.keys())
final_frequencies_tree = list(final_achieved_frequencies_tree.values())
plt.plot(
    queue_sizes_tree,
    final_frequencies_tree,
    marker="x",
    label="Register Tree",
)

plt.xlabel("Queue Size", fontsize=20)
plt.ylabel("Maximum Frequency (MHz)", fontsize=20)

plt.xscale("log", base=2)

# Set axis ticks manually
plt.xticks([8, 16, 32, 64, 128, 256, 512, 1024])
plt.yticks(np.arange(0, 500, 50))

# plt.title("Final Achieved Frequency vs QUEUE_SIZE")
plt.legend()
plt.grid(True)
plt.tight_layout()

output_dir = "vivado_analysis_results_plots"
os.makedirs(output_dir, exist_ok=True)
plt.savefig(os.path.join(output_dir, "final_achieved_frequency_plotting.pdf"))

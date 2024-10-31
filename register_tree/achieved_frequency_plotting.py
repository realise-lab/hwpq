import os
import matplotlib.pyplot as plt
import numpy as np


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


# Directory containing the log files
log_dir = "vivado_register_tree_analysis_results"

# Dictionary to store data from all files
all_data = {}

# Iterate over all files in the directory
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
        all_data[queue_size] = (frequencies, achieved_frequencies)

# Plotting all achieved frequencies in a single figure
plt.figure(figsize=(10, 6))

for queue_size, (frequencies, achieved_frequencies) in all_data.items():
    plt.plot(
        frequencies,
        achieved_frequencies,
        marker="o",
        label=f"QUEUE_SIZE = {queue_size}",
    )

plt.xlabel("Frequency (MHz)")
plt.ylabel("Achieved Frequency (MHz)")
plt.title("Achieved Frequency vs Frequency for Different QUEUE_SIZE")
plt.legend()
plt.grid(True)
plt.tight_layout()
# plt.show()
output_dir = "vivado_register_tree_analysis_results_plots/"
os.makedirs(output_dir, exist_ok=True)
plt.savefig(os.path.join(output_dir, "achieved_frequency_plotting.png"))

# Dictionary to store final achieved frequencies for each queue size
final_achieved_frequencies = {}

# Iterate over all data to find the final achieved frequency for each queue size
for queue_size, (frequencies, achieved_frequencies) in all_data.items():
    final_achieved_frequency = extrapolate_final_achieved_frequency(achieved_frequencies, num_points=1)
    final_achieved_frequencies[queue_size] = final_achieved_frequency

# Plot the final achieved frequencies for each queue size
plt.figure(figsize=(10, 6))

queue_sizes = list(final_achieved_frequencies.keys())
final_frequencies = list(final_achieved_frequencies.values())

plt.plot(queue_sizes, final_frequencies, marker="o")
plt.xlabel("QUEUE_SIZE")
plt.ylabel("Final Achieved Frequency (MHz)")
plt.title("Final Achieved Frequency vs QUEUE_SIZE")
plt.grid(True)
plt.tight_layout()
# plt.show()
output_dir = "vivado_register_tree_analysis_results_plots/"
os.makedirs(output_dir, exist_ok=True)
plt.savefig(os.path.join(output_dir, "final_achieved_frequency_plotting.png"))

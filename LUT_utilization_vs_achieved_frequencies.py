import os
import matplotlib.pyplot as plt
import numpy as np

plt.rcParams.update({"font.size": 16})

def parse_achieved_frequencies(file_path):
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

def parse_area_utilization(file_path):
    utilization_data = {}
    
    with open(file_path, "r") as file:
        for line in file:
            if "Frequency" in line and "LUTs Util%" in line:
                parts = line.split("->")
                frequency = float(parts[0].split(":")[1].strip().split(" ")[0])
                utilization = float(parts[1].strip().split(" ")[2])
                utilization_data[frequency] = utilization
    
    return utilization_data

def process_directory(log_dir, is_tree=False):
    data = {}
    for file_name in sorted(os.listdir(log_dir), 
                        key=lambda x: int(x.split("_")[-1].split(".")[0])):
        if file_name.startswith("vivado_analysis_on") and file_name.endswith(".txt"):
            if is_tree:
                tree_depth = int(file_name.split("_")[-1].split(".")[0])
                queue_size = (1 << tree_depth) - 1
            else:
                queue_size = int(file_name.split("_")[-1].split(".")[0])
                
            file_path = os.path.join(log_dir, file_name)
            _, achieved_frequencies = parse_achieved_frequencies(file_path)
            area_utilization = parse_area_utilization(file_path)
            
            # Calculate final achieved frequency (average of last 2 points)
            final_freq = np.mean(achieved_frequencies[-2:])
            
            # Calculate average area utilization
            avg_area = np.mean(list(area_utilization.values()))
            
            data[queue_size] = (final_freq, avg_area)
    
    return data

# Define log directories
register_array_log_dir = "register_array/vivado_register_array_analysis_results_new/"
register_tree_log_dir = "register_tree/vivado_register_tree_analysis_results_new/"
systolic_array_log_dir = "systolic_array/vivado_systolic_array_analysis_results_new/"

# Process data for all architectures
array_data = process_directory(register_array_log_dir)
tree_data = process_directory(register_tree_log_dir)
systolic_data = process_directory(systolic_array_log_dir)

# Convert LUT utilization percentage to actual LUT count
def get_plot_data(data, total_luts):
    x_values = [value[0] for value in data.values()]
    y_values = [value[1] * 0.01 * total_luts for value in data.values()]
    return x_values, y_values

# Create the plot
plt.figure(figsize=(10, 6))

# Plot data for each architecture
x_systolic, y_systolic = get_plot_data(systolic_data, 4085760)
x_array, y_array = get_plot_data(array_data, 4085760)
x_tree, y_tree = get_plot_data(tree_data, 4085760)

plt.plot(x_systolic, y_systolic, 'd-', label='Systolic Array')
plt.plot(x_array, y_array, 'o-', label='Register Array')
plt.plot(x_tree, y_tree, 'x-', label='Register Tree')

plt.xlabel('Achieved Frequency (MHz)', fontsize=20)
plt.ylabel('LUT Utilization (%)', fontsize=20)

plt.yscale('log')
plt.grid(True)
plt.legend()
plt.tight_layout()

# Save the plot
output_dir = "vivado_analysis_results_plots"
os.makedirs(output_dir, exist_ok=True)
plt.savefig(os.path.join(output_dir, "LUT_utilization_vs_achieved_frequencies.pdf"))
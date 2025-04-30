# Hardware Priority Queue Architecture Analysis - A Scalability Study

## Abstract

This project presents a comprehensive evaluation of hardware priority queue architectures, focusing on their performance, resource utilization, and scalability in modern FPGA implementations. We analyze various architectures including register tree, register array, systolic array, BRAM tree, and hybrid tree designs under different configurations and queue sizes. Our study provides insights into architectural trade-offs and helps researchers choose the most suitable design for their specific requirements. To support reproducibility and further research, we composed this open-source library containing parameterized RTL implementations of each architecture, along with synthesis and analysis scripts using Xilinx Vivado.

## Overview

In typical software implementations, a priority queue is often realized using a binary heap. During an enqueue operation, the new item is inserted at the leftmost available position in the heap and then may be repeatedly swapped with its parent node (a process nown as heapify-up) to restore the heap property. Conversely, a dequeue operation retrieves the maximum/minimum element from the root and replaces it with the rightmost non-empty node at the last level. The displaced element is then propagated downward (heapify-down), repeatedly compared with its children until it reaches its correct position in the tree. Both enqueue and dequeue operations have a worst-case time complexity of \(O(log\ N)\), as an element may need to traverse the height of the binary tree to maintain the heap structure.

By implementing the priority queue in hardware, we can leverage the inherent parallelism of FPGAs to perform compare-and-swap operations concurrently across different levels of the data structure, thereby achieving constant-time operation in ideal scenarios.

## Methodology

To ensure uniform testing across all architectures, we developed a **standardized interface** that encapsulates each implementation, enabling seamless integration with a unified testbench. This interface facilitated a consistent verification environment to validate the functionality of all modules, ensuring support for the core operations: **enqueue**, **dequeue**, and **replace**.

<!-- Following functional verification using a suite of RTL testbenches, each priority queue architecture was synthesized and implemented using AMD Vivado. A parameter sweep was conducted to evaluate how different design factors influence performance and resource utilization. The parameters explored included queue size, support for the enqueue operation, and the use of pipelining. -->

[The AMD Artix UltraScale+ FPGA (XCAU25P)](https://www.amd.com/en/products/adaptive-socs-and-fpgas/fpga/artix-ultrascale-plus.html) was selected as the test platform due to its ample availability of LUTs, FFs, and BRAMs. This resource-rich environment helped mitigate the impact of hardware limitations, allowing for a more accurate assessment of architectural scalability and efficiency. **The users of this library are free to switch to any other platform as they like by changing the parameter in the Tcl script, the step by step method will be described below.**

<!-- As a result, observed performance bottlenecks and scalability constraints were attributed primarily to architectural design choices rather than hardware shortages.  -->

For each configuration, we measured the maximum achievable operating frequency and recorded resource consumption in terms of lookup tables (LUTs), flip-flops (FFs), and block RAMs (BRAMs). These measurements enabled us to evaluate both raw performance and resource efficiency relative to the targeted throughput.

## How to Use

### Project Structure

- `hwpq/` - Contains RTL implementations of different priority queue architectures along with key metrics logs that we have collected
- `py-scripts/` - Python scripts for data analysis and visualization
- `vivado-runtime/` - Shell script that runs Vivado in TCL mode to sweep through parameters of each architecture in parallel.
  - It is suggested that user to execute any tcl or bash scripts inside this directory, since Vivado generate log and journal files automatically, it is better to contain them in this specific direcotory for later access.
- `vivado-synthesis_tcl/` - TCL scripts for Vivado synthesis

### Prerequisites

Before running the synthesis and analysis, ensure you have the following installed:

- **Xilinx Vivado**: The synthesis and implementation process requires Vivado to be installed and properly configured. The project has been tested with Vivado 2024.2, but other recent versions should work as well.
- **Python3**: The data analysis and visualization scripts require Python 3.8 or later.

### Running Synthesis and Analysis

#### Synthesis

1.  Clone the repository
2.  Run Vivado synthesis using the provided TCL scripts:

    ```bash
    cd hwpq_qw2246
    cd vivado-runtime
    vivado -mode batch -source ../vivado-synthesis_tcl/<tcl_script>
    ```

    - `synth_design_param_sweep.tcl`

      - This might be a good starting point for user who would like to run analysis on one specific module. The Tcl script would sweep throgh **enqueue on/off switch**, **queue sizes**, and **various frequencies**.

    - `synth_design_param_sweep_parallel.tcl`

        - The major difference between this script with `synth_design_param_sweep.tcl` is that this script only sweep through frequencies in script itself, the other parameters are handled by the bash script, or user will need to pass those parameters in by themselves. 
        - If you would like to just find the max achieveable freqenucu along with other metrics for a module that under a set parameter setting run this command:
          - enqueue_one/off: 1 or 0
          - data_width: 8, 16, 32, 64, etc. (int)
          - queue_size: architecture and application determined (int)

    ```bash
    vivado -mode batch -source ../vivado-synthesis_tcl/synth_design_param_sweep_parallel.tcl -tclargs <enqueue_on/off> <data_width> <queue_size>
    ```

#### Analysis

1.  Run bash script

    ```bash
    ./run_param_sweep_parallel.sh
    ```

2.  Install required Python packages

    ```bash
    pip install -r ../py-scripts/requirements.txt
    ```

3.  Process and visualize results using the Python scripts:

    ```bash
    python ../py-scripts/analysis_py/src/plotter
    ```

## Priority Queue Architectures (Updating)

### Register Based

#### [Register Tree](hwpq/register_tree/README.md)

#### [Register Array](hwpq/register_array/README.md)

#### [Systolic Array](hwpq/systolic_array/README.md)

### BRAM Based

#### [BRAM Tree](hwpq/bram_tree/README.md)

#### [Hybrid Tree](hwpq/hybrid_tree/README.md)

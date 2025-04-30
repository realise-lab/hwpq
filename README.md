# Hardware Priority Queue Architecture Analysis - A Scalability Study

## Abstract

This project presents a comprehensive evaluation of hardware priority queue architectures, focusing on their performance, resource utilization, and scalability in modern FPGA implementations. We analyze various architectures proposed in the past decades, including register tree, register array, systolic array, BRAM tree, and hybrid tree designs, under different configurations and queue sizes. Our study provides insights into architectural trade-offs and helps researchers choose the most suitable design for their specific requirements. To support reproducibility and further research, we provide this open-source library containing parameterized RTL implementations of each architecture, along with synthesis and analysis scripts compatible with [Xilinx Vivado](https://www.amd.com/en/products/software/adaptive-socs-and-fpgas/vivado.html).

## Overview

In typical software implementations, a priority queue is often realized using a binary heap. During an enqueue operation, the new item is inserted at the leftmost available position in the heap and may then be repeatedly swapped with its parent node (a process known as heapify-up) to restore the heap property. Conversely, a dequeue operation retrieves the maximum/minimum element from the root and replaces it with the rightmost non-empty node at the last level. This displaced element is then propagated downward (heapify-down), repeatedly compared with its children until it reaches its correct position in the tree. Both enqueue and dequeue operations have a worst-case time complexity of \(O(log\ N)\), as an element may need to traverse the height of the binary tree to maintain the heap structure.

By implementing the priority queue in hardware, we can leverage the inherent parallelism of FPGAs to perform compare-and-swap operations concurrently across different levels of the data structure, potentially achieving constant-time operation in ideal scenarios.

## Methodology

To ensure uniform testing across all architectures, we developed a **standardized interface** that encapsulates each implementation, enabling seamless integration with a unified testbench. This interface facilitated a consistent verification environment to validate the functionality of all modules, ensuring support for the core operations: **enqueue**, **dequeue**, and **replace**.

<!-- Following functional verification using a suite of RTL testbenches, each priority queue architecture was synthesized and implemented using AMD Vivado. A parameter sweep was conducted to evaluate how different design factors influence performance and resource utilization. The parameters explored included queue size, support for the enqueue operation, and the use of pipelining. -->

[The AMD Artix UltraScale+ FPGA (XCAU25P)](https://www.amd.com/en/products/adaptive-socs-and-fpgas/fpga/artix-ultrascale-plus.html) was selected as the test platform due to its ample availability of LUTs, FFs, and BRAMs. This resource-rich environment helped mitigate the impact of hardware limitations, allowing for a more accurate assessment of architectural scalability and efficiency. **Users of this library are free to switch to any other platform by changing the relevant parameters in the Tcl scripts; the step-by-step method is described below.**

<!-- As a result, observed performance bottlenecks and scalability constraints were attributed primarily to architectural design choices rather than hardware shortages.  -->

For each configuration, we measured the **maximum achievable operating frequency** and recorded resource consumption in terms of **lookup tables (LUTs)**, **flip-flops (FFs)**, and **block RAMs (BRAMs)**. These measurements enabled us to evaluate both performance and resource efficiency relative to the targeted throughput.

## How to Use

### Project Structure

- `hwpq/` - Contains RTL implementations of different priority queue architectures, along with collected key metrics logs.
- `py-scripts/` - Python scripts for data analysis and visualization.
- `vivado-runtime/` - Contains shell scripts that run Vivado in Tcl mode to sweep through parameters of each architecture in parallel.
  - It is suggested that users execute any Tcl or Bash scripts inside this directory. Since Vivado generates log and journal files automatically, keeping them in this specific directory facilitates later access.
- `vivado-synthesis_tcl/` - Tcl scripts for Vivado synthesis.

### Prerequisites

Before running the synthesis and analysis, ensure you have the following installed:

- **Xilinx Vivado**: The synthesis and implementation process requires Vivado to be installed and properly configured. The project has been tested with Vivado 2024.2, but other recent versions should also work.
  - Download here: https://www.xilinx.com/support/download.html
- **Python 3**

### Running Synthesis and Analysis

#### Synthesis

1.  Clone the repository.
2.  Navigate to the `vivado-runtime` directory:
    ```bash
    cd hwpq_qw2246/vivado-runtime
    ```
3.  Run Vivado synthesis using the provided Tcl scripts. Replace `<tcl_script>` with the desired script name:

    ```bash
    vivado -mode batch -source ../vivado-synthesis_tcl/<tcl_script>
    ```

    Available scripts:

    - `synth_design_param_sweep.tcl`

      - This script is a good starting point for analyzing a specific module. It sweeps through the **enqueue on/off switch**, **queue sizes**, and **various frequencies**.

    - `synth_design_param_sweep_parallel.tcl`
      - This script differs from `synth_design_param_sweep.tcl` by only sweeping frequencies within the script itself. Other parameters (enqueue switch, data width, queue size) must be provided via command-line arguments or handled by a controlling Bash script. This script is designed to find the **maximum achievable frequency** for a given parameter set.
      - To find the maximum achievable frequency and other metrics for a module with specific parameters, run:
        ```bash
        vivado -mode batch -source ../vivado-synthesis_tcl/synth_design_param_sweep_parallel.tcl -tclargs <enqueue_on/off> <data_width> <queue_size>
        ```
        - **`<enqueue_on/off>`**: `1` (on) or `0` (off)
        - **`<data_width>`**: e.g., `8`, `16`, `32`, `64` (integer)
        - **`<queue_size>`**: architecture and application-dependent (integer)

#### Analysis

1.  Execute the parameter sweep Bash script (ensure you are in the `vivado-runtime` directory):
    ```bash
    ./run_param_sweep_parallel.sh
    ```
2.  Install the required Python packages:
    ```bash
    pip install -r ../py-scripts/requirements.txt
    ```
3.  Process and visualize the results using the Python plotting script:
    ```bash
    python ../py-scripts/analysis_py/src/plotter
    ```

## Priority Queue Architectures (Work in Progress)

### Register Based

#### [Register Tree](hwpq/register_tree/README.md)

#### [Register Array](hwpq/register_array/README.md)

#### [Systolic Array](hwpq/systolic_array/README.md)

### BRAM Based

#### [BRAM Tree](hwpq/bram_tree/README.md)

#### [Hybrid Tree](hwpq/hybrid_tree/README.md)

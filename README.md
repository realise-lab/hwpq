# Hardware Priority Queue Architecture Analysis - A Scalability Study

## Abstract

This project presents a comprehensive evaluation of various hardware priority queue architectures proposed in recent years, with a focus on their performance, resource utilization, and scalability in the context of modern hardware technologies. The selected architectures are analyzed under different queue sizes and configurations to provide insights that aid researchers and engineers in choosing the most suitable design for their specific application requirements. To support reproducibility and further research, we also composed an open-source library that includes parameterized RTL implementations of each architecture, along with scripts for synthesis and analysis using Xilinx Vivado.

## How to Use

### Project Structure

- `hwpq/` - Contains RTL implementations of different priority queue architectures along with key metrics logs.
- `py-scripts/` - Python scripts for data analysis and visualization
- `vivado-analysis_plots/` - Generated plots comparing different architectures
- `vivado-runtime/` - Shell script that runs Vivado in TCL mode to sweep through parameters of each architecture
- `vivado-synthesis_tcl/` - TCL scripts for Vivado synthesis

### Prerequisites

Before running the synthesis and analysis, ensure you have the following installed:

- **Xilinx Vivado**: The synthesis and implementation process requires Vivado to be installed and properly configured. The project has been tested with Vivado 2024.2, but other recent versions should work as well.
- **Python3**: The data analysis and visualization scripts require Python 3.8 or later. Required Python packages are listed in `py-scripts/requirements.txt`. Install all required packages with:
  ```
  pip install -r py-scripts/requirements.txt
  ```

### Running Synthesis and Analysis

1. Clone the repository
2. Run Vivado synthesis using the provided TCL scripts:
   ```
   cd vivado-synthesis_tcl
   vivado -mode batch -source run_synthesis.tcl
   ```
3. Process and visualize results using the Python scripts:
   ```
   cd py-scripts/analysis_py
   python -m src.plotter
   ```

## Methodology

To ensure uniform testing across all architectures, we developed a standardized interface that encapsulates each implementation, enabling seamless integration with a unified testbench. This interface facilitated a consistent verification environment to validate the functionality of all modules, ensuring support for the core operations:
enqueue, dequeue, and replace.

Following functional verification using a suite of RTL testbenches, each priority queue architecture was synthesized and implemented using AMD Vivado. A parameter sweep was conducted to evaluate how different design factors influence performance and resource utilization. The parameters explored included queue size, support for the enqueue operation, and the use of pipelining.

For each configuration, we measured the maximum achievable operating frequency and recorded resource consumption in terms of lookup tables (LUTs), flip-flops (FFs), and block RAMs (BRAMs). These measurements enabled us to evaluate both raw performance and resource efficiency relative to the targeted throughput.

The AMD Artix UltraScale+ FPGA (XCAU25P) was selected as the test platform due to its ample availability of LUTs, FFs, and BRAMs. This resource-rich environment helped mitigate the impact of hardware limitations, allowing for a more accurate assessment of architectural scalability and efficiency. As a result, observed performance bottlenecks and scalability constraints were attributed primarily to architectural design choices rather than hardware shortages.

## Overview

In typical software implementations, a priority queue is often realized using a binary heap. During an enqueue operation, the new item is inserted at the leftmost available position in the heap and then may be repeatedly swapped with its parent node (a process nown as heapify-up) to restore the heap property. Conversely, a dequeue operation retrieves the maximum/minimum element from the root and replaces it with the rightmost non-empty node at the last level. The displaced element is then propagated downward (heapify-down), repeatedly compared with its children until it reaches its correct position in the tree. Both enqueue and dequeue operations have a worst-case time complexity of \(O(log\ N)\), as an element may need to traverse the height of the binary tree to maintain the heap structure.

By implementing the priority queue in hardware, we can leverage the inherent parallelism of FPGAs to perform compare-and-swap operations concurrently across different levels of the data structure, thereby achieving constant-time operation in ideal scenarios.

## Priority Queue Architectures

### Register Tree

Among all hardware architectures, the register tree most closely resembles a software-based priority queue, preserving the heap property to maintain element order. In this discussion, we focus on a max-priority queue that returns the largest element; a min-priority queue operates analogously, substituting comparisons for the smallest value.

We evaluated four variations of the register tree architecture, including the baseline implementation with enqueue functionality \cite{huang2014}, a variant without enqueue functionality, and two pipelined counterparts in which each compare-and-swap stage was split across two cycles to improve maximum achievable frequency. As shown from figure ~\ref{fig:reg_tree_perf_comp}, Contrary to initial expectations, pipelining did not yield performance advantages compare to un-pipelined version, as the frequency gains were insufficient to offset the latency overhead introduced by the additional pipeline stage. However, we do see that the performance drop as queue size grow is much more gradual than the un-pipelined one, which indicates the pipelined version is more scalable when it comes to larger size of queue. Especially for the implementation with enqueue funtionality enabled. If be able to enqueue during operations is a ciritcal aspect of your design, and a large queue size is needed, then pipelining is a must.

### Register Array

The register array architecture is derived from the register tree, but instead of arranging registers in a hierarchical heap structure, it organizes them in a flat, array-lie layout. The replace operation in this design retains behavioral similarity to that of the register tree. Specifically, during a replace operation, the leftmost entry in the array is overwritten with the new item in a single cycle. This is followed by two phases of array-wide compare-and-swap operations: first, all entries at even indices are compared and potentially swapped with their adjacent odd-indexed neighbors; then, the process is repeated with odd-indexed entries compared and potentially swapped with the adjacent even-indexed entries.

### Systolic Array

The systolic array architecture consists of two buffers: an input buffer (IB) to store incoming nodes and an output buffer (OB) to hold nodes that are ready for output\cite{zhou2020}.

When a new node is inserted into the array, it is first stored in the IB. The sorting mechanism employed in this architecture resembles the bubble sort algorithm. As a new node propagates through the IB and reaches position \(IB*i\), it is compared with the node in the subsequent OB position \(OB*{i+1}\). If the evaluation function value \(f\) of the node in \(IB*i\) is smaller than that in \(OB*{i+1}\), the two nodes are swapped, and the node previously in \(OB*{i+1}\) is passed to the next IB cell, \(IB*{i+1}\). This process effectively shifts nodes with higher \(f\) values into the IB, preserving order in the OB.

A second case occurs when the head of the OB is dequeued, leaving a "bubble" at position \(OB_0\). In response, the corresponding input cell \(IB_0\) compares its node with the next OB cell \(OB_1\). If the \(f\) value of \(IB_0\) is lower than that of \(OB_1\), the node in \(IB_0\) is inserted into \(OB_0\). Otherwise, the node from \(OB_1\) fills the vacancy, and the bubble propagates one position to the right in the OB.

### BRAM Tree

### Hybrid Tree

This is a architecture proposed by Huang et al. in 2014\cite{huang2014}.

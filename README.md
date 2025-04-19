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

## Architectures

### Register Array

[Description]

Features:

### Register Tree

[Description]

Features:

### Systolic Array

[Description]

Features:

### BRAM Tree

[Description]

Features:

### Pipelined BRAM Tree

[Description]

Features:

### Hybrid Tree

[Description]

Features:

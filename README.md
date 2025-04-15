# Hardware Priority Queue Architecture Analysis - A Scalability Study

## Abstract

This project presents a comprehensive analysis of various hardware priority queue architectures proposed in the past decfor FPGA implementation. Priority queues are fundamental data structures used in many applications such as task scheduling, graph algorithms, and hardware accelerators. This study evaluates and compares the performance, resource utilization, and scalability characteristics of different hardware priority queue implementations.

The architectures are analyzed across various queue sizes and data widths to provide insights into their scalability properties. Performance metrics include maximum clock frequency, throughput, latency, and resource usage (LUTs, registers, BRAMs). The analysis helps in selecting the most appropriate priority queue architecture based on specific application requirements.

## How to Use

### Project Structure
- `hwpq/` - Contains RTL implementations of different priority queue architectures
- `py-scripts/` - Python scripts for data analysis and visualization
- `vivado-analysis_plots/` - Generated plots comparing different architectures
- `vivado-runtime/` - Vivado runtime files
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
A simple array-based priority queue implementation where elements are stored in registers and sorted in each cycle. This architecture provides fast access to the highest priority element but suffers from scalability issues as queue size increases due to quadratic growth in comparison logic.

Features:
- Good for small queue sizes (up to 16-32 elements)
- Low latency for dequeue operations
- Simple design and easy to implement
- Versions with and without enqueue capability

### Register Tree
A binary tree-based implementation using registers. Elements are organized in a heap structure, which provides better scalability than the register array approach while maintaining reasonable access time to the highest priority element.

Features:
- Better scalability than register array (efficient for queue sizes up to 64-128 elements)
- Logarithmic time complexity for operations
- Balanced resource utilization
- Available in standard and cycled variants with configurable enqueue capabilities

### Systolic Array
A pipelined architecture using systolic processing elements that operate in a synchronized manner. The systolic array distributes computation across multiple processing units, improving throughput at the cost of increased latency.

Features:
- High throughput for streaming applications
- Regular structure well-suited for FPGA implementation
- Good scalability for medium-sized queues
- Efficient for applications with continuous streaming data

### BRAM Tree
A binary heap implementation that uses Block RAMs (BRAMs) for storage instead of registers. This architecture significantly reduces LUT and register usage while increasing the maximum possible queue size.

Features:
- Excellent for large queue sizes (1000+ elements)
- Efficient use of FPGA BRAM resources
- Reduced logic utilization
- Higher latency compared to register-based implementations

### Pipelined BRAM Tree
An extension of the BRAM Tree architecture with pipelining to improve throughput. This implementation trades increased latency for higher clock frequencies, making it suitable for high-performance applications requiring large queue sizes.

Features:
- Improved clock frequency compared to basic BRAM tree
- Better throughput through pipelining
- Efficient for large queues with high-performance requirements
- Higher resource usage than basic BRAM tree

### Hybrid Tree
A composite architecture that combines register-based and BRAM-based approaches. It uses registers for the first few levels of the tree (frequently accessed) and BRAMs for deeper levels, balancing performance and resource utilization.

Features:
- Combines advantages of register tree and BRAM tree
- Better performance than pure BRAM implementation
- More scalable than pure register implementation
- Good compromise for medium to large queue sizes

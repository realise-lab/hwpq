# Architecture Overviews

This repository contains various hardware implementations of priority queues, each designed with different architectural approaches to optimize for specific performance metrics. Below is a brief overview of each architecture.

## Register-based Implementations

### [Register Array](./register_array/README.md)

A simple implementation that stores priority queue elements in registers arranged linearly, performing sequential comparisons for queue operations. While conceptually straightforward, this approach offers limited scalability for larger queue sizes.

### [Register Array Pipelined](./register_array_pipelined/README.md)

An enhanced version of the register array that employs pipelining to divide comparison operations across multiple clock cycles, improving achievable clock frequency at the cost of increased latency.

### [Register Tree](./register_tree/README.md)

A heap-based implementation that closely resembles a software priority queue. Unlike software implementations that typically require $O(log\ N)$ time complexity, this hardware version achieves $O(1)$ time complexity for dequeue and replace operations through parallel compare-and-swap operations across the tree structure.

### [Register Tree Pipelined](./register_tree_pipelined/README.md)

A pipelined version of the register tree that splits the compare-and-swap logic between cycles, reducing combinational path lengths and allowing for higher clock frequencies.

## Memory-based Implementations

### [BRAM Tree](./bram_tree/README.md)

An implementation that leverages Block RAM (BRAM) for storing queue elements, reducing resource utilization compared to register-based approaches while increasing access latency.

### [BRAM Tree Pipelined](./bram_tree_pipelined/README.md)

A pipelined version of the BRAM tree architecture that improves throughput by breaking down one BRAM into mutiples that represent each depth of tree.

## Hybrid and Advanced Implementations

### [Hybrid Tree](./hybrid_tree/README.md)

A combined approach that utilizes both registers and memory elements, attempting to balance the performance advantages of registers with the resource efficiency of memory-based storage.

### [Systolic Array](./systolic_array/README.md)

A specialized architecture that employs a systolic array design pattern for highly parallel processing of priority queue operations, potentially offering superior throughput for specific workloads.

## Performance Comparisons

Each architecture has been analyzed for various performance metrics including maximum achievable frequency, resource utilization, and operation latency. Refer to individual README files for detailed performance characteristics and comparisons. (Updating in progress)

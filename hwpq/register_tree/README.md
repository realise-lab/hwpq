# Register Tree

## Description

Among all hardware architectures, the register tree most closely resembles a software-based priority queue, preserving the heap property to maintain element order.

## Dataflow

![register_tree_cycle_data_flow](imgs/register_tree_overall.png)

During a replace operation, the highest-priority element is removed and returned in a single clock cycle. Concurrently, compare-and-swap operations are performed between nodes on alternating levels of the tree to restore the heap property. The dequeue operation behaves similarly, with the only distinction being that an invalid value is inserted in place of the removed root element.

In contrast, the enqueue operation follows a different procedure. It searches for the leftmost invalid entry and replaces it with the new data. This insertion triggers a reordering process to maintain the heap structure, resulting in a worst-case time complexity of $O(log\ N)$, consistent with its software counterpart.

As illustrated in Figure, both dequeue and replace operations complete in a single cycle, while the enqueue operation requires two cycles to propagate the new entry to its correct position. A detailed view of the compare-and-swap operation occurring between cycle 2 and cycle 3 is provided in Figure~\ref{register_tree-compNswap}.

Alternatively, if single-cycle throughput is not a critical requirement for the target application, the two consecutive compare-and-swap phases can be distributed across two clock cycles. This relaxed scheduling reduces the per-cycle logic depth, effectively achieving a time complexity of $O(2)$.

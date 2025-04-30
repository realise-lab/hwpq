# Register Tree Architecture Detailed Explaination

During a replace operation, the highest-priority element is removed and returned in a single clock cycle.
Concurrently, compare-and-swap operations are performed between nodes on alternating levels of the tree to restore the heap property.
The dequeue operation behaves similarly, with the only distinction being that an invalid value is inserted in place of the removed root element.

In contrast, the enqueue operation follows a different procedure. It searches for the leftmost invalid entry and replaces it with the new data. This insertion triggers a reordering process to maintain the heap structure, resulting in a worst-case time complexity of $O(log\ N)$, consistent with its software counterpart.

As illustrated in Figure, both dequeue and replace operations complete in a single cycle, while the enqueue operation requires two cycles to propagate the new entry to its correct position. A detailed view of the compare-and-swap operation occurring between cycle 2 and cycle 3 is provided in Figure~\ref{register_tree-compNswap}.

Alternatively, if single-cycle throughput is not a critical requirement for the target application, the two consecutive compare-and-swap phases can be distributed across two clock cycles. This relaxed scheduling reduces the per-cycle logic depth, effectively achieving a time complexity of $O(2)$.

## Description

Among all hardware architectures, the register tree most closely resembles a software-based priority queue, preserving the heap property to maintain element order. In this discussion, we focus on a max-priority queue that returns the largest element; a min-priority queue operates analogously, substituting comparisons for the smallest value.

We evaluated four variations of the register tree architecture, including the baseline implementation with enqueue functionality \cite{huang2014}, a variant without enqueue functionality, and two pipelined counterparts in which each compare-and-swap stage was split across two cycles to improve maximum achievable frequency. As shown from figure ~\ref{fig:reg_tree_perf_comp}, Contrary to initial expectations, pipelining did not yield performance advantages compare to un-pipelined version, as the frequency gains were insufficient to offset the latency overhead introduced by the additional pipeline stage. However, we do see that the performance drop as queue size grow is much more gradual than the un-pipelined one, which indicates the pipelined version is more scalable when it comes to larger size of queue. Especially for the implementation with enqueue funtionality enabled. If be able to enqueue during operations is a ciritcal aspect of your design, and a large queue size is needed, then pipelining is a must.

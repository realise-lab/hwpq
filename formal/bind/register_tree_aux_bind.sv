// Attaches hwpq_tree_aux to register_tree. NODES_NEEDED, not QUEUE_SIZE: the invariant ranges
// over every allocated node. The read side reopens early only when a sink outlasts HEAD_CYCLES.
bind register_tree hwpq_tree_aux #(
    .DATA_WIDTH  (DATA_WIDTH),
    .NODES_NEEDED(NODES_NEEDED),
    .EARLY_HEAD  (HEAD_CYCLES < SINK_CYCLES)
) u_aux (
    .i_CLK     (i_CLK),
    .i_RSTn    (i_RSTn),
    .head_valid(head_valid),
    .head_ready(head_ready),
    .queue     (queue)
);

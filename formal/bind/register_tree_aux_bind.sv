// Attaches hwpq_tree_aux to register_tree
//
// Separate from register_tree_bind.sv because the two specs answer different
// questions: the shared spec is black-box and portable, this one reaches inside
// a single family. Keeping the binds apart keeps that boundary visible.
//
// NODES_NEEDED, not QUEUE_SIZE: the tree allocates (1 << TREE_DEPTH) - 1 nodes
// (register_tree.sv:47), which is the array the invariant has to range over.
bind register_tree hwpq_tree_aux #(
    .DATA_WIDTH  (DATA_WIDTH),
    .NODES_NEEDED(NODES_NEEDED)
) u_aux (
    .i_CLK     (i_CLK),
    .i_RSTn    (i_RSTn),
    .head_valid(head_valid),
    .queue     (queue)
);

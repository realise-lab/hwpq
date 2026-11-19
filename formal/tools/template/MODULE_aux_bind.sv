// Attaches hwpq_@MODULE@_aux to @MODULE@
//
// Separate from @MODULE@_bind.sv because the two answer different questions:
// the shared spec is black-box and portable, this one reaches inside a single
// module. Keeping the binds apart keeps that boundary visible in the file list.
//
// Bind to the DUT TYPE, and pass the DUT's own localparams where the addendum
// needs to range over an internal array: a tree allocates (1 << TREE_DEPTH)-1
// nodes, which is not QUEUE_SIZE.
bind @MODULE@ hwpq_@MODULE@_aux #(
    .DATA_WIDTH(DATA_WIDTH),
    .QUEUE_SIZE(QUEUE_SIZE)
) u_aux (
    .i_CLK (i_CLK),
    .i_RSTn(i_RSTn)
);

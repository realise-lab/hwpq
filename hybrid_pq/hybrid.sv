/*******************************************************************************
  Module Name: hybrid_pq
  Description: Implements a hybrid priority queue using a register array and 
               multiple BRAM-based trees. It takes new entries, manages their 
               distribution among the components, and outputs the top entry.
  Inputs:  clk       - Clock signal
           new_entry - New entry to be inserted into the priority queue
  Outputs: top_entry - The highest priority entry in the queue
*******************************************************************************/

module hybrid_pq #(parameter N_TREES = 4, WIDTH = 32) (
    input  logic                clk,
    input  logic [WIDTH-1:0]    new_entry,
    output logic [WIDTH-1:0]    top_entry
);
    logic [WIDTH-1:0] reg_array_entry;
    logic [WIDTH-1:0] tree_entries [0:N_TREES-1];

    // Instantiate register array
    register_array #(N_TREES, WIDTH) reg_array_inst (
        .clk(clk),
        .new_entry(new_entrY),
        .top_entry(reg_array_entry)
    );

    // Instantiate BRAM-trees
    genvar i;
    generate
        for (i = 0; i < N_TREES; i = i + 1) begin
            // Create N_TREES instances of bram_tree modules
            bram_tree #(WIDTH) bram_tree_inst (
                .clk(clk),
                .new_entry(tree_entries[i]),
                .top_entry(tree_entries[i])
            );
        end
    endgenerate

    // Logic to select and update trees
    always_ff @(posedge clk) begin
        // This block should contain logic to determine which BRAM tree to update
        // and pass the new_entry down to the selected tree
        // Currently, it's simplified to always update tree 0
        tree_entries[0] <= reg_array_entry;
        
        // Set the output to be the top entry from tree 0
        // In a full implementation, this should select the highest priority
        // entry from all trees and the register array
        top_entry <= tree_entries[0];
    end
endmodule

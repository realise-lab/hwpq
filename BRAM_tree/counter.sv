module counter(
    input clk,
    output reg [7:0] w_data,
    output reg [7:0] w_addr,
    output reg [7:0] r_addr
    );

    always @(posedge clk) begin
	    w_data <= w_data == 255 ? 0 : w_data + 1;
	    w_addr <= w_addr == 255 ? 0 : w_addr + 1;
	    r_addr <= r_addr == 255 ? 0 : r_addr + 1;
    end
endmodule
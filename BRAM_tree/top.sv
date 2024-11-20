module top(
    input clk,
    input [1:0] sw,
    output [1:0] led
    );

    wire [7:0] w_data;
    wire [7:0] r_data;
    wire [7:0] w_addr;
    wire [7:0] r_addr;

    counter counter(.clk(clk), .w_data(w_data), .w_addr(w_addr), .r_addr(r_addr));

    maybe_bram maybe_bram(.clk(clk), .i_addr(w_addr), .i_data(w_data), .o_addr(r_addr), .write(sw[0]), .read(sw[1]), .o_read(r_data));

    // Do something with the data read from bram so that it does not get
    // eliminated in synthesis.
    assign led[0] = r_data > 100 ? 1 : 0;
endmodule
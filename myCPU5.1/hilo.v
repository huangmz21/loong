module hilo(
    input        clk,
    input  [1:0]  hl_we,
    input  [31:0] h_wdata,
    input  [31:0] l_wdata,
    output [31:0] h_rdata,
    output [31:0] l_rdata
);
reg [1:0] hilo[31:0];

always @(posedge clk) begin
    if(hl_we[1])
        hilo[1]<=h_wdata;
    if(hl_we[0])
        hilo[0]<=h_wdata;

end

assign h_rdata = hilo[1];
assign l_rdata = hilo[0];


endmodule
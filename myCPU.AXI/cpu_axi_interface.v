/*------------------------------------------------------------------------------
--------------------------------------------------------------------------------
Copyright (c) 2016, Loongson Technology Corporation Limited.

All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this 
list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, 
this list of conditions and the following disclaimer in the documentation and/or
other materials provided with the distribution.

3. Neither the name of Loongson Technology Corporation Limited nor the names of 
its contributors may be used to endorse or promote products derived from this 
software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
DISCLAIMED. IN NO EVENT SHALL LOONGSON TECHNOLOGY CORPORATION LIMITED BE LIABLE
TO ANY PARTY FOR DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE 
GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) 
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT 
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--------------------------------------------------------------------------------
------------------------------------------------------------------------------*/

module cpu_axi_interface
(
    input         clk,
    input         resetn, 

    //inst sram-like 
    input         inst_req     ,
    input         inst_wr      ,
    input  [1 :0] inst_size    ,
    input  [31:0] inst_addr    ,
    input  [ 3:0] inst_wstrb   ,
    input  [31:0] inst_wdata   ,
    output [31:0] inst_rdata   ,
    output        inst_addr_ok ,
    output        inst_data_ok ,
    
    //data sram-like 
    input         data_req     ,
    input         data_wr      ,
    input  [1 :0] data_size    ,
    input  [31:0] data_addr    ,
    input  [ 3:0] data_wstrb   ,
    input  [31:0] data_wdata   ,
    output [31:0] data_rdata   ,
    output        data_addr_ok ,
    output        data_data_ok ,

    //axi
    //ar
    output [3 :0] arid         ,
    output [31:0] araddr       ,
    output [7 :0] arlen        ,
    output [2 :0] arsize       ,
    output [1 :0] arburst      ,
    output [1 :0] arlock        ,
    output [3 :0] arcache      ,
    output [2 :0] arprot       ,
    output        arvalid      ,
    input         arready      ,
    //r           
    input  [3 :0] rid          ,
    input  [31:0] rdata        ,
    input  [1 :0] rresp        ,
    input         rlast        ,
    input         rvalid       ,
    output        rready       ,
    //aw          
    output [3 :0] awid         ,
    output [31:0] awaddr       ,
    output [7 :0] awlen        ,
    output [2 :0] awsize       ,
    output [1 :0] awburst      ,
    output [1 :0] awlock       ,
    output [3 :0] awcache      ,
    output [2 :0] awprot       ,
    output        awvalid      ,
    input         awready      ,
    //w          
    output [3 :0] wid          ,
    output [31:0] wdata        ,
    output [3 :0] wstrb        ,
    output        wlast        ,
    output        wvalid       ,
    input         wready       ,
    //b           
    input  [3 :0] bid          ,
    input  [1 :0] bresp        ,
    input         bvalid       ,
    output        bready       
);

reg         reset;
always @(posedge clk) reset <= ~resetn;

//addr
//这些寄存器存储请求的各种信息
reg        do_req;  // Whether there's a request
reg        do_req_or; //req is inst or data;1:data,0:inst
reg        do_wr_r;
reg [1 :0] do_size_r;
reg [31:0] do_addr_r;
reg [ 3:0] do_wstrb_r;
reg [31:0] do_wdata_r;
wire       data_back;
//该次inst请求的地址传输是否ok，首先要求有过data_back为1-->地址握手和响应握手都成功
//然后认为该指令完成了，没有未完成的指令，且确保这不是data指令，即inst_addr_ok
assign inst_addr_ok = !do_req && !data_req;
//没有未完成的指令
assign data_addr_ok = !do_req;
always @(posedge clk)
begin
    do_req     <= !resetn                           ? 1'b0 : 
                  //没有未完成的请求，而且有新的请求发送时;与时钟同步更新
                  (inst_req || data_req) && !do_req ? 1'b1 :
                  //数据返回后，没有请求
                  data_back                         ? 1'b0 : do_req;
    //表示当前请求的类型，如果没有未完成的请求，看输入，如果有data_req，表示是data请求，否则是inst请求              
    do_req_or  <= !resetn ? 1'b0 : 
                  !do_req ? data_req : do_req_or; //1 stands for datarequest
    //表示当前请求的写使能，如果是数据请求，看data_wr，否则看inst_wr
    do_wr_r    <= data_req && data_addr_ok ? data_wr   :
                  inst_req && inst_addr_ok ? inst_wr   : do_wr_r; //data has a higher priority
    //表示大小，和上面同理
    do_size_r  <= data_req && data_addr_ok ? data_size :
                  inst_req && inst_addr_ok ? inst_size : do_size_r;
    //地址
    do_addr_r  <= data_req && data_addr_ok ? data_addr :
                  inst_req && inst_addr_ok ? inst_addr : do_addr_r;
    //写数据
    do_wdata_r <= data_req && data_addr_ok ? data_wdata :
                  inst_req && inst_addr_ok ? inst_wdata :do_wdata_r;
    //字节写使能
    do_wstrb_r <= data_req && data_addr_ok ? data_wstrb :
                  inst_req && inst_addr_ok ? inst_wstrb :do_wstrb_r;
end

//inst sram-like
assign inst_data_ok = do_req && !do_req_or && data_back; //Last trasmission finished && new request is inst_req. Changes after the next posedge after the request.
assign data_data_ok = do_req &&  do_req_or && data_back;
assign inst_rdata   = rdata;
assign data_rdata   = rdata;

//---axi
reg addr_rcv;
reg wdata_rcv;
//databack
assign data_back = addr_rcv && (rvalid && rready || bvalid && bready); //done sending data
always @(posedge clk)
begin
    // 地址是否已经接受;No matter write or read.
    addr_rcv  <= !resetn            ? 1'b0 :
                 arvalid && arready ? 1'b1 :
                 awvalid && awready ? 1'b1 :
                 data_back          ? 1'b0 : addr_rcv;
    //数据是否已经接受
    wdata_rcv <= !resetn            ? 1'b0 :
                 wvalid  && wready  ? 1'b1 :
                 data_back          ? 1'b0 : wdata_rcv;
end
//ar
assign arid    = 4'd0;
assign araddr  = do_addr_r;
assign arlen   = 8'd0;
assign arsize  = do_size_r;
assign arburst = 2'd0;
assign arlock  = 2'd0;
assign arcache = 4'd0;
assign arprot  = 3'd0;
assign arvalid = do_req && !do_wr_r && !addr_rcv;
//r
assign rready  = 1'b1;

//aw
assign awid    = 4'd0;
assign awaddr  = do_addr_r;
assign awlen   = 8'd0;
assign awsize  = do_size_r;
assign awburst = 2'd0;
assign awlock  = 2'd0;
assign awcache = 4'd0;
assign awprot  = 3'd0;
assign awvalid = do_req && do_wr_r && !addr_rcv; //Have request whose wr and addr aren't yet received by slave
//w
assign wid    = 4'd0;
assign wdata  = do_wdata_r;
// assign wstrb  = do_size_r == 2'd0 ? 4'b0001 << do_addr_r[1:0] :
//                 do_size_r == 2'd1 ? 4'b0011 << do_addr_r[1:0] : 4'b1111;
assign wstrb  = do_wstrb_r;
assign wlast  = 1'd1; //No burst, every signal is the last one.
assign wvalid = do_req && do_wr_r && !wdata_rcv;
//b
assign bready  = 1'b1;

endmodule


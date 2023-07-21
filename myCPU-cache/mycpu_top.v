module mycpu_top(
    input [5:0] ext_int,
    input aclk,
    input aresetn,

    //ar
    output  [3 :0] arid   ,
    output  [31:0] araddr ,
    output  [7 :0] arlen  ,
    output  [2 :0] arsize ,
    output  [1 :0] arburst,
    output  [1 :0] arlock ,
    output  [3 :0] arcache,
    output  [2 :0] arprot ,
    output         arvalid,
    input          arready,
    //r
    input [3 :0]   rid    ,
    input [31:0]   rdata  ,
    input [1 :0]   rresp  ,
    input          rlast  ,
    input          rvalid ,
    output         rready ,
    //aw
    output  [3 :0] awid   ,
    output  [31:0] awaddr ,
    output  [7 :0] awlen  ,
    output  [2 :0] awsize ,
    output  [1 :0] awburst,
    output  [1 :0] awlock ,
    output  [3 :0] awcache,
    output  [2 :0] awprot ,
    output         awvalid,
    input          awready,
    //w
    output  [3 :0] wid    ,
    output  [31:0] wdata  ,
    output  [3 :0] wstrb  ,
    output         wlast  ,
    output         wvalid ,
    input          wready ,
    //b
    input [3 :0]   bid    ,
    input [1 :0]   bresp  ,
    input          bvalid ,
    output         bready ,

    //debug
    output [31:0]  debug_wb_pc,
    output [ 3:0]  debug_wb_rf_wen,
    output [ 4:0]  debug_wb_rf_wnum,
    output [31:0]  debug_wb_rf_wdata
);

//cpu inst sram
wire        cpu_inst_req;
wire        cpu_inst_wr;
wire [1 :0] cpu_inst_size;
wire [31:0] cpu_inst_addr;
wire [3 :0] cpu_inst_wstrb;
wire [31:0] cpu_inst_wdata;
wire        cpu_inst_addr_ok;
wire        cpu_inst_data_ok;
wire [31:0] cpu_inst_rdata;
//cpu data sram
wire        cpu_data_req;
wire        cpu_data_wr;
wire [1 :0] cpu_data_size;
wire [31:0] cpu_data_addr;
wire [3 :0] cpu_data_wstrb;
wire [31:0] cpu_data_wdata;
wire        cpu_data_addr_ok;
wire        cpu_data_data_ok;
wire [31:0] cpu_data_rdata;

wire         inst_rd_req;
wire [  2:0] inst_rd_type;
wire [ 31:0] inst_rd_addr;
wire         inst_rd_rdy;
wire         inst_ret_valid;
wire         inst_ret_last;
wire [ 31:0] inst_ret_data;

wire         inst_wr_req;
wire [  2:0] inst_wr_type;
wire [ 31:0] inst_wr_addr;
wire [  3:0] inst_wr_wstrb;
wire [127:0] inst_wr_data;
wire         inst_wr_rdy;

wire         data_rd_req;
wire [  2:0] data_rd_type;
wire [ 31:0] data_rd_addr;
wire         data_rd_rdy;
wire         data_ret_valid;
wire         data_ret_last;
wire [ 31:0] data_ret_data;

wire         data_wr_req;
wire [  2:0] data_wr_type;
wire [ 31:0] data_wr_addr;
wire [  3:0] data_wr_wstrb;
wire [127:0] data_wr_data;
wire         data_wr_rdy;

//cpu
mycpu cpu(
    .clk              (aclk   ),
    .resetn           (aresetn),  //low active
    .ext_int          (ext_int    ),

    .inst_sram_req    (cpu_inst_req    ),
    .inst_sram_wr     (cpu_inst_wr     ),
    .inst_sram_size   (cpu_inst_size   ),
    .inst_sram_addr   (cpu_inst_addr   ),
    .inst_sram_wstrb  (cpu_inst_wstrb  ),
    .inst_sram_wdata  (cpu_inst_wdata  ),
    .inst_sram_addr_ok(cpu_inst_addr_ok),
    .inst_sram_data_ok(cpu_inst_data_ok),
    .inst_sram_rdata  (cpu_inst_rdata  ),
    
    .data_sram_req    (cpu_data_req    ),
    .data_sram_wr     (cpu_data_wr     ),
    .data_sram_size   (cpu_data_size   ),
    .data_sram_addr   (cpu_data_addr   ),
    .data_sram_wstrb  (cpu_data_wstrb  ),
    .data_sram_wdata  (cpu_data_wdata  ),
    .data_sram_addr_ok(cpu_data_addr_ok),
    .data_sram_data_ok(cpu_data_data_ok),
    .data_sram_rdata  (cpu_data_rdata  ),

    //debug interface
    .debug_wb_pc      (debug_wb_pc      ),
    .debug_wb_rf_wen  (debug_wb_rf_wen  ),
    .debug_wb_rf_wnum (debug_wb_rf_wnum ),
    .debug_wb_rf_wdata(debug_wb_rf_wdata)
);

cache_axi_interface my_cache_axi_interface
(
    .clk(aclk),
    .resetn(aresetn), 

    //inst cache 
    .inst_rd_req(inst_rd_req)  ,
    .inst_rd_type(inst_rd_type) ,
    .inst_rd_addr(inst_rd_addr) ,
    .inst_rd_rdy(inst_rd_rdy)  ,
    .inst_ret_valid(inst_ret_valid),
    .inst_ret_last(inst_ret_last),
    .inst_rdata(inst_ret_data)   ,

    .inst_wr_req(inst_wr_req)  ,
    .inst_wr_type(inst_wr_type) ,
    .inst_wr_addr(inst_wr_addr) ,
    .inst_wstrb(inst_wr_wstrb)   ,
    .inst_wdata(inst_wr_data)   ,
    .inst_wr_rdy(inst_wr_rdy)  ,
    
    //data cache 
    .data_rd_req(data_rd_req)  ,
    .data_rd_type(data_rd_type) ,
    .data_rd_addr(data_rd_addr) ,
    .data_rd_rdy(data_rd_rdy)  ,
    .data_ret_valid(data_ret_valid),
    .data_ret_last(data_ret_last),
    .data_rdata(data_ret_data)   ,

    .data_wr_req(data_wr_req)   ,
    .data_wr_type(data_wr_type) ,
    .data_wr_addr(data_wr_addr) ,
    .data_wstrb(data_wr_wstrb)  ,
    .data_wdata(data_wr_data)   ,
    .data_wr_rdy(data_wr_rdy)   ,

    //axi///////
    //ar
    .arid   (arid   )         ,
    .araddr (araddr )         ,
    .arlen  (arlen  )         ,
    .arsize (arsize )         ,
    .arburst(arburst)         ,
    .arlock (arlock )         ,
    .arcache(arcache)         ,
    .arprot (arprot )         ,
    .arvalid(arvalid)         ,
    .arready(arready)         ,
    
    //r           
    .rid    (rid    )         ,
    .rdata  (rdata  )         ,
    .rresp  (rresp  )         ,
    .rlast  (rlast  )         ,
    .rvalid (rvalid )         ,
    .rready (rready )         ,
    
    //aw          
    .awid   (awid   )         ,
    .awaddr (awaddr )         ,
    .awlen  (awlen  )         ,
    .awsize (awsize )         ,
    .awburst(awburst)         ,
    .awlock (awlock )         ,
    .awcache(awcache)         ,
    .awprot (awprot )         ,
    .awvalid(awvalid)         ,
    .awready(awready)         ,
    
    //w          
    .wid    (wid    )         ,
    .wdata  (wdata  )         ,
    .wstrb  (wstrb  )         ,
    .wlast  (wlast  )         ,
    .wvalid (wvalid )         ,
    .wready (wready )         ,
    
    //b           
    .bid    (bid    )         ,
    .bresp  (bresp  )         ,
    .bvalid (bvalid )         ,
    .bready (bready )       
);

cache icache(
    //与CPU的接口
    .clk_g    (aclk),
    .resetn (aresetn),
    
    .valid  (cpu_inst_req ),
    .op     (cpu_inst_wr ),
    .index  (cpu_inst_addr[11:4 ]  ),
    .tag    (cpu_inst_addr[31:12]  ),
    .offset (cpu_inst_addr[3 :0 ]  ),
    .wstrb  (cpu_inst_wstrb),
    .wdata  (cpu_inst_wdata),

    .addr_ok(cpu_inst_addr_ok),
    .data_ok(cpu_inst_data_ok),
    .rdata  (cpu_inst_rdata ),
     //与AXI总线的交互接口
    .rd_req   (inst_rd_req   ),
    .rd_type  (inst_rd_type  ),
    .rd_addr  (inst_rd_addr  ),
    .rd_rdy   (inst_rd_rdy   ),
    .ret_valid(inst_ret_valid),
    .ret_last (inst_ret_last ),
    .ret_data (inst_ret_data ),

    .wr_req  (inst_wr_req  ),
    .wr_type (inst_wr_type ),
    .wr_addr (inst_wr_addr ),
    .wr_wstrb(inst_wr_wstrb),
    .wr_data (inst_wr_data ),
    .wr_rdy  (inst_wr_rdy  )
);

cache dcache(
    //与CPU的接口
    .clk_g    (aclk),
    .resetn (aresetn),
    
    .valid  (cpu_data_req ),
    .op     (cpu_data_wr ),
    .index  (cpu_data_addr[11:4 ]  ),
    .tag    (cpu_data_addr[31:12]  ),
    .offset (cpu_data_addr[3 :0 ]  ),
    .wstrb  (cpu_data_wstrb),
    .wdata  (cpu_data_wdata),

    .addr_ok(cpu_data_addr_ok),
    .data_ok(cpu_data_data_ok),
    .rdata  (cpu_data_rdata ),
     //与AXI总线的交互接口
    .rd_req   (data_rd_req   ),
    .rd_type  (data_rd_type  ),
    .rd_addr  (data_rd_addr  ),
    .rd_rdy   (data_rd_rdy   ),
    .ret_valid(data_ret_valid),
    .ret_last (data_ret_last ),
    .ret_data (data_ret_data ),

    .wr_req  (data_wr_req  ),
    .wr_type (data_wr_type ),
    .wr_addr (data_wr_addr ),
    .wr_wstrb(data_wr_wstrb),
    .wr_data (data_wr_data ),
    .wr_rdy  (data_wr_rdy  )
);
endmodule
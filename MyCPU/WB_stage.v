`include "mycpu.h"

module wb_stage(
    input                           clk           ,
    input                           reset         ,
    //allowin
    output                          ws_allowin    ,
    //from ms
    input                           ms_to_ws_valid,
    input  [`MS_TO_WS_BUS_WD -1:0]  ms_to_ws_bus  ,
    //to rf: for write back
    output [`WS_TO_RF_BUS_WD -1:0]  ws_to_rf_bus  ,

    /**********************/
    //from cp0: data for mtc0
    input  [31:0] cp0_rdata       ,
    output [`WB_TO_CP0_REGISTER_BUS_WD -1:0] wb_to_cp0_register_bus,
    /**********************/

    //forwardpath
    output [32-1:0]                 es_forward_ws,
    //trace debug interface
    output [31:0] debug_wb_pc     ,
    output [ 3:0] debug_wb_rf_wen ,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata,
    output ws_res_from_cp0_h,
    output ws_valid_h,

    output        ws_ex_forward , //Used as a signal of flushing the pipeline
    output        ws_eret
);

 (* keep = "true" *) reg         ws_valid;
wire        ws_ready_go;

 (* keep = "true" *) reg [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus_r;
 //////1
// wire        ws_res_from_mem_h;
// wire        ws_res_from_mem_b;
// wire        ws_res_from_mem_sign;
// wire [1:0]  ws_whb_mux;
//////0
wire        ws_gr_we;
wire [ 4:0] ws_dest;
wire [31:0] ws_final_result;
wire [31:0] ws_pc;
wire        ws_res_from_cp0;
wire [ 4:0] ws_cp0_addr;
wire [ 4:0] ws_excode;
wire [ 4:0] excode_from_ms;
wire [31:0] ws_rt_value;
wire [31:0] badvaddr_from_ms;
assign {ws_rt_value,
        inst_eret,
        bd_from_if,
        mtc0_we_from_ms,
        ws_cp0_addr    ,
        ws_res_from_cp0,  // mfc0: load the value of CP0[rd,sel] to R[rt]
        badvaddr_from_ms, //wrong virtual address passed to WB_stage
        ex_from_ms     ,
        excode_from_ms ,
        
        ws_gr_we       ,  //69:69
        ws_dest        ,  //68:64
        ws_final_result,  //63:32
        ws_pc             //31:0
       } = ms_to_ws_bus_r;

wire   ws_ex;
assign ws_excode = excode_from_ms;
assign ws_ex     = ex_from_ms;
assign ws_ex_forward = ex_from_ms || eret_flush;

assign ws_eret = eret_flush;

wire        rf_we;
wire [4 :0] rf_waddr;
wire [31:0] rf_wdata;
assign ws_to_rf_bus = {rf_we   ,  //37:37
                       rf_waddr,  //36:32
                       rf_wdata   //31:0
                      };

wire        ws_bd;
assign      ws_bd = bd_from_if; 

wire        eret_flush; 
assign      eret_flush = inst_eret;

wire mtc0_we;
assign mtc0_we = mtc0_we_from_ms && ws_valid;

assign wb_to_cp0_register_bus = {ws_ex,             //110:110
                                 ws_excode,         //109:104
                                 badvaddr_from_ms,  //103:72
                                 ws_bd,             //71:71
                                 ws_pc,             //70:39
                                 mtc0_we,   //38:38
                                 ws_cp0_addr,       //37:33
                                 ws_rt_value,       //32:1
                                 eret_flush         //0:0
                                };

assign ws_ready_go = 1'b1;
assign ws_allowin  = !ws_valid || ws_ready_go;
always @(posedge clk) begin
    if (reset || ws_ex) begin
        ws_valid <= 1'b0;
        ms_to_ws_bus_r[75] <= 1'b0;
    end
    else if (ws_allowin) begin
        ws_valid <= ms_to_ws_valid;
    end

    if (ms_to_ws_valid && ws_allowin) begin
        ms_to_ws_bus_r <= ms_to_ws_bus;
    end
    else begin
        ms_to_ws_bus_r[75] <= 1'b0;
    end
end

/************************************/

// to be continued???
assign cp0_addr = ws_cp0_addr;


/************************************/
assign rf_we    = ws_gr_we && ws_valid && ~ws_ex;
assign rf_waddr = ws_dest;
/********************************/
assign rf_wdata = ws_res_from_cp0 ? cp0_rdata : ws_final_result;
/********************************/
assign es_forward_ws = ws_final_result;/////鏄惁鏀规垚rf_wdata锟??

// debug info generate
assign debug_wb_pc       = ws_pc;
assign debug_wb_rf_wen   = {4{rf_we}};
assign debug_wb_rf_wnum  = ws_dest;
//----------------0
assign debug_wb_rf_wdata = rf_wdata;  //更改了debug抓取的信息
assign ws_res_from_cp0_h =ws_res_from_cp0 && ws_valid;
assign ws_valid_h =ws_valid;
endmodule

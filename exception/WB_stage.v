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
    //to cp0:
    output [ 4:0] cp0_addr        ,
    output [31:0] cp0_wdata       ,
    output [`WB_TO_CP0_REGISTER_BUS_WD -1:0] wb_to_cp0_register_bus,
    /**********************/

    //trace debug interface
    output [31:0] debug_wb_pc     ,
    output [ 3:0] debug_wb_rf_wen ,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata
);

reg         ws_valid;
wire        ws_ready_go;

reg [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus_r;
wire        ws_gr_we;
wire [ 4:0] ws_dest;
wire [31:0] ws_final_result;
wire [31:0] ws_pc;
wire        ws_res_from_cp0;
wire [ 4:0] ws_cp0_addr;
wire [ 4:0] ws_excode;
wire        ws_ex;
wire        ws_rt_value;
wire        excode_from_ms;
assign {mtc0_we_from_ms,
        ws_cp0_addr    ,
        ws_res_from_cp0,  // mfc0: load the value of CP0[rd,sel] to R[rt]
        ex_from_ms     ,
        excode_from_ms ,
        badvaddr_from_ms, //wrong virtual address passed to WB_stage
        ws_gr_we       ,  //69:69
        ws_dest        ,  //68:64
        ws_final_result,  //63:32
        ws_rt_value    ,  
        ws_pc             //31:0
       } = ms_to_ws_bus_r;

assign ws_excode = excode_from_ms;
assign ws_ex     = ex_from_ms;

wire        rf_we;
wire [4 :0] rf_waddr;
wire [31:0] rf_wdata;
assign ws_to_rf_bus = {rf_we   ,  //37:37
                       rf_waddr,  //36:32
                       rf_wdata   //31:0
                      };

wire        ws_bd; // ! absence of its' logical part
assign wb_to_cp0_register_bus = {ws_ex,
                                 ws_excode,
                                 badvaddr_from_ms,
                                 ws_bd,
                                 ws_pc,
                                 mtc0_we_from_ms,
                                 ws_cp0_addr,
                                 ws_rt_value
                                 // ! eret_flush signal to be finished
                                };

assign ws_ready_go = 1'b1;
assign ws_allowin  = !ws_valid || ws_ready_go;
always @(posedge clk) begin
    if (reset) begin
        ws_valid <= 1'b0;
    end
    else if (ws_allowin) begin
        ws_valid <= ms_to_ws_valid;
    end

    if (ms_to_ws_valid && ws_allowin) begin
        ms_to_ws_bus_r <= ms_to_ws_bus;
    end
end

/************************************/

// to be continued
assign cp0_addr = ws_cp0_addr;


/************************************/
assign rf_we    = ws_gr_we&&ws_valid;
assign rf_waddr = ws_dest;
/********************************/
assign rf_wdata = ws_res_from_cp0 ? cp0_rdata : ws_final_result;
/********************************/

// debug info generate
assign debug_wb_pc       = ws_pc;
assign debug_wb_rf_wen   = {4{rf_we}};
assign debug_wb_rf_wnum  = ws_dest;
assign debug_wb_rf_wdata = ws_final_result;

endmodule

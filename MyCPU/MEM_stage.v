`include "mycpu.h"

module mem_stage(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          ws_allowin    ,
    output                         ms_allowin    ,
    //from es
    input                          es_to_ms_valid,
    input  [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus  ,
    //to ws
    output                         ms_to_ws_valid,
    output [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus  ,
    //from data-sram
    input  [31                 :0] data_sram_rdata,

    input                          ex_from_ws        //Need to flush
);

reg         ms_valid;
wire        ms_ready_go;

reg [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus_r;
wire        ex_from_es;
wire        excode_from_es;
wire        ms_res_from_mem;
wire        ms_res_from_cp0;
wire        ms_gr_we;
wire [ 4:0] ms_dest;
wire [31:0] ms_alu_result;
wire [31:0] ms_pc;
wire [ 4:0] ms_cp0_addr;     
wire [ 4:0] ms_excode;
wire        ms_ex;
wire        mtc0_we_from_es;
wire        mtc0_we_ms;
wire        rt_value_from_es;
wire        ms_rt_value;
assign ms_rt_value = rt_value_from_es;
assign mtc0_we_ms = mtc0_we_from_es;
assign {mtc0_we_from_es,
        ms_cp0_addr    ,
        ex_from_es     ,
        excode_from_es ,
        ms_res_from_cp0,  // mfc0: load the value of CP0[rd,sel] to R[rt]
        ms_res_from_mem,  //70:70
        ms_gr_we       ,  //69:69
        ms_dest        ,  //68:64
        ms_alu_result  ,  //63:32
        rt_value_from_es,
        ms_pc             //31:0
       } = es_to_ms_bus_r;

wire [31:0] mem_result;
wire [31:0] ms_final_result;

assign ms_to_ws_bus = {mtc0_we_ms    ,
                       ms_cp0_addr    ,
                       ms_res_from_cp0,
                       ms_alu_result  ,
                       ms_ex,
                       ms_excode,
                       ms_gr_we       ,  //69:69
                       ms_dest        ,  //68:64
                       ms_final_result,  //63:32
                       ms_rt_value    ,
                       ms_pc             //31:0
                      };

assign ms_ready_go    = 1'b1;
assign ms_allowin     = !ms_valid || ms_ready_go && ws_allowin;
assign ms_to_ws_valid = ms_valid && ms_ready_go;
always @(posedge clk) begin
    if (reset || ex_from_ws) begin
        ms_valid <= 1'b0;
    end
    else if (ms_allowin) begin
        ms_valid <= es_to_ms_valid;
    end

    if (es_to_ms_valid && ms_allowin) begin
        es_to_ms_bus_r  = es_to_ms_bus;
    end
end

assign mem_result = data_sram_rdata;

assign ms_final_result = ms_res_from_mem ? mem_result
                                         : ms_alu_result;

endmodule

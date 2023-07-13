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
    //forward
    output [32-1:0] ds_forward_ms,
    output [32-1:0] es_forward_ms,
    output ms_res_from_mem,
    output ms_res_from_cp0_h,
    output ms_valid_h,
    //input  [2*5              -1:0] es_to_ms_addr ,
    //output [2*5              -1:0] ms_to_ws_addr 

    output          ex_to_es                    ,
    input           ex_from_ws        //Need to flush
);

 (* keep = "true" *) reg         ms_valid;
wire        ms_ready_go;

 (* keep = "true" *) reg [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus_r;

wire        ex_from_es;
wire [4:0]  excode_from_es;
wire        ms_res_from_cp0;

//////1
wire        ms_res_from_mem_w;
wire        ms_res_from_mem_h;
wire        ms_res_from_mem_b;
wire        ms_res_from_mem_sign;
wire        ms_res_from_mem_lwl;
wire        ms_res_from_mem_lwr;
wire [1:0]  ms_whb_mux;
//////0
wire        ms_gr_we;
wire [ 4:0] ms_dest;
wire [31:0] ms_alu_result;
wire [31:0] ms_pc;
wire [ 4:0] ms_cp0_addr;     
wire [ 4:0] ms_excode;
wire        ms_ex;
wire        mtc0_we_from_es;
wire        mtc0_we_ms;
wire [31:0] ms_rt_value;
wire        inst_addr_ex_ms;
assign mtc0_we_ms = mtc0_we_from_es;
assign {inst_addr_ex_ms,
        inst_eret ,
        bd_from_if,
        mtc0_we_from_es,
        ms_cp0_addr    ,
        ex_from_es     ,
        excode_from_es ,
        ms_res_from_cp0,  // mfc0: load the value of CP0[rd,sel] to R[rt]
        ms_res_from_mem_lwl,   //109:109
        ms_res_from_mem_lwr,   //108:108
        ms_rt_value,        //107:76
        ms_res_from_mem_w,  //75:75
        ms_res_from_mem_h,  //74:74
        ms_res_from_mem_b,  //73:73
        ms_res_from_mem_sign,//72:72
        ms_whb_mux,//71:70
        ms_gr_we       ,  //69:69
        ms_dest        ,  //68:64
        ms_alu_result  ,  //63:32
        ms_pc             //31:0
       } = es_to_ms_bus_r;


assign ms_ex = ex_from_es;
assign ex_to_es = ms_ex || inst_eret; //eret also breaks former insts
assign ms_excode = excode_from_es;

wire [31:0] mem_result;
wire [31:0] ms_final_result;

assign ms_to_ws_bus = {inst_addr_ex_ms,  //149:149
                       ms_rt_value,      //148:117
                       inst_eret ,       //116:116
                       bd_from_if,       //115:115
                       mtc0_we_ms    ,   //114:114
                       ms_cp0_addr    ,  //113:109
                       ms_res_from_cp0,  //108:108
                       ms_alu_result  ,  //107:76
                       ms_ex,            //75:75
                       ms_excode,        //74:70

                       //////0
                       ms_gr_we       ,  //69:69
                       ms_dest        ,  //68:64
                       ms_final_result,  //63:32
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
        es_to_ms_bus_r  <= es_to_ms_bus;
    end
    else begin
        es_to_ms_bus_r[116] <= 1'b0;
    end
end
wire [31:0] mem_result_t1;
wire [1:0] ms_addr_last;
assign ms_addr_last = ms_whb_mux;
assign mem_result_t1 = data_sram_rdata << 8 *(3-ms_addr_last);
wire [31:0] mem_result_lwl;
assign mem_result_lwl = ms_addr_last == 2'b00 ? {data_sram_rdata[7:0],ms_rt_value[23:0]}:
                        ms_addr_last == 2'b01 ? {data_sram_rdata[15:0],ms_rt_value[15:0]}:
                        ms_addr_last == 2'b10 ? {data_sram_rdata[23:0],ms_rt_value[7:0]}:
                        data_sram_rdata[31:0];
wire [31:0] mem_result_lwr;
assign mem_result_lwr = ms_addr_last == 2'b00 ?  data_sram_rdata[31:0]:
                        ms_addr_last == 2'b01 ? {ms_rt_value[31:24],data_sram_rdata[31:8]}:
                        ms_addr_last == 2'b10 ? {ms_rt_value[31:16],data_sram_rdata[31:16]}:
                        {ms_rt_value[31:8],data_sram_rdata[31:24]};

assign mem_result = (ms_res_from_mem_h && ~ms_whb_mux[1] && ms_res_from_mem_sign) ? {{16{data_sram_rdata[15]}}, data_sram_rdata[15:0]} :
                  (ms_res_from_mem_h && ~ms_whb_mux[1] &&~ms_res_from_mem_sign) ? {{16{1'b0}}, data_sram_rdata[15:0]} :
                  (ms_res_from_mem_h &&  ms_whb_mux[1] && ms_res_from_mem_sign) ? {{16{data_sram_rdata[31]}}, data_sram_rdata[31:16]} :
                  (ms_res_from_mem_h &&  ms_whb_mux[1] &&~ms_res_from_mem_sign) ? {{16{1'b0}}, data_sram_rdata[31:16]} :
                  (ms_res_from_mem_b && ~ms_whb_mux[1] && ~ms_whb_mux[0] && ms_res_from_mem_sign) ? {{24{data_sram_rdata[7]}}, data_sram_rdata[7:0]} :
                  (ms_res_from_mem_b && ~ms_whb_mux[1] && ~ms_whb_mux[0] &&~ms_res_from_mem_sign) ? {{24{1'b0}}, data_sram_rdata[7:0]} :
                  (ms_res_from_mem_b && ~ms_whb_mux[1] &&  ms_whb_mux[0] && ms_res_from_mem_sign) ? {{24{data_sram_rdata[15]}}, data_sram_rdata[15:8]} :
                  (ms_res_from_mem_b && ~ms_whb_mux[1] &&  ms_whb_mux[0] &&~ms_res_from_mem_sign) ? {{24{1'b0}}, data_sram_rdata[15:8]} :
                  (ms_res_from_mem_b &&  ms_whb_mux[1] && ~ms_whb_mux[0] && ms_res_from_mem_sign) ? {{24{data_sram_rdata[23]}}, data_sram_rdata[23:16]} :
                  (ms_res_from_mem_b &&  ms_whb_mux[1] && ~ms_whb_mux[0] &&~ms_res_from_mem_sign) ? {{24{1'b0}}, data_sram_rdata[23:16]} :
                  (ms_res_from_mem_b &&  ms_whb_mux[1] &&  ms_whb_mux[0] && ms_res_from_mem_sign) ? {{24{data_sram_rdata[31]}}, data_sram_rdata[31:24]} :
                  (ms_res_from_mem_b &&  ms_whb_mux[1] &&  ms_whb_mux[0] &&~ms_res_from_mem_sign) ? {{24{1'b0}}, data_sram_rdata[31:24]} :
                   data_sram_rdata;

assign ms_final_result = (ms_res_from_mem_w | ms_res_from_mem_h | ms_res_from_mem_b) ? mem_result :
                         (ms_res_from_mem_lwl) ? mem_result_lwl :
                         (ms_res_from_mem_lwr) ? mem_result_lwr :
                          ms_alu_result;
assign ds_forward_ms = ms_final_result;  
assign es_forward_ms = ms_final_result;                                       
assign ms_res_from_cp0_h =ms_res_from_cp0 && ms_valid;
assign ms_valid_h = ms_valid;
endmodule

`include "mycpu.h"

module exe_stage(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          ms_allowin    ,
    output                         es_allowin    ,
    //from ds
    input                          ds_to_es_valid,
    input  [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus  ,
    /*********************************************/
    //from mem
    input  [`MS_TO_ES_BUS_WD -1:0] ms_to_es_bus  ,
    //from wb
    input  [`WS_TO_ES_BUS_WD -1:0] ws_to_es_bus  ,
    /*********************************************/
    //to ms
    output                         es_to_ms_valid,
    output [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus  ,
    // data sram interface
    output        data_sram_en   ,
    output [ 3:0] data_sram_wen  ,
    output [31:0] data_sram_addr ,
    output [31:0] data_sram_wdata
);

reg         es_valid      ;
wire        es_ready_go   ;

reg  [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus_r;
wire [11:0] es_alu_op     ;
wire        es_load_op    ;
wire        es_src1_is_sa ;  
wire        es_src1_is_pc ;
wire        es_src2_is_imm; 
wire        es_src2_is_8  ;
wire        es_gr_we      ;
wire        es_mem_we     ;
wire [ 4:0] es_dest       ;
wire [15:0] es_imm        ;
wire [31:0] es_rs_value   ;
wire [31:0] es_rt_value   ;
wire [31:0] es_pc         ;
/***************************/
wire        ex_from_id    ;
wire        excode_from_id;
wire        signed_from_id;

assign {signed_from_id,
        ex_from_id,
        excode_from_id,
        es_alu_op      ,  //135:124
        es_load_op     ,  //123:123
        es_src1_is_sa  ,  //122:122
        es_src1_is_pc  ,  //121:121
        es_src2_is_imm ,  //120:120
        es_src2_is_8   ,  //119:119
        es_gr_we       ,  //118:118
        es_mem_we      ,  //117:117
        es_dest        ,  //116:112
        es_imm         ,  //111:96
        es_rs_value    ,  //95 :64
        es_rt_value    ,  //63 :32
        es_pc             //31 :0
       } = ds_to_es_bus_r;
/***************************/
wire [31:0] es_alu_src1   ;
wire [31:0] es_alu_src2   ;
wire [31:0] es_alu_result ;

wire        es_res_from_mem;

assign es_res_from_mem = es_load_op;
/*************************************************/
reg        overflow       ;
reg        es_ex          ;
reg [ 4:0] es_excode      ;
// overflow logic part
// ! when alu is unsigned?
always @(*) begin
    if      (signed_from_id && es_alu_op[ 0] && ~es_alu_src1[31] && ~es_alu_src2[31] && es_alu_result[31] )
        overflow  <= 1'b1;
    else if (signed_from_id && es_alu_op[ 0] && es_alu_src1[31]  && es_alu_src2[31]  && ~es_alu_result[31]) 
        overflow  <= 1'b1;
    else if (signed_from_id && es_alu_op[ 1] && es_alu_src1[31]  && ~es_alu_src2[31] && ~es_alu_result[31]) 
        overflow  <= 1'b1;
    else if (signed_from_id && es_alu_op[ 1] && ~es_alu_src1[31] && es_alu_src2[31]  && es_alu_result[31]) 
        overflow  <= 1'b1;
    else overflow <= 1'b0;
end
// es_ex and es_excode logic part
always @(*) begin
    if (ex_from_id) begin
        es_ex     <= 1'b1;
        es_excode <= excode_from_id;
    end
    else if (es_load_op && es_alu_result[1:0]!=2'b00) begin
        es_ex     <= 1'b1;
        es_excode <= 5'h04;
    end
    else if (es_mem_we && es_alu_result[1:0]!=2'b00) begin
        es_ex     <= 1'b1;
        es_excode <= 5'h05;
    end
    else if (overflow) begin
        es_ex     <= 1'b1;
        es_excode <= 5'h0c;
    end 
    else begin
        es_ex     <= 1'b0;
        es_excode <= 5'hxx; // ! do need to be undetermined? 
    end
end
assign es_to_ms_bus = {es_ex,
                       es_excode,
                       es_res_from_mem,  //70:70
                       es_gr_we       ,  //69:69
                       es_dest        ,  //68:64
                       es_alu_result  ,  //63:32
                       es_pc             //31:0
                      };

assign {ex_from_cur_ms
       } = ms_to_es_bus;

assign {ex_from_cur_ws
       } = ws_to_es_bus;
/*************************************************/

assign es_ready_go    = 1'b1;
assign es_allowin     = !es_valid || es_ready_go && ms_allowin;
assign es_to_ms_valid =  es_valid && es_ready_go;
always @(posedge clk) begin
    if (reset) begin
        es_valid <= 1'b0;
    end
    else if (es_allowin) begin
        es_valid <= ds_to_es_valid;
    end

    if (ds_to_es_valid && es_allowin) begin
        ds_to_es_bus_r <= ds_to_es_bus;
    end
end

assign es_alu_src1 = es_src1_is_sa  ? {27'b0, es_imm[10:6]} : 
                     es_src1_is_pc  ? es_pc[31:0] :
                                      es_rs_value;
assign es_alu_src2 = es_src2_is_imm ? {{16{es_imm[15]}}, es_imm[15:0]} : 
                     es_src2_is_8   ? 32'd8 :
                                      es_rt_value;

alu u_alu(
    .alu_op     (es_alu_op    ),
    .alu_src1   (es_alu_src1  ),
    .alu_src2   (es_alu_src2  ),
    .alu_result (es_alu_result)
    );

assign data_sram_en    = 1'b1;
assign data_sram_wen   = es_mem_we && es_valid && ~es_ex && ~ex_from_cur_ms && ~ex_from_cur_ws? 4'hf : 4'h0;
assign data_sram_addr  = es_alu_result;
assign data_sram_wdata = es_rt_value;

endmodule

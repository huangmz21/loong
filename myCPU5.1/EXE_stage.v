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
    //to ms
    output                         es_to_ms_valid,
    output [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus  ,
    // data sram interface
    output        data_sram_en   ,
    output [ 3:0] data_sram_wen  ,
    output [31:0] data_sram_addr ,
    output [31:0] data_sram_wdata,
    //forward datapath
    input [32-1:0] es_forward_ms,
    input [32-1:0] es_forward_ws,
    //forward control
    input [2*2-1:0] es_forward_ctrl,
    output es_mem_we_tohazard,
    output es_valid_tohazard,
    // stall control
    input [1:0] stallE,
    input  [2*5              -1:0] ds_to_es_addr,
    output [2*5              -1:0] es_to_ms_addr,
    output                         es_stop
    
);

 (* keep = "true" *) reg         es_valid      ;
 assign es_valid_tohazard = es_valid;
wire        es_ready_go   ;

 (* keep = "true" *) reg  [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus_r;
reg [2*5-1:0] ds_to_es_addr_r; 
wire [11:0] es_alu_op     ;
//////1
wire [3:0]  es_mudi;
wire [1:0]  es_hl_we;
wire        es_tvalid;
wire        es_tvalid_out;
wire        es_tvalidu;
wire        es_tvalid_outu;
//wire        es_stop;
reg         diva;
wire        es_dst_is_hi;
wire        es_dst_is_lo;
wire        es_res_from_hi;
wire        es_res_from_lo;
//////0
wire        es_load_op    ;
wire        es_src1_is_sa ;  
wire        es_src1_is_pc ;
//////1改名
wire        es_src2_is_usimm; 
wire        es_src2_is_simm; 
//////0
wire        es_src2_is_8  ;
wire        es_gr_we      ;
wire        es_mem_we     ;
wire [ 4:0] es_dest       ;
wire [15:0] es_imm        ;
wire [31:0] es_rs_value   ;
wire [31:0] es_rt_value   ;
wire [31:0] es_pc         ;
//forward datapath

//forward control
wire[1:0] es_f_ctrl1;
wire[1:0] es_f_ctrl2;
// addr
assign es_to_ms_addr = ds_to_es_addr_r;
//wire [4:0] es_rf_raddr1;
//wire [4:0] es_rf_raddr2;
//assign {es_rf_raddr1,  //9:5
 //       es_rf_raddr2  //4:0
  //      }=ds_to_es_addr_r;

assign {es_f_ctrl1,   //3:2
        es_f_ctrl2   //1:0
        } = es_forward_ctrl;

assign {//////1
        es_dst_is_hi   ,  //146:146
        es_dst_is_lo   ,  //145:145
        es_res_from_hi ,  //144:144
        es_res_from_lo ,  //143:143
        es_hl_we       ,  //142:141
        es_mudi        ,  //140:137
        //////0
        es_alu_op      ,  //136:125
        es_load_op     ,  //124:124
        es_src1_is_sa  ,  //123:123
        es_src1_is_pc  ,  //122:122
        //////1改名
        es_src2_is_usimm,  //121:121
        es_src2_is_simm,  //120:120
        //////0
        es_src2_is_8   ,  //119:119
        es_gr_we       ,  //118:118
        es_mem_we      ,  //117:117
        es_dest        ,  //116:112
        es_imm         ,  //111:96
        es_rs_value    ,  //95 :64
        es_rt_value    ,  //63 :32
        es_pc             //31 :0
       } = ds_to_es_bus_r;
assign es_mem_we_tohazard = es_mem_we;
wire [31:0] es_alu_src1   ;
wire [31:0] es_alu_src2   ;
wire [31:0] es_alu_result ;
//////1
wire [31:0] es_final_alu_result ;
wire [63:0] es_prodata   ;
wire [63:0] es_divdata   ;
wire [63:0] es_divdatau  ;
wire [31:0] es_h_wdata   ;
wire [31:0] es_l_wdata   ;
wire [31:0] es_h_rdata   ;
wire [31:0] es_l_rdata   ;

// always @(posedge clk)begin
//     if(reset)
//         diva<=0;
//     else if(es_tvalid)
//         diva<=1;
//     else 
//         diva<=0;
// end

assign es_tvalid  = (es_mudi[2] & ~diva);
assign es_tvalidu = (es_mudi[3] & ~diva);
//////0

wire        es_res_from_mem;
//assign es_gr_we = es_gr_we && es_valid;
//assign es_mem_we = es_mem_we && es_valid;
assign es_res_from_mem = es_load_op && es_valid;
//输出的时候和valid 做与运算
assign es_to_ms_bus = {es_res_from_mem ,//&& !(stallE==2'b10),  //70:70
                       es_gr_we ,//&& !(stallE==2'b10)       ,  //69:69
                       es_dest        ,  //68:64
                       es_final_alu_result , //63:32
                       es_pc             //31:0
                      };

assign es_ready_go    = 1'b1;
assign es_allowin     = (stallE==2'b01)?1'b0:
                        (stallE==2'b10)?1'b1:(!es_valid || es_ready_go && ms_allowin);
assign es_to_ms_valid =  (stallE==2'b01)?1'b0:
                        (stallE==2'b10)?1'b0:(es_valid && es_ready_go);
always @(posedge clk) begin
    if (reset) begin
        es_valid <= 1'b0;
        diva<=0;
    end
  else if (es_allowin) begin
        es_valid <= ds_to_es_valid;
    end
    if (ds_to_es_valid && es_allowin) begin 
        ds_to_es_bus_r <= ds_to_es_bus;
        ds_to_es_addr_r<=ds_to_es_addr;//这个寄存器用来存储上一个周期的地址，用于forward
    end
    if(es_tvalid | es_tvalidu)
        diva<=1;
    else 
        diva<=0;
end



assign es_alu_src1 = es_src1_is_sa  ? {27'b0, es_imm[10:6]} : 
                     es_src1_is_pc  ? es_pc[31:0] :
                     es_f_ctrl1==2'b01    ? es_forward_ms:
                     es_f_ctrl1==2'b10    ? es_forward_ws :
                                      es_rs_value;
assign es_alu_src2 = es_src2_is_simm ? {{16{es_imm[15]}}, es_imm[15:0]} : 
                     es_src2_is_usimm? {{16{1'b0}}, es_imm[15:0]} : 
                     es_src2_is_8   ? 32'd8 :
                     es_f_ctrl2==2'b01    ? es_forward_ms :
                     es_f_ctrl2==2'b10    ? es_forward_ws :
                                      es_rt_value;
                                      assign es_prodata = es_mudi[0] ? $signed(es_alu_src1)*$signed(es_alu_src2) :
              es_mudi[1] ? es_alu_src1*es_alu_src2                   :
              0;

div_gen_0 div_gen_0sign(
    .aclk(clk), 
    .s_axis_divisor_tvalid(es_tvalid), 
    .s_axis_divisor_tready(), 
    .s_axis_divisor_tdata(es_alu_src2), 
    .s_axis_dividend_tvalid(es_tvalid), 
    .s_axis_dividend_tready(), 
    .s_axis_dividend_tdata(es_alu_src1), 
    .m_axis_dout_tvalid(es_tvalid_out), 
    .m_axis_dout_tdata(es_divdata)
);
divu_gen_0 div_gen_0unsign(
    .aclk(clk), 
    .s_axis_divisor_tvalid(es_tvalidu), 
    .s_axis_divisor_tready(), 
    .s_axis_divisor_tdata(es_alu_src2), 
    .s_axis_dividend_tvalid(es_tvalidu), 
    .s_axis_dividend_tready(), 
    .s_axis_dividend_tdata(es_alu_src1), 
    .m_axis_dout_tvalid(es_tvalid_outu), 
    .m_axis_dout_tdata(es_divdatau)
);

assign es_h_wdata = (es_mudi[0] | es_mudi[1]) ? es_prodata[63:32] :
                    es_mudi[2] ? es_divdata[31:0]                 :
                    es_mudi[3] ? es_divdatau[31:0]                :
                    es_dst_is_hi ? es_alu_src1                    :
                    0;
assign es_l_wdata = (es_mudi[0] | es_mudi[1]) ? es_prodata[31:0]  :
                    es_mudi[2] ? es_divdata[63:32]                :
                    es_mudi[3] ? es_divdatau[63:32]               :
                    es_dst_is_lo ? es_alu_src1                    :
                    0;

assign es_stop = (es_mudi[2] & ~es_tvalid_out) | (es_mudi[3] & ~es_tvalid_outu);

hilo hilo1(
    .clk(clk),
    .hl_we(es_hl_we),
    .h_wdata(es_h_wdata),
    .l_wdata(es_l_wdata),
    .h_rdata(es_h_rdata),
    .l_rdata(es_l_rdata)
);
//////0


alu u_alu(
    .alu_op     (es_alu_op    ),
    .alu_src1   (es_alu_src1  ),
    .alu_src2   (es_alu_src2  ),
    .alu_result (es_alu_result)
    );
assign es_final_alu_result = es_res_from_hi ? es_h_rdata:
                             es_res_from_lo ? es_l_rdata:
                             es_alu_result;
assign data_sram_en    = 1'b1;
assign data_sram_wen   = es_mem_we&&es_valid ? 4'hf : 4'h0;
assign data_sram_addr  = es_alu_result;
//如果es_fctrl1
assign data_sram_wdata =   (es_f_ctrl2==2'b01)?es_forward_ms:
                            (es_f_ctrl2==2'b10)?es_forward_ws:
                           es_rt_value;

//hazard unit  处理EX_MEM 和 MEM_WB 之间的数据冒险
wire es_src1_is_ex_mem ;
wire es_src2_is_ex_mem ;
wire es_src1_is_mem_wb ;
wire es_src2_is_mem_wb ;




endmodule
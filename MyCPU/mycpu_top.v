`include "mycpu.h"  //bug4
module mycpu_top(
    input         clk,
    input         resetn,
    // inst sram interface
    output        inst_sram_en,
    output [ 3:0] inst_sram_wen,
    output [31:0] inst_sram_addr,
    output [31:0] inst_sram_wdata,
    input  [31:0] inst_sram_rdata,
    // data sram interface
    output        data_sram_en,
    output [ 3:0] data_sram_wen,
    output [31:0] data_sram_addr,
    output [31:0] data_sram_wdata,
    input  [31:0] data_sram_rdata,
    // trace debug interface
    output [31:0] debug_wb_pc,
    output [ 3:0] debug_wb_rf_wen,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata
);
reg         reset;
always @(posedge clk) reset <= ~resetn;

wire         ds_allowin;
wire         es_allowin;
wire         ms_allowin;
wire         ws_allowin;
wire         fs_to_ds_valid;
wire         ds_to_es_valid;
wire         es_to_ms_valid;
wire         ms_to_ws_valid;
wire [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus;
wire [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus;
wire [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus;
wire [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus;
wire [`WS_TO_RF_BUS_WD -1:0] ws_to_rf_bus;
wire [`BR_BUS_WD       -1:0] br_bus;

//exception signal
wire            ex_from_ws  ;
//forward unit
wire [32-1:0] ds_forward_bus;
wire [2-1:0] ds_forward_ctrl;
wire ifbranch;
wire [10-1:0] ds_to_es_addr;
wire es_valid;
wire [10-1:0] es_to_ms_addr;
wire [32-1:0] es_forward_ms;
wire [32-1:0] es_forward_ws;
wire es_mem_we;
wire [2*2-1:0] es_forward_ctrl;
wire [32-1:0] mem_result;
wire ms_res_from_mem;

//stall
//////1exestop
wire div_stop;
wire ds_res_from_cp0_h;
wire es_res_from_cp0_h;
wire ms_res_from_cp0_h;
wire ws_res_from_cp0_h;
//////0
wire [1:0] stallF;
wire [1:0] stallD;
wire [1:0] stallE;


/////For Exception
wire ex_from_ms_to_es;

wire eret_from_ws;
wire cp0_epc;

// IF stage
if_stage if_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ds_allowin     (ds_allowin     ),
    //brbus
    .br_bus         (br_bus         ),
    //outputs
    .fs_to_ds_valid (fs_to_ds_valid ),
    .fs_to_ds_bus   (fs_to_ds_bus   ),
    // inst sram interface
    .inst_sram_en   (inst_sram_en   ),
    .inst_sram_wen  (inst_sram_wen  ),
    .inst_sram_addr (inst_sram_addr ),
    .inst_sram_wdata(inst_sram_wdata),
    .inst_sram_rdata(inst_sram_rdata),
    //stall
    .stallF(stallF),
    .ex_from_ws(ex_from_ws),
    .bd_from_ds(ifbranch),
    .eret_from_ws(eret_from_ws),
    .cp0_epc(cp0_epc)
);
// ID stage
id_stage id_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .es_allowin     (es_allowin     ),
    .ds_allowin     (ds_allowin     ),
    //from fs
    .fs_to_ds_valid (fs_to_ds_valid ),
    .fs_to_ds_bus   (fs_to_ds_bus   ),
    //to es
    .ds_to_es_valid (ds_to_es_valid ),
    .ds_to_es_bus   (ds_to_es_bus   ),
    //to fs
    .br_bus         (br_bus         ),
    //to rf: for write back
    .ws_to_rf_bus   (ws_to_rf_bus   ),

    .ex_from_ws(ex_from_ws),
    //forward datapath
    .ds_forward_bus (ds_forward_bus),
    //forward control
    .ds_forward_ctrl(ds_forward_ctrl),
    //stall
    .stallD (stallD),
    .ds_to_es_addr(ds_to_es_addr),
    .ifbranch(ifbranch),
    .ds_res_from_cp0_h(ds_res_from_cp0_h)
);
// EXE stage
exe_stage exe_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ms_allowin     (ms_allowin     ),
    .es_allowin     (es_allowin     ),
    //from ds
    .ds_to_es_valid (ds_to_es_valid ),
    .ds_to_es_bus   (ds_to_es_bus   ),
    //to ms
    .es_to_ms_valid (es_to_ms_valid ),
    .es_to_ms_bus   (es_to_ms_bus   ),
    // data sram interface
    .data_sram_en   (data_sram_en   ),
    .data_sram_wen  (data_sram_wen  ),
    .data_sram_addr (data_sram_addr ),
    .data_sram_wdata(data_sram_wdata),

    .ex_from_ws(ex_from_ws)          ,
    .ex_from_ms(ex_from_ms_to_es)    ,
    //forward datapath
    .es_forward_ms  (es_forward_ms  ),
    .es_forward_ws  (es_forward_ws  ),
    //.mem_result(ms_to_ws_bus[63:32]),
    //forward control
    .es_forward_ctrl(es_forward_ctrl),
    .es_mem_we_tohazard(es_mem_we),
    .es_valid_tohazard(es_valid),
    // stall control
    .stallE(stallE),
    .ds_to_es_addr(ds_to_es_addr),
    .es_to_ms_addr(es_to_ms_addr),
    .es_stop(div_stop),
    .es_res_from_cp0_h(es_res_from_cp0_h)

);
// MEM stage
mem_stage mem_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ws_allowin     (ws_allowin     ),
    .ms_allowin     (ms_allowin     ),
    //from es
    .es_to_ms_valid (es_to_ms_valid ),
    .es_to_ms_bus   (es_to_ms_bus   ),
    //to ws
    .ms_to_ws_valid (ms_to_ws_valid ),
    .ms_to_ws_bus   (ms_to_ws_bus   ),
    //from data-sram
    .data_sram_rdata(data_sram_rdata),

    .ex_from_ws(ex_from_ws),
    //forward 
    .ms_res_from_mem(ms_res_from_mem),
    .ds_forward_bus(ds_forward_bus),
    .es_forward_ms(es_forward_ms)   ,
    //.es_to_ms_addr(es_to_ms_addr),
    //.ms_to_ws_addr(ms_to_ws_addr)
    .ex_to_es(ex_from_ms_to_es),
    //hazard
    .ms_res_from_cp0_h(ms_res_from_cp0_h)
);

wire [31:0] cp0_rdata;
wire [`WB_TO_CP0_REGISTER_BUS_WD -1:0] wb_to_cp0_register_bus;

// WB stage
wb_stage wb_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ws_allowin     (ws_allowin     ),
    //from ms
    .ms_to_ws_valid (ms_to_ws_valid ),
    .ms_to_ws_bus   (ms_to_ws_bus   ),
    //to rf: for write back
    .ws_to_rf_bus   (ws_to_rf_bus   ),
    //forward
    .es_forward_ws  (es_forward_ws  ),
    //trace debug interface
    .debug_wb_pc      (debug_wb_pc      ),
    .debug_wb_rf_wen  (debug_wb_rf_wen  ),
    .debug_wb_rf_wnum (debug_wb_rf_wnum ),
    .debug_wb_rf_wdata(debug_wb_rf_wdata),

    .ws_ex(ex_from_ws)                   ,

    .cp0_rdata(cp0_rdata)                ,
    .wb_to_cp0_register_bus(wb_to_cp0_register_bus),
    .ws_eret(eret_from_ws),
    .ws_res_from_cp0_h(ws_res_from_cp0_h)
);


hazard hazard (
       //decode_stage beq
    .ifbranch(ifbranch),            //是否跳转
    .rf_raddr1(ds_to_es_addr[9:5]),       //使用的源寄存器号,IF阶段
    .rf_raddr2(ds_to_es_addr[4:0]), 
    .ds_forward_ctrl(ds_forward_ctrl),
    .mem_we(ds_to_es_bus[117]),
    .ds_res_from_cp0_h(ds_res_from_cp0_h),


    //ex_stage alu
    .es_valid(es_valid),
    .es_rf_raddr1(es_to_ms_addr[9:5]),
    .es_rf_raddr2(es_to_ms_addr[4:0]),
    .es_dest(es_to_ms_bus[68:64]),
    .es_res_from_mem(es_to_ms_bus[70]),
    .es_gr_we(es_to_ms_bus[69]),
    .es_forward_ctrl(es_forward_ctrl),
    .es_mem_we(es_mem_we),
    .es_res_from_cp0_h(es_res_from_cp0_h),

    //mem_stage 
    .ms_dest(ms_to_ws_bus[68:64]),
    .ms_res_from_mem(ms_res_from_mem),
    .ms_gr_we(ms_to_ws_bus[69]),
    .ms_res_from_cp0_h(ms_res_from_cp0_h),

    //wb_stage
    .ws_dest(ws_to_rf_bus[36:32]),
    .ws_gr_we(ws_to_rf_bus[37]),
    .ws_res_from_cp0_h(ws_res_from_cp0_h),

    //stall and flush
    //00=normal�?01=stall�?10=flush
    .stallF(stallF),
    .stallD(stallD),
    //.stallF(stallF),
    .stallE(stallE),
    .div_stop(div_stop)
);
//-------------------------------temporary
wire [5:0] ext_int_in;
assign ext_int_in = 6'b0;

cp0 cp0(
    .clk(clk),
    .reset(reset),
    .ext_int_in(ext_int_in),
    .wb_to_cp0_register_bus(wb_to_cp0_register_bus),
    .rdata(cp0_rdata),
    .epc(cp0_epc)
);

endmodule

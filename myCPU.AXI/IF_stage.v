`include "mycpu.h"

module if_stage(
    input                          clk            ,
    input                          reset          ,
    //allwoin
    input                          ds_allowin     ,
    //branchbus
    input  [`BR_BUS_WD       -1:0] br_bus         ,
    input  br_stall                               ,
    //to ds
    output                         fs_to_ds_valid ,
    output [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus   ,
    //whether ID to EXE
    input                          ds_to_es_valid,
    input                          es_allowin,
    // inst sram interface
    output        inst_sram_en   ,
    output        inst_sram_wr,
    output [ 1:0] inst_sram_size,
    output [ 3:0] inst_sram_wen  ,
    output [31:0] inst_sram_addr ,
    output [31:0] inst_sram_wdata,
    input         inst_sram_addr_ok,
    input         inst_sram_data_ok,
    input  [31:0] inst_sram_rdata,
    //stall
    input  [ 1:0] stallF,
    input         ex_from_ws,     // flush signal
    input         bd_from_ds,     // connect to id_stage's output -- ifbranch
    input         eret_from_ws,
    input  [31:0] cp0_epc,
    output        fs_valid_h
);

reg         fs_valid;
wire        fs_ready_go;
wire        fs_allowin;
wire        to_fs_valid;

wire [31:0] seq_pc;
wire [31:0] nextpc;

wire        br_taken;
wire [31:0] br_target;
reg          br_taken_r;
reg  [ 31:0] br_target_r;
reg          br_r_valid;
reg          br_stall_r;
wire         br_taken_true;
wire [ 31:0] br_target_true;
wire         br_stall_true;

assign {br_taken,br_target} = br_bus;
assign br_taken_true = br_r_valid ? br_taken_r : br_taken;
assign br_target_true = br_r_valid ? br_target_r : br_target;
assign br_stall_true = br_r_valid ? br_stall_r : br_stall;

wire [31:0] fs_inst;
reg  [31:0] fs_pc;
wire        fs_ex;
assign fs_ex = (fs_pc[1:0]==2'b00) ? 0 : 1;

wire        bd_to_ds;  //not bd if this inst is not valid
assign bd_to_ds = bd_from_ds && !fs_ex;

assign fs_to_ds_bus = {bd_to_ds,  //65:65
                       fs_ex   ,  //64:64
                       fs_inst ,  //63:32
                       fs_pc      //31:0   
                       };

// pre-IF stage
wire prfs_ready_go;
reg  arready_r;
reg  prfs_to_fs_inst_valid;
reg  [31:0] prfs_to_fs_inst_r;
reg  [31:0] prfs_to_fs_inst_r_t;
reg  inst_req_not_allow;
reg  fsinst_from_pre_r_num;

assign prfs_ready_go = !br_stall_true && ((inst_sram_addr_ok && inst_sram_en) || arready_r);
assign to_fs_valid  = ~reset && prfs_ready_go;
assign seq_pc       = fs_pc + 3'h4;
assign nextpc       = br_taken_true && fs_valid ? br_target_true : seq_pc; 

// IF stage
reg  [ 1:0] cancle_throw_inst;
reg  fs_to_ds_inst_valid;
reg  [31:0] fs_to_ds_inst_r;
reg  rvalid_r;
reg  inst_sram_data_ok_r;
reg  inst_for_fs_waiting;
reg  [31:0] inst_stopped_for_br;
wire fs_ready_go_for_cancle;

assign fs_ready_go    = (stallF==2'b01 || (br_taken_true && ~prfs_ready_go))?1'b0:
                        //(inst_sram_data_ok || prfs_to_fs_inst_valid || fs_to_ds_inst_valid || (inst_sram_data_ok_r && inst_sram_addr_ok)) && ~cancle_throw_inst;
                        (inst_sram_data_ok || prfs_to_fs_inst_valid || fs_to_ds_inst_valid || (inst_sram_data_ok_r)) && !cancle_throw_inst;
assign fs_ready_go_for_cancle = (stallF==2'b01)?1'b0:
                                //(inst_sram_data_ok || prfs_to_fs_inst_valid || fs_to_ds_inst_valid || (inst_sram_data_ok_r && inst_sram_addr_ok)) && ~cancle_throw_inst;
                                (inst_sram_data_ok || prfs_to_fs_inst_valid || fs_to_ds_inst_valid || (inst_sram_data_ok_r)) && !cancle_throw_inst;

assign fs_allowin     = !fs_valid || (fs_ready_go) && ds_allowin;
assign fs_to_ds_valid = (fs_valid && fs_ready_go);
//assign inst_rready    = fs_allowin || cancle_throw_inst;

always @(posedge clk) begin
    //暂存brbus信号
    if(reset || ex_from_ws) begin
        br_r_valid  <= 1'b0;
        br_stall_r  <= 1'b0;
        br_taken_r  <= 1'b0;
        br_target_r <= 1'b0;
    end
    else if(br_taken_true && fs_valid && fs_allowin && prfs_ready_go) begin
        br_r_valid <= 1'b0;////////////////可以考虑加双重保险（把stall、taken等都置零）
    end
    else if(br_taken && ds_to_es_valid && es_allowin) begin
        br_stall_r<=br_stall;
        br_taken_r<=br_taken;
        br_target_r<=br_target;
        br_r_valid <= 1'b1;
    end
    //单周期内已有addrok和dataok但还不能走，等待allowin之前，nextpc对应的dataok到来
    if(reset || ex_from_ws) begin
        inst_for_fs_waiting <= 1'b0;
    end
    else if(to_fs_valid && fs_allowin) begin
        inst_for_fs_waiting <= 1'b0;
    end
    else if(inst_sram_data_ok && prfs_ready_go && (fs_to_ds_inst_valid || prfs_to_fs_inst_valid)) begin
        inst_for_fs_waiting <= 1'b1;
    end
    //prfs_to_fs_inst_r_t该变就变，取指由prfs_to_fs_inst_r解决
    if(reset || ex_from_ws) begin
        prfs_to_fs_inst_r_t <= 0;
    end
    else if(inst_sram_data_ok && prfs_ready_go && (fs_to_ds_inst_valid || prfs_to_fs_inst_valid)) begin
        prfs_to_fs_inst_r_t <= inst_sram_rdata;
    end
    //解决prfs_to_fs_inst_r提前变化问题
    if(reset || ex_from_ws) begin
        prfs_to_fs_inst_valid <= 1'b0;
        prfs_to_fs_inst_r <= 0;
    end
    else if((inst_sram_data_ok && prfs_ready_go && (fs_to_ds_inst_valid || prfs_to_fs_inst_valid)) && (to_fs_valid && fs_allowin)) begin
        prfs_to_fs_inst_r <= inst_sram_rdata;
        prfs_to_fs_inst_valid <= 1'b1;
    end
    else if((inst_for_fs_waiting) && (to_fs_valid && fs_allowin)) begin
        prfs_to_fs_inst_r <= prfs_to_fs_inst_r_t;
        prfs_to_fs_inst_valid <= 1'b1;
    end
    else if(to_fs_valid && fs_allowin) begin
        prfs_to_fs_inst_valid <= 1'b0;
    end

    // if(reset) begin
    //     fsinst_from_pre_r <= 1'b0;
    // end
    // else if(to_fs_valid && fs_allowin) begin
    //     fsinst_from_pre_r <= prfs_to_fs_inst_valid;
    // end

    //已握手成功但还不能走，接下来不允许继续发送请求
    if(reset || ex_from_ws) begin
        inst_req_not_allow <= 1'b0;
    end
    else if(to_fs_valid && fs_allowin) begin
        inst_req_not_allow <= 1'b0;
    end
    else if(inst_sram_addr_ok && prfs_ready_go && ~fs_allowin) begin//////////inst_sram_addr_ok && 感觉不需要
        inst_req_not_allow <= 1'b1;
    end
    //保证强行把延迟槽指令留在IF级之后，addrok到来时fs_readygo是1
    if(reset || ex_from_ws) begin
        inst_sram_data_ok_r <= 1'b0;
        inst_stopped_for_br <= 0;
    end
    else if(to_fs_valid && fs_allowin) begin
        inst_sram_data_ok_r <= 1'b0;
        inst_stopped_for_br <= 0;
    end
    else if(inst_sram_data_ok && (br_taken_true && ~prfs_ready_go)) begin
        inst_sram_data_ok_r <= 1'b1;
        inst_stopped_for_br <= inst_sram_rdata;
    end
    //表明该周期已握手成功
    if(reset || ex_from_ws) begin
        arready_r <= 1'b0;
    end
    else if(to_fs_valid && fs_allowin) begin
        arready_r <= 1'b0;
    end
    else if(inst_sram_addr_ok && inst_sram_en) begin
        arready_r <= 1'b1;
    end
    //解决dataok已到来但ID不允许进入
    if(reset || ex_from_ws) begin
        fs_to_ds_inst_valid <= 1'b0;///////////////need more thinking considering exception
        fs_to_ds_inst_r <= 0;
    end
    //else if(inst_sram_data_ok && fs_ready_go && ~ds_allowin && ~fs_valid) begin
    else if(inst_sram_data_ok && fs_ready_go && ~ds_allowin && ~fs_to_ds_inst_valid && ~prfs_to_fs_inst_valid) begin
        fs_to_ds_inst_r <= inst_sram_rdata;
        fs_to_ds_inst_valid <= 1'b1;
    end
    else if(fs_to_ds_valid && ds_allowin) begin
        fs_to_ds_inst_valid <= 1'b0;
    end
    //cancle时多取的指令需舍弃
    if(reset) begin
        cancle_throw_inst <= 2'b00;
    end
    else if(ex_from_ws && (to_fs_valid  && ~(~fs_allowin && ~fs_ready_go_for_cancle))) begin
        cancle_throw_inst <= 2'b01;
    end
    else if(ex_from_ws && (~to_fs_valid && (~fs_allowin && ~fs_ready_go_for_cancle))) begin
        cancle_throw_inst <= 2'b01;
    end
    else if(ex_from_ws && (to_fs_valid  && (~fs_allowin && ~fs_ready_go_for_cancle))) begin
        cancle_throw_inst <= 2'b10;
    end
    else if(inst_sram_data_ok && cancle_throw_inst) begin
        cancle_throw_inst <= cancle_throw_inst - 2'b01;
    end    
    // if(reset) begin
    //     cancle_throw_inst <= 2'b00;
    // end
    // else if(ex_from_ws && (to_fs_valid  || (~fs_allowin && ~fs_ready_go))) begin
    //     cancle_throw_inst <= 2'b01;
    // end
    // else if(inst_sram_data_ok && cancle_throw_inst) begin
    //     cancle_throw_inst <= cancle_throw_inst - 2'b01;
    // end
end

always @(posedge clk) begin
    if (reset) begin
        fs_valid <= 1'b0;
    end
    else if (ex_from_ws) begin
        fs_valid <= 1'b0;
    end
    else if (fs_allowin) begin
        fs_valid <= to_fs_valid;
    end

    if (reset) begin
        fs_pc <= 32'hbfbf_fffc;  //trick: to make nextpc be 0xbfc00000 during reset 
    end
    else if (ex_from_ws && ~eret_from_ws) begin
        fs_pc <= 32'hbfc0_037c;  //jump to the exception handler
    end
    else if (eret_from_ws) begin
        fs_pc <= cp0_epc - 32'h4; //exception handle finished, back to the original inst
    end
    else if (to_fs_valid && fs_allowin) begin
        fs_pc <= nextpc;
    end
end

// always @(posedge clk) begin
// end
//virtual - real address
wire i_kuseg  ;
wire i_kseg0  ;
wire i_kseg1  ;
wire i_kseg2  ;
wire i_kseg3  ;
assign i_kuseg   = ~nextpc[31];
assign i_kseg0   = nextpc[31:29]==3'b100;
assign i_kseg1   = nextpc[31:29]==3'b101;
assign i_kseg2   = nextpc[31:29]==3'b110;
assign i_kseg3   = nextpc[31:29]==3'b111;

assign inst_sram_addr[28:0]  = nextpc[28:0];
assign inst_sram_addr[31:29] =   
                       i_kuseg ? {(!nextpc[30]) ? 2'b01 : 2'b10, nextpc[29]} :
          (i_kseg0 || i_kseg1) ? 3'b000 :
                                 nextpc[31:29];
          
//assign inst_sram_en    = ~(prfs_ready_go && ~fs_ready_go) && ~br_stall_true && ~prfs_to_fs_inst_valid;

// reg crazy;
// always @(posedge clk) begin
//     if(reset) begin
//         crazy<=1'b1;
//     end
//     if(inst_sram_data_ok) begin
//         crazy<=1'b1;
//     end
//     else if(inst_sram_addr_ok) begin
//         crazy<=1'b0;
//     end
// end
// assign inst_sram_en    = ~br_stall_true && ~prfs_to_fs_inst_valid && crazy;
//assign inst_sram_en    = ~br_stall_true && ~prfs_to_fs_inst_valid;
//assign inst_sram_en    = ~br_stall_true && ~prfs_to_fs_inst_valid && ~inst_req_not_allow;

assign inst_sram_en    = ~br_stall_true && ~inst_req_not_allow && ~reset;
assign inst_sram_wen   = 4'h0;
assign inst_sram_wr    = |inst_sram_wen;
assign inst_sram_size  = 2'b10;
//assign inst_sram_addr  = nextpc;
assign inst_sram_wdata = 32'b0;

assign fs_inst         = fs_to_ds_inst_valid     ? fs_to_ds_inst_r   :
                         prfs_to_fs_inst_valid   ? prfs_to_fs_inst_r :
                         inst_sram_data_ok       ? inst_sram_rdata   :
                         inst_sram_data_ok_r     ? inst_stopped_for_br   :
                         0;
assign fs_valid_h      = fs_valid;

endmodule
`include "mycpu.h"

module if_stage(
    input                          clk            ,
    input                          reset          ,
    //allwoin
    input                          ds_allowin     ,
    //brbus
    input  [`BR_BUS_WD       -1:0] br_bus         ,
    input  br_stall                               ,
    //input  [`BR_BUS_WD       :0] br_bus         ,
    //to ds
    output                         fs_to_ds_valid ,
    output [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus   ,
    // inst sram interface
    output        inst_sram_en   ,
    output [ 3:0] inst_sram_wen  ,
    output [31:0] inst_sram_addr ,
    output [31:0] inst_sram_wdata,
    input  [31:0] inst_sram_rdata,
    //stall
    input [1:0] stallF,
    input       ex_from_ws,        //Need to flush
    input       bd_from_ds, // connect to id_stage's output -- ifbranch
    input       eret_from_ws,
    input [31:0]cp0_epc,
    output fs_valid_h
);

 (* keep = "true" *) reg         fs_valid;
wire        fs_ready_go;
wire        fs_allowin;
wire        to_fs_valid;

wire [31:0] seq_pc;
wire [31:0] nextpc;

wire         br_taken;
wire [ 31:0] br_target;
assign {br_taken,br_target} = br_bus;

wire [31:0] fs_inst;
 (* keep = "true" *) reg  [31:0] fs_pc;
/*******************************/
wire if_ex;
assign if_ex = (fs_pc[1:0]==2'b00) ? 0 : 1;


assign fs_to_ds_bus = {bd_from_ds,//65:65
                       if_ex,     //64:64
                       fs_inst ,  //63:32
                       fs_pc      //31:0   
                       };
/*******************************/

// pre-IF stage
wire prfs_ready_go;
assign prfs_ready_go = !br_stall;
assign to_fs_valid  = ~reset && prfs_ready_go;
assign seq_pc       = fs_pc + 3'h4;
assign nextpc       = br_taken ? br_target : seq_pc; 

// IF stage
assign fs_ready_go    = (stallF==2'b01)?1'b0:1'b1;


assign fs_allowin     = (!fs_valid || fs_ready_go && ds_allowin);

assign fs_to_ds_valid = (fs_valid && fs_ready_go);

always @(posedge clk) begin
    if (reset || ex_from_ws) begin
        fs_valid <= 1'b0;
    end
    else if (fs_allowin) begin
        fs_valid <= to_fs_valid;
    end

    if (reset) begin
        fs_pc <= 32'hbfbf_fffc;  //trick: to make nextpc be 0xbfc00000 during reset 
    end
    else if (ex_from_ws&&~eret_from_ws) begin
        fs_pc <= 32'hbfc0_037c;  //jump to the exception handler
    end
    else if (eret_from_ws) begin
        fs_pc <= cp0_epc - 32'h4;
    end
    else if (to_fs_valid && fs_allowin) begin
        fs_pc <= nextpc;
    end
end

assign inst_sram_en    = to_fs_valid && fs_allowin;
assign inst_sram_wen   = 4'h0;
assign inst_sram_addr  = nextpc;
assign inst_sram_wdata = 32'b0;

assign fs_inst         = inst_sram_rdata;
assign fs_valid_h = fs_valid;

endmodule

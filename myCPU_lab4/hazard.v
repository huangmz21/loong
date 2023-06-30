module hazard(

    //decode_stage beq
    input ifbranch,            //是否跳转
    input [4:0] rf_raddr1,       //使用的源寄存器号,IF阶段
    input [4:0] rf_raddr2, 
    input mem_we,                 
    output [1:0] ds_forward_ctrl,
    //ex_stage alu
    input es_valid,
    input [4:0] es_rf_raddr1,
    input [4:0] es_rf_raddr2,
    input [4:0] es_dest,
    input es_mem_we,
    input es_res_from_mem,
    input es_gr_we,
    output [3:0] es_forward_ctrl,

    //mem_stage 
    input [4:0] ms_dest,
    input ms_res_from_mem,
    input ms_gr_we,

    //wb_stage
    input [4:0] ws_dest,
    input ws_gr_we,

    //stall and flush
    //00=normal，01=stall，10=flush
    output  [1:0]stallD,
    //output  [1:0]stallF, IF阶段不用stall,因为ID阶段的allowin=0会使得前面为0.否则无法自启动
    output  [1:0]stallE

);

//ID forward 0=normal 1=ms_forward
reg ds_f_ctrl1;
reg ds_f_ctrl2;

always @(*)
begin
    if(rf_raddr1!=0 && ms_gr_we && rf_raddr1==ms_dest)
        ds_f_ctrl1=1'b1;
    else begin
        ds_f_ctrl1=1'b0;
    end

    if(rf_raddr2!=0 && ms_gr_we && rf_raddr2==ms_dest)
        ds_f_ctrl2=1'b1;
    else begin
        ds_f_ctrl2=1'b0;
    end
end
assign ds_forward_ctrl={ds_f_ctrl1,  //1:1
                        ds_f_ctrl2   //0:0
                           };
//ID stall
//include change-beq stall , lw-use stall
//reg [1:0] sF;
reg [1:0] sD;
reg [1:0] sE;
//assign stallF=sF;
assign stallD=sD;
assign stallE=sE;
always @(*)
begin
    if(ifbranch &&  es_valid
       &&( es_gr_we && (rf_raddr1==es_dest || rf_raddr2==es_dest))
       //||(ms_res_from_mem && (rf_raddr1==ms_dest || rf_raddr2 == ms_dest)))
    ) //如果该条是条件跳转指令，而且上一条为R或者LW,则在EXE处stall,注：上上条为lw的情况不阻塞
    begin
        //sF=2'b01;
        sD=2'b01;
        sE=2'b00;
    end
    else begin
        //sF=2'b00;
        sD=2'b00;
        sE=2'b00;
    end
end


//EX forward ,deal with alu_use
//如果是mem阶段的用01，如果是wb阶段的用10，如果都不是用00,如果是Lw_sw用11
reg [1:0]es_f_ctrl1;
reg [1:0]es_f_ctrl2;
always @(*) begin
    if(es_rf_raddr1!=0 && ms_gr_we && es_rf_raddr1==ms_dest)
        es_f_ctrl1=2'b01;
    else if(es_rf_raddr1!=0 && ws_gr_we && es_rf_raddr1==ws_dest)
        es_f_ctrl1=2'b10;
    else 
        es_f_ctrl1=2'b00;
end
always @(*) begin
    if(es_rf_raddr2!=0 && ms_gr_we && es_rf_raddr2==ms_dest) //上一条R型，从mem转发到exe，exe执行R或者sw
        es_f_ctrl2=2'b01;
    else if(es_rf_raddr2!=0 && ws_gr_we && es_rf_raddr2==ws_dest)//上上一条R型，从wb转发到exe
        es_f_ctrl2=2'b10;
    else 
        es_f_ctrl2=2'b00;
end
assign es_forward_ctrl={
                            es_f_ctrl1,  //3:2
                            es_f_ctrl2   //1:0
                            };

endmodule
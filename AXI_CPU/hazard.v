module hazard(
    //if_stage
    input fs_valid_h,
    output  reg br_stall,

    //
    //decode_stage beq
    input ifbranch,            //??????
    input [4:0] rf_raddr1,       //????????????,IF???
    input [4:0] rf_raddr2, 
    input mem_we,          
    input ds_res_from_cp0_h,   
    input ds_valid_h,    
    output [1:0] ds_forward_ctrl,

    //ex_stage alu
    input [4:0] es_rf_raddr1,
    input [4:0] es_rf_raddr2,
    input [4:0] es_dest,
    input es_mem_we,
    input es_res_from_mem,
    input es_gr_we,
    input es_res_from_cp0_h,
    input es_valid_h,
    output [3:0] es_forward_ctrl,

    //mem_stage 
    input [4:0] ms_dest,
    input ms_res_from_mem,
    input ms_gr_we,
    input ms_valid_h,
    input   ms_res_from_cp0_h,  

    //wb_stage
    input [4:0] ws_dest,
    input ws_gr_we,
    //input ws_res_from_mem,
    input ws_res_from_cp0_h,
    input ws_valid_h,

    //stall and flush
    output [1:0] stallF,
    //00=normal??01=stall??10=flush
    output  [1:0]stallD,
    //output  [1:0]stallF, IF??��???stall,???ID??��?allowin=0?????????0.?????????????
    output  [1:0]stallE,
    input        div_stop

);

//ID forward 0=normal 1=ms_forward
reg ds_f_ctrl1;
reg ds_f_ctrl2;

always @(*)
begin
    if(rf_raddr1!=0 && ms_gr_we && rf_raddr1==ms_dest && ms_valid_h)
        ds_f_ctrl1=1'b1;
    else begin
        ds_f_ctrl1=1'b0;
    end

    if(rf_raddr2!=0 && ms_gr_we && rf_raddr2==ms_dest && ms_valid_h)
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
reg [1:0] sF;
reg [1:0] sD;
reg [1:0] sE;
assign stallF=sF;
assign stallD=sD;
assign stallE=sE;
wire ifmfc0;
assign ifmfc0 = (ds_res_from_cp0_h || es_res_from_cp0_h || ms_res_from_cp0_h || ws_res_from_cp0_h);
always @(*)
begin
    if(ifbranch &&  es_valid_h
       &&( es_gr_we && (rf_raddr1==es_dest || rf_raddr2==es_dest))
    ) 
    begin
        sF=2'b00;
        sD=2'b01;
        sE=2'b00;
        br_stall = 1'b1 && ds_valid_h;
        //change-beq��stall����Ϊ�����R����lw����mem�׶βŻ�ͳһת��
        //���Կ��Է���br_stall
    end
    else if(div_stop)
    begin
        sF=2'b00;
        sD=2'b00;
        sE=2'b01;
        br_stall = 1'b0 && ds_valid_h;
    end
    else if(ifmfc0)
    begin
        sF=2'b01;
        sD=2'b00;
        sE=2'b00;
        br_stall = 1'b0 && ds_valid_h;
    end
    else begin
        sF=2'b00;
        sD=2'b00;
        sE=2'b00;
        br_stall = 1'b0 && ds_valid_h;
    end
end


//EX forward ,deal with alu_use
//?????mem??��???01???????wb??��???10??????????????00,?????Lw_sw??11
reg [1:0]es_f_ctrl1;
reg [1:0]es_f_ctrl2;
always @(*) begin
    if(es_rf_raddr1!=0 && ms_gr_we && es_rf_raddr1==ms_dest && ms_valid_h)
        es_f_ctrl1=2'b01;
    else if(es_rf_raddr1!=0 && ws_gr_we && es_rf_raddr1==ws_dest && ws_valid_h)
        es_f_ctrl1=2'b10;
    else 
        es_f_ctrl1=2'b00;
end
always @(*) begin
    if(es_rf_raddr2!=0 && ms_gr_we && es_rf_raddr2==ms_dest && ms_valid_h) //?????R?????mem?????exe??exe???R????sw
        es_f_ctrl2=2'b01;
    else if(es_rf_raddr2!=0 && ws_gr_we && es_rf_raddr2==ws_dest && ws_valid_h)//???????R?????wb?????exe
        es_f_ctrl2=2'b10;
    else 
        es_f_ctrl2=2'b00;
end
assign es_forward_ctrl={
                            es_f_ctrl1,  //3:2
                            es_f_ctrl2   //1:0
                            };

endmodule
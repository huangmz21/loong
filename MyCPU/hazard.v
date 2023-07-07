module hazard(

    //decode_stage beq
    input ifbranch,            //�Ƿ���ת
    input [4:0] rf_raddr1,       //ʹ�õ�Դ�Ĵ�����,IF�׶�
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
    //00=normal��01=stall��10=flush
    output  [1:0]stallD,
    //output  [1:0]stallF, IF�׶β���stall,��ΪID�׶ε�allowin=0��ʹ��ǰ��Ϊ0.�����޷�������
    output  [1:0]stallE,
    input        div_stop

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
    ) 
    begin
        sD=2'b01;
        sE=2'b00;
    end
    else if(div_stop)
    begin
        sD=2'b00;
        sE=2'b01;
    end
    else begin
        sD=2'b00;
        sE=2'b00;
    end
end


//EX forward ,deal with alu_use
//�����mem�׶ε���01�������wb�׶ε���10�������������00,�����Lw_sw��11
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
    if(es_rf_raddr2!=0 && ms_gr_we && es_rf_raddr2==ms_dest) //��һ��R�ͣ���memת����exe��exeִ��R����sw
        es_f_ctrl2=2'b01;
    else if(es_rf_raddr2!=0 && ws_gr_we && es_rf_raddr2==ws_dest)//����һ��R�ͣ���wbת����exe
        es_f_ctrl2=2'b10;
    else 
        es_f_ctrl2=2'b00;
end
assign es_forward_ctrl={
                            es_f_ctrl1,  //3:2
                            es_f_ctrl2   //1:0
                            };

endmodule
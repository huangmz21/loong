`define  IDLE     3'b000
`define  LOOKUP   3'b001
`define  MISS     3'b010
`define  REPLACE  3'b011
`define  REFILL   3'b100
`define  WRITE    3'b101

`define  True_v   1'b1
`define  False_v  1'b0
`define  ZeroWord 32'h00000000


module cache(
    
    input clk_g,
    input resetn,
    //��CPU�Ľӿ�
    input valid,
    input op,
    input [7:0] index,
    input [19:0] tag,
    input [3:0] offset,
    input [3:0] wstrb ,
    input [31:0] wdata ,

    output addr_ok ,
    output data_ok ,
    output [31:0] rdata ,
     //��AXI���ߵĽ����ӿ�
    output wire rd_req   ,
    output [2:0] rd_type  ,
    output [31:0] rd_addr ,
    input rd_rdy ,
    input ret_valid ,
    input  ret_last ,
    input [31:0] ret_data ,

    output reg wr_req ,
    output [2:0] wr_type ,
    output [31:0] wr_addr ,
    output [3:0] wr_wstrb,
    output [127:0] wr_data ,
    input wr_rdy  
);
//״̬��
reg [2:0] main_cur_state;
reg [2:0] main_next_state;

reg [2:0] w_cur_state;
reg [2:0] w_next_state;
//the table ,as the Tag,V,bank use the IP core
//-------------------------------------------//Request Buffer
reg op_request;
reg [7:0] index_request;
reg [19:0] tag_request;
reg [3:0] offset_request;
reg [3:0] wstrb_request;
reg [31:0] wdata_request;
wire wea_request;
assign wea_request = ((main_cur_state==`IDLE && main_next_state==`LOOKUP)
                     ||(main_cur_state==`LOOKUP && main_next_state == `LOOKUP));
always @(posedge clk_g) begin
    if(!resetn) begin
        op_request <= `False_v;
        index_request <= 8'h00;
        tag_request <= 20'h00000;
        offset_request <= 4'h0;
        wstrb_request <= 4'h0;
        wdata_request <= 32'h00000000;
    end
    else if(valid && wea_request)
    begin
        op_request <= op;
        index_request <= index;
        tag_request <= tag;
        offset_request <= offset;
        wstrb_request <= wstrb;
        wdata_request <= wdata;
    end
end


//Tag Compare (not considering uncache)
wire Way0_hit;
wire Way1_hit;
wire cache_hit;
assign Way0_hit = Way0_V && (Way0_Tag == tag_request);
assign Way1_hit = Way1_V && (Way1_Tag == tag_request);
assign cache_hit = (Way0_hit || Way1_hit) && (main_cur_state == `LOOKUP) && (~uncache);

wire uncache;
assign uncache = tag_request[19:4] == 16'h1faf; //invalid is not uncache

//Data Select
wire [31:0] Way0_load_word;
wire [31:0] Way1_load_word;
wire load_res;
wire replace_way;
wire [127:0] Way0_data;
wire [127:0] Way1_data;
wire [127:0] replace_data;
assign Way0_load_word = (offset[3:2]==2'b00)?Way0_Bank0_douta:
                        (offset[3:2]==2'b01)?Way0_Bank1_douta:
                        (offset[3:2]==2'b10)?Way0_Bank2_douta:
                        Way0_Bank3_douta;
assign Way1_load_word = (offset[3:2]==2'b00)?Way1_Bank0_douta:
                        (offset[3:2]==2'b01)?Way1_Bank1_douta:
                        (offset[3:2]==2'b10)?Way1_Bank2_douta:
                        Way1_Bank3_douta;
assign load_res = (Way0_hit)?Way0_load_word:        //����miss
                  (Way1_hit)?Way1_load_word:
                  (!cache_hit)?ret_data:
                  32'h00000000;
assign Way0_data = {Way0_Bank0_douta,
                    Way0_Bank1_douta,
                    Way0_Bank2_douta,
                    Way0_Bank3_douta};
assign Way1_data = {Way1_Bank0_douta,
                    Way1_Bank1_douta,
                    Way1_Bank2_douta,
                    Way1_Bank3_douta};     
assign replace_data = replace_way ? Way1_data : Way0_data;   
//Miss Buffer
reg miss_way;
reg [3:0] miss_read_num;
reg [31:0] miss_addr;
reg miss_op;

wire [3:0] miss_wea;    //��ʱ��ȷ���Ƿ�Ӧ����refillʱ�������е�bank����ˢ�£�Ĭ��Ϊ1111
assign miss_wea =4'b1111;
wire miss_to_replace;
assign miss_to_replace = (main_cur_state == `MISS && main_next_state ==`REPLACE);
wire lookup_to_miss;
assign lookup_to_miss = (main_cur_state == `LOOKUP && main_next_state ==`MISS);
always @(posedge clk_g) begin
    if(miss_to_replace)
        miss_way<=(Way0_V==1'b0)?1'b0:
                    (Way1_V==1'b0)?1'b1:
                    lfsr_reg;
    else if(lookup_to_miss) begin
        miss_addr<=uncache?{tag_request,index_request,offset_request}
                    :{tag_request,index_request,4'b0};
        miss_op <= op_request;
        
    end
        

    if(ret_valid)
        miss_read_num<=miss_read_num+1;
    else if (main_cur_state==`REPLACE && main_next_state ==`REFILL)
        miss_read_num<=4'b0;
    
end
//LFSR   ֮����滻ΪLRU�㷨
reg lfsr_reg;       // 1-bit register to hold the LFSR value
always @(posedge clk_g)
begin
    if (!resetn)
        lfsr_reg <= 1'b1; // Initialize the LFSR with a non-zero value (1)
    else
        lfsr_reg <= lfsr_reg ^ (lfsr_reg >> 1); // Feedback logic based on XOR
end

//Write Buffer �����Ӧ��д���У�����Ϣ����
reg valid_write;  //�Ƿ��д�д������
reg way_write;
//reg [1:0] bank_write;
reg [19:0] tag_write;
reg [7:0] index_write;
reg [3:0] offset_write;
reg [3:0] wea_write;
reg [31:0] dina_write;
wire ena_write;
assign ena_write = (cache_hit==1'b1 && main_cur_state == `LOOKUP 
                    && op_request == 1'b1)?1'b1:1'b0;

always @(posedge clk_g) begin
    if(!resetn) begin
        valid_write <= 1'b0;
        tag_write <= 20'h00000;
        way_write <= 1'b0;
        index_write <= 8'b0;
        offset_write <= 4'b0;
        wea_write <= 4'b0;
        dina_write <= 32'h00000000;
    end

    else if(ena_write) begin
        valid_write <= 1'b1;
        tag_write <= tag_request;
        way_write <= Way0_hit?1'b0:1'b1;
        index_write <= index_request;
        offset_write <= offset_request;
        wea_write <= wstrb_request;
        dina_write <= wdata_request;
        
    end

    
end



//------------------------------------------//Way0_TagV
wire Way0_TagV_ena;
wire [2:0] Way0_TagV_wea;
wire [7:0] Way0_TagV_addra;
wire [23:0] Way0_TagV_dina;
wire [23:0] Way0_TagV_douta;
wire Way0_V;
wire [19:0] Way0_Tag;
assign Way0_V = Way0_TagV_douta[0];
assign Way0_Tag = Way0_TagV_douta[20:1];
//
wire [7:0] index_replace_0;
assign index_replace_0 = (lfsr_reg == 1'b0)? index_request: 8'b0;
wire [7:0] index_refill_0;
assign index_refill_0 = (miss_way == 1'b0)? index_request: 8'b0;
//
assign Way0_TagV_addra = (main_next_state == `LOOKUP) ? index:
                         (main_next_state == `REPLACE) ? index_replace_0:
                         (main_next_state == `REFILL) ? index_refill_0:
                         8'b0;
assign Way0_TagV_dina = (main_next_state == `REFILL) ? {3'b0,tag_request,1'b1}:
                        24'b0;
assign Way0_TagV_ena = (main_next_state == `LOOKUP)? 1'b1:
                       (main_next_state == `REPLACE && miss_way == 1'b0)? 1'b1:
                       (main_next_state == `REFILL && miss_way == 1'b0)? 1'b1: 1'b0; 
//����һ��ʼӦ��дʹ��Ϊ��                               
assign Way0_TagV_wea = (main_next_state == `LOOKUP) ? 3'b000:
                       (main_next_state == `REFILL && miss_way == 1'b0)? 3'b111: 3'b000;                                                        
Way0_TagV Way0_TagV(

  .clka(clk_g),
  .ena(Way0_TagV_ena),
  .wea(Way0_TagV_wea),
  .addra(Way0_TagV_addra),
  .dina(Way0_TagV_dina),
  .douta(Way0_TagV_douta)
  );
//--------------------------------------------//Way1_TagV
wire Way1_TagV_ena;
wire [2:0] Way1_TagV_wea;
wire [7:0] Way1_TagV_addra;
wire [23:0] Way1_TagV_dina;
wire [23:0] Way1_TagV_douta;
wire Way1_V;
wire [19:0] Way1_Tag;
assign Way1_V = Way1_TagV_douta[0];
assign Way1_Tag = Way1_TagV_douta[20:1];
//
wire [7:0] index_replace_1;
assign index_replace_1 = (lfsr_reg == 1'b1)? index_request: 8'b0;
wire [7:0] index_refill_1;
assign index_refill_1 = (miss_way == 1'b1)? index_request: 8'b0;
//
assign Way1_TagV_addra = (main_next_state == `LOOKUP) ? index:
                         (main_next_state == `REPLACE) ? index_replace_1:
                         (main_next_state == `REFILL) ? index_refill_1:
                         8'b0;
assign Way1_TagV_dina = (main_next_state == `REFILL) ? {3'b0,tag_request,1'b1}:
                        24'b0;
assign Way1_TagV_ena = (main_next_state == `LOOKUP)? 1'b1:
                       (main_next_state == `REPLACE && miss_way == 1'b1)? 1'b1:
                       (main_next_state == `REFILL && miss_way == 1'b1)? 1'b1: 1'b0; 
assign Way1_TagV_wea = (main_next_state == `LOOKUP) ? 3'b000:
                       (main_next_state == `REFILL && miss_way == 1'b1)? 3'b111: 3'b000;   

Way1_TagV Way1_TagV(

  .clka(clk_g),
  .ena(Way1_TagV_ena),
  .wea(Way1_TagV_wea),
  .addra(Way1_TagV_addra),
  .dina(Way1_TagV_dina),
  .douta(Way1_TagV_douta)
  );
//------------------------------------------// Way0_Bank0
wire Way0_Bank0_ena;
wire [3:0] Way0_Bank0_wea;
wire [7:0] Way0_Bank0_addra;
wire [31:0] Way0_Bank0_dina;
wire [31:0] Way0_Bank0_douta;

assign  Way0_Bank0_ena = uncache?1'b0
                        :(w_cur_state == `WRITE && way_write == 1'b0 && offset_write[3:2] == 2'b00)?1'b1:
                        (main_next_state == `LOOKUP && offset[3:2] == 2'b00)?1'b1:
                         (main_next_state == `REPLACE && miss_way == 1'b0)?1'b1:
                         (main_cur_state == `REFILL && miss_way == 1'b0 && miss_read_num == 2'b00)?1'b1:
                         1'b0;
assign Way0_Bank0_wea = (w_cur_state == `WRITE && way_write == 1'b0 && offset_write[3:2] == 2'b00)?wea_write:
                        (main_cur_state == `REFILL && miss_way == 1'b0 && miss_read_num == 2'b00)?miss_wea:
                        4'b0;
assign  Way0_Bank0_addra = (w_cur_state == `WRITE && way_write == 1'b0 && offset_write[3:2] == 2'b00)?index_write:
                           (main_next_state == `LOOKUP && offset[3:2] == 2'b00)?index:
                           (main_next_state == `REPLACE && miss_way == 1'b0)?index_replace_0:
                           (main_cur_state == `REFILL && miss_way == 1'b0 && miss_read_num == 2'b00)?index_refill_0:
                           8'b0;
assign Way0_Bank0_dina = (w_cur_state == `WRITE)?dina_write:
                         (main_cur_state == `REFILL && offset_request[3:2] == 2'b00 && op_request == 1'b1)?wdata_request:
                         (main_cur_state == `REFILL )?ret_data:
                         32'b0;
    
Way0_Bank0 Way0_Bank0(

  .clka(clk_g),
  .ena(Way0_Bank0_ena),
  .wea(Way0_Bank0_wea),
  .addra(Way0_Bank0_addra),
  .dina(Way0_Bank0_dina),
  .douta(Way0_Bank0_douta)
  );
//------------------------------------------// Way0_Bank1
wire Way0_Bank1_ena;
wire [3:0] Way0_Bank1_wea;
wire [7:0] Way0_Bank1_addra;
wire [31:0] Way0_Bank1_dina;
wire [31:0] Way0_Bank1_douta;

assign  Way0_Bank1_ena = uncache?1'b0
                        :(w_cur_state == `WRITE && way_write == 1'b0 && offset_write[3:2] == 2'b01)?1'b1:
                        (main_next_state == `LOOKUP && offset[3:2] == 2'b01)?1'b1:
                         (main_next_state == `REPLACE && miss_way == 1'b0)?1'b1:
                         (main_cur_state == `REFILL && miss_way == 1'b0 && miss_read_num == 2'b01)?1'b1:
                         1'b0;
assign Way0_Bank1_wea = (w_cur_state == `WRITE && way_write == 1'b0 && offset_write[3:2] == 2'b01)?wea_write:
                        (main_cur_state == `REFILL && miss_way == 1'b0 && miss_read_num == 2'b01)?miss_wea:
                        4'b0;
assign  Way0_Bank1_addra = (w_cur_state == `WRITE && way_write == 1'b0 && offset_write[3:2] == 2'b01)?index_write:
                           (main_next_state == `LOOKUP && offset[3:2] == 2'b01)?index:
                           (main_next_state == `REPLACE && miss_way == 1'b0)?index_replace_0:
                           (main_cur_state == `REFILL && miss_way == 1'b0 && miss_read_num == 2'b01)?index_refill_0:
                           8'b0;
assign Way0_Bank1_dina = (w_cur_state == `WRITE)?dina_write:
                         (main_cur_state == `REFILL && offset_request[3:2] == 2'b01 && op_request == 1'b1)?wdata_request:
                         (main_cur_state == `REFILL )?ret_data:
                         32'b0;
Way0_Bank1 Way0_Bank1(

  .clka(clk_g),
  .ena(Way0_Bank1_ena),
  .wea(Way0_Bank1_wea),
  .addra(Way0_Bank1_addra),
  .dina(Way0_Bank1_dina),
  .douta(Way0_Bank1_douta)
  );
//------------------------------------------//Way0_Bank2
wire Way0_Bank2_ena;
wire [3:0] Way0_Bank2_wea;
wire [7:0] Way0_Bank2_addra;
wire [31:0] Way0_Bank2_dina;
wire [31:0] Way0_Bank2_douta;
assign  Way0_Bank2_ena = uncache?1'b0
                        :(w_cur_state == `WRITE && way_write == 1'b0 && offset_write[3:2] == 2'b10)?1'b1:
                        (main_next_state == `LOOKUP && offset[3:2] == 2'b10)?1'b1:
                         (main_next_state == `REPLACE && miss_way == 1'b0)?1'b1:
                         (main_cur_state == `REFILL && miss_way == 1'b0 && miss_read_num == 2'b10)?1'b1:
                         1'b0;
assign Way0_Bank2_wea = (w_cur_state == `WRITE && way_write == 1'b0 && offset_write[3:2] == 2'b10)?wea_write:
                        (main_cur_state == `REFILL && miss_way == 1'b0 && miss_read_num == 2'b10)?miss_wea:
                        4'b0;
assign  Way0_Bank2_addra = (w_cur_state == `WRITE && way_write == 1'b0 && offset_write[3:2] == 2'b10)?index_write:
                           (main_next_state == `LOOKUP && offset[3:2] == 2'b10)?index:
                           (main_next_state == `REPLACE && miss_way == 1'b0)?index_replace_0:
                           (main_cur_state == `REFILL && miss_way == 1'b0 && miss_read_num == 2'b10)?index_refill_0:
                           8'b0;
assign Way0_Bank2_dina = (w_cur_state == `WRITE)?dina_write:
                         (main_cur_state == `REFILL && offset_request[3:2] == 2'b10 && op_request == 1'b1)?wdata_request:
                         (main_cur_state == `REFILL )?ret_data:
                         32'b0;
Way0_Bank2 Way0_Bank2(

  .clka(clk_g),
  .ena(Way0_Bank2_ena),
  .wea(Way0_Bank2_wea),
  .addra(Way0_Bank2_addra),
  .dina(Way0_Bank2_dina),
  .douta(Way0_Bank2_douta)
  );
//------------------------------------------//Way0_Bank3
wire Way0_Bank3_ena;
wire [3:0] Way0_Bank3_wea;
wire [7:0] Way0_Bank3_addra;
wire [31:0] Way0_Bank3_dina;
wire [31:0] Way0_Bank3_douta;
assign  Way0_Bank3_ena = uncache?1'b0
                        :(w_cur_state == `WRITE && way_write == 1'b0 && offset_write[3:2] == 2'b11)?1'b1:
                        (main_next_state == `LOOKUP && offset[3:2] == 2'b11)?1'b1:
                         (main_next_state == `REPLACE && miss_way == 1'b0)?1'b1:
                         (main_cur_state == `REFILL && miss_way == 1'b0 && miss_read_num == 2'b11)?1'b1:
                         1'b0;
assign Way0_Bank3_wea = (w_cur_state == `WRITE && way_write == 1'b0 && offset_write[3:2] == 2'b11)?wea_write:
                        (main_cur_state == `REFILL && miss_way == 1'b0 && miss_read_num == 2'b11)?miss_wea:
                        4'b0;
assign  Way0_Bank3_addra = (w_cur_state == `WRITE && way_write == 1'b0 && offset_write[3:2] == 2'b11)?index_write:
                           (main_next_state == `LOOKUP && offset[3:2] == 2'b11)?index:
                           (main_next_state == `REPLACE && miss_way == 1'b0)?index_replace_0:
                           (main_cur_state == `REFILL && miss_way == 1'b0 && miss_read_num == 2'b11)?index_refill_0:
                           8'b0;
assign Way0_Bank3_dina = (w_cur_state == `WRITE)?dina_write:
                         (main_cur_state == `REFILL && offset_request[3:2] == 2'b11 && op_request == 1'b1)?wdata_request:
                         (main_cur_state == `REFILL )?ret_data:
                         32'b0;
Way0_Bank3 Way0_Bank3(

  .clka(clk_g),
  .ena(Way0_Bank3_ena),
  .wea(Way0_Bank3_wea),
  .addra(Way0_Bank3_addra),
  .dina(Way0_Bank3_dina),
  .douta(Way0_Bank3_douta)
  );
//------------------------------------------//Way1_Bank0
wire Way1_Bank0_ena;
wire [3:0] Way1_Bank0_wea;
wire [7:0] Way1_Bank0_addra;
wire [31:0] Way1_Bank0_dina;
wire [31:0] Way1_Bank0_douta;
assign  Way1_Bank0_ena = uncache?1'b0
                        :(w_cur_state == `WRITE && way_write == 1'b1 && offset_write[3:2] == 2'b00)?1'b1:
                        (main_next_state == `LOOKUP && offset[3:2] == 2'b00)?1'b1:
                         (main_next_state == `REPLACE && miss_way == 1'b1)?1'b1:
                         (main_cur_state == `REFILL && miss_way == 1'b1 && miss_read_num == 2'b00)?1'b1:
                         1'b0;
assign Way1_Bank0_wea = (w_cur_state == `WRITE && way_write == 1'b1 && offset_write[3:2] == 2'b00)?wea_write:
                        (main_cur_state == `REFILL && miss_way == 1'b1 && miss_read_num == 2'b00) ?miss_wea:
                        4'b0;
assign  Way1_Bank0_addra = (w_cur_state == `WRITE && way_write == 1'b1 && offset_write[3:2] == 2'b00)?index_write:
                           (main_next_state == `LOOKUP && offset[3:2] == 2'b00)?index:
                           (main_next_state == `REPLACE && miss_way == 1'b1)?index_replace_1:
                           (main_cur_state == `REFILL && miss_way == 1'b1 && miss_read_num == 2'b00)?index_refill_1:
                           8'b0;
assign Way1_Bank0_dina = (w_cur_state == `WRITE)?dina_write:
                         (main_cur_state == `REFILL && offset_request[3:2] == 2'b00 && op_request == 1'b1)?wdata_request:
                         (main_cur_state == `REFILL )?ret_data:
                         32'b0;
Way1_Bank0 Way1_Bank0(

  .clka(clk_g),
  .ena(Way1_Bank0_ena),
  .wea(Way1_Bank0_wea),
  .addra(Way1_Bank0_addra),
  .dina(Way1_Bank0_dina),
  .douta(Way1_Bank0_douta)
  );
//------------------------------------------//Way1_Bank1
wire Way1_Bank1_ena;
wire [3:0] Way1_Bank1_wea;
wire [7:0] Way1_Bank1_addra;
wire [31:0] Way1_Bank1_dina;
wire [31:0] Way1_Bank1_douta;
assign  Way1_Bank1_ena = uncache?1'b0
                        :(w_cur_state == `WRITE && way_write == 1'b1 && offset_write[3:2] == 2'b01)?1'b1:
                        (main_next_state == `LOOKUP && offset[3:2] == 2'b01)?1'b1:
                         (main_next_state == `REPLACE && miss_way == 1'b1)?1'b1:
                         (main_cur_state == `REFILL && miss_way == 1'b1 && miss_read_num == 2'b01)?1'b1:
                         1'b0;
assign Way1_Bank1_wea = (w_cur_state == `WRITE && way_write == 1'b1 && offset_write[3:2] == 2'b01)?wea_write:
                        (main_cur_state == `REFILL && miss_way == 1'b1 && miss_read_num == 2'b01)?miss_wea:
                        4'b0;
assign  Way1_Bank1_addra = (w_cur_state == `WRITE && way_write == 1'b1 && offset_write[3:2] == 2'b01)?index_write:
                           (main_next_state == `LOOKUP && offset[3:2] == 2'b01)?index:
                           (main_next_state == `REPLACE && miss_way == 1'b1)?index_replace_1:
                           (main_cur_state == `REFILL && miss_way == 1'b1 && miss_read_num == 2'b01)?index_refill_1:
                           8'b0;
assign Way1_Bank1_dina = (w_cur_state == `WRITE)?dina_write:
                         (main_cur_state == `REFILL && offset_request[3:2] == 2'b01 && op_request == 1'b1 )?wdata_request:
                         (main_cur_state == `REFILL )?ret_data:
                         32'b0;
Way1_Bank1 Way1_Bank1(

  .clka(clk_g),
  .ena(Way1_Bank1_ena),
  .wea(Way1_Bank1_wea),
  .addra(Way1_Bank1_addra),
  .dina(Way1_Bank1_dina),
  .douta(Way1_Bank1_douta)
  );
//------------------------------------------//Way1_Bank2
wire Way1_Bank2_ena;
wire [3:0] Way1_Bank2_wea;
wire [7:0] Way1_Bank2_addra;
wire [31:0] Way1_Bank2_dina;
wire [31:0] Way1_Bank2_douta;
assign  Way1_Bank2_ena = uncache?1'b0
                        :(w_cur_state == `WRITE && way_write == 1'b1 && offset_write[3:2] == 2'b10)?1'b1:
                        (main_next_state == `LOOKUP && offset[3:2] == 2'b10)?1'b1:
                         (main_next_state == `REPLACE && miss_way == 1'b1)?1'b1:
                         (main_cur_state == `REFILL && miss_way == 1'b1 && miss_read_num == 2'b10)?1'b1:
                         1'b0;
assign Way1_Bank2_wea = (w_cur_state == `WRITE && way_write == 1'b1 && offset_write[3:2] == 2'b10)?wea_write:
                        (main_cur_state == `REFILL && miss_way == 1'b1 && miss_read_num == 2'b10)?miss_wea:
                        4'b0;
assign  Way1_Bank2_addra = (w_cur_state == `WRITE && way_write == 1'b1 && offset_write[3:2] == 2'b10)?index_write:
                           (main_next_state == `LOOKUP && offset[3:2] == 2'b10)?index:
                           (main_next_state == `REPLACE && miss_way == 1'b1)?index_replace_1:
                           (main_cur_state == `REFILL && miss_way == 1'b1 && miss_read_num == 2'b10)?index_refill_1:
                           8'b0;
assign Way1_Bank2_dina = (w_cur_state == `WRITE)?dina_write:
                         (main_cur_state == `REFILL && offset_request[3:2] == 2'b10 && op_request == 1'b1)?wdata_request:
                         (main_cur_state == `REFILL )?ret_data:
                         32'b0;
Way1_Bank2 Way1_Bank2(

  .clka(clk_g),
  .ena(Way1_Bank2_ena),
  .wea(Way1_Bank2_wea),
  .addra(Way1_Bank2_addra),
  .dina(Way1_Bank2_dina),
  .douta(Way1_Bank2_douta)
  );
//------------------------------------------//Way1_Bank3
wire  Way1_Bank3_ena;
wire [3:0] Way1_Bank3_wea;
wire [7:0] Way1_Bank3_addra;
wire [31:0] Way1_Bank3_dina;
wire [31:0] Way1_Bank3_douta;
assign  Way1_Bank3_ena = uncache?1'b0
                        :(w_cur_state == `WRITE && way_write == 1'b1 && offset_write[3:2] == 2'b11)?1'b1:
                        (main_next_state == `LOOKUP && offset[3:2] == 2'b11)?1'b1:
                         (main_next_state == `REPLACE && miss_way == 1'b1)?1'b1:
                         (main_cur_state == `REFILL && miss_way == 1'b1 && miss_read_num == 2'b11)?1'b1:
                         1'b0;
assign Way1_Bank3_wea = (w_cur_state == `WRITE && way_write == 1'b1 && offset_write[3:2] == 2'b11)?wea_write:
                        (main_cur_state == `REFILL && miss_way == 1'b1 && miss_read_num == 2'b11)?miss_wea:
                        4'b0;
assign  Way1_Bank3_addra = (w_cur_state == `WRITE && way_write == 1'b1 && offset_write[3:2] == 2'b11)?index_write:
                           (main_next_state == `LOOKUP && offset[3:2] == 2'b11)?index:
                           (main_next_state == `REPLACE && miss_way == 1'b1)?index_replace_1:
                           (main_cur_state == `REFILL && miss_way == 1'b1 && miss_read_num == 2'b11)?index_refill_1:
                           8'b0;
assign Way1_Bank3_dina = (w_cur_state == `WRITE)?dina_write:
                         (main_cur_state == `REFILL && offset_request[3:2] == 2'b11 && op_request == 1'b1)?wdata_request:
                         (main_cur_state == `REFILL )?ret_data:
                         32'b0;
Way1_Bank3 Way1_Bank3(

  .clka(clk_g),
  .ena(Way1_Bank3_ena),
  .wea(Way1_Bank3_wea),
  .addra(Way1_Bank3_addra),
  .dina(Way1_Bank3_dina),
  .douta(Way1_Bank3_douta)
  );
//-------------------------------------------//Dirty
reg [255:0] Way0_D;
wire [7:0] Way0_D_addra;
wire Way0_D_dina;
wire Way0_D_ena;
wire Way0_D_wea;
wire Way0_D_douta;

assign Way0_D_addra = (w_cur_state==`WRITE)?index_write:
                      (main_next_state==`REPLACE)?index_replace_0:
                      (main_next_state==`REFILL)?index_refill_0:
                      8'b0;
assign Way0_D_dina = (w_cur_state==`WRITE)?1'b1:
                     (main_next_state==`REFILL)?1'b0:
                     1'b0;
assign Way0_ena = (w_cur_state ==`WRITE && way_write == 1'b0)? 1'b1:
                  (main_next_state == `REPLACE && miss_way == 1'b0) ? 1'b1:
                  (main_next_state == `REFILL && miss_way == 1'b0) ? 1'b1: 1'b0;
//ע��˴�Dirty��дʹ��
assign Way0_wea = (w_cur_state == `WRITE && way_write == 1'b0)?1'b1:
                  (main_next_state == `REFILL && miss_way == 1'b0 && w_cur_state == `WRITE) ? 1'b1: 1'b0;



reg [255:0] Way1_D;
wire [7:0] Way1_D_addra;
wire Way1_D_dina;
wire Way1_D_ena;
wire Way1_D_wea;
wire Way1_D_douta;

assign Way1_D_addra = (w_cur_state==`WRITE)?index_write:
                      (main_next_state==`REPLACE)?index_replace_1:
                      (main_next_state==`REFILL)?index_refill_1:
                      8'b0;
assign Way1_D_dina = (w_cur_state==`WRITE)?1'b1:
                     (main_next_state==`REFILL)?1'b0:
                     1'b0;
assign Way1_ena = (w_cur_state ==`WRITE && way_write == 1'b1)? 1'b1:
                  (main_next_state == `REPLACE && miss_way == 1'b1) ? 1'b1:
                  (main_next_state == `REFILL && miss_way == 1'b1) ? 1'b1: 1'b0;
//ע��˴�Dirty��дʹ��
assign Way1_wea = (w_cur_state == `WRITE && way_write == 1'b1)?1'b1:
                  (main_next_state == `REFILL && miss_way == 1'b1 && w_cur_state == `WRITE) ? 1'b1: 1'b0;

always @(posedge clk_g) begin
    if(!resetn) begin
        Way0_D<=256'b0;
    end
    else if(Way0_D_ena == 1'b1) begin
        if(Way0_D_wea == 1'b1) begin
            Way0_D[Way0_D_addra] <= Way0_D_dina;
        end           
    end
end
assign Way0_D_douta = (Way0_D_ena == 1'b1)?Way0_D[Way0_D_addra]:1'b0;

always @(posedge clk_g) begin
    if(!resetn) begin
        Way1_D<=256'b0;
    end
    else if(Way1_D_ena == 1'b1) begin
        if(Way1_D_wea == 1'b1) begin
            Way1_D[Way1_D_addra] <= Way1_D_dina;
        end           
    end
end
assign Way1_D_douta = (Way1_D_ena == 1'b1)?Way1_D[Way1_D_addra]:1'b0;
//״̬��ת��


// always @(posedge clk_g) begin
//     if(!resetn) begin
//         main_cur_state <= `IDLE;
//         w_cur_state <= `IDLE;
//     end
//     else begin
//         main_cur_state <= main_next_state;
//         w_cur_state <= w_next_state;
//     end
// end

//����Ƿ���hit-write�ĳ�ͻ
wire hitwrite_conf;
assign hitwrite_conf = (if_hitwrite && valid == 1'b1 && op== 1'b0 && offset_request[3:2] == offset[3:2])?1'b1:
                     ((w_cur_state == `WRITE) && op==1'b0 && (offset[3:2] == offset_write[3:2]) )?1'b1:
                     1'b0;
wire if_hitwrite;
assign if_hitwrite = cache_hit && (op_request == 1'b1) && (main_cur_state == `LOOKUP);

always @(posedge clk_g) begin
    if(resetn == `False_v) begin
        main_cur_state <= `IDLE;
        w_cur_state <= `IDLE;
    end
    else begin
        case(main_cur_state)
            `IDLE: begin
                if(valid == `False_v || (valid == `True_v && hitwrite_conf)) begin
                    main_cur_state <= `IDLE;
                end
                else begin
                    main_cur_state <= `LOOKUP;
                end
            end
            `LOOKUP: begin
                if(cache_hit && (valid ==1'b0 || hitwrite_conf) && ~uncache) begin
                    main_cur_state <= `IDLE;
                end
                else if(cache_hit && (valid == 1'b1 && hitwrite_conf == 1'b0) && ~uncache)begin
                    //ע����һ��RAM�Ķ�ʹ���ź�
                    main_cur_state <= `LOOKUP;
                end
                else if(cache_hit == 1'b0 || uncache) begin
                    main_cur_state <= `MISS;
                end

            end
            `MISS: begin
                if(wr_rdy == 1'b0) begin
                    main_cur_state <= `MISS;
                end
                else if (wr_rdy == 1'b1) begin
                    if( (uncache && (op_request == 1'b1)) || (miss_way ? ((Way1_TagV_douta[0] == 1'b1)&&(Way1_D_douta == 1'b1)) :
                            ((Way0_TagV_douta[0] == 1'b1)&&(Way0_D_douta == 1'b1)))) begin
                        wr_req <= 1'b1;
                    end
                    main_cur_state <= `REPLACE;  //�����дʹ���߼�Ӧ�ÿ��Ի�Ϊnext���Ƶ������
                end
            end
            `REPLACE: begin
                wr_req <= 1'b0;
                if(rd_rdy == 1'b1 || (uncache && (op_request == 1'b1)))begin
                    main_cur_state <= `REFILL;
                end
                else if(rd_rdy == 1'b0 ) begin
                    main_cur_state <= `REPLACE;
                end
            end
            `REFILL: begin
                if(!(ret_valid == 1'b1 && ret_last == 1'b1) && !(uncache && (op_request == 1'b1))) begin
                    main_cur_state <= `REFILL;
                end
                else if((ret_valid == 1'b1 && ret_last == 1'b1)||(uncache && (op_request == 1'b1)))begin
                    main_cur_state <= `IDLE;
                end
            end
            default: begin
                main_cur_state <= `IDLE;
            end
        endcase

        case(w_cur_state)
            `IDLE: begin
                if((valid_write == 1'b0 && if_hitwrite == 1'b0)||!resetn) begin
                    w_cur_state <= `IDLE;
                end
                else if (valid_write == 1'b0 && if_hitwrite == 1'b1)begin
                    valid_write <= 1'b1;
                    w_cur_state <= `WRITE;
                end
            end
            `WRITE: begin
                if(valid_write == 1'b1 && if_hitwrite == 1'b1) begin
                    w_cur_state <= `WRITE;
                end
                else if(valid_write == 1'b1 && if_hitwrite == 1'b0)begin
                    valid_write <= 1'b0;
                    w_cur_state <= `IDLE;
                end

            end
            
            default: begin
                main_cur_state <= `IDLE;
            end
        endcase
    end
end

always @(*) begin
    if(resetn == `False_v) begin
        main_next_state = `IDLE;
    end
    else begin
        case(main_cur_state)
            `IDLE: begin
                if(valid == `False_v || (valid == `True_v && hitwrite_conf)) begin
                    main_next_state = `IDLE;
                end
                else begin
                    main_next_state = `LOOKUP;
                end
            end
            `LOOKUP: begin
                if(cache_hit && (valid ==1'b0 || hitwrite_conf)) begin
                    main_next_state = `IDLE;
                end
                else if(cache_hit && (valid == 1'b1 && hitwrite_conf == 1'b0))begin
                    //ע����һ��RAM�Ķ�ʹ���ź�
                    main_next_state = `LOOKUP;
                end
                else if(cache_hit == 1'b0) begin
                    main_next_state = `MISS;
                end

            end
            `MISS: begin
                if(wr_rdy == 1'b0 ) begin
                    main_next_state = `MISS;
                end
                else if (wr_rdy == 1'b1) begin
                    //wr_req <= 1'b1;
                    main_next_state = `REPLACE;
                end
            end
            `REPLACE: begin
                if(rd_rdy == 1'b0 ) begin
                    //rd_req <= 1'b1;
                    main_next_state = `REPLACE;
                end
                else if(rd_rdy == 1'b1)begin
                    main_next_state = `REFILL;
                end
            end
            `REFILL: begin
                if(ret_valid == 1'b1 && ret_last == 1'b0) begin
                    main_next_state = `REFILL;
                end
                else if(ret_valid == 1'b1 && ret_last == 1'b1)begin
                    main_next_state = `IDLE;
                end
            end
            default: begin
                main_next_state = `IDLE;
            end
        endcase

        case(w_cur_state)
            `IDLE: begin
                if(valid_write == 1'b0 && if_hitwrite == 1'b0) begin
                    w_next_state = `IDLE;
                end
                else if (valid_write == 1'b0 && if_hitwrite == 1'b1)begin
                    //valid_write <= 1'b1;
                    w_next_state = `WRITE;
                end
            end
            `WRITE: begin
                if(valid_write == 1'b1 && if_hitwrite == 1'b1) begin
                    w_next_state = `WRITE;
                end
                else if(valid_write == 1'b1 && if_hitwrite == 1'b0)begin
                    //valid_write <= 1'b0;
                    w_next_state = `IDLE;
                end

            end
            
            default: begin
                main_next_state = `IDLE;
            end
        endcase
    end
end

//ѡ��������� ����miss
assign rdata = cache_hit? (Way0_hit?(
                                      (offset_request[3:2]==2'b00)?Way0_Bank0_douta:
                                      (offset_request[3:2]==2'b01)?Way0_Bank1_douta:
                                      (offset_request[3:2]==2'b10)?Way0_Bank2_douta:
                                      Way0_Bank3_douta
                                      ):
                           (//Way1_hit
                                      (offset_request[3:2]==2'b00)?Way1_Bank0_douta:
                                      (offset_request[3:2]==2'b01)?Way1_Bank1_douta:
                                      (offset_request[3:2]==2'b10)?Way1_Bank2_douta:
                                      Way1_Bank3_douta
                                      )
                            ):
                            (miss_read_num[1:0] == offset_request[3:2] || uncache) ? ret_data:
                          
                32'habcd_abcd;
//if uncache, only write a word.
assign wr_data = uncache? {96'b0, wdata_request}
                :miss_way ? {Way1_Bank0_douta,Way1_Bank1_douta,Way1_Bank2_douta,Way1_Bank3_douta}:
                         {Way0_Bank0_douta,Way0_Bank1_douta,Way0_Bank2_douta,Way0_Bank3_douta};
//ע�������addrok��Ӱ��stall
// If uncache, stall all until IDLE stage.
assign addr_ok = uncache? main_cur_state == `IDLE
                :(main_cur_state == `IDLE)
                 || (main_cur_state == `LOOKUP && main_next_state == `LOOKUP && valid);
assign data_ok = uncache? ((main_cur_state == `REFILL && (op_request == 1'b1))||(main_cur_state == `REFILL && ret_valid == 1'b1 && ret_last == 1'b1 && op_request==1'b0))
                :(main_cur_state == `LOOKUP && cache_hit)
                 //|| (main_cur_state == `LOOKUP && op_request == 1'b1)
                 || (main_cur_state == `REFILL && ret_valid == 1'b1 && miss_read_num[1:0] == offset_request [3:2]);
assign rd_addr = miss_addr;
assign wr_addr = cache_hit ?{tag_write,index_write,4'b0}:
                            uncache? {tag_request,index_request,offset_request}
                                :{tag_request,index_request,4'b0};

assign rd_req = ((main_cur_state==`REPLACE && ~uncache)||(main_cur_state==`REPLACE && uncache && op_request == 1'b0)) ? 1'b1 :1'b0;

assign wr_wstrb = wstrb;
assign rd_type = uncache? 3'b010:3'b100;
assign wr_type = uncache? 3'b010:3'b100;

endmodule
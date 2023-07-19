`include "defines.v"
module cache_axi_interface
(
    input         clk,
    input         resetn, 

    //inst cache 
    input         inst_rd_req  ,
    input  [2 :0] inst_rd_type ,
    input  [31:0] inst_rd_addr ,
    output        inst_rd_rdy  ,
    output reg    inst_ret_valid,
    output [1 :0] inst_ret_last,
    output reg[31:0] inst_rdata   ,

    input         inst_wr_req  ,
    input  [2 :0] inst_wr_type ,
    input  [31:0] inst_wr_addr ,
    input  [3 :0] inst_wstrb   ,
    input  [127:0]inst_wdata   ,
    output reg    inst_wr_rdy  ,
    
    //data cache 
    input         data_rd_req  ,
    input  [2 :0] data_rd_type ,
    input  [31:0] data_rd_addr ,
    output        data_rd_rdy  ,
    output reg    data_ret_valid,
    output [1 :0] data_ret_last,
    output reg[31:0] data_rdata   ,

    input         data_wr_req  ,
    input  [2 :0] data_wr_type ,
    input  [31:0] data_wr_addr ,
    input  [3 :0] data_wstrb   ,
    input  [127:0]data_wdata   ,
    output reg    data_wr_rdy  ,

    //axi
    //ar
    output [3 :0]    arid         ,
    output reg[31:0] araddr       ,
    output reg[7 :0] arlen        ,
    output reg[2 :0] arsize       ,
    output reg[1 :0] arburst      ,
    output [1 :0]    arlock       ,
    output reg[3 :0] arcache      ,
    output [2 :0]    arprot       ,
    output reg       arvalid      ,
    input            arready      ,
    
    //r           
    input  [3 :0] rid          ,
    input  [31:0] rdata        ,
    input  [1 :0] rresp        ,
    input         rlast        ,
    input         rvalid       ,
    output reg    rready       ,
    
    //aw          
    output [3 :0]    awid         ,
    output reg[31:0] awaddr       ,
    output reg[7 :0] awlen        ,
    output reg[2 :0] awsize       ,
    output reg[1 :0] awburst      ,
    output [1 :0]    awlock       ,
    output reg[3 :0] awcache      ,
    output [2 :0]    awprot       ,
    output reg       awvalid      ,
    input            awready      ,
    
    //w          
    output [3 :0]     wid          ,
    output wire[31:0] wdata        ,
    output reg[3 :0]  wstrb        ,
    output wire       wlast        ,
    output wire       wvalid       ,
    input             wready       ,
    
    //b           
    input  [3 :0] bid          ,
    input  [1 :0] bresp        ,
    input         bvalid       ,
    output        bready    
);

reg rcurrent_state;
reg wcurrent_state;
reg rnext_state;
reg wnext_state;

reg [127:0] cache_line_r ;
reg [  1:0] wcount       ;

//state_update
always @(posedge clk) begin
    if(~resetn) begin
        rcurrent_state <= `AXI_IDLE;
        wcurrent_state <= `AXI_IDLE;
        rnext_state <= `AXI_IDLE;
        wnext_state <= `AXI_IDLE;
    end
    else begin
        rcurrent_state <= rnext_state;
        wcurrent_state <= wnext_state;
    end
end

//FSM
always @(posedge clk) begin
    if(~resetn) begin
        inst_rd_rdy     <= 1'b0 ;
        inst_ret_valid  <= 1'b0 ;
        inst_ret_last   <= 2'b0 ;
        inst_rdata      <=32'b0 ;
        inst_wr_rdy     <= 1'b1 ;//Set to 1 when buffer is empty

        data_rd_rdy     <= 1'b0 ;
        data_ret_valid  <= 1'b0 ;
        data_ret_last   <= 2'b0 ;
        data_rdata      <=32'b0 ;
        data_wr_rdy     <= 1'b1 ;

        arid    <= 4'b0 ;
        araddr  <=32'b0 ;
        arlen   <= 8'b0 ;
        arsize  <= 3'b0 ;
        arburst <= 2'b0 ;
        arlock  <= 2'b0 ;
        arcache <= 4'b0 ;
        arprot  <= 3'b0 ;
        arvalid <= 1'b0 ;

        rready  <= 1'b0 ;

        awid    <= 4'b0 ;
        awaddr  <=32'b0 ;
        awlen   <= 8'b0 ;
        awsize  <= 3'b0 ;
        awburst <= `BURST_INCR ;
        awlock  <= 2'b0 ;
        awcache <= 4'b0 ;
        awprot  <= 3'b0 ;
        awvalid <= 1'b0 ;

        wid     <= 4'b0 ;
        wdata   <=32'b0 ;
        wstrb   <= 4'b0 ;
        wlast   <= 1'b0 ;
        wvalid  <= 1'b0 ;

        bready  <= 1'b0 ;
    end
    else begin
        case(rcurrent_state)
        `AXI_IDLE: begin
            //next_state , data request first
            if(data_rd_req && 
                !(data_rd_addr == data_wr_addr && wcurrent_state != `AXI_IDLE)) begin
                rnext_state <= `DATA_WAIT_FOR_ARREADY;

                arvalid <= 1'b1;
                araddr <= data_rd_addr;
                arburst <= `BURST_INCR;
                //arsize & arlen
                case(data_rd_type)
                `TYPE_BYTE:begin
                    arsize <= 3'b000; //1 byte per beat
                    arlen <= 8'd0; //1 beat per burst
                end
                `TYPE_HALF_WORD:begin
                    arsize <= 3'b001; //2 bytes per beat
                    arlen <= 8'd0; //1 beat per burst
                end
                `TYPE_WORD:begin
                    arsize <= 3'b010; //4 bytes per beat
                    arlen <= 8'd0; //1 beat per burst
                end
                `TYPE_CACHE_LINE:begin
                    arsize <= 3'b010; //4 bytes per beat
                    arlen <= 8'd4; //4 beat per burst
                end
                default:begin
                    arsize <= 3'b010; //4 byte per beat
                    arlen <= 8'd0; //1 beat per burst
                end;
                endcase
            end
            else if(inst_rd_req && 
                !(inst_rd_addr == inst_wr_addr && wcurrent_state != `AXI_IDLE)) begin
                rnext_state <= `INST_WAIT_FOR_ARREADY;

                arvalid <= 1'b1;
                araddr <= inst_rd_addr;
                arburst <= `BURST_INCR;
                //arsize & arlen
                case(inst_rd_type)
                `TYPE_BYTE:begin
                    arsize <= 3'b000; //1 byte per beat
                    arlen <= 8'd0; //1 beat per burst
                end
                `TYPE_HALF_WORD:begin
                    arsize <= 3'b001; //2 bytes per beat
                    arlen <= 8'd0; //1 beat per burst
                end
                `TYPE_WORD:begin
                    arsize <= 3'b010; //4 bytes per beat
                    arlen <= 8'd0; //1 beat per burst
                end
                `TYPE_CACHE_LINE:begin
                    arsize <= 3'b010; //4 bytes per beat
                    arlen <= 8'd4; //4 beat per burst
                end
                default:begin
                    arsize <= 3'b010; //4 byte per beat
                    arlen <= 8'd0; //1 beat per burst
                end;
                endcase
            end
            else begin
                rnext_state <= `AXI_IDLE;

                //refresh output
                inst_rd_rdy     <= 1'b0 ;
                inst_ret_valid  <= 1'b0 ;
                inst_ret_last   <= 2'b0 ;
                inst_rdata      <=32'b0 ;

                data_rd_rdy     <= 1'b0 ;
                data_ret_valid  <= 1'b0 ;
                data_ret_last   <= 2'b0 ;
                data_rdata      <=32'b0 ;

                arid    <= 4'b0 ;
                araddr  <=32'b0 ;
                arlen   <= 8'b0 ;
                arsize  <= 3'b0 ;
                arburst <= 2'b0 ;
                arlock  <= 2'b0 ;
                arcache <= 4'b0 ;
                arprot  <= 3'b0 ;
                arvalid <= 1'b0 ;

                rready  <= 1'b0 ;
            end
        end

        `DATA_WAIT_FOR_ARREADY:begin
            if(arready == 1'b1)begin
                rnext_state <= `DATA_WAIT_FOR_READ_DONE;

                araddr <= 32'd0;
                arvalid <= 1'b0;
                rready <= 1'b1;
                arburst <= `BURST_INCR;
            end
            else begin
                rnext_state <= `DATA_WAIT_FOR_ARREADY;
            end
        end

        `INST_WAIT_FOR_ARREADY:begin
            if(arready == 1'b1)begin
                rnext_state <= `INST_WAIT_FOR_READ_DONE;

                araddr <= 32'd0;
                arvalid <= 1'b0;
                rready <= 1'b1;
                arburst <= `BURST_INCR;
            end
            else begin
                rnext_state <= `INST_WAIT_FOR_ARREADY;
            end
        end

        `DATA_WAIT_FOR_READ_DONE:begin
            data_ret_valid <= rvalid;
            if(rvalid == 1'b1 && rlast == 1'b1) begin
                rready <= 1'b0;
                data_rdata <= rdata;
            end
            else if(rvalid == 1'b1) begin
                data_rdata <= rdata;
            end
            else if(rvalid == 1'b0 && rready == 1'b0) begin //already read at least 1 bit
                rnext_state <= `AXI_IDLE;
            end
        end

        `DATA_WAIT_FOR_READ_DONE:begin
            data_ret_valid <= rvalid;
            if(rvalid == 1'b1 && rlast == 1'b1) begin
                rready <= 1'b0;
                data_rdata <= rdata;
            end
            else if(rvalid == 1'b1) begin
                data_rdata <= rdata;
            end
            else if(rvalid == 1'b0 && rready == 1'b0) begin //already read at least 1 bit
                rnext_state <= `AXI_IDLE;
            end
        end

        `INST_WAIT_FOR_READ_DONE:begin
            inst_ret_valid <= rvalid;
            if(rvalid == 1'b1 && rlast == 1'b1) begin
                rready <= 1'b0;
                inst_rdata <= rdata;
            end
            else if(rvalid == 1'b1) begin
                inst_rdata <= rdata;
            end
            else if(rvalid == 1'b0 && rready == 1'b0) begin //already read at least 1 bit
                rnext_state <= `AXI_IDLE;
            end
        end

        default:begin
            rnext_state <= `AXI_IDLE;
        end

        endcase

        case(wcurrent_state)
        `AXI_IDLE:begin
            if(data_wr_req) begin
                wnext_state <= `DATA_WAIT_FOR_AWREADY;
                cache_line_r <= data_wdata;
                data_wr_rdy <= 1'b0; //not ready for another line
                wstrb <= data_wstrb;

                awvalid <= 1'b1;
                awaddr <= data_rd_addr;
                awburst <= `BURST_INCR;

                //awsize & awlen
                case(data_wr_type)
                `TYPE_BYTE:begin
                    awsize <= 3'b000; //1 byte per beat
                    awlen <= 8'd0; //1 beat per burst
                end
                `TYPE_HALF_WORD:begin
                    awsize <= 3'b001; //2 bytes per beat
                    awlen <= 8'd0; //1 beat per burst
                end
                `TYPE_WORD:begin
                    awsize <= 3'b010; //4 bytes per beat
                    awlen <= 8'd0; //1 beat per burst
                end
                `TYPE_CACHE_LINE:begin
                    awsize <= 3'b010; //4 bytes per beat
                    awlen <= 8'd4; //4 beat per burst
                end
                default:begin
                    awsize <= 3'b010; //4 byte per beat
                    awlen <= 8'd0; //1 beat per burst
                end;
                endcase

            end
            else if(inst_wr_req) begin
                wnext_state <= `INST_WAIT_FOR_AWREADY;
                cache_line_r <= inst_wdata;
                wstrb <= inst_wstrb;

                awvalid <= 1'b1;
                awaddr <= inst_rd_addr;
                awburst <= `BURST_INCR;

                inst_wr_rdy <= 1'b0;

                //awsize & awlen
                case(inst_wr_type)
                `TYPE_BYTE:begin
                    awsize <= 3'b000; //1 byte per beat
                    awlen <= 8'd0; //1 beat per burst
                end
                `TYPE_HALF_WORD:begin
                    awsize <= 3'b001; //2 bytes per beat
                    awlen <= 8'd0; //1 beat per burst
                end
                `TYPE_WORD:begin
                    awsize <= 3'b010; //4 bytes per beat
                    awlen <= 8'd0; //1 beat per burst
                end
                `TYPE_CACHE_LINE:begin
                    awsize <= 3'b010; //4 bytes per beat
                    awlen <= 8'd4; //4 beat per burst
                end
                default:begin
                    awsize <= 3'b010; //4 byte per beat
                    awlen <= 8'd0; //1 beat per burst
                end;
                endcase
            end
            else begin
                inst_wr_rdy     <= 1'b1 ;
                data_wr_rdy     <= 1'b1 ;

                awid    <= 4'b0 ;
                awaddr  <=32'b0 ;
                awlen   <= 8'b0 ;
                awsize  <= 3'b0 ;
                awburst <= `BURST_INCR ;
                awlock  <= 2'b0 ;
                awcache <= 4'b0 ;
                awprot  <= 3'b0 ;
                awvalid <= 1'b0 ;

                wid     <= 4'b0 ;
                wdata   <=32'b0 ;
                wstrb   <= 4'b0 ;
                wlast   <= 1'b0 ;
                wvalid  <= 1'b0 ;

                bready  <= 1'b0 ;
            end
        end
            
        `DATA_WAIT_FOR_AWREADY:begin
            if(awready) begin
                wnext_state <= `DATA_WAIT_FOR_WREADY;
                awvalid <= 1'b0;
                wcount <= 1'b0;
            end
            else begin
                wnext_state <= `DATA_WAIT_FOR_AWREADY
            end
        end

        `INST_WAIT_FOR_AWREADY:begin
            if(awready) begin
                wnext_state <= `INST_WAIT_FOR_WREADY;
                awvalid <= 1'b0;
                wcount <= 1'b0;
            end
            else begin
                wnext_state <= `INST_WAIT_FOR_AWREADY;
            end
        end

        `DATA_WAIT_FOR_WREADY begin
            if(wready == 1'b1 && wlast == 1'b0) begin
                wcount <= wcount + 2'b01;
                wdata <= wcount == 2'b00? cache_line_r[31:0]:
                        wcount == 2'b01 ? cache_line_r[63:32]:
                        wcount == 2'b10 ? cache_line_r[95:64]:
                        wcount == 2'b11 ? cache_line_r[127:96];
                if(wcount == awlen) begin
                    wlast <= 1'b1;
                end
                else begin
                    wlast <= 1'b0;
                end
            end
            else if(wready == 1'b1 && wlast == 1'b1) begin
                wnext_state <= `DATA_WAIT_FOR_BVALID;
            end
            else begin
                wnext_state <= `DATA_WAIT_FOR_WREADY;
            end
        end

        `INST_WAIT_FOR_WREADY begin
            if(wready == 1'b1 && wlast == 1'b0) begin
                wcount <= wcount + 2'b01;
                wdata <= wcount == 2'b00? cache_line_r[31:0]:
                        wcount == 2'b01 ? cache_line_r[63:32]:
                        wcount == 2'b10 ? cache_line_r[95:64]:
                        wcount == 2'b11 ? cache_line_r[127:96];
                if(wcount == awlen) begin
                    wlast <= 1'b1;
                end
                else begin
                    wlast <= 1'b0;
                end
            end
            else if(wready == 1'b1 && wlast == 1'b1) begin
                wnext_state <= `INST_WAIT_FOR_BVALID;
            end
            else begin
                wnext_state <= `INST_WAIT_FOR_WREADY;
            end
        end

        `DATA_WAIT_FOR_BVALID: begin
            if(bvalid == 1'b1) begin
                wnext_state <= `AXI_IDLE;
                data_rd_rdy <= 1'b1;
            end
        end

        `INST_WAIT_FOR_BVALID: begin
            if(bvalid == 1'b1) begin
                wnext_state <= `AXI_IDLE;
                inst_wr_rdy <= 1'b1;
            end
        end

        default begin
            wnext_state <= `AXI_IDLE;
        end

        endcase
    end
end


endmodule


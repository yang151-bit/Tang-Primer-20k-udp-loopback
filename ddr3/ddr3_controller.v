`timescale 1ns/1ps
module ddr3_controller #(
        parameter DATA_WD = 16,
        parameter DQ_WIDTH = 16,
        parameter ADDR_WIDTH = 27,
        parameter MASK_WIDTH = 4,
        parameter MAX_ADDR = 518400,
        parameter BURST_LEN = 64)
        (
        input                           clk_ref,                //ddr3控制器时钟
        input                           rst_n,                  //系统复位 

        //PSRAM 控制器写端口                        
        input                           ddr3_wr_req,           // 写请求
        output                          ddr3_wr_ack,           // 写响应
        input                           ddr3_wr_load,          // 写复位
        input       [8*DQ_WIDTH-1:0]    ddr3_din,              // 写入ddr3中的数据

        //PSRAM 控制器读端口                        
        input                           ddr3_rd_req,           // 读请求
        input                           ddr3_rd_load,          // 读复位
        output                          ddr3_rd_ack,           // 读响应 
        output      [8*DQ_WIDTH-1:0]    ddr3_dout,             // 从ddr3中读出的数据 

        //PSRAM 芯片端口
        input                           init_done,
        input                           cmd_rdy,      
        input       [8*DQ_WIDTH-1:0]    ddr3_rd_data,
        input                           ddr3_rd_valid,
        input                           ddr3_wr_rdy,       
        output reg                      ddr3_wren,         
        output                          ddr3_wr_end,       
        output reg  [2:0]               cmd,
        output reg                      cmd_en,
        output reg  [ADDR_WIDTH-1:0]    addr,
        output      [8*DQ_WIDTH-1:0]    ddr3_wr_data
        );
//reg define
    reg [ADDR_WD-1:0] ddr3_wr_addr;
    reg [ADDR_WD-1:0] ddr3_rd_addr;
    reg [1:0]ddr3_wr_bank_sel;
    reg ddr3_bank_sw_flag;
    reg [1:0]ddr3_rd_bank_sel;

    reg   [4:0]                     curr_state;
    reg   [4:0]                     next_state;
    reg   [2:0]                     next_cmd;
    reg                             next_cmd_en;
    reg   [ADDR_WIDTH-1:0]          addr_next;
    reg   [5:0]                     WR_CNT;
    reg   [5:0]                     RD_CNT;
    reg   [RANGE_WD-1:0]            WR_CYC_CNT;
    reg   [RANGE_WD-1:0]            RD_CYC_CNT;
    reg                             WR_DONE;
    reg                             RD_DONE;
    reg                             DATA_W_END;
    reg                             DATA_R_END;
    reg                             rd_ack_flag;
    reg                             ddr3_rd_req_r1;
                                        
//wire define                            
    wire  [2:0]                     addr_sel;
    wire  [2:0]                     cmd_sel;
    wire                            ddr3_rd_req_ris;
//=====test state machine=====

    localparam  IDLE                = 5'b00001;
    localparam  START_WAITE         = 5'b00010;
    localparam  EXEC_WR_CMD         = 5'b00100;
    localparam  EXEC_RD_CMD         = 5'b01000;
    localparam  CYC_DONE_WAITE      = 5'b10000;

    localparam  Burst_Num           = BURST_LEN/8;  // burst 128 = 6'd16;
                                                    // burst 64  = 6'd8;
                                                    // burst 32  = 6'd4;
                                                    // burst 16  = 6'd2;
    localparam  ADDR_RANGE          = MAX_ADDR/BURST_LEN;
    localparam  RANGE_WD            = $clog2(ADDR_RANGE);
    localparam  ADDR_WD             = $clog2(MAX_ADDR);
    localparam  TCMD_2_1            = MAX_ADDR - ADDR_RANGE*BURST_LEN;
    localparam  TCMD_2 = MAX_ADDR%BURST_LEN ? TCMD_2_1 : BURST_LEN;

    localparam WR_CMD = 3'h0;
    localparam RD_CMD = 3'h1;
    
    always@(posedge clk_ref or negedge rst_n)
        if(!rst_n)
            curr_state <= IDLE;
        else 
            curr_state <= next_state;
    
    always@(*)begin
        next_state = curr_state;
        case(curr_state)
            IDLE:
                if(init_done) 
                    next_state = START_WAITE;
            
            START_WAITE: 
                if(ddr3_wr_req && cmd_rdy && ddr3_wr_rdy)
                    next_state = EXEC_WR_CMD;
                else if(rd_ack_flag && cmd_rdy && ~ddr3_rd_load)
                    next_state = EXEC_RD_CMD;

            EXEC_WR_CMD:
                if(WR_DONE && DATA_W_END)
                    next_state = CYC_DONE_WAITE;
                else if(DATA_W_END) 
                    next_state = START_WAITE;

            EXEC_RD_CMD:
                if(RD_DONE && DATA_R_END)
                    next_state = CYC_DONE_WAITE;
                else if(DATA_R_END) 
                    next_state = START_WAITE;
            CYC_DONE_WAITE:  
                next_state = IDLE; 

            default: next_state = IDLE;
        endcase
    end

//psram写地址产生模块
    always @(posedge clk_ref or negedge rst_n) begin
        if (!rst_n || ddr3_wr_load) begin
            ddr3_wr_addr <= 0;
        end
        else if(WR_DONE && DATA_W_END)
            ddr3_wr_addr <= 0;
        else if(DATA_W_END)
            ddr3_wr_addr <= ddr3_wr_addr + BURST_LEN;
        else
            ddr3_wr_addr <= ddr3_wr_addr;
    end

//psram读地址产生模块
    always @(posedge clk_ref or negedge rst_n) begin
        if(!rst_n  || ddr3_rd_load)
            ddr3_rd_addr <= 0;
        else if(RD_DONE && DATA_R_END)
            ddr3_rd_addr <= 0;
        else if(DATA_R_END)
            ddr3_rd_addr <= ddr3_rd_addr + BURST_LEN;
        else
            ddr3_rd_addr <= ddr3_rd_addr;
    end

//=====BURST WRITE =====

    always@(posedge clk_ref)
        if(curr_state == EXEC_WR_CMD && ddr3_wr_rdy)
            WR_CNT <= WR_CNT + 1'b1;
        else
            WR_CNT <= 0;
    
    always@(posedge clk_ref)
        if(next_state == EXEC_WR_CMD && ddr3_wr_rdy)
            ddr3_wren <= 1;
        else
            ddr3_wren <= 0;

    always@(posedge clk_ref or negedge rst_n)
        if(!rst_n || ddr3_wr_load)
            WR_CYC_CNT <= 'd0;
        else if(WR_DONE)
            WR_CYC_CNT <= 'd0;
        else if(DATA_W_END)
            WR_CYC_CNT <= WR_CYC_CNT + 1'b1;

    always@(posedge clk_ref or negedge rst_n)
      if(!rst_n  || ddr3_wr_load)
          WR_DONE <= 'd0;
      else if(WR_CYC_CNT == ADDR_RANGE-1)
          WR_DONE <= 1'b1;
      else if(curr_state == CYC_DONE_WAITE)
          WR_DONE <= 'd0;
      else
          WR_DONE <= WR_DONE;

    always@(posedge clk_ref)
        if(WR_CNT == Burst_Num-2)
            DATA_W_END <= 1'b1;
        else 
            DATA_W_END <= 1'b0;

    assign ddr3_wr_ack = next_state == EXEC_WR_CMD && ddr3_wr_rdy;

    assign ddr3_wr_end = ddr3_wren;

    // assign ddr3_wr_ack = curr_state == EXEC_WR_CMD && WR_CNT < Burst_Num;
    // assign ddr3_wr_data = 128'hff8fff8fff8fff8fff8fff8fff8fff8f;
    // assign ddr3_wr_data = 128'hffffffffffffffff0000000000000000;
    // assign ddr3_wr_data = {ddr3_din[15:0], ddr3_din[31:16], ddr3_din[47:32], ddr3_din[63:48],
    //                     ddr3_din[79:64], ddr3_din[95:80], ddr3_din[111:96], ddr3_din[127:112]};
    assign ddr3_wr_data = ddr3_din;
    
//=====BURST READ =====
    
    always@(posedge clk_ref)
        ddr3_rd_req_r1 <= ddr3_rd_req;

    assign ddr3_rd_req_ris = ~ddr3_rd_req_r1 & ddr3_rd_req;

    always@(posedge clk_ref or negedge rst_n)
        if(!rst_n)
            rd_ack_flag <= 0;
        else if(ddr3_rd_req_ris & ~rd_ack_flag)
            rd_ack_flag <= 1;
        else if(DATA_R_END)
            rd_ack_flag <= 0;

    always@(posedge clk_ref)
        if(curr_state == EXEC_RD_CMD)
            RD_CNT <= RD_CNT + 1'b1;
        else
            RD_CNT <= 0;

    always@(posedge clk_ref or negedge rst_n)
        if(!rst_n || ddr3_rd_load)
            RD_CYC_CNT <= 'd0;
        else if(RD_DONE)
            RD_CYC_CNT <= 'd0;
        else if(DATA_R_END)
            RD_CYC_CNT <= RD_CYC_CNT + 1'b1;

    always@(posedge clk_ref or negedge rst_n)
        if(!rst_n  || ddr3_rd_load)
            RD_DONE <= 'd0;
        else if(RD_CYC_CNT == ADDR_RANGE-1)
            RD_DONE <= 1'b1;
        else if(RD_DONE && DATA_R_END)
            RD_DONE <= 'd0;
        else
            RD_DONE <= RD_DONE;
         

    always@(posedge clk_ref)
        if(RD_CNT == Burst_Num-2)
            DATA_R_END <= 1'b1;
        else
            DATA_R_END <= 0;

    assign ddr3_rd_ack = ddr3_rd_valid;
    // assign ddr3_dout = 128'hffffffffffffffffffffffffffffffff;
    // assign ddr3_dout = {ddr3_rd_data[15:0], ddr3_rd_data[31:16], ddr3_rd_data[47:32], ddr3_rd_data[63:48],
    //                     ddr3_rd_data[79:64], ddr3_rd_data[95:80], ddr3_rd_data[111:96], ddr3_rd_data[127:112]};
    assign ddr3_dout = ddr3_rd_data;

//===== pSRAM CTRL =====
    assign cmd_sel = {curr_state == START_WAITE ,next_state == EXEC_WR_CMD, next_state == EXEC_RD_CMD};
    
    always@(posedge clk_ref or negedge rst_n)
        if(!rst_n)begin
            cmd         <= 0;
            cmd_en      <= 0;
        end
        else begin
            cmd         <= next_cmd;
            cmd_en      <= next_cmd_en;
        end

    always @(cmd_sel) begin
        case(cmd_sel)
            3'b110 : next_cmd = WR_CMD;
            default : next_cmd = RD_CMD;
        endcase
    end

    always @(cmd_sel) begin
        case(cmd_sel)
            3'b110 : next_cmd_en = 1'd1;
            3'b101 : next_cmd_en = 1'd1;
            default : next_cmd_en = 1'd0;
        endcase
    end

    always@(posedge clk_ref or negedge rst_n)
        if(!rst_n)
            ddr3_wr_bank_sel <= 0;
        else if(WR_DONE && DATA_W_END)
            ddr3_wr_bank_sel <= ddr3_wr_bank_sel + 1;
    
    always@(posedge clk_ref or negedge rst_n)
        if(!rst_n)
            ddr3_bank_sw_flag <= 0;
        else if(WR_DONE && DATA_W_END)
            ddr3_bank_sw_flag <= 1;
        else if(RD_DONE && DATA_R_END)
            ddr3_bank_sw_flag <= 0;

    always@(posedge clk_ref or negedge rst_n)
        if(!rst_n)
            ddr3_rd_bank_sel <= 2;
        else if(RD_DONE && DATA_R_END && ddr3_bank_sw_flag)
            ddr3_rd_bank_sel <= ddr3_rd_bank_sel + 1;

    // assign addr_sel = cmd_sel;

    // always @(addr_sel,ddr3_rd_addr,ddr3_wr_addr) begin
    //     case(addr_sel)
    //         2'b10 : addr_next = {{(ADDR_WIDTH-ADDR_WD-2){1'b0}}, ddr3_wr_bank_sel, ddr3_wr_addr};
    //         2'b01 : addr_next = {{(ADDR_WIDTH-ADDR_WD-2){1'b0}}, ddr3_rd_bank_sel, ddr3_rd_addr};
    //     endcase
    // end

    always@(posedge clk_ref or negedge rst_n)
    if(!rst_n)
        addr         <= {ADDR_WIDTH{1'd0}};
    else
        // addr         <= addr_next;
        case(cmd_sel)
            3'b110 : addr <= {{(ADDR_WIDTH-ADDR_WD-2){1'b0}}, ddr3_wr_bank_sel, ddr3_wr_addr};
            3'b101 : addr <= {{(ADDR_WIDTH-ADDR_WD-2){1'b0}}, ddr3_rd_bank_sel, ddr3_rd_addr};
        endcase

endmodule
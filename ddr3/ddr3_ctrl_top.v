`timescale 1ns/1ps
module ddr3_ctrl_top #(
            parameter DATA_WD = 16,
            parameter DQ_WIDTH = 16,
            parameter ADDR_WIDTH = 22,
            parameter MASK_WIDTH = 4,
            parameter MAX_ADDR = 518400,
            parameter BURST_LEN = 128)          
            (
            input                       ref_clk,                  //psram 控制器参考时钟
            input                       rst_n,                    //系统复位

            //用户写端口         
            input                       wr_clk,                   //写端口FIFO: 写时钟
            input                       wr_en,                    //写端口FIFO: 写使能
            input  [DATA_WD-1 : 0]      wr_data,                  //写端口FIFO: 写数据
            input                       wr_load,                  //写端口复位: 复位读地址,清空写FIFO

            //用户读端口
            input                       rd_clk,                   //读端口FIFO: 读时钟
            input                       rd_en,                    //读端口FIFO: 读使能
            input                       rd_load,                  //读端口复位: 复位读地址,清空读FIFO
            output [DATA_WD-1 : 0]      rd_data,                  //读端口FIFO: 读数据
            output                      rd_valid,        

            //ddr3芯片接口
            input                       ddr3_rd_valid,
            input  [8*DQ_WIDTH-1:0]     ddr3_rd_data,
            input                       ddr3_wr_rdy,
            input                       init_done,
            input                       cmd_rdy,
            output [2:0]                cmd,
            output                      cmd_en,
            output  [5:0]               ddr3_burst_number,
            output [ADDR_WIDTH-1:0]     addr,
            output [8*DQ_WIDTH-1:0]     ddr3_wr_data, 
            output                      ddr3_wren, 
            output                      ddr3_wr_end
            );

    localparam N = 2;

    reg  [N-1:0]  Pout_rd_valid   ;
    reg        rd_load_r1;                   //读端口复位寄存器      
    reg        rd_load_r2;
    reg        wr_load_r1;                   //写端口复位寄存器      
    reg        wr_load_r2;                   

    wire [8*DQ_WIDTH-1:0] ddr3_din;
    wire [8*DQ_WIDTH-1:0] ddr3_dout;
    wire ddr3_wr_req;
    wire ddr3_rd_req;
    wire ddr3_rd_ack;
    wire ddr3_wr_ack;
    wire rd_load_flag;                 //rd_load      上升沿标志位  
    wire wr_load_flag;

    assign rd_load_flag    = ~rd_load_r2 & rd_load_r1;
    assign wr_load_flag    = ~wr_load_r2 & wr_load_r1;

    always@(posedge rd_clk or negedge rst_n)
    begin
        if(!rst_n)             
            Pout_rd_valid  <= {N{1'b0}};
        else
            Pout_rd_valid  <= {Pout_rd_valid[N-2:0],rd_en};
    end
    assign rd_valid = Pout_rd_valid[N-1];

    //同步读端口复位信号，同时用于捕获rd_load上升沿
    always @(posedge ref_clk or negedge rst_n) begin
        if(!rst_n) begin
            rd_load_r1 <= 1'b0;
            rd_load_r2 <= 1'b0;
        end
        else begin
            rd_load_r1 <= rd_load;
            rd_load_r2 <= rd_load_r1;
        end
    end

    //同步写端口复位信号，同时用于捕获wr_load上升沿
    always @(posedge ref_clk or negedge rst_n) begin
        if(!rst_n) begin
            wr_load_r1 <= 1'b0;
            wr_load_r2 <= 1'b0;
        end
        else begin
            wr_load_r1 <= wr_load;
            wr_load_r2 <= wr_load_r1;
        end
    end

//PSRAM 读写端口FIFO控制模块
    ddr3_fifo_ctrl #(
        .DATA_WD                (DATA_WD       ),
        .DQ_WIDTH               (DQ_WIDTH      ))
    u_ddr3_fifo_ctrl(
        .clk_ref            (ref_clk),          //PSRAM控制器时钟
        .rst_n              (rst_n),            //系统复位
    
        //用户写端口
        .wclk               (wr_clk),           //写端口FIFO: 写时钟
        .wrf_wr_en          (wr_en),            //写端口FIFO: 写使能
        .wr_load            (wr_load_flag),
        .wrf_din            (wr_data),          //写端口FIFO: 写数据
        
        //用户读端口                                                 
        .rclk               (rd_clk),           //读端口FIFO: 读时钟
        .rdf_rd_en          (rd_en),            //读端口FIFO: 读使能
        .rd_load            (rd_load_flag),
        .rdf_dout           (rd_data),          //读端口FIFO: 读数据
    
        //PSRAM 芯片端口
        .ddr3_init_done    (init_done),        //psram 初始化完成标志
        
        //PSRAM 控制器写端口
        .ddr3_wr_req       (ddr3_wr_req),     //psram 写请求
        .ddr3_wr_ack       (ddr3_wr_ack),     //psram 写响应
        .ddr3_din          (ddr3_din),        //写入psram中的数据
        
        //PSRAM 控制器读端口
        .ddr3_rd_req       (ddr3_rd_req),     //psram 读请求
        .ddr3_rd_ack       (ddr3_rd_ack),     //psram 读响应
        .ddr3_dout         (ddr3_dout)        //从psram中读出的数据
        );

//PSRAM控制器
    ddr3_controller #(
        .DATA_WD                (DATA_WD       ),
        .DQ_WIDTH               (DQ_WIDTH       ),       
        .ADDR_WIDTH             (ADDR_WIDTH     ),
        .MAX_ADDR               (MAX_ADDR       ),
        .BURST_LEN              (BURST_LEN      ))
    u_ddr3_controller(
        .clk_ref            (ref_clk),          //psram 控制器时钟
        .rst_n              (rst_n),            //系统复位

        //ddr3 控制器写端口  
        .ddr3_wr_req       (ddr3_wr_req),     //psram 写请求
        .ddr3_wr_ack       (ddr3_wr_ack),     //psram 写响应
        .ddr3_wr_load      (wr_load_flag),
        .ddr3_din          (ddr3_din),        //写入psram中的数据

        //ddr3 控制器读端口
        .ddr3_rd_req       (ddr3_rd_req),     //psram 读请求
        .ddr3_rd_load      (rd_load_flag),
        .ddr3_rd_ack       (ddr3_rd_ack),     //psram 读响应
        .ddr3_dout         (ddr3_dout),       //从psram中读出的数据

        //ddr3 芯片接口
        .ddr3_rd_data      (ddr3_rd_data),
        .ddr3_rd_valid     (ddr3_rd_valid),
        .ddr3_burst_number (ddr3_burst_number),
        .ddr3_wr_rdy       (ddr3_wr_rdy    ),
        .ddr3_wren         (ddr3_wren      ),
        .ddr3_wr_end       (ddr3_wr_end  ),
        .init_done         (init_done),    
        .cmd               (cmd),          
        .cmd_en            (cmd_en), 
        .cmd_rdy           (cmd_rdy     ),        
        .addr              (addr),            
        .ddr3_wr_data      (ddr3_wr_data)
        );

endmodule





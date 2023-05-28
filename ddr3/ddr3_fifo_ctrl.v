`timescale 1ns/1ps
module ddr3_fifo_ctrl #(
        parameter DATA_WD = 16,
        parameter DQ_WIDTH = 16)
        (
        input                           clk_ref,                //PSRAM控制器时钟
        input                           rst_n,                  //系统复位 

        //用户写端口                                
        input                           wclk,                   //写端口FIFO: 写时钟 
        input                           wrf_wr_en,              //写端口FIFO: 写使能
        input                           wr_load,                //写端口复位: 清空写FIFO 
        input       [DATA_WD-1:0]       wrf_din,                //写端口FIFO: 写数据

        //用户读端口                                
        input                           rclk,                   //读端口FIFO: 读时钟
        input                           rdf_rd_en,              //读端口FIFO: 读使能
        input                           rd_load,                //读端口复位: 清空读FIFO 
        output      [DATA_WD-1:0]       rdf_dout,               //读端口FIFO: 读数据

        //PSRAM 芯片端口
        input                           ddr3_init_done,        //PSRAM 初始化完成标志

        //PSRAM 控制器写端口                        
        output                          ddr3_wr_req,           //psram 写请求
        input                           ddr3_wr_ack,           //psram 写响应
        output      [8*DQ_WIDTH-1:0]    ddr3_din,              //写入PSRAM中的数据 

        //PSRAM 控制器读端口                        
        output                          ddr3_rd_req,           //psram 读请求
        input                           ddr3_rd_ack,           //psram 读响应 
        input       [8*DQ_WIDTH-1:0]    ddr3_dout              //从PSRAM中读出的数据 
        );

//reg define
                                         
//wire define                            
    wire wfifo_almostE;
    wire rfifo_almostF;
    wire [4:0] wr_fifo_Rnum;

//*****************************************************
//**                    main code
//***************************************************** 

    assign ddr3_wr_req = ~wfifo_almostE;  
    assign ddr3_rd_req = ~rfifo_almostF;



//例化写端口FIFO    
	wrfifo u_wrfifo(
		.Data           (wrf_din),          //input [15:0] Data
		.Reset          (~rst_n || wr_load),           //input Reset
		.WrClk          (wclk),             //input WrClk
		.RdClk          (clk_ref),          //input RdClk
		.WrEn           (wrf_wr_en),        //input WrEn
		.RdEn           (ddr3_wr_ack),     //input RdEn
		.Almost_Empty   (wfifo_almostE),    //output Almost_Empty
		.Q              (ddr3_din)        //output [127:0] Q
	);

//例化读端口FIFO
	rdfifo u_rdfifo(
		.Data           (ddr3_dout),       //input [127:0] Data
		.Reset          (~rst_n || rd_load),           //input Reset
		.WrClk          (clk_ref),          //input WrClk
		.RdClk          (rclk),             //input RdClk
		.WrEn           (ddr3_rd_ack),     //input WrEn
		.RdEn           (rdf_rd_en),        //input RdEn
		.Almost_Full    (rfifo_almostF),    //output Almost_Full
		.Q              (rdf_dout)         //output [15:0] Q
	);
endmodule 
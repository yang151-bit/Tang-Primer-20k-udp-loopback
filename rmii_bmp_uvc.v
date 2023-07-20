//----------------------------------------------------------------------------------------
// File name:           rmii_bmp_uvc
// Last modified Date:  2022/12/27 10:39:20
// Last Version:        V1.0
// Descriptions:        rmii读图片UVC显示
//                      
//----------------------------------------------------------------------------------------
// Created by:          
// Created date:        2023/5/19 10:39:20
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

//According to IP parameters to choose
`define	    WR_VIDEO_WIDTH_16 //16/24/32
`define	DEF_WR_VIDEO_WIDTH 16 //16/24/32

`define	    RD_VIDEO_WIDTH_16 //16/24/32
`define	DEF_RD_VIDEO_WIDTH 16 //16/24/32



module rmii_bmp_uvc(    
    input                 sys_clk,      //系统时钟
    input                 sys_rst_n,    //系统复位，低电平有效
    //
    input                 key,
    //LED
    output                 led,            //LED灯                       
    //rtl8201 接口
	input						rmii_clk,
	input						rmii_rxdv,
	input	[1:0]				rmii_rxdata,
	output						rmii_txen,
	output	[1:0]				rmii_txdata,
	output						rmii_rst,
	output  					mdc,
	inout   					mdio,
    //ddr3 接口
    output [14-1:0]             ddr_addr,       //ROW_WIDTH=14
    output [3-1:0]              ddr_bank,       //BANK_WIDTH=3
    output                      ddr_cs,
    output                      ddr_ras,
    output                      ddr_cas,
    output                      ddr_we,
    output                      ddr_ck,
    output                      ddr_ck_n,
    output                      ddr_cke,
    output                      ddr_odt,
    output                      ddr_reset_n,
    output [2-1:0]              ddr_dm,         //DM_WIDTH=2
    inout [16-1:0]              ddr_dq,         //DQ_WIDTH=16
    inout [2-1:0]               ddr_dqs,        //DQS_WIDTH=2
    inout [2-1:0]               ddr_dqs_n,      //DQS_WIDTH=2
    //ulpi interface
    output                      ulpi_rst,
    input                       ulpi_clk,
    input                       ulpi_dir,
    input                       ulpi_nxt,
    output                      ulpi_stp,
    inout  [7:0]                ulpi_data
    );

//parameter define 
//PSDRAM读写最大地址 480 * 360 = 172800
    localparam  HPRAM_MAX_ADDR = 172800;
//USB分包数 360 + 1 = 361
    localparam  USB_PKT_NUM = 361;  
//DRAM parameters
    localparam  DQ_WIDTH = 16;
    localparam  DATA_WD = 16;
    localparam  ADDR_WIDTH = 27;
    localparam  BURST_LEN = 64;

//read mode define
    localparam  RD_PIC0         = 2'b00;
    localparam  RD_PIC1         = 2'b01;
    localparam  RD_IDLE         = 2'b11;
    localparam  RD_NONE         = 2'b10;

//reg define
    reg  [1:0]   read_mode;
    reg  [1:0]   read_mode_next;
    reg  [2:0]   led_;
    reg          key_value_r; 

    reg [7:0]   off0_syn_data_;

//wire define  
    wire         memory_clk     ;  //
    wire         locked         ;  //时钟锁定信号 
    wire         rst_n          ;  //全局复位
    wire         hdmi_rst_n     ; 
    wire         sys_init_done  ;  //系统初始化完成

    wire         key_value; 

    //frame buffer in
    wire                  vfb_de_in      ;
    wire [DATA_WD-1:0]    vfb_data_in    ;
    wire [DATA_WD-1:0]    vfb_data_out   ;
    wire                  vfb_rd_valid   ;

    //syn_code
    wire                        syn_off0_re;  // ofifo read enable signal
    wire                        syn_off0_vs;
    wire                        syn_off0_hs;
                        
    wire                        off0_syn_de  ;
    reg [7:0]   off0_syn_data;
    

    wire                    memory_clk_div4;
    wire                    ddr3_init_done;

    //yuv data
    wire [23:0] yuv_data   ;
//*****************************************************
//**                    main code
//*****************************************************

//待时钟锁定后产生复位结束信号
    assign  rst_n = sys_rst_n & locked;

//系统初始化完成：PSDRAM初始化完成
    assign  sys_init_done = ddr3_init_done;

//按键切换显示模式
    key_debounce u_key_debounce(
         .sys_clk (sys_clk),
         .sys_rst_n (sys_rst_n),

         .key (key),
         .key_flag (key_flag),
         .key_value (key_value)
         );

    always @(*) begin
        case(read_mode)
            RD_PIC0 : read_mode_next = RD_PIC1;
            RD_PIC1 : read_mode_next = RD_IDLE;
            RD_IDLE : read_mode_next = RD_NONE;
            RD_NONE : read_mode_next = RD_PIC0;
            default : read_mode_next = RD_PIC0;
        endcase
    end

    always@(posedge sys_clk or negedge rst_n)
        if(!rst_n)
            read_mode <= RD_PIC0;
        else if(~key_value && key_value_r)
            read_mode <= read_mode_next;
        else
            read_mode <= read_mode;

    always@(posedge sys_clk or negedge rst_n)
        if(!rst_n)
            key_value_r <= 0;
        else
            key_value_r <= key_value;

    always @(read_mode) begin
        case(read_mode)
            RD_PIC0 : led_ = ~3'b001;
            RD_PIC1 : led_ = ~3'b010;
            RD_IDLE : led_ = ~3'b100;
            default : led_ = ~3'b000;
        endcase
    end

    assign led = ddr3_init_done;

//时钟IP核
  Gowin_rPLL pll(
      .clkout(memory_clk), //output clkout
      .lock(locked), //output locked
      .clkoutd(rmii_mdc_2x), //output clkoutd
      .clkin(sys_clk) //input clkin
    );


    CLKDIV u_clkdiv_rmii_mdc(
        .RESETN     (rst_n      ),
        .HCLKIN     (rmii_mdc_2x),      //clk  x2
        .CLKOUT     (rmii_mdc   ),      //clk  x1
        .CALIB      (1'b0       )
    );
    defparam u_clkdiv_rmii_mdc.DIV_MODE="2";
    defparam u_clkdiv_rmii_mdc.GSREN="false";


//读取UDP图片
    eth_rmii_read_photo 
    #(
        .PKT_SIZE           (480),
        .USB_PKT_NUM        (USB_PKT_NUM))
    u_eth_rmii_read_photo(
        .rmii_mdc      (rmii_mdc               ),
        .mdc_locked    (locked                 ),
    	.rst_n         (rst_n & sys_init_done  ),
        .ddr3_wr_clk   (ddr3_wr_clk            ),
        .ddr3_wr_en    (vfb_de_in              ),
        .ddr3_wr_data  (vfb_data_in            ),
        .ddr3_vs       (vfb_vs                 ),
        .rmii_clk      (rmii_clk               ),
        .rmii_rxdv     (rmii_rxdv              ),
        .rmii_rxdata   (rmii_rxdata            ),
        .rmii_txen     (rmii_txen              ),
        .rmii_txdata   (rmii_txdata            ),
        .rmii_rst      (rmii_rst               ),
        .mdclk         (mdc                    ),
	    .mdio          (mdio             	   )
    );
       

//DDR3

  wire [27-1:0]             ddr3_addr;        //ADDR_WIDTH=27

  wire                      ddr3_cmd_en;
  wire [2:0]                ddr3_cmd;
  wire                      ddr3_cmd_rdy;

  wire                      ddr3_wren;
  wire                      ddr3_data_end;
  wire [128-1:0]            ddr3_wdata;    //APP_DATA_WIDTH=128
  wire                      ddr3_wr_rdy;

  wire                      ddr3_rd_valid;
  wire                      ddr3_rdata_end;
  wire [128-1:0]            ddr3_rdata;     //APP_DATA_WIDTH=128

  wire [5:0]                ddr3_burst_number;

  //ddr3_memory_top u_ddr3 (
  DDR3_Memory_Interface_Top u_ddr3 (
      .clk                  (sys_clk),
      .memory_clk           (memory_clk),
      .pll_lock             (locked),
      .rst_n                (rst_n),   //rst_n
      .app_burst_number     (ddr3_burst_number),
      .cmd_ready            (ddr3_cmd_rdy),
      .cmd                  (ddr3_cmd),
      .cmd_en               (ddr3_cmd_en),
      .addr                 ({1'b0,ddr3_addr}),//IDK why Gowin Set the addr width to 28. But it should be 27
      .wr_data_rdy          (ddr3_wr_rdy),
      .wr_data              (ddr3_wdata),
      .wr_data_en           (ddr3_wren),
      .wr_data_end          (ddr3_data_end),
      .wr_data_mask         (16'h0000),
      .rd_data              (ddr3_rdata),
      .rd_data_valid        (ddr3_rd_valid),
      .rd_data_end          (ddr3_rdata_end),
      .sr_req               (1'b0),
      .ref_req              (1'b0),
      .sr_ack               (),
      .ref_ack              (),
      .init_calib_complete  (ddr3_init_done),
      .clk_out              (memory_clk_div4),
      .burst                (1'b1),

      // mem interface
      .ddr_rst         (),
      .O_ddr_addr      (ddr_addr),
      .O_ddr_ba        (ddr_bank),
      .O_ddr_cs_n      (ddr_cs1),
      .O_ddr_ras_n     (ddr_ras),
      .O_ddr_cas_n     (ddr_cas),
      .O_ddr_we_n      (ddr_we),
      .O_ddr_clk       (ddr_ck),
      .O_ddr_clk_n     (ddr_ck_n),
      .O_ddr_cke       (ddr_cke),
      .O_ddr_odt       (ddr_odt),
      .O_ddr_reset_n   (ddr_reset_n),
      .O_ddr_dqm       (ddr_dm),
      .IO_ddr_dq       (ddr_dq),
      .IO_ddr_dqs      (ddr_dqs),
      .IO_ddr_dqs_n    (ddr_dqs_n)
    );

    assign ddr_cs = 1'b0;
    
    ddr3_ctrl_top #(
        .DATA_WD                (DATA_WD            ),
        .DQ_WIDTH               (DQ_WIDTH           ),       
        .ADDR_WIDTH             (ADDR_WIDTH         ),
        .MAX_ADDR               (HPRAM_MAX_ADDR     ),
        .BURST_LEN              (BURST_LEN          ))
    u_ddr3_ctrl_top(
        .ref_clk                (memory_clk_div4),
        .rst_n                  (rst_n),
        .wr_clk                 (ddr3_wr_clk),
        .wr_en                  (vfb_de_in),
        .wr_load                (vfb_vs), 
        .wr_data                (vfb_data_in),
        .rd_clk                 (~ulpi_clk),
        .rd_en                  (syn_off0_re),  
        .rd_load                (~syn_off0_vs),
        .rd_data                (vfb_data_out),
        .rd_valid               (vfb_rd_valid),
        
        // mem interface
        .init_done              (ddr3_init_done ),
        .cmd                    (ddr3_cmd       ),
        .cmd_en                 (ddr3_cmd_en    ),
        .cmd_rdy                (ddr3_cmd_rdy   ),
        .addr                   (ddr3_addr      ),
        .ddr3_wr_data           (ddr3_wdata     ),
        .ddr3_wr_rdy            (ddr3_wr_rdy    ),
        .ddr3_wren              (ddr3_wren      ),
        .ddr3_wr_end            (ddr3_data_end  ),
        .ddr3_burst_number      (ddr3_burst_number),
        .ddr3_rd_data           (ddr3_rdata     ),
        .ddr3_rd_valid          (ddr3_rd_valid  )
    );

    wire  [1:0]   read_mode_ulpi_clk;

    fifo #(.WIDTH(2),
           .DEPTH(2)) 
    shift2_read_mode_ulpi_clk(
        .clk(ulpi_clk),
        .inp(read_mode),
        .outp(read_mode_ulpi_clk));

    always @(read_mode_ulpi_clk, vfb_data_out) begin
        case(read_mode_ulpi_clk)
            RD_PIC0 : off0_syn_data_ = vfb_data_out[0+:8];
            RD_PIC1 : off0_syn_data_ = vfb_data_out[8+:8];
            default : off0_syn_data_ = 'd0;
        endcase
    end
    
    always@(posedge ulpi_clk or negedge rst_n)
        if(!rst_n)
            off0_syn_data <= 'd0;
        else
            off0_syn_data <= off0_syn_data_;

//==============================================================================
//usb TX(uvc) 
    assign yuv_data = {off0_syn_data, 8'h80, 8'h80};//{y,u,v}

    uvc_top u_uvc_top(
    .RESET_N        (sys_rst_n ),
    .ulpi_rst       (ulpi_rst  ),
    .ulpi_clk       (ulpi_clk  ),
    .ulpi_dir       (ulpi_dir  ),
    .ulpi_nxt       (ulpi_nxt  ),
    .ulpi_stp       (ulpi_stp  ),
    .ulpi_data      (ulpi_data ),

    .vfb_data_in    (yuv_data   ),
    .vfb_re         (syn_off0_re),
    .vfb_vs         (syn_off0_vs)
    );



endmodule

//----------------------------------------------------------------------------------------
// File name:           rmii_bmp_hdmi
// Last modified Date:  2022/12/27 10:39:20
// Last Version:        V1.0
// Descriptions:        rmii读图片HDMI显示
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



module rmii_bmp_hdmi(    
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
    //HDMI接口
    output                O_tmds_clk_p,
    output                O_tmds_clk_n,
    output     [2:0]      O_tmds_data_p,//{r,g,b}
    output     [2:0]      O_tmds_data_n  
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
    wire         memory_clk     ;  //180Mhz时钟,SDRAM操作时钟
    wire         hdmi_clk       ;  //40Mhz
    wire         hdmi_clk_5     ;  //200Mhz
    wire         locked         ;  //时钟锁定信号 
    wire         locked_hdmi    ;
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

    //rgb data
    wire        rgb_vs     ;
    wire        rgb_hs     ;
    wire        rgb_de     ;
    wire [23:0] rgb_data   ;
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
        .rd_clk                 (hdmi_clk), 
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

    wire  [1:0]   read_mode_hdmi_clk;

    fifo #(.WIDTH(2),
           .DEPTH(2)) 
    shift2_read_mode_hdmi_clk(
        .clk(hdmi_clk),
        .inp(read_mode),
        .outp(read_mode_hdmi_clk));

    always @(read_mode_hdmi_clk, vfb_data_out) begin
        case(read_mode_hdmi_clk)
            RD_PIC0 : off0_syn_data_ = vfb_data_out[0+:8];
            RD_PIC1 : off0_syn_data_ = vfb_data_out[8+:8];
            default : off0_syn_data_ = 'd0;
        endcase
    end
    
    always@(posedge hdmi_clk or negedge rst_n)
        if(!rst_n)
            off0_syn_data <= 'd0;
        else
            off0_syn_data <= off0_syn_data_;

//================================================
    wire out_de;
    syn_gen syn_gen_inst
    (                                   
        .I_pxl_clk   (hdmi_clk        ),//23.85MHz  //25.2MHz    //40MHz      //65MHz      //74.25MHz    //148.5MHz
        .I_rst_n     (hdmi_rst_n      ),//640x480   //640x480    //800x600    //1024x768   //1280x720    //1920x1080    
        .I_h_total   (16'd800         ),// 16'd800  // 16'd800   // 16'd1056  // 16'd1344  // 16'd1650   // 16'd2200  
        .I_h_sync    (16'd96          ),// 16'd64   // 16'd96    // 16'd128   // 16'd136   // 16'd40     // 16'd44   
        .I_h_bporch  (16'd48          ),// 16'd80   // 16'd48    // 16'd88    // 16'd160   // 16'd220    // 16'd148   
        .I_h_res     (16'd640         ),// 16'd640  // 16'd640   // 16'd800   // 16'd1024  // 16'd1280   // 16'd1920  
        .I_v_total   (16'd525         ),// 16'd497  // 16'd525   // 16'd628   // 16'd806   // 16'd750    // 16'd1125   
        .I_v_sync    (16'd2           ),// 16'd3    // 16'd2     // 16'd4     // 16'd6     // 16'd5      // 16'd5      
        .I_v_bporch  (16'd33          ),// 16'd13   // 16'd33    // 16'd23    // 16'd29    // 16'd20     // 16'd36      
        .I_v_res     (16'd480         ),// 16'd480  // 16'd480   // 16'd600   // 16'd768   // 16'd720    // 16'd1080   
        .I_rd_hres   (16'd480         ),
        .I_rd_vres   (16'd360         ),
        .I_hs_pol    (1'b1            ),//HS polarity , 0:负极性，1：正极性
        .I_vs_pol    (1'b1            ),//VS polarity , 0:负极性，1：正极性
        .O_rden      (syn_off0_re     ),
        .O_de        (out_de          ),   
        .O_hs        (syn_off0_hs     ),
        .O_vs        (syn_off0_vs     )
    );

    localparam N = 3; //delay N clocks
    localparam M = 1;

    reg  [N-1:0]  Pout_hs_dn   ;
    reg  [N-1:0]  Pout_vs_dn   ;
    reg  [N-1:0]  Pout_de_dn   ;
    reg  [M-1:0]  vfb_rd_valid_r;

    always@(posedge hdmi_clk or negedge hdmi_rst_n)
    begin
        if(!hdmi_rst_n)
            begin                          
                Pout_hs_dn  <= {N{1'b1}};
                Pout_vs_dn  <= {N{1'b1}}; 
                Pout_de_dn  <= {N{1'b0}};
                vfb_rd_valid_r <= {M{1'b0}}; 
            end
        else 
            begin                          
                Pout_hs_dn  <= {Pout_hs_dn[N-2:0],syn_off0_hs};
                Pout_vs_dn  <= {Pout_vs_dn[N-2:0],syn_off0_vs}; 
                Pout_de_dn  <= {Pout_de_dn[N-2:0],out_de};
                vfb_rd_valid_r <= {vfb_rd_valid_r[M-2:0],vfb_rd_valid};  
            end
    end

    assign off0_syn_de = vfb_rd_valid_r[M-1];
//==============================================================================
//TMDS TX(HDMI) 
    assign rgb_data    = off0_syn_de ? {off0_syn_data, off0_syn_data, off0_syn_data} : 24'h0000ff;//{r,g,b}
    assign rgb_vs      = Pout_vs_dn[N-1];//syn_off0_vs;
    assign rgb_hs      = Pout_hs_dn[N-1];//syn_off0_hs;
    assign rgb_de      = Pout_de_dn[N-1];//off0_syn_de;

    TMDS_PLL u_TMDS_PLL(
        .clkout(hdmi_clk_5), //output clkout
        .lock(locked_hdmi), //output lock
        .clkin(sys_clk) //input clkin
    );

    assign  hdmi_rst_n = sys_rst_n & locked_hdmi;

    CLKDIV u_tmds_clkdiv(
        .RESETN     (hdmi_rst_n ),
        .HCLKIN     (hdmi_clk_5 ),      //clk  x5
        .CLKOUT     (hdmi_clk   ),      //clk  x1
        .CALIB      (1'b0       )
    );
    defparam u_tmds_clkdiv.DIV_MODE="5";
    defparam u_tmds_clkdiv.GSREN="false";

    DVI_TX_Top DVI_TX_Top_inst
    (
        .I_rst_n       (hdmi_rst_n      ),  //asynchronous reset, low active
        .I_serial_clk  (hdmi_clk_5      ),
        .I_rgb_clk     (hdmi_clk        ),  //pixel clock
        .I_rgb_vs      (rgb_vs          ), 
        .I_rgb_hs      (rgb_hs          ),    
        .I_rgb_de      (rgb_de          ), 
        .I_rgb_r       (rgb_data[23:16] ),  
        .I_rgb_g       (rgb_data[15: 8] ),  
        .I_rgb_b       (rgb_data[ 7: 0] ),  
        .O_tmds_clk_p  (O_tmds_clk_p    ),
        .O_tmds_clk_n  (O_tmds_clk_n    ),
        .O_tmds_data_p (O_tmds_data_p   ),  //{r,g,b}
        .O_tmds_data_n (O_tmds_data_n   )
    );

endmodule

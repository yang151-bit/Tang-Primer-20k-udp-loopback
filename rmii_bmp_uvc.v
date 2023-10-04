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
//DRAM读写最大地址 480 * 360 * 2 = 172800
    localparam  DRAM_MAX_ADDR   = 172800;
    localparam  ADDR_WIDTH      = $clog2(DRAM_MAX_ADDR);
//USB分包数 360 + 1 = 361
    localparam  USB_PKT_NUM = 361;  
//DRAM parameters
    localparam  DQ_WIDTH        = 5'h16;
    localparam  DDR_ADDR_WIDTH  = 27;
    localparam  BANK_WIDTH      = 3;
    localparam  ROW_WIDTH       = 14;
    localparam  COL_WIDTH       = 10;
    localparam  DM_WIDTH        = 2;
    localparam  DQS_WIDTH       = 2;
    localparam  AXI_ADDR_WIDTH  = 32;
    localparam  AXI_ID_WIDTH    = 1;
    localparam  AXI_BURST_WIDTH = 6;
    localparam  AXI_DATA_WIDTH  = 128;
    localparam  AXI_STRB_WIDTH  = AXI_DATA_WIDTH >> 3;
    localparam  DATA_WD         = 16;

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
    reg [7:0]                   off0_syn_data;
    

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

    wire                                aclk;        
    wire                                aresetn;

    wire  [AXI_ADDR_WIDTH-1 : 0]        ddr_awaddr;    
    wire  [AXI_ID_WIDTH-1 : 0]          ddr_awid;        
    wire  [AXI_BURST_WIDTH-1 : 0]       ddr_awlen;       
    wire                                ddr_awvalid;     
    wire                                ddr_awready;

    wire  [AXI_DATA_WIDTH - 1 : 0]      ddr_wdata;       
    wire  [AXI_STRB_WIDTH - 1 : 0]      ddr_wstrb;       
    wire                                ddr_wlast;       
    wire                                ddr_wvalid;      
    wire                                ddr_wready;

    wire  [AXI_ID_WIDTH - 1 : 0]        ddr_bid;         
    wire  [1 : 0]                       ddr_bresp;       
    wire                                ddr_bvalid;      
    wire                                ddr_bready;

    wire  [AXI_ID_WIDTH - 1 : 0]        ddr_arid;        
    wire  [AXI_ADDR_WIDTH - 1 : 0]      ddr_araddr;      
    wire  [AXI_BURST_WIDTH-1 : 0]       ddr_arlen;       
    wire                                ddr_arvalid;     
    wire                                ddr_arready;

    wire  [AXI_ID_WIDTH - 1 : 0]        ddr_rid;         
    wire  [AXI_DATA_WIDTH - 1 : 0]      ddr_rdata;       
    wire  [1 : 0]                       ddr_rresp;       
    wire                                ddr_rvalid;      
    wire                                ddr_rready;      
    wire                                ddr_rlast; 

//axi ddr
    axi_ddr3 
    #(
        .AXI_ADDR_WIDTH     (AXI_ADDR_WIDTH     ),
        .AXI_DATA_WIDTH     (AXI_DATA_WIDTH     ),
        .AXI_ID_WIDTH       (AXI_ID_WIDTH       ),
        .AXI_BURST_WIDTH    (AXI_BURST_WIDTH    ),
        .BANK_WIDTH         (BANK_WIDTH         ), 
        .ROW_WIDTH          (ROW_WIDTH          ), 
        .COL_WIDTH          (COL_WIDTH          ), 
        .DQ_WIDTH           (DQ_WIDTH           ), 
        .DM_WIDTH           (DM_WIDTH           ), 
        .DQS_WIDTH          (DQS_WIDTH          )
    )   
    u_axi_ddr3( 
    	.aclk               (aclk               ),
        .aresetn            (aresetn            ),
        .awaddr             (ddr_awaddr         ),
        .awid               (ddr_awid           ),
        .awlen              (ddr_awlen          ),
        .awvalid            (ddr_awvalid        ),
        .awready            (ddr_awready        ),
        .wdata              (ddr_wdata          ),
        .wstrb              (ddr_wstrb          ),
        .wlast              (ddr_wlast          ),
        .wvalid             (ddr_wvalid         ),
        .wready             (ddr_wready         ),
        .bid                (ddr_bid            ),
        .bresp              (ddr_bresp          ),
        .bvalid             (ddr_bvalid         ),
        .bready             (ddr_bready         ),
        .arid               (ddr_arid           ),
        .araddr             (ddr_araddr         ),
        .arlen              (ddr_arlen          ),
        .arvalid            (ddr_arvalid        ),
        .arready            (ddr_arready        ),
        .rid                (ddr_rid            ),
        .rdata              (ddr_rdata          ),
        .rresp              (ddr_rresp          ),
        .rvalid             (ddr_rvalid         ),
        .rready             (ddr_rready         ),
        .rlast              (ddr_rlast          ),
    
        .sys_clk            (sys_clk            ),
        .m_rstn             (rst_n              ),
        .m_clk              (memory_clk         ),
        .m_clk_locked       (locked             ),
        .clk_ref            (aclk               ),
    
        .ddr_init_done      (ddr3_init_done     ),
        .ddr_addr           (ddr_addr           ),
        .ddr_bank           (ddr_bank           ),
        .ddr_cs             (ddr_cs             ),
        .ddr_ras            (ddr_ras            ),
        .ddr_cas            (ddr_cas            ),
        .ddr_we             (ddr_we             ),
        .ddr_ck             (ddr_ck             ),
        .ddr_ck_n           (ddr_ck_n           ),
        .ddr_cke            (ddr_cke            ),
        .ddr_odt            (ddr_odt            ),
        .ddr_reset_n        (ddr_reset_n        ),
        .ddr_dm             (ddr_dm             ),
        .ddr_dq             (ddr_dq             ),
        .ddr_dqs            (ddr_dqs            ),
        .ddr_dqs_n          (ddr_dqs_n          )
    );

    assign ddr_cs = 1'b0;

    assign aresetn = rst_n;
    

    ddr_ctrl_top 
    #(
        .DATA_WD         (DATA_WD         ),
        .MAX_ADDR        (DRAM_MAX_ADDR   ),
        .DQ_WIDTH        (DQ_WIDTH        ),
        .DDR_ADDR_WIDTH  (DDR_ADDR_WIDTH  ),
        .AXI_ADDR_WIDTH  (AXI_ADDR_WIDTH  ),
        .AXI_BURST_WIDTH (AXI_BURST_WIDTH ),
        .AXI_ID_WIDTH    (AXI_ID_WIDTH    ),
        .AXI_DATA_WIDTH  (AXI_DATA_WIDTH  )
    )
    u_ddr_ctrl_top(
    	.rst_n       (rst_n         ),
        .wr_clk      (ddr3_wr_clk   ),
        .wr_en       (vfb_de_in     ),
        .wr_data     (vfb_data_in   ),
        .wr_load     (vfb_vs        ),
        .rd_clk      (~ulpi_clk     ),
        .rd_en       (syn_off0_re   ),
        .rd_load     (~syn_off0_vs  ),
        .rd_data     (vfb_data_out  ),
        .rd_valid    (vfb_rd_valid  ),

        .aclk        (aclk          ),
        .aresetn     (aresetn       ),
        .ddr_awaddr  (ddr_awaddr    ),
        .ddr_awid    (ddr_awid      ),
        .ddr_awlen   (ddr_awlen     ),
        .ddr_awvalid (ddr_awvalid   ),
        .ddr_awready (ddr_awready   ),
        .ddr_wdata   (ddr_wdata     ),
        .ddr_wstrb   (ddr_wstrb     ),
        .ddr_wlast   (ddr_wlast     ),
        .ddr_wvalid  (ddr_wvalid    ),
        .ddr_wready  (ddr_wready    ),
        .ddr_bid     (ddr_bid       ),
        .ddr_bresp   (ddr_bresp     ),
        .ddr_bvalid  (ddr_bvalid    ),
        .ddr_bready  (ddr_bready    ),
        .ddr_arid    (ddr_arid      ),
        .ddr_araddr  (ddr_araddr    ),
        .ddr_arlen   (ddr_arlen     ),
        .ddr_arvalid (ddr_arvalid   ),
        .ddr_arready (ddr_arready   ),
        .ddr_rid     (ddr_rid       ),
        .ddr_rdata   (ddr_rdata     ),
        .ddr_rresp   (ddr_rresp     ),
        .ddr_rvalid  (ddr_rvalid    ),
        .ddr_rready  (ddr_rready    ),
        .ddr_rlast   (ddr_rlast     )
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
    assign uvc_rstn = sys_rst_n;

    uvc_top u_uvc_top(
    .RESET_N        (uvc_rstn  ),
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

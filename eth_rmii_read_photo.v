//----------------------------------------------------------------------------------------
// File name:           eth_rmii_read_photo
// Last modified Date:  2023/5/19 15:16:38
// Last Version:        V1.0
// Descriptions:        udp读取BMP图片
//----------------------------------------------------------------------------------------
// Created by:          
// Created date:        2023/5/19 15:16:38
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

module eth_rmii_read_photo  #(
            parameter USB_PKT_NUM = 361,
            parameter PKT_SIZE = 480)
            (
            input                   mdc_locked     ,
            input                   rmii_mdc       , 
            input                   rst_n,
            output                  ddr3_wr_clk   ,
            output                  ddr3_wr_en    ,    //SDRAM写使能信号
            output      [15:0]      ddr3_wr_data  ,    //SDRAM写数据
            output                  ddr3_vs       ,
            //rmii 接口
            input 					rmii_clk,
	        input 					rmii_rxdv,
	        input [1:0]				rmii_rxdata,
	        output 					rmii_txen,
	        output [1:0]			rmii_txdata,
	        output 					rmii_rst,
            output  				mdclk,
	        inout   				mdio
            );

//首部校验状态
    localparam [3:0]    HEADER_CRC_IDLE     = 4'b0001;
    localparam [3:0]    HEADER_CRC_BM       = 4'b0010;
    localparam [3:0]    HEADER_CRC_COLS     = 4'b0100;
    localparam [3:0]    HEADER_CRC_ROWS     = 4'b1000;

//文件首部长度='B' + 'M' + Width(2bytes) + Heigth(2bytes) + Size(4bytes) + Channels(2bytes)
    localparam HEAD_NUM = 4'd12;           //=1+1+2+2+4+2=12

//reg define
    reg [3:0]                           header_crc_state;
    reg [$clog2(PKT_SIZE)-1 : 0]        word_cnt;
    reg [$clog2(USB_PKT_NUM)-1 : 0]     pkt_cnt;
    reg                                 header_flag;
    reg                                 header_flag_r;
    reg [15:0]                          read_word;
    reg                                 onebyte_flag;
    reg                                 word_valid;
    reg                                 pkt_flag_r;   
//wire define
    wire                                clk;  
    wire [7:0]                          read_byte;
    wire                                read_valid;   
//*****************************************************
//**                    main code
//*****************************************************

    assign clk = rmii_clk;
    assign ddr3_wr_clk = rmii_clk;

    assign ddr3_wr_data = read_word;
    assign ddr3_wr_en = pkt_cnt != 0 & word_valid;
    assign ddr3_vs = header_flag;

    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)
            header_crc_state <= HEADER_CRC_IDLE;
        else if(word_valid)
            case(header_crc_state)
                HEADER_CRC_IDLE : header_crc_state <= 
                    (pkt_cnt=='d0 && read_word ==16'h424d)?
                    HEADER_CRC_BM : HEADER_CRC_IDLE;
                HEADER_CRC_BM : header_crc_state <= read_word ==16'h01e0 ?
                    HEADER_CRC_COLS : HEADER_CRC_IDLE;
                HEADER_CRC_COLS : header_crc_state <= read_word ==16'h0168 ?
                    HEADER_CRC_ROWS : HEADER_CRC_IDLE;
                HEADER_CRC_ROWS : header_crc_state <= HEADER_CRC_IDLE;
                default : header_crc_state <= HEADER_CRC_IDLE;
            endcase
        else
            header_crc_state <= header_crc_state;
    end

    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)
            word_cnt <= 0;
        else if(word_cnt==PKT_SIZE-1 && word_valid)
            word_cnt <= 0;
        else if(header_flag && word_valid)
            word_cnt <= word_cnt + 'd1;
        else if(pkt_cnt == 0 && word_cnt==(HEAD_NUM-6)/2)
            word_cnt <= 0;
        
    end

    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)
            pkt_cnt <= 'd0;
        else if(header_flag && pkt_cnt == 0 && word_cnt==(HEAD_NUM-6)/2)
            pkt_cnt <= pkt_cnt + 'd1;
        else if(header_flag && word_cnt==PKT_SIZE-1 && word_valid)
            pkt_cnt <= pkt_cnt + 'd1;    
        else if(pkt_cnt==USB_PKT_NUM)
            pkt_cnt <= 'd0;
        else
            pkt_cnt <= pkt_cnt;
    end
    
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)
            header_flag <= 0;
        else if(header_crc_state == HEADER_CRC_ROWS)
            header_flag <= 1;
        else if(pkt_cnt==USB_PKT_NUM)
            header_flag <= 0;
        else
            header_flag <= header_flag;
    end

    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)
            onebyte_flag <= 0;
        else if(udp_rxstart)
            onebyte_flag <= 1;
        else if(read_valid)
            onebyte_flag <= ~onebyte_flag;
        else
            onebyte_flag <= onebyte_flag;
    end

    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)
            read_word <= 'd0;
        else
            read_word <= read_valid ? {read_word[7:0],read_byte}:read_word;
    end

    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)
            word_valid <= 'd0;
        else
            word_valid <= read_valid & onebyte_flag;
    end

    assign read_byte = udp_rxdata;
    assign read_valid = udp_rxdv;

	wire								udp_rxstart;
	wire								udp_rxend;
	wire								udp_rxdv;
	wire	[7:0]						udp_rxdata;
	wire	[15:0]						udp_rxamount;
	wire	[15:0]						udp_rxnum;
	reg									udp_txstart;
	reg		[15:0]						udp_txamount;
	wire	[7:0]						udp_txdata;
	wire								udp_txreq;
	wire								udp_txbusy;



eth_rmii								u1_eth_rmii (
	.sys_rst_n							( rst_n 		),
	.rmii_clk							( rmii_clk		),
	.rmii_rxdv							( rmii_rxdv		),
	.rmii_rxdata						( rmii_rxdata	),
	.rmii_txen							( rmii_txen		),
	.rmii_txdata						( rmii_txdata	),
	.rmii_rst							( rmii_rst		),
	.udp_rxstart						( udp_rxstart	),
	.udp_rxend							( udp_rxend		),
	.udp_rxdv							( udp_rxdv		),
	.udp_rxdata							( udp_rxdata	),
	.udp_rxamount						( udp_rxamount	),
	.udp_rxnum							( udp_rxnum		),
	.udp_txstart						( udp_txstart	),
	.udp_txamount						( udp_txamount	),
	.udp_txdata							( udp_txdata	),
	.udp_txreq							( udp_txreq		),
	.udp_txbusy							( udp_txbusy	)
);

mdio_config u_mdio_config(
	.sys_clk          (rmii_mdc          	),
	.sys_clk_rst_sync (~(rst_n | mdc_locked)),
	.mdc              (mdclk              	),
	.mdio             (mdio             	),
	.done             (done             	)
);

endmodule

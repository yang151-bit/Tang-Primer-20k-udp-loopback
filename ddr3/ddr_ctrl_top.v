`timescale 1ns/1ps

module ddr_ctrl_top #(
    parameter DATA_WD           = 16,
    parameter MAX_ADDR          = 518400,
    parameter DDR_ADDR_WIDTH    = 27,
    parameter ROW_WIDTH         = 14,
    parameter COL_WIDTH         = 10,
    parameter BANK_WIDTH        = 3,
    parameter DQ_WIDTH          = 5'h16,
    parameter AXI_ADDR_WIDTH    = 32,
    parameter AXI_ID_WIDTH      = 1,
    parameter AXI_BURST_WIDTH   = 6,
    parameter AXI_DATA_WIDTH    = 128,
    parameter AXI_STRB_WIDTH    = AXI_DATA_WIDTH >> 3
    )          
    (               
    input                       rst_n,                    

    //user write port         
    input                               wr_clk,                   
    input                               wr_en,                    
    input   [DATA_WD-1 : 0]             wr_data,                  
    input                               wr_load,                  

    //user read port
    input                               rd_clk,                   
    input                               rd_en,                    
    input                               rd_load,                  
    output  [DATA_WD-1 : 0]             rd_data,                  
    output                              rd_valid,        

    //axi ddr interface
    input                               aclk,
    input                               aresetn,

    output  [AXI_ADDR_WIDTH-1 : 0]      ddr_awaddr,
    output  [AXI_ID_WIDTH-1 : 0]        ddr_awid,
    output  [AXI_BURST_WIDTH-1 : 0]     ddr_awlen,
    output                              ddr_awvalid,
    input                               ddr_awready,

    output  [AXI_DATA_WIDTH - 1 : 0]    ddr_wdata,
    output  [AXI_STRB_WIDTH - 1 : 0]    ddr_wstrb,
    input                               ddr_wlast,
    output                              ddr_wvalid,
    input                               ddr_wready,

    input   [AXI_ID_WIDTH - 1 : 0]      ddr_bid,
    input   [1 : 0]                     ddr_bresp,
    input                               ddr_bvalid,
    output                              ddr_bready,

    output  [AXI_ID_WIDTH - 1 : 0]      ddr_arid,
    output  [AXI_ADDR_WIDTH - 1 : 0]    ddr_araddr,
    output  [AXI_BURST_WIDTH-1 : 0]     ddr_arlen,
    output                              ddr_arvalid,
    input                               ddr_arready,
    input   [AXI_ID_WIDTH - 1 : 0]      ddr_rid,
    input   [AXI_DATA_WIDTH - 1 : 0]    ddr_rdata,
    input   [1 : 0]                     ddr_rresp,
    input                               ddr_rvalid,
    output                              ddr_rready,
    input                               ddr_rlast

);

//DRAM parameters
    localparam  LEN_WIDTH           = $clog2(MAX_ADDR);
    localparam  SEC_WIDTH           = 2;
    localparam  DESC_ADDR_WIDTH     = BANK_WIDTH + SEC_WIDTH + LEN_WIDTH;

    localparam N = 2;

    reg  [N-1:0]  Pout_rd_valid   ;
    reg        rd_load_r1;                  
    reg        rd_load_r2;
    reg        wr_load_r1;                  
    reg        wr_load_r2;                  

    wire rd_load_flag;         
    wire wr_load_flag;

    assign rd_load_flag    = rd_load_r2 & ~rd_load_r1;
    assign wr_load_flag    = ~wr_load_r2 & wr_load_r1;

    always@(posedge rd_clk or negedge rst_n)
    begin
        if(!rst_n)             
            Pout_rd_valid  <= {N{1'b0}};
        else
            Pout_rd_valid  <= {Pout_rd_valid[N-2:0],rd_en};
    end
    assign rd_valid = Pout_rd_valid[N-1];

    always @(posedge aclk or negedge rst_n) begin
        if(!rst_n) begin
            rd_load_r1 <= 1'b0;
            rd_load_r2 <= 1'b0;
        end
        else begin
            rd_load_r1 <= rd_load;
            rd_load_r2 <= rd_load_r1;
        end
    end


    always @(posedge aclk or negedge rst_n) begin
        if(!rst_n) begin
            wr_load_r1 <= 1'b0;
            wr_load_r2 <= 1'b0;
        end
        else begin
            wr_load_r1 <= wr_load;
            wr_load_r2 <= wr_load_r1;
        end
    end

    reg [1:0] wr_sec;
    reg [1:0] rd_sec;
    reg new_frame_flag;

    always @(posedge aclk or negedge rst_n)
        if(!rst_n) 
            wr_sec <= 0;
        else if(wrfifo_last & ~new_frame_flag)
            wr_sec <= wr_sec +1;

    always @(posedge aclk or negedge rst_n)
        if(!rst_n) 
            new_frame_flag <= 0;
        else if(wrfifo_last)
            new_frame_flag <= 1;
        else if(rdfifo_last & new_frame_flag)
            new_frame_flag <= 0;
    
    always @(posedge aclk or negedge rst_n)
        if(!rst_n) 
            rd_sec <= 2;
        else if(rdfifo_last & new_frame_flag)
            rd_sec <= rd_sec +1;

// Axi dma read interface
    wire [DESC_ADDR_WIDTH-1 :0]     rdfifo_desc_addr;   
    wire [LEN_WIDTH-1 :0]           rdfifo_desc_len ;   
    wire                            rdfifo_valid    ;   
    wire                            rdfifo_ready    ;   
    wire                            rdfifo_if_ready ;   
    wire                            rdfifo_if_push  ;   
    wire [AXI_DATA_WIDTH-1 :0]      rdfifo_if_data  ;   
    wire                            rdfifo_if_req   ;   
    wire                            rdfifo_last     ;   
                          
    assign rdfifo_desc_addr = {3'b000, rd_sec, {LEN_WIDTH{1'b0}}};
    assign rdfifo_desc_len = MAX_ADDR;
    assign rdfifo_valid = ~rd_load_r2 & rd_load_r1;

    axi_dma_rd_if 
    #(
        .AXI_ADDR_WIDTH     (AXI_ADDR_WIDTH     ),
        .AXI_DATA_WIDTH     (AXI_DATA_WIDTH     ),
        .AXI_ID_WIDTH       (AXI_ID_WIDTH       ),
        .AXI_ID             (0                  ),
        .AXI_BURST_WIDTH    (AXI_BURST_WIDTH    ),
        .DDR_WIDTH          (DDR_ADDR_WIDTH     ),
        .BANK_WIDTH         (BANK_WIDTH         ),
        .LEN_WIDTH          (LEN_WIDTH          ),
        .SEC_WIDTH          (2                  ),
        .BURST_LEN          (16                 )
    )
    u_axi_dma_rd_if_rfifo(
    	.aclk               (aclk               ),
        .aresetn            (aresetn            ),
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

        .cfg_desc_addr      (rdfifo_desc_addr   ),
        .cfg_desc_len       (rdfifo_desc_len    ),
        .cfg_valid          (rdfifo_valid       ),
        .cfg_ready          (rdfifo_ready       ),
        .if_wr_push         (rdfifo_if_push     ),
        .if_wr_data         (rdfifo_if_data     ),
        .if_wr_req          (rdfifo_if_req      ),
        .if_wr_ready        (rdfifo_if_ready    ),
        .st_last            (rdfifo_last        )
    );

// Axi dma write interface
    wire [DESC_ADDR_WIDTH-1 :0]     wrfifo_desc_addr;  
    wire [LEN_WIDTH-1 :0]           wrfifo_desc_len ;  
    wire                            wrfifo_valid    ;  
    wire                            wrfifo_ready    ;  
    wire                            wrfifo_if_pop   ;  
    wire [AXI_DATA_WIDTH-1 :0]      wrfifo_if_data  ;  
    wire                            wrfifo_if_ready ;  
    wire                            wrfifo_if_req   ;  
    wire                            wrfifo_last     ;  

    assign wrfifo_desc_addr = {3'b000, wr_sec, {LEN_WIDTH{1'b0}}};
    assign wrfifo_desc_len = MAX_ADDR;
    assign wrfifo_valid = wr_load_flag;

    axi_dma_wr_if 
    #(
        .AXI_ADDR_WIDTH     (AXI_ADDR_WIDTH     ),
        .AXI_DATA_WIDTH     (AXI_DATA_WIDTH     ),
        .AXI_ID_WIDTH       (AXI_ID_WIDTH       ),
        .AXI_ID             (1                  ),
        .AXI_BURST_WIDTH    (AXI_BURST_WIDTH    ),
        .DDR_WIDTH          (DDR_ADDR_WIDTH     ),
        .BANK_WIDTH         (BANK_WIDTH         ),
        .LEN_WIDTH          (LEN_WIDTH          ),
        .SEC_WIDTH          (2                  ),
        .BURST_LEN          (8                  )
    )
    u_axi_dma_wr_if_wfifo(
    	.aclk               (aclk               ),
        .aresetn            (aresetn            ),
        .awid               (ddr_awid           ),
        .awaddr             (ddr_awaddr         ),
        .awlen              (ddr_awlen          ),
        .awvalid            (ddr_awvalid        ),
        .awready            (ddr_awready        ),
        .wid                (ddr_wid            ),
        .wdata              (ddr_wdata          ),
        .wresp              (ddr_wresp          ),
        .wvalid             (ddr_wvalid         ),
        .wready             (ddr_wready         ),
        .wstrb              (ddr_wstrb          ),
        .wlast              (ddr_wlast          ),
        .bid                (ddr_bid            ),
        .bresp              (ddr_bresp          ),
        .bvalid             (ddr_bvalid         ),
        .bready             (ddr_bready         ),

        .cfg_desc_addr      (wrfifo_desc_addr   ),
        .cfg_desc_len       (wrfifo_desc_len    ),
        .cfg_valid          (wrfifo_valid       ),
        .cfg_ready          (wrfifo_ready       ),
        .if_rd_pop          (wrfifo_if_pop      ),
        .if_rd_data         (wrfifo_if_data     ),
        .if_rd_ready        (wrfifo_if_ready    ),
        .if_rd_req          (wrfifo_if_req      ),
        .st_last            (wrfifo_last        )
    );

// Instantiate write port FIFO
    reg [3:0]wrfifo_rst_r;

    wire wrfifo_almostE;
    wire wrfifo_rst;

    always @(posedge aclk or posedge wr_load_flag)
        if(wr_load_flag)
            wrfifo_rst_r <= 4'b1111;
        else
            wrfifo_rst_r <= {wrfifo_rst_r[2:0], 1'b0};

    assign wrfifo_rst = wrfifo_rst_r[3];

    wrfifo u_wfifo(
		.Data           (wr_data),                      //input [15:0] Data
		.Reset          (~rst_n | wrfifo_rst),          //input Reset
		.WrClk          (wr_clk),                       //input WrClk
		.RdClk          (aclk),                         //input RdClk
		.WrEn           (wr_en),                        //input WrEn
		.RdEn           (wrfifo_if_pop),                //input RdEn
		.Almost_Empty   (wrfifo_almostE),               //output Almost_Empty
		.Q              (wrfifo_if_data)                //output [127:0] Q
	);
    
    assign wrfifo_if_req = ~wrfifo_almostE;

// Instantiate read port FIFO
    wire rdfifo_almostF;
    wire rdfifo_full;
    wire rdfifo_rst;

    reg [3:0]rdfifo_rst_r;

    always @(posedge aclk or posedge rd_load_flag)
        if(rd_load_flag)
            rdfifo_rst_r <= 0;
        else
            rdfifo_rst_r <= {rdfifo_rst_r[2:0], 1'b1};

    assign rdfifo_rst = ~rdfifo_rst_r[3] & rdfifo_ready;

	rdfifo u_rfifo(
		.Data           (rdfifo_if_data),               //input [127:0] Data
		.Reset          (~rst_n),                       //input Reset
		.WrClk          (aclk),                         //input WrClk
		.RdClk          (rd_clk),                       //input RdClk
		.WrEn           (rdfifo_if_push),               //input WrEn
		.RdEn           (rd_en),                        //input RdEn
		.Almost_Full    (rdfifo_almostF),               //output Almost_Full
		.Full           (rdfifo_full),                  //output Full
		.Q              (rd_data)                       //output [15:0] Q
	);

    assign rdfifo_if_req = ~rdfifo_almostF;
    assign rdfifo_if_ready = ~rdfifo_full;

endmodule





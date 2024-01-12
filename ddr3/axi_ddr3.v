//----------------------------------------------------------------------------------------
// File name:           ddr3_axi
// Last modified Date:  2023/09/29 20:36:20
// Last Version:        V1.0
// Descriptions:        The original version
//                      
//----------------------------------------------------------------------------------------
// Created by:          
// Created date:        2023/09/29 20:36:20
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//


module axi_ddr3 #(
    parameter AXI_ADDR_WIDTH    = 32,
    parameter AXI_ID_WIDTH      = 4,
    parameter AXI_BURST_WIDTH   = 6,
    parameter BANK_WIDTH        = 3,
    parameter ROW_WIDTH         = 14,
    parameter COL_WIDTH         = 10,
    parameter DQ_WIDTH          = 5'd16,
    parameter DM_WIDTH          = 2,
    parameter DQS_WIDTH         = 2,
    parameter AXI_DATA_WIDTH    = DQ_WIDTH * 8,
    parameter AXI_STRB_WIDTH    = AXI_DATA_WIDTH >> 3
) (
    input                               aclk,
    input                               aresetn,
    input   [AXI_ADDR_WIDTH-1 : 0]      awaddr,
    input   [AXI_ID_WIDTH-1 : 0]        awid,
    input   [AXI_BURST_WIDTH-1 : 0]     awlen,
    /* not used
    input   [1 : 0]                     awburst,
    input   [2 : 0]                     awsize,
    input   [1 : 0]                     awlock,
    input   [3 : 0]                     awcache,
    input   [2 : 0]                     awport,
    */
    input                               awvalid,
    output                              awready,

    input   [AXI_DATA_WIDTH - 1 : 0]    wdata,
    input   [AXI_STRB_WIDTH - 1 : 0]    wstrb,
    output                              wlast,
    input                               wvalid,
    output                              wready,
    output  [AXI_ID_WIDTH - 1 : 0]      bid,
    output  [1 : 0]                     bresp,
    output                              bvalid,
    input                               bready,
    input   [AXI_ID_WIDTH - 1 : 0]      arid,
    input   [AXI_ADDR_WIDTH - 1 : 0]    araddr,
    input   [AXI_BURST_WIDTH-1 : 0]     arlen,
    /* not used
    input   [1 : 0]                     arburst,
    input   [2 : 0]                     arsize,
    input   [1 : 0]                     arlock,
    input   [3 : 0]                     arcache,
    input   [2 : 0]                     arport,
    */
    input                               arvalid,
    output                              arready,
    output  [AXI_ID_WIDTH - 1 : 0]      rid,
    output  [AXI_DATA_WIDTH - 1 : 0]    rdata,
    output  [1 : 0]                     rresp,
    output                              rvalid,
    input                               rready,
    output                              rlast,
    // inputs & outputs for memory interface
    input                               sys_clk,
    input                               m_rstn,
    input                               m_clk,
    input                               m_clk_locked,
    output                              clk_ref,
    output                              ddr_init_done,

    // ddr interface
    output [ROW_WIDTH-1:0]              ddr_addr,       //ROW_WIDTH=14
    output [BANK_WIDTH-1:0]             ddr_bank,       //BANK_WIDTH=3
    output                              ddr_cs,
    output                              ddr_ras,
    output                              ddr_cas,
    output                              ddr_we,
    output                              ddr_ck,
    output                              ddr_ck_n,
    output                              ddr_cke,
    output                              ddr_odt,
    output                              ddr_reset_n,
    output [DM_WIDTH-1:0]               ddr_dm,         //DM_WIDTH=2
    inout  [DQ_WIDTH-1:0]               ddr_dq,         //DQ_WIDTH=16
    inout  [DQS_WIDTH-1:0]              ddr_dqs,        //DQS_WIDTH=2
    inout  [DQS_WIDTH-1:0]              ddr_dqs_n       //DQS_WIDTH=2
    
);

    wire rstn;
    wire sclk;

/*
* Gowin defined DDR command
* Using READ and WRITE only.
*/
    localparam DDR_CMD_READ     = 3'h1;
    localparam DDR_CMD_WRITE    = 3'h0;

/*
* AXI defined response type
*/
    localparam AXI_RESP_OKAY    = 2'b00;
    localparam AXI_RESP_EXOKAY  = 2'b01;
    localparam AXI_RESP_SLVERR  = 2'b10;
    localparam AXI_RESP_DECERR  = 2'b11;

/*
* AXI Read/Write Address Channel
*/

    localparam DDR_CMD_WIDTH    = 3;
    localparam DDR_ADDR_WIDTH   = BANK_WIDTH + ROW_WIDTH + COL_WIDTH;

    wire [AXI_DATA_WIDTH - 1 : 0]   ddr_wdata;
    wire [AXI_STRB_WIDTH - 1 : 0]   ddr_wr_mask;
    wire [DDR_ADDR_WIDTH-1 :0]      addr;
    wire ddr_cmd_rdy;
    wire ddr_cmd_en;
    wire ddr_wr_rdy;
    wire ddr_wr_en;
    wire ddr_wdata_end;

    wire [AXI_DATA_WIDTH - 1 : 0] ddr_rdata;
    wire ddr_rd_valid;
    wire ddr_rdata_end;

    wire [DDR_CMD_WIDTH - 1 : 0] ddr_cmd;

    reg [AXI_BURST_WIDTH-1:0]   cmd_exec_cnt;
    reg                         ddr_idle;
    reg                         ddr_exec_wr;

    assign arready = ddr_idle & ~awvalid & & ddr_init_done;
    assign awready = ddr_idle & ddr_init_done;

    always @(posedge aclk or negedge aresetn)
        if (~aresetn)
            ddr_idle <= 1;
        else if(arready & arvalid || awvalid & awready)
            ddr_idle <= 0;
        else
            if(ddr_exec_wr)
                ddr_idle <= cmd_exec_cnt == awlen & wvalid & wready;
            else if(~ddr_idle)
                ddr_idle <= cmd_exec_cnt == arlen & ddr_rd_cmd_rdy;

    always @(posedge aclk or negedge aresetn)
        if (~aresetn)
            ddr_exec_wr <= 0;
        else if(awvalid & awready)
            ddr_exec_wr <= 1;
        else if(wlast)
            ddr_exec_wr <= 0;
    
    wire ddr_rd_cmd_rdy;
    assign ddr_rd_cmd_rdy = ~ddr_exec_wr & ddr_cmd_rdy & ~ddr_idle;

    assign ddr_cmd_en = wvalid & wready || ddr_rd_cmd_rdy;
    assign ddr_cmd = ddr_exec_wr ? DDR_CMD_WRITE : DDR_CMD_READ;
    assign addr = {addr_b, addr_r_c};
    

    always @(posedge aclk)
        if(ddr_idle)
            cmd_exec_cnt <= 0;
        else if(ddr_cmd_en)
            cmd_exec_cnt <= cmd_exec_cnt + 1;

    reg [ROW_WIDTH+COL_WIDTH-1:0]   addr_r_c;
    reg [BANK_WIDTH-1:0]            addr_b;

    always @(posedge aclk)
        if(awvalid & awready)
            addr_r_c <= awaddr[ROW_WIDTH+COL_WIDTH-1:0];
        else if(arvalid & arready)
            addr_r_c <= araddr[ROW_WIDTH+COL_WIDTH-1:0];
        else if(wvalid & wready || ddr_rd_cmd_rdy)
            addr_r_c <= addr_r_c + 'h8;

    always @(posedge aclk)
        if(awvalid & awready)
            addr_b <= awaddr[ROW_WIDTH+COL_WIDTH +: BANK_WIDTH];
        else if(arvalid & arready)
            addr_b <= araddr[ROW_WIDTH+COL_WIDTH +: BANK_WIDTH];

/*
* AXI Write Data Channel
* Based on Lattice DDR Controller IP limitation, we highly recommend you to write data before address
*/
    
    assign wready = ddr_exec_wr & ddr_wr_rdy & ddr_cmd_rdy;

/*
* AXI Write Data Response Channel
*/

    reg [AXI_ID_WIDTH - 1 : 0] bid_reg;

    reg r_bvalid;

    assign wlast = cmd_exec_cnt == awlen & wvalid & wready;
    assign bid = bid_reg;
    assign bresp = AXI_RESP_OKAY;
    assign bvalid = r_bvalid;

    always @(posedge aclk)
        if (awready & awvalid)
            bid_reg <= awid;

    always @(posedge aclk or negedge aresetn)
        if (~aresetn)
            r_bvalid <= 0;
        else
            if (bvalid & bready)
                r_bvalid <= 0;
            else
                r_bvalid <= wlast;

/*
* AXI Read Response Channel
*/
    localparam RTAG_WIDTH = AXI_ID_WIDTH + AXI_BURST_WIDTH;

    
    wire rtag_fifo_push, rtag_fifo_pop;
    wire rtag_fifo_full, rtag_fifo_empty;
    wire [RTAG_WIDTH-1 : 0] rtag_fifo_idata, rtag_fifo_odata;
    wire [AXI_BURST_WIDTH-1 : 0] rlen;

    reg [AXI_BURST_WIDTH-1 : 0] burst_read_counter;
    reg rtag_fifo_init_flag;

    wire rtag_fifo_init;


    always @(posedge aclk or negedge aresetn)
        if (~aresetn)
            rtag_fifo_init_flag <= 0;
        else if(~rtag_fifo_init_flag & ~rtag_fifo_empty)
            rtag_fifo_init_flag <= 1;
        else if(rlast & rtag_fifo_empty)
            rtag_fifo_init_flag <= 0;


    assign rtag_fifo_push = arready & arvalid;
    assign rtag_fifo_idata = {arid, arlen};
    
    assign rtag_fifo_init = ~rtag_fifo_init_flag & ~rtag_fifo_empty;
    assign rtag_fifo_pop = rtag_fifo_init | (rlast & ~rtag_fifo_empty);
    assign {rid, rlen} = rtag_fifo_odata;

    sfifo 
    #(
        .width (RTAG_WIDTH   ),
        .depth (4            )
    )
    u_sfifo_rid(
    	.clk        (aclk               ),
        .rstn       (aresetn            ),
        .wr_en      (rtag_fifo_push     ),
        .rd_en      (rtag_fifo_pop      ),
        .wr_data    (rtag_fifo_idata    ),
        .rd_data    (rtag_fifo_odata    ),
        .fifo_full  (rtag_fifo_full     ),
        .fifo_empty (rtag_fifo_empty    )
    );
    
    reg rvalid_reg;
    reg pre_rvalid;
    reg rd_last;

    always @(posedge aclk or negedge aresetn)
        if (~aresetn)
            pre_rvalid <= 0;
        else if(rvalid & rready)
            pre_rvalid <= 0;
        else if(rvalid_reg & ~rready)
            pre_rvalid <= 1;
        

    always @(posedge aclk)
        rvalid_reg <= ~rdata_fifo_empty & rready;

    assign rresp = AXI_RESP_OKAY;
    assign rvalid = rvalid_reg | pre_rvalid;
    assign rlast = rd_last & rvalid & rready;

    always @(posedge aclk)
        if (rtag_fifo_pop)
            burst_read_counter <= 0;
        else if(rvalid & rready)
            burst_read_counter <= burst_read_counter +1;
    
    always @(posedge aclk or negedge aresetn)
        if (~aresetn)
            rd_last <= 0;
        else if (rtag_fifo_pop | rlast)
            rd_last <= 0;
        else if(burst_read_counter == rlen-1 & rvalid & rready)
            rd_last <= 1;

/*
* DDR Write Channel
*/

    reg ddr_wr_en_reg;

    always @(posedge aclk)
        if (wvalid & wready)
            ddr_wr_en_reg <= 1;
        else
            ddr_wr_en_reg <= 0;

    assign ddr_wdata = wdata;
    assign ddr_wr_mask = wstrb;
    assign ddr_wr_en = ddr_wr_en_reg;
    assign ddr_wdata_end = ddr_wr_en;

/*
* DDR Read Channel
*/
    wire rdata_fifo_push, rdata_fifo_pop;
    wire rdata_fifo_full, rdata_fifo_empty;
    wire [AXI_DATA_WIDTH-1 : 0] rdata_fifo_idata; 
    wire [AXI_DATA_WIDTH-1 : 0] rdata_fifo_odata;

    assign rdata_fifo_idata = ddr_rdata;
    assign rdata_fifo_push = ddr_rd_valid & ddr_init_done;
    assign rdata_fifo_pop = ~rdata_fifo_empty & rready;
    assign rdata = rdata_fifo_odata;

    sfifo 
    #(
        .width (AXI_DATA_WIDTH      ),
        .depth (16                  )
    )
    u_sfifo_rdata(
    	.clk        (aclk               ),
        .rstn       (rtag_fifo_init_flag   ),
        .wr_en      (rdata_fifo_push    ),
        .rd_en      (rdata_fifo_pop     ),
        .wr_data    (rdata_fifo_idata   ),
        .rd_data    (rdata_fifo_odata   ),
        .fifo_full  (rdata_fifo_full    ),
        .fifo_empty (rdata_fifo_empty   )
    )/* synthesis syn_ramstyle = "distributed_ram" */;


/*
* DDR3 IP core instantiation
*/
    DDR3_Memory_Interface_Top u_ddr3 (
        .clk                  (sys_clk),
        .memory_clk           (m_clk),
        .pll_lock             (m_clk_locked),
        .rst_n                (m_rstn),   //rst_n
        // .app_burst_number     (ddr_burst_number),
        .cmd_ready            (ddr_cmd_rdy),
        .cmd                  (ddr_cmd),
        .cmd_en               (ddr_cmd_en),
        .addr                 ({1'b0, addr}),//IDK why Gowin Set the addr width to 28. But it should be 27
        .wr_data_rdy          (ddr_wr_rdy),
        .wr_data              (ddr_wdata),
        .wr_data_en           (ddr_wr_en),
        .wr_data_end          (ddr_wdata_end),
        .wr_data_mask         (ddr_wr_mask),
        .rd_data              (ddr_rdata),
        .rd_data_valid        (ddr_rd_valid),
        .rd_data_end          (ddr_rdata_end),
        .sr_req               (1'b0),
        .ref_req              (1'b0),
        .sr_ack               (),
        .ref_ack              (),
        .init_calib_complete  (ddr_init_done),
        .clk_out              (clk_ref),
        .burst                (1'b1),

        // mem interface
        .ddr_rst              (),
        .O_ddr_addr           (ddr_addr),
        .O_ddr_ba             (ddr_bank),
        .O_ddr_cs_n           (ddr_cs1),
        .O_ddr_ras_n          (ddr_ras),
        .O_ddr_cas_n          (ddr_cas),
        .O_ddr_we_n           (ddr_we),
        .O_ddr_clk            (ddr_ck),
        .O_ddr_clk_n          (ddr_ck_n),
        .O_ddr_cke            (ddr_cke),
        .O_ddr_odt            (ddr_odt),
        .O_ddr_reset_n        (ddr_reset_n),
        .O_ddr_dqm            (ddr_dm),
        .IO_ddr_dq            (ddr_dq),
        .IO_ddr_dqs           (ddr_dqs),
        .IO_ddr_dqs_n         (ddr_dqs_n)
    );

    assign ddr_cs = 1'b0;

endmodule
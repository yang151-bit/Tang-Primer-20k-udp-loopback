//----------------------------------------------------------------------------------------
// File name:           axi_dma_wr_if
// Last modified Date:  2023/10/01 17:06:10
// Last Version:        V1.0
// Descriptions:        The original version
//                      
//----------------------------------------------------------------------------------------
// Created by:          
// Created date:        2023/10/01 17:06:10
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

module axi_dma_wr_if #(
    parameter AXI_ADDR_WIDTH    = 32,
    parameter AXI_DATA_WIDTH    = 128,
    parameter AXI_ID_WIDTH      = 1,
    parameter AXI_ID            = 1,
    parameter AXI_BURST_WIDTH   = 6,
    parameter LEN_WIDTH         = 20,
    parameter DDR_WIDTH         = 27,
    parameter BANK_WIDTH        = 3,
    parameter SEC_WIDTH         = 2,
    parameter BURST_LEN         = 8,
    parameter SUB_WIDTH         = LEN_WIDTH,
    parameter AXI_STRB_WIDTH    = AXI_DATA_WIDTH >> 3,
    parameter ADDR_WIDTH        = BANK_WIDTH + SEC_WIDTH + SUB_WIDTH
) (
    input                               aclk,
    input                               aresetn,
    
    /*
     * AXI master interface
     */
    output  [AXI_ID_WIDTH - 1 : 0]      awid,
    output  [AXI_ADDR_WIDTH - 1 : 0]    awaddr,
    output  [AXI_BURST_WIDTH-1 : 0]     awlen,
    output                              awvalid,
    input                               awready,
    output  [AXI_ID_WIDTH - 1 : 0]      wid,
    output  [AXI_DATA_WIDTH - 1 : 0]    wdata,
    output  [1 : 0]                     wresp,
    output  [AXI_STRB_WIDTH - 1 : 0]    wstrb,
    output                              wvalid,
    input                               wready,
    input                               wlast,

    input   [AXI_ID_WIDTH - 1 : 0]      bid,
    input   [1 : 0]                     bresp,
    input                               bvalid,
    output                              bready,

    /*
     * Control interface
     */
    input   [ADDR_WIDTH - 1 : 0]        cfg_desc_addr,
    input   [LEN_WIDTH - 1 : 0]         cfg_desc_len,
    input                               cfg_valid,
    output                              cfg_ready,

    output                              if_rd_pop,   
    input   [AXI_DATA_WIDTH-1:0]        if_rd_data,  
    input                               if_rd_ready,
    input                               if_rd_req,   

    output                              st_last      
);

    localparam [0:0]
        AXI_STATE_IDLE = 1'd0,
        AXI_STATE_START = 1'd1;

    localparam SSUB_WIDTH = $clog2(8) + $clog2(BURST_LEN);
    
    reg [0:0] axi_state_reg = AXI_STATE_IDLE, axi_state_next;
    
    reg [SUB_WIDTH-1 :SSUB_WIDTH] addr_reg, addr_next;
    reg [LEN_WIDTH-1 :SSUB_WIDTH] len_reg, len_next;
    reg if_ready, if_ready_next;

    assign cfg_ready = axi_state_reg == AXI_STATE_IDLE;

    always @(*) begin
        axi_state_next = axi_state_reg;
        addr_next = addr_reg;
        len_next = len_reg;
        if_ready_next = if_ready;

        case(axi_state_reg)
            AXI_STATE_IDLE:begin
                if (cfg_valid) begin
                    addr_next = cfg_desc_addr[SUB_WIDTH-1 :SSUB_WIDTH];
                    len_next = cfg_desc_len[LEN_WIDTH-1 :SSUB_WIDTH];
                    axi_state_next = AXI_STATE_START;
                end
            end
            AXI_STATE_START:begin
                if(st_last)
                    axi_state_next = AXI_STATE_IDLE;

                if_ready_next = awready & awvalid ? 1 : if_ready;

                if(wlast)
                    if_ready_next = 0;

                if(len_reg != 1)begin
                    if(bvalid & bready)begin
                        addr_next = addr_reg + 1;
                        len_next = len_reg - 1;
                    end
                end
            end
        endcase
    end

    assign awid = AXI_ID;
    assign wid = AXI_ID;
    assign awvalid = if_rd_req & ~if_ready & axi_state_reg == AXI_STATE_START;
    assign awaddr = {{(AXI_ADDR_WIDTH - DDR_WIDTH){1'b0}}, cfg_desc_addr[ADDR_WIDTH-1 -:BANK_WIDTH], {(DDR_WIDTH - ADDR_WIDTH){1'b0}},
                    cfg_desc_addr[SUB_WIDTH +:SEC_WIDTH], addr_reg, {SSUB_WIDTH{1'b0}}};
    assign awlen = BURST_LEN-1;

    assign bready = 1;
    assign wvalid = if_ready;
    assign wdata = if_rd_data;
    assign wstrb = {(AXI_STRB_WIDTH){1'b0}};

    assign if_rd_pop = wvalid & wready && bid == AXI_ID;

    assign st_last = axi_state_reg == AXI_STATE_START && len_reg == 1 && wlast;  

    reg [$clog2(BURST_LEN)-1:0] burst_write_counter;
    
    // always @(posedge aclk)
    //     if (awvalid & awready)
    //         burst_write_counter <= 0;
    //     else if(wvalid & wready)
    //         burst_write_counter <= burst_write_counter +1;

    // assign wlast = burst_write_counter == BURST_LEN-1 && wvalid & wready;

    always @(posedge aclk) begin
        axi_state_reg <= axi_state_next;
        addr_reg <= addr_next;
        len_reg <= len_next;
        if_ready <= if_ready_next;

        if (~aresetn) begin
            if_ready <= 0;
            axi_state_reg <= AXI_STATE_IDLE;
        end
    end

endmodule
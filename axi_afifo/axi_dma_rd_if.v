//----------------------------------------------------------------------------------------
// File name:           axi_dma_rd_if
// Last modified Date:  2023/10/01 15:25:20
// Last Version:        V1.0
// Descriptions:        The original version
//                      
//----------------------------------------------------------------------------------------
// Created by:          
// Created date:        2023/10/01 15:25:20
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

module axi_dma_rd_if #(
    parameter AXI_ADDR_WIDTH    = 32,
    parameter AXI_DATA_WIDTH    = 128,
    parameter AXI_ID_WIDTH      = 4,
    parameter AXI_ID            = 4,
    parameter AXI_BURST_WIDTH   = 6,
    parameter DDR_WIDTH         = 27,
    parameter BANK_WIDTH        = 3,
    parameter SEC_WIDTH         = 2,
    parameter LEN_WIDTH         = 20,
    parameter BURST_LEN         = 8,
    parameter AXI_STRB_WIDTH    = AXI_DATA_WIDTH >> 3,
    parameter SUB_WIDTH         = LEN_WIDTH,
    parameter ADDR_WIDTH        = BANK_WIDTH + SEC_WIDTH + SUB_WIDTH
) (
    input                               aclk,
    input                               aresetn,
    
    /*
     * AXI master interface
     */
    output  [AXI_ID_WIDTH - 1 : 0]      arid,
    output  [AXI_ADDR_WIDTH - 1 : 0]    araddr,
    output  [AXI_BURST_WIDTH-1 : 0]     arlen,
    output                              arvalid,
    input                               arready,
    input   [AXI_ID_WIDTH - 1 : 0]      rid,
    input   [AXI_DATA_WIDTH - 1 : 0]    rdata,
    input   [1 : 0]                     rresp,
    input                               rvalid,
    output                              rready,
    input                               rlast,

    /*
     * Control interface
     */
    input   [ADDR_WIDTH - 1 : 0]        cfg_desc_addr,
    input   [LEN_WIDTH - 1 : 0]         cfg_desc_len,
    input                               cfg_valid,
    input                               cfg_ready,

    output                              if_wr_push,
    output  [AXI_DATA_WIDTH-1:0]        if_wr_data,
    input                               if_wr_req,

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

                if_ready_next = arready & arvalid ? 1 : if_ready;

                if(rlast & rid == AXI_ID)
                    if_ready_next = 0;

                if(len_reg != 0)begin
                    if(rlast & rid == AXI_ID)begin
                        addr_next = addr_reg + 1;
                        len_next = len_reg - 1;
                    end
                end
            end
        endcase
    end

    assign arid = AXI_ID;
    assign arvalid = if_wr_req & ~if_ready & axi_state_reg == AXI_STATE_START;
    assign araddr = {{(AXI_ADDR_WIDTH - DDR_WIDTH){1'b0}}, cfg_desc_addr[ADDR_WIDTH-1 -:BANK_WIDTH], {(DDR_WIDTH - ADDR_WIDTH){1'b0}},
                    cfg_desc_addr[SUB_WIDTH +:SEC_WIDTH], addr_reg, {SSUB_WIDTH{1'b0}}};
    assign arlen = BURST_LEN-1;

    assign rready = 1;

    assign if_wr_data = rdata;
    assign if_wr_push = if_ready & rvalid && rid == AXI_ID;

    assign st_last = axi_state_reg == AXI_STATE_START && len_reg == 0 && rlast && rid == AXI_ID;  

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
/******************************************************************************
Copyright 2022 GOWIN SEMICONDUCTOR CORPORATION

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

The Software is used with products manufacturered by GOWIN Semconductor only
unless otherwise authorized by GOWIN Semiconductor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
******************************************************************************/
`include "usb_defs.v"
`include "uvc_defs.v"

module uvc_top(
    input      RESET_N,

    //ulpi interface
    output        ulpi_rst,
    input         ulpi_clk,
    input         ulpi_dir,
    input         ulpi_nxt,
    output        ulpi_stp,
    inout [7:0]   ulpi_data,
    input         vfb_rdy,
    input [23:0]  vfb_data_in,
    output        vfb_re,
    output        vfb_vs
);




wire [1:0]  PHY_XCVRSELECT      ;
wire        PHY_TERMSELECT      ;
wire [1:0]  PHY_OPMODE          ;
wire [1:0]  PHY_LINESTATE       ;
wire        PHY_TXVALID         ;
wire        PHY_TXREADY         ;
wire        PHY_RXVALID         ;
wire        PHY_RXACTIVE        ;
wire        PHY_RXERROR         ;
wire [7:0]  PHY_DATAIN          ;
wire [7:0]  PHY_DATAOUT         ;
wire        PHY_CLKOUT          ;

wire [7:0]  usb_txdat;
reg [11:0]  txdat_len;
wire        usb_txval;
reg         usb_txcork;
wire        usb_txpop;
wire        usb_txact;
wire [7:0]  usb_rxdat;
wire        usb_rxact;
wire        usb_rxval;
wire        usb_rxrdy;
reg  [7:0]  rst_cnt;
wire [3:0]  endpt_sel;
wire        setup_active;
wire        setup_val;
wire [7:0]  setup_data;
wire        fclk_480M;

wire [9:0]  DESCROM_RADDR       ;
wire [7:0]  DESCROM_RDAT        ;
wire [9:0]  DESC_DEV_ADDR       ;
wire [7:0]  DESC_DEV_LEN        ;
wire [9:0]  DESC_QUAL_ADDR      ;
wire [7:0]  DESC_QUAL_LEN       ;
wire [9:0]  DESC_FSCFG_ADDR     ;
wire [7:0]  DESC_FSCFG_LEN      ;
wire [9:0]  DESC_HSCFG_ADDR     ;
wire [7:0]  DESC_HSCFG_LEN      ;
wire [9:0]  DESC_OSCFG_ADDR     ;
wire [9:0]  DESC_STRLANG_ADDR   ;
wire [9:0]  DESC_STRVENDOR_ADDR ;
wire [7:0]  DESC_STRVENDOR_LEN  ;
wire [9:0]  DESC_STRPRODUCT_ADDR;
wire [7:0]  DESC_STRPRODUCT_LEN ;
wire [9:0]  DESC_STRSERIAL_ADDR ;
wire [7:0]  DESC_STRSERIAL_LEN  ;
wire        DESCROM_HAVE_STRINGS;
wire        RESET_IN;


//==============================================================
//======Reset
assign RESET_IN = rst_cnt<32;
always@(posedge PHY_CLKOUT, negedge RESET_N) begin
    if (!RESET_N) begin
        rst_cnt <= 8'd0;
    end
    else if (rst_cnt <= 32) begin
        rst_cnt <= rst_cnt + 8'd1;
    end
end


reg [7:0] dect;
always@(posedge PHY_CLKOUT, negedge RESET_N) begin
    if (!RESET_N) begin
         dect <= 'd0;
    end
    else begin
        if (PHY_TXVALID) begin
            dect <= 'd0;
        end
        else begin
            dect <= dect + 1'd1;
        end
    end
end

//==============================================================
//======UVC Frame Data

// reg  [11:0] txdat_len;
wire [11:0] uvc_txlen;
wire [7:0] frame_data;





wire fifo_afull;
wire fifo_aempty;
wire [7:0]  fifo_rdat;
wire [11:0] fifo_wnum;
frame u_frame
(
     .CLK_I       (PHY_CLKOUT   )      //clock
    ,.RST_I       (RESET_IN     )      //reset
    ,.FIFO_AFULL_I(fifo_afull   )      //
    ,.FIFO_EMPTY_I(fifo_empty   )      //
    ,.SOF_I       (usb_sof      )      //
    ,.DATA_READY_I(vfb_rdy      )
    ,.DATA_O      (frame_data   )      //
    ,.DVAL_O      (frame_dval   )      //
    ,.VS_O        (vfb_vs       )
    ,.PIXEL_REQ_O (vfb_re       )
    ,.DATA_I      (vfb_data_in  )
);

fifo_sc_top u_fifo_sc_top(
     .Clk         (PHY_CLKOUT) //input Clk
    ,.Reset       (RESET_IN  ) //input Reset
    ,.WrEn        (frame_dval) //input WrEn
    ,.Data        (frame_data) //input [7:0] Data
    ,.RdEn        (usb_txact&usb_txpop&(endpt_sel==4'd2)) //input RdEn
    ,.Q           (fifo_rdat) //output [7:0] Q
    ,.Wnum        (fifo_wnum) //output [11:0] Wnum
    ,.Almost_Empty(fifo_aempty) //output Almost_Empty
    ,.Almost_Full (fifo_afull) //output Almost_Full
    ,.Empty       (fifo_empty) //output Empty
    ,.Full        (Full) //output Full
);


reg txact_d0;
reg txact_d1;
wire txact_rise;
assign txact_rise = txact_d0&(~txact_d1);
assign txact_fall = txact_d1&(~txact_d0);
always@(posedge PHY_CLKOUT, posedge RESET_IN) begin
    if (RESET_IN) begin
        txact_d0 <= 1'b0;
        txact_d1 <= 1'b0;
    end
    else begin
        txact_d0 <= usb_txact;
        txact_d1 <= txact_d0;
    end
end
reg sof_d0;
reg sof_d1;
wire sof_rise;
assign sof_rise = sof_d0&(~sof_d1);
always@(posedge PHY_CLKOUT, posedge RESET_IN) begin
    if (RESET_IN) begin
        sof_d0 <= 1'b0;
        sof_d1 <= 1'b0;
    end
    else begin
        sof_d0 <= usb_sof;
        sof_d1 <= sof_d0;
    end
end
reg [15:0] in_cnt;
reg [15:0] sof_cnt;
always@(posedge PHY_CLKOUT, posedge RESET_IN) begin
    if (RESET_IN) begin
        in_cnt <= 16'd0;
        sof_cnt <= 16'd0;
    end
    else begin
        if (sof_rise) begin
            in_cnt <= 16'd0;
            if (sof_cnt>=16'd3) begin
                sof_cnt <= 16'd0;
            end
            else begin
                sof_cnt <= sof_cnt + 16'd1;
            end
        end
        else if (txact_rise&(endpt_sel == 4'd2)) begin
            in_cnt <= in_cnt + 16'd1;
        end
    end
end


reg phy_txvalid_d0;
reg phy_txvalid_d1;
wire phy_txvalid_rise;
assign  phy_txvalid_rise = phy_txvalid_d0&(!phy_txvalid_d1);
always@(posedge PHY_CLKOUT, posedge RESET_IN) begin
    if (RESET_IN) begin
        phy_txvalid_d0 <= 1'b0;
        phy_txvalid_d1 <= 1'b0;
    end
    else begin
        phy_txvalid_d0 <=  PHY_TXVALID;
        phy_txvalid_d1 <= phy_txvalid_d0;
    end
end
reg [15:0] sof_dly_cnt;
wire tx_dual_flag;
always@(posedge PHY_CLKOUT, posedge RESET_IN) begin
    if (RESET_IN) begin
        sof_dly_cnt <= 16'd0;
    end
    else begin
        if (sof_rise) begin
            sof_dly_cnt <= 16'd0;
        end
        else  begin
            sof_dly_cnt <= sof_dly_cnt + 16'd1;
        end
    end
end

reg [7:0] txvalid_cnt;
reg [15:0] tx_width_cnt;
reg [3:0] iso_pid_data;
// wire tx_dual_flag;
always@(posedge PHY_CLKOUT, posedge RESET_IN) begin
    if (RESET_IN) begin
        txvalid_cnt <= 8'd0;
        tx_width_cnt <= 16'd0;
    end
    else begin
        if (txact_fall&&(endpt_sel==4'd2)) begin
            tx_width_cnt <= 16'd0;
        end
        else if (usb_txact&&(endpt_sel==4'd2)) begin
            tx_width_cnt <= 16'd0;
        end
        else begin
            if (iso_pid_data == 4'b1011) begin
                tx_width_cnt <= tx_width_cnt + 16'd1;
            end
        end
    end
end
assign tx_dual_flag = (tx_width_cnt>350)&fifo_afull;




always@(posedge PHY_CLKOUT, posedge RESET_IN) begin
    if (RESET_IN) begin
        txdat_len <= 12'd34;
        usb_txcork <= 1'b0;
    end
    else if (usb_txact) begin
        if (endpt_sel == 0) begin
            //txdat_len <= 12'd34; //Read FIFO Data Bytes Count
            txdat_len <= 12'd0; //Read FIFO Data Bytes Count
        end
        else begin
            txdat_len <= txdat_len;
        end
    end
    else begin
        if (endpt_sel == 0) begin
            txdat_len <= 12'd34; //Read FIFO Data Bytes Count
            usb_txcork <= 1'b0;
        end
        //else if ((endpt_sel == 4'd2)&&(in_cnt == 16'd0)) begin
        else if (endpt_sel == 4'd2) begin
            //if (fifo_aempty&frame_dval) begin
            if (fifo_afull) begin
                txdat_len <= 12'd1024;
                //txdat_len <= 12'd52;//fifo_wnum;
                //txdat_len <= fifo_wnum;
                usb_txcork <= 1'b0;
            end
            else begin
                if (frame_dval) begin
                    usb_txcork <= 1'b1;
                    txdat_len <= 12'd0;
                end
                else if (fifo_empty) begin
                    usb_txcork <= 1'b1;
                    txdat_len <= 12'd0;
                end
                else if (fifo_aempty) begin
                    usb_txcork <= 1'b0;
                    txdat_len <= fifo_wnum;
                end
                else begin
                    usb_txcork <= 1'b0;
                    txdat_len <= 12'd1024;//fifo_wnum;
                end
            end
        end
        else begin
            txdat_len <= 12'd0;
            usb_txcork <= 1'b1;
        end
    end
end

`define ENDPT1_ISO_HB
`define ENDPT2_ISO_HB
`define ENDPT3_ISO_HB
`define ENDPT4_ISO_HB
`define ENDPT5_ISO_HB
`define ENDPT6_ISO_HB
`define ENDPT7_ISO_HB
`define ENDPT8_ISO_HB
`define ENDPT9_ISO_HB
`define ENDPT10_ISO_HB
`define ENDPT11_ISO_HB
`define ENDPT12_ISO_HB
`define ENDPT13_ISO_HB
`define ENDPT14_ISO_HB
`define ENDPT15_ISO_HB
`define MFRAME_PACKETS3
`define HSSUPPORT
//`define MFRAME_PACKETS2
always @(posedge PHY_CLKOUT /*or posedge s_reset*/) begin
    if(RESET_IN) begin
        `ifdef HSSUPPORT
            `ifdef MFRAME_PACKETS3
                iso_pid_data <= 4'b0111;//DATA2
            `elsif MFRAME_PACKETS2
                iso_pid_data <= 4'b1011;//DATA1
            `else
                iso_pid_data <= 4'b0011;//DATA1
            `endif
        `else
            iso_pid_data <= 4'b0011;//DATA0
        `endif
    end
    else begin
        `ifdef HSSUPPORT
            `ifdef MFRAME_PACKETS3
                if (usb_sof) begin
                    if (fifo_afull) begin
                        iso_pid_data <= 4'b0111;//DATA2
                    end
                    else if (fifo_aempty) begin
                        iso_pid_data <= 4'b0011;//DATA0
                    end
                    else begin
                        iso_pid_data <= 4'b1011;//DATA1
                    end
                    //iso_pid_data <= 4'b0111;//DATA2
                end
                else if (txact_fall&&(endpt_sel==4'd2)) begin
                    iso_pid_data <= (iso_pid_data == 4'b0111) ? 4'b1011 : ((iso_pid_data == 4'b1011) ? 4'b0011 : iso_pid_data);//DATA2(0111) -> DATA1(1011) -> DATA0(0011)
                end
            `elsif MFRAME_PACKETS2
                if (usb_sof) begin
                    //if (fifo_afull) begin
                    //    iso_pid_data <= 4'b0111;//DATA2
                    //end
                    //else if (fifo_aempty) begin
                    //    iso_pid_data <= 4'b0011;//DATA0
                    //end
                    //else begin
                    //    iso_pid_data <= 4'b1011;//DATA1
                    //end
                    iso_pid_data <= 4'b0111;//DATA2
                end
                else if (txact_fall&&(endpt_sel==4'd2)) begin
                    iso_pid_data <= (iso_pid_data == 4'b1011) ? 4'b0011 : iso_pid_data;//DATA1(1011) -> DATA0(0011)
                end
            `else
                iso_pid_data <= 4'b0011;//DATA0
            `endif
        `else
            iso_pid_data <= 4'b0011;//DATA0
        `endif
    end
end

//==============================================================
//======Interface Setting
wire [7:0] interface_alter_i;
wire [7:0] interface_alter_o;
wire [7:0] interface_sel;
wire       interface_update;

reg [7:0] interface0_alter;
reg [7:0] interface1_alter;
assign interface_alter_i = (interface_sel == 0) ?  interface0_alter :
                           (interface_sel == 1) ?  interface1_alter : 8'd0;
always@(posedge PHY_CLKOUT, posedge RESET_IN   ) begin
    if (RESET_IN) begin
        interface0_alter <= 'd0;
        interface1_alter <= 'd0;
    end
    else begin
        if (interface_update) begin
            if (interface_sel == 0) begin
                interface0_alter <= interface_alter_o;
            end
            else if (interface_sel == 1) begin
                interface1_alter <= interface_alter_o;
            end
        end
    end
end

USB_Device_Controller_Top u_usb_device_controller_top (
    .clk_i                 (PHY_CLKOUT          )
   ,.reset_i               (RESET_IN            )
   ,.usbrst_o              (usb_busreset        )
   ,.highspeed_o           (usb_highspeed       )
   ,.suspend_o             (usb_suspend         )
   ,.online_o              (usb_online          )
   //,.iso_pid_i           (usb_iso_pid           )//
   ,.txdat_i             (usb_txdat           )//
   ,.txval_i             (usb_txval           )//endpt0_send
   ,.txdat_len_i         (txdat_len           )//
   ,.txiso_pid_i         (iso_pid_data        )//
   ,.txcork_i            (usb_txcork          )//usb_txcork
   ,.txpop_o             (usb_txpop           )
   ,.txact_o             (usb_txact           )
   ,.rxdat_o             (usb_rxdat           )
   ,.rxval_o             (usb_rxval           )
   ,.rxact_o             (usb_rxact           )
   ,.rxrdy_i             (1'b1                )
   ,.rxpktval_o          (rxpktval            )
   ,.setup_o             (setup_active        )
   ,.endpt_o             (endpt_sel           )
   ,.sof_o               (usb_sof             )
   ,.inf_alter_i         (interface_alter_i   )
   ,.inf_alter_o         (interface_alter_o   )
   ,.inf_sel_o           (interface_sel       )
   ,.inf_set_o           (interface_update    )
   ,.descrom_rdata_i     (DESCROM_RDAT        )
   ,.descrom_raddr_o     (DESCROM_RADDR       )
   ,.desc_dev_addr_i       (DESC_DEV_ADDR       )
   ,.desc_dev_len_i        (DESC_DEV_LEN        )
   ,.desc_qual_addr_i      (DESC_QUAL_ADDR      )
   ,.desc_qual_len_i       (DESC_QUAL_LEN       )
   ,.desc_fscfg_addr_i     (DESC_FSCFG_ADDR     )
   ,.desc_fscfg_len_i      (DESC_FSCFG_LEN      )
   ,.desc_hscfg_addr_i     (DESC_HSCFG_ADDR     )
   ,.desc_hscfg_len_i      (DESC_HSCFG_LEN      )
   ,.desc_oscfg_addr_i     (DESC_OSCFG_ADDR     )
   ,.desc_strlang_addr_i   (DESC_STRLANG_ADDR   )
   ,.desc_strvendor_addr_i (DESC_STRVENDOR_ADDR )
   ,.desc_strvendor_len_i  (DESC_STRVENDOR_LEN  )
   ,.desc_strproduct_addr_i(DESC_STRPRODUCT_ADDR)
   ,.desc_strproduct_len_i (DESC_STRPRODUCT_LEN )
   ,.desc_strserial_addr_i (DESC_STRSERIAL_ADDR )
   ,.desc_strserial_len_i  (DESC_STRSERIAL_LEN  )
   ,.desc_have_strings_i   (DESCROM_HAVE_STRINGS)

   ,.utmi_dataout_o        (PHY_DATAOUT       )
   ,.utmi_txvalid_o        (PHY_TXVALID       )
   ,.utmi_txready_i        (PHY_TXREADY       )
   ,.utmi_datain_i         (PHY_DATAIN        )
   ,.utmi_rxactive_i       (PHY_RXACTIVE      )
   ,.utmi_rxvalid_i        (PHY_RXVALID       )
   ,.utmi_rxerror_i        (PHY_RXERROR       )
   ,.utmi_linestate_i      (PHY_LINESTATE     )
   ,.utmi_opmode_o         (PHY_OPMODE        )
   ,.utmi_xcvrselect_o     (PHY_XCVRSELECT    )
   ,.utmi_termselect_o     (PHY_TERMSELECT    )
   ,.utmi_reset_o          (PHY_RESET         )
);

    
    wire [7:0] ulpi_out_w;
    wire [7:0] ulpi_in_w;

    assign ulpi_rst  = 1'b1;
    assign PHY_CLKOUT = ~ulpi_clk;


    assign ulpi_data = ulpi_dir ? 8'hz : ulpi_out_w;
    assign ulpi_in_w = ulpi_data;

    ulpi_wrapper 
    u_ulpi_wrapper(
    	.ulpi_clk60_i      (~ulpi_clk         ),
        .ulpi_rst_i        (RESET_IN          ),
        .ulpi_data_out_i   (ulpi_in_w         ),
        .ulpi_dir_i        (ulpi_dir          ),
        .ulpi_nxt_i        (ulpi_nxt          ),
        .utmi_data_out_i   (PHY_DATAOUT       ),
        .utmi_txvalid_i    (PHY_TXVALID       ),
        .utmi_op_mode_i    (PHY_OPMODE        ),
        .utmi_xcvrselect_i (PHY_XCVRSELECT    ),
        .utmi_termselect_i (PHY_TERMSELECT    ),
        .utmi_dppulldown_i (1'b0              ),
        .utmi_dmpulldown_i (1'b0              ),

        .ulpi_data_in_o    (ulpi_out_w        ),
        .ulpi_stp_o        (ulpi_stp          ),
        .utmi_data_in_o    (PHY_DATAIN        ),
        .utmi_txready_o    (PHY_TXREADY       ),
        .utmi_rxvalid_o    (PHY_RXVALID       ),
        .utmi_rxactive_o   (PHY_RXACTIVE      ),
        .utmi_rxerror_o    (PHY_RXERROR       ),
        .utmi_linestate_o  (PHY_LINESTATE     )
    );

//==============================================================
//======USB Device descriptor Demo
usb_desc
#(

         .VENDORID    (16'h33AA)//0403   08bb
        ,.PRODUCTID   (16'h0200)//6010   27c6
        ,.VERSIONBCD  (16'h0200)
        ,.HSSUPPORT   (1)
        ,.SELFPOWERED (0)
)
u_usb_desc (
         .CLK                    (PHY_CLKOUT          )
        ,.RESET                  (RESET_IN            )
        ,.i_descrom_raddr        (DESCROM_RADDR       )
        ,.o_descrom_rdat         (DESCROM_RDAT        )
        ,.o_desc_dev_addr        (DESC_DEV_ADDR       )
        ,.o_desc_dev_len         (DESC_DEV_LEN        )
        ,.o_desc_qual_addr       (DESC_QUAL_ADDR      )
        ,.o_desc_qual_len        (DESC_QUAL_LEN       )
        ,.o_desc_fscfg_addr      (DESC_FSCFG_ADDR     )
        ,.o_desc_fscfg_len       (DESC_FSCFG_LEN      )
        ,.o_desc_hscfg_addr      (DESC_HSCFG_ADDR     )
        ,.o_desc_hscfg_len       (DESC_HSCFG_LEN      )
        ,.o_desc_oscfg_addr      (DESC_OSCFG_ADDR     )
        ,.o_desc_strlang_addr    (DESC_STRLANG_ADDR   )
        ,.o_desc_strvendor_addr  (DESC_STRVENDOR_ADDR )
        ,.o_desc_strvendor_len   (DESC_STRVENDOR_LEN  )
        ,.o_desc_strproduct_addr (DESC_STRPRODUCT_ADDR)
        ,.o_desc_strproduct_len  (DESC_STRPRODUCT_LEN )
        ,.o_desc_strserial_addr  (DESC_STRSERIAL_ADDR )
        ,.o_desc_strserial_len   (DESC_STRSERIAL_LEN  )
        ,.o_descrom_have_strings (DESCROM_HAVE_STRINGS)
);

//==============================================================
//======USB SoftPHY 
    // USB2_0_SoftPHY_Top u_USB_SoftPHY_Top
    // (
    //      .clk_i            (PHY_CLKOUT    )
    //     ,.rst_i            (PHY_RESET     )
    //     ,.fclk_i           (fclk_480M     )
    //     ,.pll_locked_i     (pll_locked    )
    //     ,.utmi_data_out_i  (PHY_DATAOUT   )
    //     ,.utmi_txvalid_i   (PHY_TXVALID   )
    //     ,.utmi_op_mode_i   (PHY_OPMODE    )
    //     ,.utmi_xcvrselect_i(PHY_XCVRSELECT)
    //     ,.utmi_termselect_i(PHY_TERMSELECT)
    //     ,.utmi_data_in_o   (PHY_DATAIN    )
    //     ,.utmi_txready_o   (PHY_TXREADY   )
    //     ,.utmi_rxvalid_o   (PHY_RXVALID   )
    //     ,.utmi_rxactive_o  (PHY_RXACTIVE  )
    //     ,.utmi_rxerror_o   (PHY_RXERROR   )
    //     ,.utmi_linestate_o (PHY_LINESTATE )
    //     ,.usb_dxp_io        (usb_dxp_io   )
    //     ,.usb_dxn_io        (usb_dxn_io   )
    //     ,.usb_rxdp_i        (usb_rxdp_i   )
    //     ,.usb_rxdn_i        (usb_rxdn_i   )
    //     ,.usb_pullup_en_o   (usb_pullup_en_o)
    //     ,.usb_term_dp_io    (usb_term_dp_io)
    //     ,.usb_term_dn_io    (usb_term_dn_io)
    // );




reg  [15:0] bmHint                  ;//short
reg  [ 7:0] bFormatIndex            ;//char
reg  [ 7:0] bFrameIndex             ;//char
reg  [31:0] dwFrameInterval         ;//int
reg  [15:0] wKeyFrameRate           ;//short
reg  [15:0] wPFrameRate             ;//short
reg  [15:0] wCompQuality            ;//short
reg  [15:0] wCompWindowSize         ;//short
reg  [15:0] wDelay                  ;//short
reg  [31:0] dwMaxVideoFrameSize     ;//int
reg  [31:0] dwMaxPayloadTransferSize;//int
reg  [31:0] dwClockFrequency        ;//int
reg  [ 7:0] bmFramingInfo           ;//char
reg  [ 7:0] bPreferedVersion        ;//char
reg  [ 7:0] bMinVersion             ;//char
reg  [ 7:0] bMaxVersion             ;//char
reg  [ 7:0] bmRequestType; ///< Specifies direction of dataflow, type of rquest and recipient
reg  [ 7:0] bRequest     ; ///< Specifies the request
reg  [15:0] wValue       ; ///< Host can use this to pass info to the device in its own way
reg  [15:0] wIndex       ; ///< Typically used to pass index/offset such as interface or EP no
reg  [15:0] wLength      ; ///< Number of data bytes in the data stage (for Host -> Device this this is exact count, for Dev->Host is a max)
reg  [ 7:0] sub_stage    ;
reg  [ 7:0] stage        ;
reg  [ 7:0] endpt0_dat   ;
reg         endpt0_send  ;
always @(posedge PHY_CLKOUT,posedge RESET_IN) begin
    if (RESET_IN) begin
        stage <= 8'd0;
        sub_stage <= 8'd0;
        endpt0_send <= 1'd0;
        endpt0_dat  <= 8'd0;
        bmRequestType <= 8'd0;
        bRequest      <= 8'd0;
        wValue        <= 16'd0;
        wIndex        <= 16'd0;
        wLength       <= 16'd0;
        bmHint                   <= 0;
        bFormatIndex             <= 8'h01;
        bFrameIndex              <= 8'h01;
        dwFrameInterval          <= `FRAME_INTERVAL;//`FRAME_INTERVAL;
        wKeyFrameRate            <= 0;
        wPFrameRate              <= 0;
        wCompQuality             <= 0;
        wCompWindowSize          <= 0;
        wDelay                   <= 0;
        dwMaxVideoFrameSize      <= `MAX_FRAME_SIZE;
        dwMaxPayloadTransferSize <= `PAYLOAD_SIZE;//`PAYLOAD_SIZE;
        dwClockFrequency         <= 60000000;
        bmFramingInfo            <= 0;
        bPreferedVersion         <= 0;
        bMinVersion              <= 0;
        bMaxVersion              <= 0;
    end
    else begin
        if (setup_active) begin
            if (usb_rxval) begin
                case (stage)
                    8'd0 : begin
                        bmRequestType <= usb_rxdat;
                        stage <= stage + 8'd1;
                        sub_stage <= 8'd0;
                        endpt0_send <= 1'd0;
                    end
                    8'd1 : begin
                        bRequest <= usb_rxdat;
                        stage <= stage + 8'd1;
                    end
                    8'd2 : begin
                        wValue[7:0] <= usb_rxdat;
                        stage <= stage + 8'd1;
                    end
                    8'd3 : begin
                        wValue[15:8] <= usb_rxdat;
                        stage <= stage + 8'd1;
                    end
                    8'd4 : begin
                        stage <= stage + 8'd1;
                        wIndex[7:0] <= usb_rxdat;
                    end
                    8'd5 : begin
                        stage <= stage + 8'd1;
                        wIndex[15:8] <= usb_rxdat;
                    end
                    8'd6 : begin
                        if ((bRequest == `GET_CUR)||(bRequest == `GET_DEF)) begin
                        //if ((bRequest == `SET_CUR)||(bRequest == `GET_CUR)||(bRequest == `GET_DEF)) begin
                            if (wIndex[7:0] == 8'h01) begin //Video Steam Interface
                                if (wValue[15:8] == `VS_PROBE_CONTROL) begin
                                    endpt0_send <= 1'd1;
                                end
                            end
                        end
                        wLength[7:0] <= usb_rxdat;
                        stage <= stage + 8'd1;
                    end
                    8'd7 : begin
                        wLength[15:8] <= usb_rxdat;
                        stage <= stage + 8'd1;
                        sub_stage <= 8'd0;
                    end
                    8'd8 : begin
                        ;
                    end
                endcase
            end
        end
        else if (bRequest == `SET_CUR) begin
            stage <= 8'd0;
            if (wIndex[7:0] == 8'h01) begin
                if (wValue[15:8] == `VS_PROBE_CONTROL) begin
                    if ((usb_rxact)&&(endpt_sel == 4'd0)) begin
                        if (usb_rxval) begin
                            sub_stage <= sub_stage + 8'd1;
                            case (sub_stage)
                                8'd0 :
                                    bmHint[7:0] <= usb_rxdat;
                                8'd1 :
                                    bmHint[15:8] <= usb_rxdat;
                                8'd2 :
                                    bFormatIndex[7:0] <= usb_rxdat;
                                8'd3 :
                                    bFrameIndex[7:0] <= usb_rxdat;
                                8'd4 :
                                    dwFrameInterval[7:0]  <= usb_rxdat;
                                8'd5 :
                                    dwFrameInterval[15:8] <= usb_rxdat;
                                8'd6 :
                                    dwFrameInterval[23:16] <= usb_rxdat;
                                8'd7 :
                                    dwFrameInterval[31:24] <= usb_rxdat;
                                8'd8 :
                                    wKeyFrameRate[7:0] <= usb_rxdat;
                                8'd9 :
                                    wKeyFrameRate[15:8] <= usb_rxdat;
                                8'd10 :
                                    wPFrameRate[7:0] <= usb_rxdat;
                                8'd11 :
                                    wPFrameRate[15:8]<= usb_rxdat;
                                8'd12 :
                                    wCompQuality[7:0] <= usb_rxdat;
                                8'd13 :
                                    wCompQuality[15:8] <= usb_rxdat;
                                8'd14 :
                                    wCompWindowSize[7:0] <= usb_rxdat;
                                8'd15 :
                                    wCompWindowSize[15:8] <= usb_rxdat;
                                8'd16 :
                                    wDelay[7:0] <= usb_rxdat;
                                8'd17 :
                                    wDelay[15:8] <= usb_rxdat;
                                8'd18 :
                                    dwMaxVideoFrameSize[7:0]  <= usb_rxdat;
                                8'd19 :
                                    dwMaxVideoFrameSize[15:8] <= usb_rxdat;
                                8'd20 :
                                    dwMaxVideoFrameSize[23:16] <= usb_rxdat;
                                8'd21 :
                                    dwMaxVideoFrameSize[31:24] <= usb_rxdat;
                                8'd22 :
                                    ;//dwMaxPayloadTransferSize[7:0]  <= usb_rxdat;
                                8'd23 :
                                    ;//dwMaxPayloadTransferSize[15:8] <= usb_rxdat;
                                8'd24 :
                                    ;//dwMaxPayloadTransferSize[23:16] <= usb_rxdat;
                                8'd25 :
                                    ;//dwMaxPayloadTransferSize[31:24] <= usb_rxdat;
                                8'd26 :
                                    dwClockFrequency[7:0]  <= usb_rxdat;
                                8'd27 :
                                    dwClockFrequency[15:8] <= usb_rxdat;
                                8'd28 :
                                    dwClockFrequency[23:16] <= usb_rxdat;
                                8'd29 :
                                    dwClockFrequency[31:24] <= usb_rxdat;
                                8'd30 :
                                    bmFramingInfo[7:0] <= usb_rxdat;
                                8'd31 :
                                    bPreferedVersion[7:0] <= usb_rxdat;
                                8'd32 :
                                    bMinVersion[7:0] <= usb_rxdat;
                                8'd33 :
                                    bMaxVersion[7:0] <= usb_rxdat;
                                default : ;
                            endcase
                        end
                    end
                    else begin
                        sub_stage <= 8'd0;
                    end
                end
            end
        end
        //else if ((bRequest == `SET_CUR)||(bRequest == `GET_CUR)||(bRequest == `GET_DEF)) begin
        else if ((bRequest == `GET_CUR)||(bRequest == `GET_DEF)) begin
            stage <= 8'd0;
            if (wIndex[7:0] == 8'h01) begin
                if (wValue[15:8] == `VS_PROBE_CONTROL) begin
                    if ((usb_txact)&&(endpt_sel == 4'd0)) begin
                        if (endpt0_send == 1'b1) begin
                            if (usb_txpop) begin
                                sub_stage <= sub_stage + 8'd1;
                                if (sub_stage == 12'd33) begin
                                    endpt0_send <= 1'd0;
                                end
                                case (sub_stage)
                                    8'd0 :
                                        endpt0_dat <= bmHint[15:8];
                                    8'd1 :
                                        endpt0_dat <= bFormatIndex[7:0];
                                    8'd2 :
                                        endpt0_dat <= bFrameIndex[7:0];
                                    8'd3 :
                                        endpt0_dat <= dwFrameInterval[7:0];
                                    8'd4 :
                                        endpt0_dat <= dwFrameInterval[15:8];
                                    8'd5 :
                                        endpt0_dat <= dwFrameInterval[23:16];
                                    8'd6 :
                                        endpt0_dat <= dwFrameInterval[31:24];
                                    8'd7 :
                                        endpt0_dat <= wKeyFrameRate[7:0];
                                    8'd8 :
                                        endpt0_dat <= wKeyFrameRate[15:8];
                                    8'd9 :
                                        endpt0_dat <= wPFrameRate[7:0];
                                    8'd10 :
                                        endpt0_dat <= wPFrameRate[15:8];
                                    8'd11 :
                                        endpt0_dat <= wCompQuality[7:0];
                                    8'd12 :
                                        endpt0_dat <= wCompQuality[15:8];
                                    8'd13 :
                                        endpt0_dat <= wCompWindowSize[7:0];
                                    8'd14 :
                                        endpt0_dat <= wCompWindowSize[15:8];
                                    8'd15 :
                                        endpt0_dat <= wDelay[7:0];
                                    8'd16 :
                                        endpt0_dat <= wDelay[15:8];
                                    8'd17 :
                                        endpt0_dat <= dwMaxVideoFrameSize[7:0];
                                    8'd18 :
                                        endpt0_dat <= dwMaxVideoFrameSize[15:8];
                                    8'd19 :
                                        endpt0_dat <= dwMaxVideoFrameSize[23:16];
                                    8'd20 :
                                        endpt0_dat <= dwMaxVideoFrameSize[31:24];
                                    8'd21 :
                                        endpt0_dat <= dwMaxPayloadTransferSize[7:0];
                                    8'd22 :
                                        endpt0_dat <= dwMaxPayloadTransferSize[15:8];
                                    8'd23 :
                                        endpt0_dat <= dwMaxPayloadTransferSize[23:16];
                                    8'd24 :
                                        endpt0_dat <= dwMaxPayloadTransferSize[31:24];
                                    8'd25 :
                                        endpt0_dat <= dwClockFrequency[7:0];
                                    8'd26 :
                                        endpt0_dat <= dwClockFrequency[15:8];
                                    8'd27 :
                                        endpt0_dat <= dwClockFrequency[23:16];
                                    8'd28 :
                                        endpt0_dat <= dwClockFrequency[31:24];
                                    8'd29 :
                                        endpt0_dat <= bmFramingInfo[7:0];
                                    8'd30 :
                                        endpt0_dat <= bPreferedVersion[7:0];
                                    8'd31 :
                                        endpt0_dat <= bMinVersion[7:0];
                                    8'd32 :
                                        endpt0_dat <=  bMaxVersion[7:0];
                                    default : ;
                                endcase
                            end
                            else if (sub_stage == 8'd0) begin
                                endpt0_dat <= bmHint[7:0];
                            end
                        end
                    end
                    else begin
                        sub_stage <= 8'd0;
                    end
                end
            end
        end
        else begin
             stage <= 8'd0;
             sub_stage <= 8'd0;
        end
    end
end


assign usb_txdat = (endpt_sel == 4'd0) ? endpt0_dat[7:0] : fifo_rdat[7:0];
//assign usb_txcork = (endpt_sel == 4'd1) ? 1'b1 : 1'b0;
assign usb_txval = (endpt_sel == 4'd0) ? endpt0_send : 1'b0;


endmodule

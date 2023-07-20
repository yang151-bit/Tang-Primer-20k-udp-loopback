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
`include "uvc_defs.v"
module frame
(
    input              CLK_I     ,       //clock
    input              RST_I     ,       //reset
    input              FIFO_AFULL_I,     //
    input              FIFO_EMPTY_I,     //
    input              SOF_I     ,       //
    input  [23:0]      DATA_I    ,
    output [7:0]       DATA_O    ,       //
    output             DVAL_O    ,       //
    output             VS_O      ,
    output             PIXEL_REQ_O

);

localparam HERADER_LEN = 12;
localparam WIDTH  = `WIDTH ;//480;
localparam HEIGHT = `HEIGHT;//20;//320;
localparam PAYLOAD_SIZE = `PAYLOAD_SIZE;
localparam FRAME_SIZE = WIDTH * HEIGHT * 2;

//==============================================================
//======Header Generate
reg sof_d0;
reg sof_d1;
wire sof_rise;


always @(posedge CLK_I or posedge RST_I) begin
    if (RST_I) begin
        sof_d0 <= 1'b0;
        sof_d1 <= 1'b0;
    end
    else begin
        sof_d0 <= SOF_I;
        sof_d1 <= sof_d0;
    end
end
assign sof_rise = (sof_d0)&(~sof_d1);


reg [10:0] sofCounts;
reg [10:0] sofCounts_reg;
reg [3:0] sof_1ms;
always @(posedge CLK_I or posedge RST_I) begin
    if (RST_I) begin
        sofCounts <= 11'd0;
        sof_1ms <= 4'd0;
    end
    else begin
        if (sof_rise) begin
            if (sof_1ms >= 4'd7) begin
                sof_1ms <= 4'd0;
            end
            else begin
                sof_1ms <= sof_1ms + 4'd1;
            end
        end
        if ((sof_rise)&&(sof_1ms == 3'd7)) begin
            sofCounts <= sofCounts + 'd1;
        end
    end
end

reg [31:0] pts;
reg [31:0] pts_reg;
always @(posedge CLK_I or posedge RST_I) begin
    if (RST_I) begin
        pts <= 32'd0;
    end
    else begin
        pts <= pts + 32'd1;
    end
end

//==============================================================
//======Frame Start and Over
reg [7:0] frame;
reg [15:0] byte_cnt;
reg [11:0] color_cnt;
reg [31:0] expectPixels;
reg frame_valid;
reg [7:0] dout;
reg       dval;
reg [15:0] sof_cnt;

assign DATA_O = dout;
assign DVAL_O = dval;
reg pixel_rd_en;
reg [7:0] moving_pixel;
always @(posedge CLK_I or posedge RST_I) begin
    if (RST_I) begin
        frame_valid <= 1'b0;
        dout <= 8'd0;
        dval <= 1'd0;
        byte_cnt <= 16'd0;
        color_cnt <= 12'd0;
        expectPixels <= 32'd0;
        frame <= 8'h0C;
        pts_reg <= 32'd0;
        sofCounts_reg <= 11'd0;
        moving_pixel <= 8'd0;
        pixel_rd_en <= 0;
    end
    else begin
        if (frame_valid) begin
            if(FIFO_AFULL_I == 1'b0) begin
                dval <= 1'b1;
                if (byte_cnt == PAYLOAD_SIZE - 1'b1) begin
                    pixel_rd_en <= 0;
                    byte_cnt <= 16'd0;
                end
                else begin
                    byte_cnt <= byte_cnt + 16'd1;
                end
                if(byte_cnt == 16'd11)
                    pixel_rd_en <= 1;
                
                case (byte_cnt)
                    16'd0 : dout <= HERADER_LEN;
                    16'd1 : 
                        if (expectPixels >= FRAME_SIZE - PAYLOAD_SIZE - 12 - 1'b1) begin
                            dout <= frame|8'h02;
                        end
                        else begin
                            dout <= frame;
                        end
                    16'd2 : dout <= pts_reg[7:0];     //8'hAE;//8'h11;//
                    16'd3 : dout <= pts_reg[15:8];    //8'h03;//8'h54;//
                    16'd4 : dout <= pts_reg[23:16];   //8'hB4;//8'h72;//
                    16'd5 : dout <= pts_reg[31:24];   //8'h32;//8'h9A;//
                    16'd6 : dout <= pts_reg[7:0];     //8'hAE;//8'h11;//
                    16'd7 : dout <= pts_reg[15:8];    //8'h03;//8'h54;//
                    16'd8 : dout <= pts_reg[23:16];   //8'hB4;//8'h72;//
                    16'd9 : dout <= pts_reg[31:24];   //8'h32;//8'h9A;//
                    16'd10 : dout <= sofCounts[7:0];            //8'h62;//
                    16'd11 : dout <= {5'd0,sofCounts[10:8]};    //8'h07;//
                    default : begin
                        if (color_cnt >= 12'd480 - 1) begin
                            color_cnt <= 12'd0;
                        end
                        else begin
                            color_cnt <= color_cnt + 4'd1;
                        end
                        if (expectPixels >= FRAME_SIZE - 1'b1) begin
                            frame_valid <= 1'b0;
                            expectPixels <= 32'd0;
                            frame <= {frame[7:1],frame[0]^1'b1};
                        end
                        else begin
                            expectPixels <= expectPixels + 1'b1;
                        end
                        //if (expectPixels <= 480 - 1'b1) begin
                        //    dout <= 8'h1F;
                        //end
                        //else begin
                        //    dout <= 8'h1F;
                        //end
                        ///*
                        //if (1) // best case
                        ////if (byte_cnt<1024) //worst case
                        ////if (byte_cnt<16) //The more consequitive ones there are the more times txready will go low causing the buffer to hold data
                        //   dout <= 8'hFF;
                        //else
                        //   dout <= 0;
                            //*/
                        ///*
                        // if (color_cnt < 12'd80 - moving_pixel) begin //RED
                        //     case (byte_cnt[1:0])
                        //         2'd0 : dout <= 8'h20;
                        //         2'd1 : dout <= 8'h60;
                        //         2'd2 : dout <= 8'h20;
                        //         2'd3 : dout <= 8'hDC;
                        //     endcase
                        // end
                        // else if (color_cnt < 12'd160 - moving_pixel) begin //GREEN
                        //     case (byte_cnt[1:0])
                        //         2'd0 : dout <= 8'h00;//20;//
                        //         2'd1 : dout <= 8'h00;//60;//
                        //         2'd2 : dout <= 8'h00;//20;//
                        //         2'd3 : dout <= 8'h00;//DC;//
                        //     endcase
                        // end
                        // else if (color_cnt < 12'd240 - moving_pixel) begin //BLUE
                        //     case (byte_cnt[1:0])
                        //         2'd0 : dout <= 8'h10;//20;//
                        //         2'd1 : dout <= 8'hD0;//60;//
                        //         2'd2 : dout <= 8'h10;//20;//
                        //         2'd3 : dout <= 8'h70;//DC;//
                        //     endcase
                        // end
                        // else if (color_cnt < 12'd320 - moving_pixel) begin //RED
                        //     case (byte_cnt[1:0])
                        //         2'd0 : dout <= 8'h20;//20;//
                        //         2'd1 : dout <= 8'h60;//60;//
                        //         2'd2 : dout <= 8'h20;//20;//
                        //         2'd3 : dout <= 8'hDC;//DC;//
                        //     endcase
                        // end
                        // else if (color_cnt < 12'd400 - moving_pixel) begin //GREEN
                        //     case (byte_cnt[1:0])
                        //         2'd0 : dout <= 8'h00;//20;//
                        //         2'd1 : dout <= 8'h00;//60;//
                        //         2'd2 : dout <= 8'h00;//20;//
                        //         2'd3 : dout <= 8'h00;//DC;//
                        //     endcase
                        // end
                        // else if (color_cnt < 12'd480 - moving_pixel) begin //BLUE
                        //     case (byte_cnt[1:0])
                        //         2'd0 : dout <= 8'h10;//20;//
                        //         2'd1 : dout <= 8'hD0;//60;//
                        //         2'd2 : dout <= 8'h10;//20;//
                        //         2'd3 : dout <= 8'h70;//DC;//
                        //     endcase
                        // end
                        // else begin
                        //     case (byte_cnt[1:0])
                        //         2'd0 : dout <= 8'h20;
                        //         2'd1 : dout <= 8'h60;
                        //         2'd2 : dout <= 8'h20;
                        //         2'd3 : dout <= 8'hDC;
                        //     endcase
                        // end
                        //*/
                        case (byte_cnt[1:0])
                            2'd0 : dout <= DATA_I[23:16];
                            2'd1 : dout <= DATA_I[15:8];
                            2'd2 : dout <= DATA_I[23:16];
                            2'd3 : dout <= DATA_I[7:0];
                        endcase

                    end
                endcase
            end
            else begin
                dval <= 1'b0;
            end
        end
        else if ((sof_cnt == 16'd0)&&(sof_rise)) begin
            if (FIFO_EMPTY_I) begin
                if (color_cnt >= 480) begin
                    color_cnt <= 12'd4;
                end
                else if (color_cnt >= 476) begin
                    color_cnt <= 12'd0;
                end
                else begin
                    color_cnt <= color_cnt + 12'd4;
                end
                frame_valid <= 1'b1;
                pixel_rd_en <= 0;
                pts_reg <= pts;
                sofCounts_reg <= sofCounts;
            end
            byte_cnt <= 16'd0;
            //color_cnt <= 4'd0;
            expectPixels <= 32'd0;
            dout <= 8'd0;
            dval <= 1'd0;
        end
        else begin
            byte_cnt <= 16'd0;
            //color_cnt <= 4'd0;
            expectPixels <= 32'd0;
            dout <= 8'd0;
            dval <= 1'd0;
        end
    end
end

assign PIXEL_REQ_O = pixel_rd_en && byte_cnt[0] && ~FIFO_AFULL_I;

//==============================================================
//======microframe control frame rate
always @(posedge CLK_I or posedge RST_I) begin
    if (RST_I) begin
        sof_cnt <= 16'd0;
    end
    else begin
        if (sof_rise) begin
            if (sof_cnt >= 103) begin
                sof_cnt <= 16'd0;
            end
            else begin
                sof_cnt <= sof_cnt + 16'd1;
            end
        end
    end
end

assign VS_O = frame_valid;


//==============================================================
//==============================================================
//==============================================================
//==============================================================
//==============================================================













endmodule





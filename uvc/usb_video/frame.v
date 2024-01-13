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
    input              DATA_READY_I    ,
    output             PIXEL_REQ_O,

    output [7:0]       FRAME_O   ,
    output [31:0]      PTS_O

);

localparam HERADER_LEN = 12;
localparam WIDTH  = `WIDTH ;//480;
localparam HEIGHT = `HEIGHT;//20;//320;
localparam PAYLOAD_SIZE = `PAYLOAD_SIZE;
localparam PACKET_SIZE = `PACKET_SIZE;
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
reg [7:0] frame_r;
reg [15:0] byte_cnt;
reg [31:0] expectPixels;
reg frame_valid;
reg [7:0] dout;
reg       dval;
reg pkt_end;

assign FRAME_O = pkt_end ? frame_r | 8'h02 : frame_r;
assign PTS_O   = pts_reg;

always @(posedge CLK_I or posedge RST_I) begin
    if(RST_I)
        pkt_end <= 0;
    else if(FIFO_EMPTY_I && sof_rise)
        pkt_end <= 0;
    else if(expectPixels == FRAME_SIZE - PACKET_SIZE - 1'b1)
        pkt_end <= 1;
end

assign DATA_O = dout;
assign DVAL_O = dval;

reg pixel_req_r1, pixel_req_r2;
wire pixel_val;
assign pixel_val = pixel_req_r1 | pixel_req_r2;

always @(posedge CLK_I) begin
    if(byte_cnt == 16'd11)begin
        pixel_req_r1 <= 1;
        pixel_req_r2 <= 0;
    end
    else begin
        pixel_req_r1 <= DATA_READY_I && byte_cnt[0];
        pixel_req_r2 <= pixel_req_r1;
    end
end

always @(posedge CLK_I or posedge RST_I) begin
    if (RST_I) begin
        frame_valid <= 1'b0;
        dout <= 8'd0;
        dval <= 1'd0;
        byte_cnt <= 16'd0;
        expectPixels <= 32'd0;
        frame_r <= 8'h0C;
        pts_reg <= 32'd0;
    end
    else begin
        if (frame_valid) begin
            if(FIFO_AFULL_I == 1'b0) begin
                dval <= 1'b1;
                
                if (byte_cnt == PAYLOAD_SIZE - 1'b1)
                    byte_cnt <= 16'd0;
                else
                    byte_cnt <= byte_cnt + 16'd1;
    
                if (expectPixels == FRAME_SIZE - 1'b1) begin
                    frame_valid <= 1'b0;
                    expectPixels <= 32'd0;
                    frame_r <= {frame_r[7:1],frame_r[0]^1'b1};
                end
                else begin
                    expectPixels <= expectPixels + 1'b1;
                end

                case (byte_cnt[1:0])
                    2'd0 : dout <= DATA_I[23:16];
                    2'd1 : dout <= DATA_I[15:8];
                    2'd2 : dout <= DATA_I[23:16];
                    2'd3 : dout <= DATA_I[7:0];
                endcase
            end
        
            else
                dval <= 1'b0;
        end
        else if (sof_rise) begin
            if (FIFO_EMPTY_I) begin
                frame_valid <= 1'b1;
                pts_reg <= pts;
            end
            byte_cnt <= 16'd0;
            expectPixels <= 32'd0;
            dout <= 8'd0;
            dval <= 1'd0;
        end
        else begin
            byte_cnt <= 16'd0;
            expectPixels <= 32'd0;
            dout <= 8'd0;
            dval <= 1'd0;
        end
    end
end

assign PIXEL_REQ_O = frame_valid && byte_cnt[0] && ~FIFO_AFULL_I;

assign VS_O = frame_valid;


//==============================================================
//==============================================================
//==============================================================
//==============================================================
//==============================================================













endmodule





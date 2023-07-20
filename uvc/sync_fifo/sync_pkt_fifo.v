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

module sync_pkt_fifo
#(
    parameter DSIZE = 8,
    parameter ASIZE = 9
)
(
    input        CLK,
    input        RSTn,
    input        write,
    input        pktval,
    input        rxact,
    input        read,
    input  [7:0] iData,
    
    output [7:0] oData,
    output [ASIZE:0] wrnum,
    output       full,
    output       empty
);

reg [ASIZE:0] wp;          //write point should add 1 bit(N+1) 
reg [ASIZE:0] wrnum;       //write point should add 1 bit(N+1) 
reg [ASIZE:0] pkg_wp;      //write point should add 1 bit(N+1) 
reg [ASIZE:0] rp;          //read point
reg [DSIZE - 1:0] RAM [0:(1<<ASIZE) - 1];  //deep 512, 8 bit RAM
reg [DSIZE - 1:0] oData_reg;   //regsiter of oData
reg [1:0] rxact_dly;
wire rxact_rise;

always @ ( posedge CLK or negedge RSTn )
begin                  //write to RAM
    if (!RSTn)
    begin
        wp <= 'd0;
    end
    else if ( rxact_rise ) begin
        wp <= pkg_wp;
    end
    else if ( write & (~full))
    begin
        RAM[wp[ASIZE - 1:0]] <= iData;
        wp <= wp + 1'b1;
    end
end

always @ ( posedge CLK or negedge RSTn )
begin                  // read from RAM
    if (!RSTn)
    begin
        rp <= 'd0;
        oData_reg <= 'd0;
    end
    else if ( read & (~empty)  )
    begin
        oData_reg <= RAM[rp[ASIZE - 1:0]];
        rp <= rp + 1'b1;
    end
end

always @ ( posedge CLK or negedge RSTn ) begin    // 
    if (!RSTn) begin
        rxact_dly <= 'd0;
    end
    else begin
        rxact_dly <= {rxact_dly[0],rxact};
    end
end
assign rxact_rise = (rxact_dly == 2'b01);

always @ ( posedge CLK or negedge RSTn ) begin    // 
    if (!RSTn) begin
        pkg_wp <= 'd0;
    end
    else if (pktval) begin
        pkg_wp <= wp;
    end
end

always @ ( posedge CLK or negedge RSTn ) begin    // 
    if (!RSTn) begin
        wrnum <= 'd0;
    end
    else begin
        //if (wp[ASIZE] == rp[ASIZE]) begin
        //end
        if (wp[ASIZE - 1 : 0] >= rp[ASIZE - 1 : 0]) begin
            wrnum <= wp[ASIZE - 1 : 0] - rp[ASIZE - 1 : 0];
        end
        else begin
            wrnum <= {1'b1,wp[ASIZE - 1 : 0]} - {1'b0,rp[ASIZE - 1 : 0]};
        end
        //if ((write & (~full)) && (read & (~empty))) begin
        //    wrnum <= wrnum;
        //end
        //else if (write & (~full)) begin
        //    wrnum <= wrnum + 1'b1;
        //end
        //else if ( read & (~empty)  ) begin
        //    wrnum <= wrnum - 1'b1;
        //end
    end
end

//assign full = ( pkg_wp[ASIZE] ^ rp[ASIZE] & pkg_wp[ASIZE - 1:0] == rp[ASIZE - 1:0] );
assign full = ( (wp[ASIZE] ^ rp[ASIZE]) & (wp[ASIZE - 1:0] == rp[ASIZE - 1:0]) );
assign empty = ( pkg_wp == rp );
assign oData = oData_reg;

endmodule

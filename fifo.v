//---------------------------------------------------------------------
// File name  : fifo.v
// Module name: fifo
// Created by :
// ---------------------------------------------------------------------
// Release history
// VERSION |  Date       | AUTHOR     |    DESCRIPTION
// ---------------------------------------------------------------------
// ---------------------------------------------------------------------
`timescale 1ns / 1ps

module fifo#(
    parameter WIDTH=4,
    parameter DEPTH=4
  ) (
      input clk,

      input [WIDTH-1:0] inp,
      output [WIDTH-1:0] outp
  )/* synthesis syn_ramstyle = "registers",  synthesis syn_srlstyle = "registers" */;
    reg [WIDTH*DEPTH -1 : 0] rams; 
    integer i;
    always @(posedge clk) begin
        for (i = 0; i < DEPTH; i = i+1)
            if(i == 0)
                rams[i*WIDTH +: WIDTH] <= inp;
            else
                rams[i*WIDTH +: WIDTH] <= rams[(i-1)*WIDTH +: WIDTH];
    end
    assign outp = rams[(DEPTH - 1)*WIDTH +: WIDTH];
endmodule
//Copyright (C)2014-2022 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//GOWIN Version: GowinSynthesis V1.9.8.09
//Part Number: GW2A-LV18PG256C8/I7
//Device: GW2A-18C
//Created Time: Thu May 25 15:57:43 2023

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

	fifo_sc_top your_instance_name(
		.Data(Data_i), //input [7:0] Data
		.Clk(Clk_i), //input Clk
		.WrEn(WrEn_i), //input WrEn
		.RdEn(RdEn_i), //input RdEn
		.Reset(Reset_i), //input Reset
		.Q(Q_o), //output [7:0] Q
		.Empty(Empty_o), //output Empty
		.Full(Full_o) //output Full
	);

//--------Copy end-------------------

//Copyright (C)2014-2023 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//GOWIN Version: 1.9.8.09 
//Created Time: 2023-05-25 16:14:07
create_clock -name rmii_clk -period 20 -waveform {0 10} [get_ports {rmii_clk}]

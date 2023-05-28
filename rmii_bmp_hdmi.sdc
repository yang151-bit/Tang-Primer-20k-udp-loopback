//Copyright (C)2014-2023 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//GOWIN Version: 1.9.8.09 
//Created Time: 2023-05-27 10:36:54
create_clock -name rmii_clk -period 20 -waveform {0 10} [get_ports {rmii_clk}]
create_clock -name memory_clk_div4 -period 10 -waveform {0 5} [get_pins {u_ddr3/gw3_top/i4/fclkdiv/CLKOUT}]
create_clock -name hdmi_clk -period 40 -waveform {0 20} [get_nets {hdmi_clk}] -add
create_clock -name sys_clk -period 37.037 -waveform {0 18.518} [get_ports {sys_clk}] -add
create_clock -name memory_clk -period 2.5 -waveform {0 1.25} [get_nets {memory_clk}] -add
set_clock_groups -asynchronous -group [get_clocks {memory_clk}] -group [get_clocks {memory_clk_div4}] -group [get_clocks {sys_clk}] -group [get_clocks {rmii_clk}] -group [get_clocks {hdmi_clk}]

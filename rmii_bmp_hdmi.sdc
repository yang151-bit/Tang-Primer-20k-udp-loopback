//Copyright (C)2014-2023 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//GOWIN Version: 1.9.9 Beta
//Created Time: 2023-10-02 20:48:11
create_clock -name rmii_clk -period 20 -waveform {0 10} [get_ports {rmii_clk}]
create_clock -name aclk -period 10 -waveform {0 5} [get_nets {aclk}]
create_clock -name ulpi_clk -period 16.667 -waveform {0 5.75} [get_ports {ulpi_clk}]
create_clock -name memory_clk -period 2.5 -waveform {0 1.25} [get_nets {memory_clk}] -add
create_clock -name sys_clk -period 37.037 -waveform {0 18.518} [get_ports {sys_clk}] -add
set_clock_latency -source 0.4 [get_clocks {ulpi_clk}] 
set_clock_groups -asynchronous -group [get_clocks {memory_clk}] -group [get_clocks {aclk}] -group [get_clocks {sys_clk}]

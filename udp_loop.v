// author:		Benjamin SMith
// create time:	2023/03/22 11:07
// edit time:	2023/03/22 16:21
// platform:	Cyclone ep4ce10f17i7, 野火 board
// module:		udp_loop
// function:	UDP loop, transform information back to server
// version:		1.0
// history:	

module udp_loop (
	input	wire						sys_rst_n,
	input   wire						sys_clk,	
	input	wire						rmii_clk,
	input	wire						rmii_rxdv,
	input	wire	[1:0]				rmii_rxdata,
	output	wire						rmii_txen,
	output	wire	[1:0]				rmii_txdata,
	output	wire						rmii_rst,
	output  wire 						mdc,
	inout   wire 						mdio
);

	wire								udp_rxstart;
	wire								udp_rxend;
	wire								udp_rxdv;
	wire	[7:0]						udp_rxdata;
	wire	[15:0]						udp_rxamount;
	wire	[15:0]						udp_rxnum;
	reg									udp_txstart;
	reg		[15:0]						udp_txamount;
	wire	[7:0]						udp_txdata;
	wire								udp_txreq;
	wire								udp_txbusy;

Gowin_rPLL u_rpll(
        .clkout(), //output clkout
        .lock(lock), //output lock
        .clkoutd(clk_mdc), //output clkoutd
        .clkin(sys_clk) //input clkin
    );

mdio_config u_mdio_config(
	.sys_clk          (clk_mdc          	),
	.sys_clk_rst_sync (~(sys_rst_n | lock)	),
	.mdc              (mdc              	),
	.mdio             (mdio             	),
	.done             (done             	)
);

wire rmii_rstn;
assign rmii_rstn = sys_rst_n & done;

eth_rmii								u1_eth_rmii (
	.sys_rst_n							( rmii_rstn		),
	.rmii_clk							( rmii_clk		),
	.rmii_rxdv							( rmii_rxdv		),
	.rmii_rxdata						( rmii_rxdata	),
	.rmii_txen							( rmii_txen		),
	.rmii_txdata						( rmii_txdata	),
	.rmii_rst							( rmii_rst		),
	.udp_rxstart						( udp_rxstart	),
	.udp_rxend							( udp_rxend		),
	.udp_rxdv							( udp_rxdv		),
	.udp_rxdata							( udp_rxdata	),
	.udp_rxamount						( udp_rxamount	),
	.udp_rxnum							( udp_rxnum		),
	.udp_txstart						( udp_txstart	),
	.udp_txamount						( udp_txamount	),
	.udp_txdata							( udp_txdata	),
	.udp_txreq							( udp_txreq		),
	.udp_txbusy							( udp_txbusy	)
);

fifo_sc_top u_fifo_sc_top(
		.Data(udp_rxdata), //input [7:0] Data
		.Clk(rmii_clk), //input Clk
		.WrEn(udp_rxdv), //input WrEn
		.RdEn(udp_txreq), //input RdEn
		.Reset(!rmii_rstn), //input Reset
		.Q(udp_txdata), //output [7:0] Q
		.Empty(), //output Empty
		.Full() //output Full
	);

// fifo_2048_d8							u2_fifo_2048_d8 (
// 	.aclr								( !sys_rst_n	),
// 	.clock								( rmii_clk		),
// 	.data								( udp_rxdata	),
// 	.rdreq								( udp_txreq		),
// 	.wrreq								( udp_rxdv		),
// 	.q									( udp_txdata	)
// );

always @ ( posedge rmii_clk or negedge rmii_rstn ) begin
	if ( !rmii_rstn ) begin
		udp_txstart <= 1'b0;
	end else if ( udp_rxend ) begin
		udp_txstart <= 1'b1;
	end else begin
		udp_txstart <= 1'b0;
	end
end

always @ ( posedge rmii_clk or negedge rmii_rstn ) begin
	if ( !rmii_rstn ) begin
		udp_txamount <= 16'd0;
	end else if ( udp_rxstart ) begin
		udp_txamount <= udp_rxamount;
	end else begin
		udp_txamount <= udp_txamount;
	end
end

endmodule
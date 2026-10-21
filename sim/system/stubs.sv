// Behavioural stand-ins for the Altera megafunctions / board pieces that the system
// simulation cannot use. Everything else in the sim is the real RTL.
`timescale 1ps/1ps

// ---- PLL: clk64 = exactly 2x clk_sys, rising edges coincide ----
// The reconfiguration is modelled: core_top writes the fractional K (register 7) and then 'start'
// (register 2) through pll_cfg; the PLL drops `locked` for 50 us and then runs at
// 74.25 MHz * (7 + K / 2^32) / 9 = clk64 (PAL K = 2762266829 -> 63.05 MHz, NTSC K = 4010993429 -> 65.45 MHz).
module pll_c64 (
	input  wire        refclk,
	input  wire        rst,
	output wire        outclk_0,   // clk48
	output wire        outclk_1,   // clk64
	output wire        outclk_2,   // clk_sys
	output wire        outclk_3,   // clk_sys_90
	output reg         locked,
	input  wire [63:0] reconfig_to_pll,
	output wire [63:0] reconfig_from_pll
);
	integer half64 = 7930;                     // ps, PAL
	integer reconfigs = 0;
	reg c64 = 0, csys = 0, c48 = 0, c90 = 0;
	assign reconfig_from_pll = 64'd0;
	assign outclk_0 = c48;
	assign outclk_1 = c64;
	assign outclk_2 = csys;
	assign outclk_3 = c90;
	initial begin
		locked = 1'b0;
		#20_000_000 locked = 1'b1;               // 20 us
	end
	// four steps per clk_sys period: clk64 rises at steps 0 and 2, clk_sys at step 0 (and
	// falls at step 2), clk_sys_90 lags clk_sys by one step
	initial begin
		forever begin
			c64 = 1; csys = 1;      #half64;
			c64 = 0; c90 = 1;       #half64;
			c64 = 1; csys = 0;      #half64;
			c64 = 0; c90 = 0;       #half64;
		end
	end
	initial forever #(half64 * 2 / 3) c48 = ~c48;
	reg start_d = 0;
	always @(reconfig_to_pll[32]) if (reconfig_to_pll[32] !== start_d) begin : rc
		real mult;
		start_d = reconfig_to_pll[32];
		reconfigs = reconfigs + 1;
		locked = 1'b0;
		#50_000_000;
		mult = 7.0 + reconfig_to_pll[31:0] / 4294967296.0;
		half64 = $rtoi(9.0e6 / (2.0 * 74.25 * mult) + 0.5);
		$display("[%0t] PLL reconfigured: K=%0d -> clk64 half period %0d ps (clk_sys %0.3f MHz)", $time, reconfig_to_pll[31:0], half64, 1.0e6 / (4.0 * half64));
		#10_000_000;
		locked = 1'b1;
	end
endmodule

module pll_cfg (
	input  wire        mgmt_clk,
	input  wire        mgmt_reset,
	output wire        mgmt_waitrequest,
	input  wire        mgmt_read,
	input  wire        mgmt_write,
	output wire [31:0] mgmt_readdata,
	input  wire [5:0]  mgmt_address,
	input  wire [31:0] mgmt_writedata,
	output wire [63:0] reconfig_to_pll,
	input  wire [63:0] reconfig_from_pll
);
	reg [31:0] k = 32'd2762266829;
	reg        start_t = 0;
	integer    n_writes = 0;
	assign mgmt_waitrequest = 1'b0;
	assign mgmt_readdata = 32'd0;
	assign reconfig_to_pll = {31'd0, start_t, k};
	always @(posedge mgmt_clk) if (mgmt_write) begin
		n_writes <= n_writes + 1;
		$display("[%0t] pll_cfg write reg %0d <= %0d", $time, mgmt_address, mgmt_writedata);
		if (mgmt_address == 6'd7) k <= mgmt_writedata;
		if (mgmt_address == 6'd2) start_t <= ~start_t;
	end
endmodule

// ---- APF data table (true dual-port RAM, one clock per port) ----
module mf_datatable (
	input  wire [7:0]  address_a,
	input  wire [7:0]  address_b,
	input  wire        clock_a,
	input  wire        clock_b,
	input  wire [31:0] data_a,
	input  wire [31:0] data_b,
	input  wire        wren_a,
	input  wire        wren_b,
	output reg  [31:0] q_a,
	output reg  [31:0] q_b
);
	reg [31:0] mem [0:255];
	integer i;
	initial for (i = 0; i < 256; i = i + 1) mem[i] = 32'd0;
	always @(posedge clock_a) begin
		if (wren_a) mem[address_a] <= data_a;
		q_a <= mem[address_a];
	end
	always @(posedge clock_b) begin
		if (wren_b) mem[address_b] <= data_b;
		q_b <= mem[address_b];
	end
endmodule

// ---- Altera altddio_out as used by sdram.v for SDRAM_CLK (width 1) ----
module altddio_out #(
	parameter extend_oe_disable = "OFF",
	parameter intended_device_family = "",
	parameter invert_output = "OFF",
	parameter lpm_hint = "",
	parameter lpm_type = "",
	parameter oe_reg = "",
	parameter power_up_high = "OFF",
	parameter width = 1
) (
	input  wire [width-1:0] datain_h,
	input  wire [width-1:0] datain_l,
	input  wire             outclock,
	output wire [width-1:0] dataout,
	input  wire             aclr,
	input  wire             aset,
	input  wire             oe,
	input  wire             outclocken,
	input  wire             sclr,
	input  wire             sset
);
	assign dataout = outclock ? datain_h : datain_l;
endmodule

// ---- Altera scfifo used by c1530's tap_fifo (showahead off, 64 x 8) ----
module scfifo #(
	parameter add_ram_output_register = "OFF",
	parameter intended_device_family = "",
	parameter lpm_numwords = 64,
	parameter lpm_showahead = "OFF",
	parameter lpm_type = "",
	parameter lpm_width = 8,
	parameter lpm_widthu = 6,
	parameter overflow_checking = "ON",
	parameter underflow_checking = "ON",
	parameter use_eab = "ON"
) (
	input  wire                 aclr,
	input  wire                 clock,
	input  wire [lpm_width-1:0] data,
	input  wire                 rdreq,
	input  wire                 wrreq,
	output wire                 empty,
	output wire                 full,
	output reg  [lpm_width-1:0] q
);
	reg [lpm_width-1:0] mem [0:lpm_numwords-1];
	reg [lpm_widthu:0] wp = 0, rp = 0;
	assign empty = (wp == rp);
	assign full  = ((wp - rp) == lpm_numwords);
	always @(posedge clock) begin
		if (aclr) begin wp <= 0; rp <= 0; end
		else begin
			if (wrreq && !full) begin mem[wp[lpm_widthu-1:0]] <= data; wp <= wp + 1'b1; end
			if (rdreq && !empty) begin q <= mem[rp[lpm_widthu-1:0]]; rp <= rp + 1'b1; end
		end
	end
endmodule

// ---- audio DAC: not part of this simulation ----
module sound_i2s #(
	parameter CHANNEL_WIDTH = 15,
	parameter SIGNED_INPUT  = 0
) (
	input wire clk_74a,
	input wire clk_audio,
	input wire [CHANNEL_WIDTH - 1:0] audio_l,
	input wire [CHANNEL_WIDTH - 1:0] audio_r,
	output wire audio_mclk,
	output wire audio_lrck,
	output wire audio_dac
);
	assign audio_mclk = 1'b0;
	assign audio_lrck = 1'b0;
	assign audio_dac  = 1'b0;
endmodule


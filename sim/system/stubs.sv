// Behavioural stand-ins for the Altera megafunctions / board pieces that the system
// simulation cannot use. Everything else in the sim is the real RTL.
`timescale 1ps/1ps

// ---- PLL: clk_sys 31.527954 MHz (31718 ps), clk64 = exactly 2x, edges coincide ----
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
	localparam integer HALF64 = 7930;          // clk64 period 15860 ps
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
			c64 = 1; csys = 1;      #HALF64;
			c64 = 0; c90 = 1;       #HALF64;
			c64 = 1; csys = 0;      #HALF64;
			c64 = 0; c90 = 0;       #HALF64;
		end
	end
	initial forever #(HALF64 * 2 / 3) c48 = ~c48;
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
	assign mgmt_waitrequest = 1'b0;
	assign mgmt_readdata = 32'd0;
	assign reconfig_to_pll = 64'd0;
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

// ---- 1541/1581 drive: idle (no disk in the PRG/CRT/TAP tests) ----
// With the drive held in reset (no disk mounted) c1541_multi reports disk_ready = 1.
module iec_drive #(parameter PARPORT=1, DUALROM=1, DRIVES=2)
(
	input         clk,
	input   [N:0] reset,
	input         ce,
	input         pause,
	input   [N:0] img_mounted,
	input         img_readonly,
	input  [31:0] img_size,
	input   [1:0] img_type,
	input   [2:0] drive_rpm,
	input         drive_wobble,
	output  [N:0] led,
	output wire [7:0] out_track[NDR],
	output wire [N:0] out_we,
	output        disk_ready,
	input         iec_atn_i,
	input         iec_data_i,
	input         iec_clk_i,
	output        iec_data_o,
	output        iec_clk_o,
	input   [7:0] par_data_i,
	input         par_stb_i,
	output  [7:0] par_data_o,
	output        par_stb_o,
	input         clk_sys,
	output [31:0] sd_lba[NDR],
	output  [5:0] sd_blk_cnt[NDR],
	output  [N:0] sd_rd,
	output  [N:0] sd_wr,
	input   [N:0] sd_ack,
	input  [13:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din[NDR],
	input         sd_buff_wr,
	input  [15:0] rom_addr,
	input   [7:0] rom_data,
	input         rom_wr,
	input         rom_std,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output        DDRAM_WE,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE
);
	localparam NDR = (DRIVES < 1) ? 1 : (DRIVES > 4) ? 4 : DRIVES;
	localparam N   = NDR - 1;
	assign led = '0;
	assign out_we = '0;
	assign disk_ready = 1'b1;
	assign iec_data_o = 1'b1;
	assign iec_clk_o = 1'b1;
	assign par_data_o = 8'hFF;
	assign par_stb_o = 1'b1;
	assign sd_rd = '0;
	assign sd_wr = '0;
	assign DDRAM_BURSTCNT = 8'd0;
	assign DDRAM_ADDR = 29'd0;
	assign DDRAM_RD = 1'b0;
	assign DDRAM_WE = 1'b0;
	assign DDRAM_DIN = 64'd0;
	assign DDRAM_BE = 8'd0;
	genvar gi;
	generate for (gi = 0; gi < NDR; gi = gi + 1) begin : g
		assign out_track[gi] = 8'd0;
		assign sd_lba[gi] = 32'd0;
		assign sd_blk_cnt[gi] = 6'd0;
		assign sd_buff_din[gi] = 8'd0;
	end endgenerate
endmodule

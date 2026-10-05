//============================================================================
//  C64 Top level for MiSTer
//  Copyright (C) 2017-2021 Sorgelig
//
//  Used DE2-35 Top level by Dar (darfpga@aol.fr)
//
//  FPGA64 is Copyrighted 2005-2008 by Peter Wendrich (pwsoft@syntiac.com)
//  http://www.syntiac.com/fpga64.html
//
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================ 
//
// c64_top.sv - the C64 machine of C64_MiSTer's c64.sv, without the MiSTer framework
//
// Derived from C64_MiSTer/c64.sv (Sorgelig, GPL v2+). The machine logic (memory
// loader, cartridge, REU, drives, tape, sound mixing) is kept as in c64.sv; the
// hps_io, scaler, HDMI, ADC and UART parts are replaced by ports driven from
// core_top. status[] keeps c64.sv's bit map so that logic reads unchanged; the
// bits are set from interact.json in core_top. See docs/architecture.md.
//

module c64_top
(
	input         clk_sys,        // 31.527954 MHz PAL / 32.727264 MHz NTSC
	input         clk64,          // 2 x clk_sys, SDRAM
	input         clk48,          // 1.5 x clk_sys (OPL2, not built)
	input         pll_locked,
	input         reset_req,      // held: power-on style reset with RAM erase
	input         ntsc_r,         // video standard the PLL currently runs (clk_74a domain)

	input [127:0] status,
	input         OSD_STATUS,

	// hps_io-style file download
	input         ioctl_download,
	input   [7:0] ioctl_index,
	input         ioctl_wr,
	input  [24:0] ioctl_addr,
	input   [7:0] ioctl_data,
	input  [31:0] ioctl_file_ext,
	output        ioctl_wait,

	// hps_io-style disk image access (1581 sectors, 1541 track write-back)
	output [31:0] sd_lba[2],
	output  [5:0] sd_blk_cnt[2],
	output  [1:0] sd_rd,
	output  [1:0] sd_wr,
	input   [1:0] sd_ack,
	input  [13:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din[2],
	input         sd_buff_wr,
	input   [1:0] img_mounted,
	input  [31:0] img_size,
	input         img_readonly,
	input   [1:0] img_type,       // 2'b01 1541 (G64/D64), 2'b11 1581 (D81)

	// G64 images of both drives (MiSTer DDRAM port, clk_sys)
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output        DDRAM_WE,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,

	input  [10:0] ps2_key,
	input  [24:0] ps2_mouse,
	input  [15:0] joyA,
	input  [15:0] joyB,
	input  [15:0] joyC,
	input  [15:0] joyD,
	input   [7:0] pd1,
	input   [7:0] pd2,
	input   [7:0] pd3,
	input   [7:0] pd4,
	input  [64:0] RTC,

	output [12:0] SDRAM_A,
	inout  [15:0] SDRAM_DQ,
	output  [1:0] SDRAM_BA,
	output        SDRAM_nCS,
	output        SDRAM_nWE,
	output        SDRAM_nRAS,
	output        SDRAM_nCAS,
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,

	// video, clk_sys domain, one pixel every 4 clocks
	output reg  [7:0] VGA_R,
	output reg  [7:0] VGA_G,
	output reg  [7:0] VGA_B,
	output reg        VGA_HS,
	output reg        VGA_VS,
	output reg        VGA_HB,
	output reg        VGA_VB,
	output            ntsc_out,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,

	output  [1:0] drive_led,
	output        tape_loaded,
	output        disk_ready_out,  // the drive accepts keys again after a disk swap
	output reg    at_prompt,       // the KERNAL is waiting for a key (BASIC prompt)
	output reg    basic_main       // BASIC's direct-mode main loop ran ($A483)
);

wire [7:0]  drv_ddram_burstcnt;
wire [28:0] drv_ddram_addr;
wire        drv_ddram_rd;
wire        drv_ddram_we;
wire [63:0] drv_ddram_din;
wire [7:0]  drv_ddram_be;

assign DDRAM_BURSTCNT = drv_ddram_burstcnt;
assign DDRAM_ADDR     = drv_ddram_addr;
assign DDRAM_RD       = drv_ddram_rd;
assign DDRAM_WE       = drv_ddram_we;
assign DDRAM_DIN      = drv_ddram_din;
assign DDRAM_BE       = drv_ddram_be;

// no EasyFlash save-back, user port serial or SNAC on the Pocket
wire        ioctl_rd     = 1'b0;
wire        ioctl_upload = 1'b0;
reg   [7:0] ioctl_din;
wire  [6:0] USER_IN      = 7'h7F;
wire        UART_RXD     = 1'b1;
wire        UART_CTS     = 1'b0;
wire        UART_DSR     = 1'b0;
reg         UART_TXD, UART_RTS, UART_DTR;

assign ntsc_out = ntsc;

wire        tape_play;
wire        tape_key_rew;
wire        tape_key_stop;
wire        tape_key_ff;
wire        tape_key_counter_reset;
reg ntsc_sys1 = 0, ntsc = 0;
reg reset_n;
reg reset_wait = 0;
reg ntsc_prev = 0;

always @(posedge clk_sys) begin
	integer reset_counter;
	reg old_download;
	reg do_erase = 1;

	// Bringing ntsc_r back into clk_sys domain
	ntsc_sys1 <= ntsc_r;
	ntsc <= ntsc_sys1;
	// Detect pal/ntsc switch
	ntsc_prev <= ntsc;

	reset_n <= !reset_counter;
	old_download <= ioctl_download;

	if (reset_req | status[0] | status[17] | !pll_locked | (ntsc_prev != ntsc)) begin
		if(reset_req) do_erase <= 1;
		reset_counter <= 100000;
	end
	else if(~old_download & ioctl_download & load_prg & ~status[50]) begin
		do_erase <= 1;
		reset_wait <= 1;
		reset_counter <= 255;
	end
	else if (ioctl_download & (load_crt | load_rom)) begin
		do_erase <= 1;
		reset_counter <= 255;
	end
	else if ((ioctl_download || inj_meminit) & ~reset_wait);
	else if (erasing) force_erase <= 0;
	else if (!reset_counter) begin
		do_erase <= 0;
		if(reset_wait && c64_addr == 'hFFCF) reset_wait <= 0;
	end
	else begin
		reset_counter <= reset_counter - 1;
		if (reset_counter == 100 && (~status[24] | do_erase)) force_erase <= 1;
	end
end

wire [15:0] joy = joyA | joyB | joyC | joyD;

wire        tape_ioctl_wait;

assign ioctl_wait = ioctl_req_wr|ioctl_req_rd|reset_wait|tape_ioctl_wait;


wire load_prg   = ioctl_index == 'h01;
wire load_crt   = ioctl_index == 'h41 || ioctl_index == 5;
wire load_reu   = ioctl_index == 'h81;
wire load_tap   = ioctl_index == 'hC1;
wire load_flt   = ioctl_index == 7;
wire load_rom   = ioctl_index == 8;
wire load_c1581 = ioctl_index == 9;

wire game;
wire exrom;
wire io_rom;
wire cart_ce;
wire cart_we;
wire nmi;
wire cart_oe;
wire IOF_rd;
wire  [7:0] cart_data;
wire  [7:0] cart_wrdata;
wire [24:0] cart_addr;
wire cart_mem_req;

cartridge cartridge
(
	.clk32(clk_sys),
	.reset_n(reset_n),

	.cart_loading(ioctl_download && load_crt),
	.cart_id(cart_attached ? cart_id : status[52] ? 8'd99 : 8'd255),
	.cart_exrom(cart_exrom),
	.cart_game(cart_game),
	.cart_bank_hi(cart_bank_hi),
	.cart_bank_16k(cart_bank_16k),
	.cart_bank_num(cart_bank_num),
	.cart_bank_addr(ioctl_load_addr[20:13]),
	.cart_bank_wr(cart_hdr_wr),
	.cart_boot(~status[38]),

	.exrom(exrom),
	.game(game),

	.romL(romL),
	.romH(romH),
	.UMAXromH(UMAXromH),
	.IOE(IOE),
	.IOF(IOF),
	.mem_write(ram_we),
	.mem_ce(ram_ce),
	.mem_ce_out(cart_ce),
	.mem_write_out(cart_we),
	.mem_in(sdram_data),
	.mem_out(cart_wrdata),
	.mem_addr(cart_addr),
	.mem_req(cart_mem_req),
	.mem_cycle(io_cycle),
	.IO_rom(io_rom),
	.IO_rd(cart_oe),
	.IO_data(cart_data),
	.addr_in(c64_addr),
	.data_in(c64_data_out),
	.data_out(c64_data_in),

	.freeze_key(freeze_key),
	.mod_key(mod_key),
	.nmi(nmi),
	.nmi_ack(nmi_ack)
);

wire ezfl_save = status[61] | (status[62] & OSD_STATUS & ezfl_mod);
reg  ezfl_mod = 0;
reg  ezfl_idx = 0;
reg  ezfl_save_en = 0;
always @(posedge clk_sys) begin
	reg save_old = 0;
	reg ext_old = 0;

	if(cart_mem_req) ezfl_mod <= 1;
	if(ioctl_download && load_crt) ezfl_mod <= 0;
	if(ioctl_upload) {ezfl_mod, ezfl_save_en} <= 0;
	
	save_old <= ezfl_save;
	if(~save_old & ezfl_save) ezfl_idx <= ~status[61];
	
	ext_old <= ext_crt;
	if(~ext_old & ext_crt) ezfl_save_en <= 1;
end

wire        dma_req;
wire        dma_cycle;
wire [15:0] dma_addr;
wire  [7:0] dma_dout;
wire  [7:0] dma_din;
wire        dma_we;
wire        ext_cycle;

wire [24:0] reu_ram_addr;
wire  [7:0] reu_ram_dout;
wire        reu_ram_we;

wire  [7:0] reu_dout;
wire        reu_irq;

wire        reu_oe  = IOF && reu_cfg;
wire  [1:0] reu_cfg = status[54:53];
wire        reu_wrap = ~status[63] & status[54];

reu reu
(
	.clk(clk_sys),
	.reset(~reset_n),
	.cfg(reu_cfg),
	.wrap(reu_wrap),

	.dma_req(dma_req),

	.dma_cycle(dma_cycle),
	.dma_addr(dma_addr),
	.dma_dout(dma_dout),
	.dma_din(dma_din),
	.dma_we(dma_we),

	.ram_cycle(ext_cycle),
	.ram_addr(reu_ram_addr),
	.ram_dout(reu_ram_dout),
	.ram_din(sdram_data),
	.ram_we(reu_ram_we),
	
	.cpu_addr(c64_addr),
	.cpu_dout(c64_data_out),
	.cpu_din(reu_dout),
	.cpu_we(ram_we),
	.cpu_cs(IOF),
	
	.irq(reu_irq)
);

reg ext_cycle_d;
always @(posedge clk_sys) ext_cycle_d <= ext_cycle;
wire reu_ram_ce = ~ext_cycle_d & ext_cycle & dma_req;

// rearrange joystick contacts for c64
wire [6:0] joyA_int = joy[8] ? 7'd0 : {joyA[6:4], joyA[0], joyA[1], joyA[2], joyA[3]};
wire [6:0] joyB_int = joy[8] ? 7'd0 : {joyB[6:4], joyB[0], joyB[1], joyB[2], joyB[3]};
wire [6:0] joyC_c64 = joy[8] ? 7'd0 : {joyC[6:4], joyC[0], joyC[1], joyC[2], joyC[3]};
wire [6:0] joyD_c64 = joy[8] ? 7'd0 : {joyD[6:4], joyD[0], joyD[1], joyD[2], joyD[3]};

// swap joysticks if requested
// SNAC DB9 joystick support - C64/Amiga/SMS standard pinout:
//   Pin 1 Up     -> USER_IN[1]  (active low)
//   Pin 2 Down   -> USER_IN[0]  (active low)
//   Pin 3 Left   -> USER_IN[5]  (active low)
//   Pin 4 Right  -> USER_IN[3]  (active low)
//   Pin 5 NC     -> not used
//   Pin 6 Fire A -> USER_IN[2]  (active low, Button 1)
//   Pin 9 Fire B -> USER_IN[6]  (active low, Button 2)
wire [1:0] snac_mode = status[88:87]; // 0=disabled, 1=Joy1, 2=Joy2
wire [6:0] snac_joy  = {1'b0, ~USER_IN[6], ~USER_IN[2],
                        ~USER_IN[3], ~USER_IN[5], ~USER_IN[0], ~USER_IN[1]};
// format: {fire3=0, fireB(Pin9), fireA(Pin6), right(Pin4), left(Pin3), down(Pin2), up(Pin1)}

wire [6:0] joyA_c64 = (snac_mode == 2'd1) ? snac_joy : (status[3] ? joyB_int : joyA_int);
wire [6:0] joyB_c64 = (snac_mode == 2'd2) ? snac_joy : (status[3] ? joyA_int : joyB_int);

wire [7:0] paddle_1 = status[3] ? pd3 : pd1;
wire [7:0] paddle_2 = status[3] ? pd4 : pd2;
wire [7:0] paddle_3 = status[3] ? pd1 : pd3;
wire [7:0] paddle_4 = status[3] ? pd2 : pd4;

wire       paddle_1_btn = ~joy[8] & (status[3] ? joyC[7] : joyA[7]);
wire       paddle_2_btn = ~joy[8] & (status[3] ? joyD[7] : joyB[7]);
wire       paddle_3_btn = ~joy[8] & (status[3] ? joyA[7] : joyC[7]);
wire       paddle_4_btn = ~joy[8] & (status[3] ? joyB[7] : joyD[7]);

wire [1:0] pd12_mode = status[27:26];
wire [1:0] pd34_mode = status[29:28];

reg [24:0] ioctl_load_addr;
reg        ioctl_req_wr;
reg        ioctl_req_rd;

reg  [7:0] cart_id;
reg        cart_bank_hi;
reg        cart_bank_16k;
reg  [7:0] cart_bank_num;
reg        cart_exrom;
reg        cart_game;
reg        cart_attached = 0;
reg        cart_hdr_wr;

reg        force_erase;
reg        erasing;

reg        inj_meminit = 0;

wire       io_cycle;
reg        io_cycle_ce;
reg        io_cycle_we;
reg [24:0] io_cycle_addr;
reg  [7:0] io_cycle_data;

localparam TAP_ADDR = 25'h0400000;
localparam REU_ADDR = 25'h1000000;
localparam CRT_ADDR = 25'h0200000;

wire cart_ezfl = cart_attached && (cart_id == 32 || cart_id ==33);
reg ext_crt = 0;

always @(posedge clk_sys) begin
	reg  [4:0] erase_to;
	reg        old_download;
	reg        erase_cram;
	reg        io_cycleD;
	reg        old_st0 = 0;
	reg        old_meminit;
	reg [15:0] inj_end;
	reg  [7:0] inj_meminit_data;
	reg  [2:0] rd_cyc;
	reg        ioctl_rd_en;
	reg [15:0] cart_blk_len;
	reg  [3:0] cart_hdr_cnt;
	reg  [7:0] cart_id_hi;

	old_download <= ioctl_download;
	io_cycleD <= io_cycle;
	cart_hdr_wr <= 0;
	
	if (~io_cycle & io_cycleD) begin
		io_cycle_ce <= 1;
		io_cycle_we <= 0;
		io_cycle_addr <= tap_play_addr + TAP_ADDR;
		if (ioctl_req_wr) begin
			ioctl_req_wr <= 0;
			io_cycle_we <= 1;
			io_cycle_addr <= ioctl_load_addr;
			ioctl_load_addr <= ioctl_load_addr + 1'b1;
			if (erasing) io_cycle_data <= {8{ioctl_load_addr[6]}};
			else if (inj_meminit) io_cycle_data <= inj_meminit_data;
			else io_cycle_data <= ioctl_data;
		end

		if(ioctl_req_rd) begin
			io_cycle_addr <= ioctl_load_addr;
			ioctl_rd_en <= 1;
		end
	end
	
	if (io_cycle) {io_cycle_ce, io_cycle_we, ioctl_rd_en} <= 0;

	if (ioctl_rd) begin
		if(ioctl_addr == 0) ioctl_load_addr <= CRT_ADDR;
		ioctl_req_rd <= 1;
	end

	rd_cyc <= {rd_cyc[1:0], io_cycle & io_cycle_ce & ioctl_rd_en};
	if(rd_cyc[2]) begin
		ioctl_din <= sdram_data;
		ioctl_req_rd <= 0;
		ioctl_load_addr <= ioctl_load_addr + 1'b1;
	end


	if (ioctl_wr) begin
		if (load_prg) begin
			// PRG header
			// Load address low-byte
			if      (ioctl_addr == 0) begin ioctl_load_addr[7:0]  <= ioctl_data; inj_end[7:0]  <= ioctl_data; end
			// Load address high-byte
			else if (ioctl_addr == 1) begin ioctl_load_addr[15:8] <= ioctl_data; inj_end[15:8] <= ioctl_data; end
			else begin ioctl_req_wr <= 1; inj_end <= inj_end + 1'b1; end
		end

		if (load_crt) begin
			if (ioctl_addr == 0) begin
				ioctl_load_addr <= CRT_ADDR;
				cart_blk_len <= 0;
				cart_hdr_cnt <= 0;
			end

			if (ioctl_addr == 8'h16) cart_id_hi <= ioctl_data;
			if (ioctl_addr == 8'h17) cart_id    <= cart_id_hi ? 8'd255 : ioctl_data;
			if (ioctl_addr == 8'h18) cart_exrom <= ioctl_data[0];
			if (ioctl_addr == 8'h19) cart_game  <= ioctl_data[0];

			if (ioctl_addr >= 8'h40) begin
				if (!cart_blk_len || cart_hdr_cnt) begin
					cart_hdr_cnt <= cart_hdr_cnt + 1'b1;
					if (cart_hdr_cnt == 6)  cart_blk_len  <= {ioctl_data, 8'h00};
					if (cart_hdr_cnt == 11) cart_bank_num <= ioctl_data;
					if (cart_hdr_cnt == 12) cart_bank_hi  <= ioctl_data > 8'h80;
					if (cart_hdr_cnt == 14) cart_bank_16k <= ioctl_data > 8'h20;
					if (cart_hdr_cnt == 15) cart_hdr_wr   <= 1;
				end
				else begin
					cart_blk_len <= cart_blk_len - 1'b1;
					ioctl_req_wr <= 1;
				end
			end
		end
		
		if (load_tap) begin
			if (ioctl_addr == 0)  ioctl_load_addr <= TAP_ADDR;
			ioctl_req_wr <= 1;
		end

		if (load_reu) begin
			if (ioctl_addr == 0) ioctl_load_addr <= REU_ADDR;
			ioctl_req_wr <= 1;
		end
	end
	
	if (old_download != ioctl_download && load_crt) begin
		cart_attached <= old_download;
		erase_cram <= 1;
		ext_crt <= ioctl_download && (ioctl_file_ext == ".CRT");
	end 

	// meminit for RAM injection
	if (old_download != ioctl_download && load_prg && !inj_meminit) begin
		inj_meminit <= 1;
		ioctl_load_addr <= 0;
	end

	if (inj_meminit) begin
		if (!ioctl_req_wr) begin
			// check if done
			if (ioctl_load_addr == 'h100) begin
				inj_meminit <= 0;
			end
			else begin
				ioctl_req_wr <= 1;
				
				// Initialize BASIC pointers to simulate the BASIC LOAD command
				case(ioctl_load_addr)
					// TXT (2B-2C)
					// Set these two bytes to $01, $08 just as they would be on reset (the BASIC LOAD command does not alter these)
					'h2B: inj_meminit_data <= 'h01;
					'h2C: inj_meminit_data <= 'h08;

					// SAVE_START (AC-AD)
					// Set these two bytes to zero just as they would be on reset (the BASIC LOAD command does not alter these)
					'hAC, 'hAD: inj_meminit_data <= 'h00;
					
					// VAR (2D-2E), ARY (2F-30), STR (31-32), LOAD_END (AE-AF)
					// Set these just as they would be with the BASIC LOAD command (essentially they are all set to the load end address)
					'h2D, 'h2F, 'h31, 'hAE: inj_meminit_data <= inj_end[7:0];
					'h2E, 'h30, 'h32, 'hAF: inj_meminit_data <= inj_end[15:8];
					
					default: begin
						ioctl_req_wr <= 0;
						
						// advance the address
						ioctl_load_addr <= ioctl_load_addr + 1'b1;
					end
				endcase
			end
		end
	end

	old_meminit <= inj_meminit;
	start_strk  <= old_meminit & ~inj_meminit;
	
	old_st0 <= status[17];
	if (~old_st0 & status[17]) cart_attached <= 0;
	
	if (!erasing && force_erase) begin
		erasing <= 1;
		ioctl_load_addr <= 0;
	end

	if (erasing && !ioctl_req_wr) begin
		erase_to <= erase_to + 1'b1;
		if (&erase_to) begin
			if (ioctl_load_addr < ({erase_cram, 16'hFFFF}))
				ioctl_req_wr <= 1;
			else begin
				erasing <= 0;
				erase_cram <= 0;
			end
		end
	end
end

reg        start_strk = 0;
reg        reset_keys = 0;
reg [10:0] key = 0;
always @(posedge clk_sys) begin
	reg  [3:0] act = 0;
	reg        joy_finish = 0;
	reg [17:0] joy_last = 0;
	reg [17:0] joy_key;
	int        to;

	reset_keys <= 0;

	joy_key =(joy[9:8] == 3) ?
				(joy[0] ? 18'h005 : joy[1] ? 18'h006 : joy[2] ? 18'h004 : joy[3] ? 18'h00C  :
				 joy[4] ? 18'h003 : joy[5] ? 18'h00B : joy[6] ? 18'h083 : joy[7] ? 18'h00A  : 18'h0):
				(joy[9]) ?
				(joy[0] ? 18'h016 : joy[1] ? 18'h01E : joy[2] ? 18'h026 : joy[3] ? 18'h025  :
			    joy[4] ? 18'h02E : joy[5] ? 18'h045 : joy[6] ? 18'h035 : joy[7] ? 18'h031  : 18'h0):
				(joy[0] ? 18'h174 : joy[1] ? 18'h16B : joy[2] ? 18'h172 : joy[3] ? 18'h175  : 
				 joy[4] ? 18'h05A : joy[5] ? 18'h029 : joy[6] ? 18'h076 : joy[7] ? 18'h2276 : 18'h0);
	
	if(~reset_n) {joy_finish, act} <= 0;

	if(joy[9:8]) begin
		joy_finish <= 1;
		if(!joy[7:0] && joy_last) begin
			joy_last <= 0;
			reset_keys <= 1;
		end
		else if(!joy_last[8:0] && joy_key) begin
			to <= to + 1'd1;
			if(joy_last[17:9] != joy_key[17:9]) begin
				joy_last[17:9] <= joy_key[17:9];
				key <= joy_key[17:9];
				key[9] <= 1;
				key[10] <= ~key[10];
			end
			else if(to > 640000 && joy_last[8:0] != joy_key[8:0]) begin
				joy_last[8:0] <= joy_key[8:0];
				key <= joy_key[8:0];
				key[9] <= 1;
				key[10] <= ~key[10];
			end
		end
		else begin
			to <= 0;
		end
	end
	else if(joy_finish) begin
		joy_last   <= 0;
		key        <= 0;
		key[10]    <= ps2_key[10];
		joy_finish <= 0;
		reset_keys <= 1;
	end
	else if(act) begin
		to <= to + 1;
		if(to > 1280000) begin
			to <= 0;
			act <= act + 1'd1;
			case(act)
				// PS/2 scan codes
				 1: key <= 'h2d;  // R
				 3: key <= 'h3c;  // U
				 5: key <= 'h31;  // N
				 7: key <= 'h5a;  // <RETURN>
				 9: key <= 'h00;
				10: act <= 0;
			endcase
			key[9]  <= act[0];
			key[10] <= (act >= 9) ? ps2_key[10] : ~key[10];
		end
	end
	else begin
		to <= 0;
		key <= {ps2_key[10], ps2_key[9] & disk_ready, ps2_key[8:0]};
	end
	if(start_strk & ~status[50]) begin
		act <= 1;
		key <= 0;
	end
end

assign SDRAM_CKE  = 1;

wire [7:0] sdram_data;
sdram sdram
(
	.sd_addr(SDRAM_A),
	.sd_data(SDRAM_DQ),
	.sd_ba(SDRAM_BA),
	.sd_cs(SDRAM_nCS),
	.sd_we(SDRAM_nWE),
	.sd_ras(SDRAM_nRAS),
	.sd_cas(SDRAM_nCAS),
	.sd_clk(SDRAM_CLK),
	.sd_dqm({SDRAM_DQMH,SDRAM_DQML}),

	.clk(clk64),
	.init(~pll_locked),
	.refresh(refresh),
	.addr( io_cycle ? (cart_mem_req ? cart_addr   : io_cycle_addr ) : ext_cycle ? reu_ram_addr : cart_addr   ),
	.ce  ( io_cycle ? (cart_mem_req ? cart_ce     : io_cycle_ce   ) : ext_cycle ? reu_ram_ce   : cart_ce     ),
	.we  ( io_cycle ? (cart_mem_req ? cart_we     : io_cycle_we   ) : ext_cycle ? reu_ram_we   : cart_we     ),
	.din ( io_cycle ? (cart_mem_req ? cart_wrdata : io_cycle_data ) : ext_cycle ? reu_ram_dout : cart_wrdata ),
	.dout( sdram_data )
);

wire  [7:0] c64_data_out;
wire  [7:0] c64_data_in;
wire [15:0] c64_addr;
wire        c64_pause;
wire        refresh;
wire        ram_ce;
wire        ram_we;
wire        nmi_ack;
wire        freeze_key;
wire        mod_key;

wire        IOE;
wire        IOF;
wire        romL;
wire        romH;
wire        UMAXromH;

wire [17:0] audio_l,audio_r;
wire  [7:0] r,g,b;

wire        ntsc_req = status[2];

fpga64_sid_iec fpga64
(
	.clk32(clk_sys),
	.reset_n(reset_n),
	.pause(freeze),
	.pause_out(c64_pause),
	.bios(status[15:14]),
	
	.turbo_mode({status[47] & ~disk_access, status[46]}),
	.turbo_speed(status[49:48]),

	.ps2_key(key),
	.kbd_reset((~reset_n & ~status[1]) | reset_keys),
	.shift_mod(~status[60:59]),

	.ramAddr(c64_addr),
	.ramDout(c64_data_out),
	.ramDin(c64_data_in),
	.ramCE(ram_ce),
	.ramWE(ram_we),

	.vic_variant(status[35:34]),
	.ntscmode(ntsc),
	.hsync(hsync),
	.vsync(vsync),
	.palette(status[84:82]),
	.r(r),
	.g(g),
	.b(b),

	.game(game),
	.exrom(exrom),
	.UMAXromH(UMAXromH),
	.irq_n(1),
	.nmi_n(~nmi),
	.nmi_ack(nmi_ack),
	.freeze_key(freeze_key),
	.tape_play(tape_play),
	.tape_rew(tape_key_rew),
	.tape_stop(tape_key_stop),
	.tape_ff(tape_key_ff),
	.tape_reset_counter(tape_key_counter_reset),
	.mod_key(mod_key),
	.roml(romL),
	.romh(romH),
	.ioe(IOE),
	.iof(IOF),
	.io_rom(io_rom),
	.io_ext(cart_oe | reu_oe | opl_en),
	.io_data(cart_oe ? cart_data : reu_oe ? reu_dout : opl_dout),
	
	.dma_req(dma_req),
	.dma_cycle(dma_cycle),
	.dma_addr(dma_addr),
	.dma_dout(dma_dout),
	.dma_din(dma_din),
	.dma_we(dma_we),
	.irq_ext_n(~reu_irq),

	.cia_mode(status[45]),

	.joya({(pd12_mode && !joy[9:8]) ? joyA_c64[6:5] : 2'b00, joyA_c64[4:0] | {1'b0, pd12_mode[1] & paddle_2_btn, pd12_mode[1] & paddle_1_btn, 2'b00} | {pd12_mode[0] & mouse_btn[0], 3'b000, pd12_mode[0] & mouse_btn[1]}}),
	.joyb({(pd34_mode && !joy[9:8]) ? joyB_c64[6:5] : 2'b00, joyB_c64[4:0] | {1'b0, pd34_mode[1] & paddle_4_btn, pd34_mode[1] & paddle_3_btn, 2'b00} | {pd34_mode[0] & mouse_btn[0], 3'b000, pd34_mode[0] & mouse_btn[1]}}),

	.pot1(pd12_mode[1] ? paddle_1 : pd12_mode[0] ? mouse_x : {8{joyA_c64[5]}}),
	.pot2(pd12_mode[1] ? paddle_2 : pd12_mode[0] ? mouse_y : {8{joyA_c64[6]}}),
	.pot3(pd34_mode[1] ? paddle_3 : pd34_mode[0] ? mouse_x : {8{joyB_c64[5]}}),
	.pot4(pd34_mode[1] ? paddle_4 : pd34_mode[0] ? mouse_y : {8{joyB_c64[6]}}),

	.io_cycle(io_cycle),
	.ext_cycle(ext_cycle),
	.refresh(refresh),

	.sid_ld_clk(clk_sys),
	.sid_ld_addr(sid_ld_addr),
	.sid_ld_data(sid_ld_data),
	.sid_ld_wr(sid_ld_wr),
	.sid_mode(status[22:20]),
	.sid_filter(2'b11),
	.sid_ver({status[16],status[13]}),
	.sid_cfg({status[68:67],status[65:64]}),
	.sid_fc_off_l(status[66] ? (13'h600 - {status[72:70],7'd0}) : 13'd0),
	.sid_fc_off_r(status[69] ? (13'h600 - {status[75:73],7'd0}) : 13'd0),
	.sid_digifix(~status[37]),
	.audio_l(audio_l),
	.audio_r(audio_r),

	.iec_data_o(c64_iec_data),
	.iec_atn_o(c64_iec_atn),
	.iec_clk_o(c64_iec_clk),
	.iec_data_i(drive_iec_data),
	.iec_clk_i(drive_iec_clk),

	.pb_i(pb_i),
	.pb_o(pb_o),
	.pa2_i(pa2_i),
	.pa2_o(pa2_o),
	.pc2_n_o(pc2_n_o),
	.flag2_n_i(flag2_n_i),
	.sp2_i(sp2_i),
	.sp2_o(sp2_o),
	.sp1_i(sp1_i),
	.sp1_o(sp1_o),
	.cnt2_i(cnt2_i),
	.cnt2_o(cnt2_o),
	.cnt1_i(cnt1_i),
	.cnt1_o(cnt1_o),

	.c64rom_addr(ioctl_addr[13:0]),
	.c64rom_data(ioctl_data),
	.c64rom_wr(load_rom && !ioctl_addr[16:14] && ioctl_download && ioctl_wr),

	.cass_write(cass_write),
	.cass_motor(cass_motor),
	.cass_sense(~tape_adc_act & (use_tape ? cass_sense : cass_rtc)),
	.cass_read(tape_adc_act ? ~tape_adc : cass_read)
);

wire [7:0] mouse_x;
wire [7:0] mouse_y;
wire [1:0] mouse_btn;

c1351 mouse
(
	.clk_sys(clk_sys),
	.reset(~reset_n),

	.ps2_mouse(ps2_mouse),
	
	.potX(mouse_x),
	.potY(mouse_y),
	.button(mouse_btn)
);

wire       c64_iec_clk;
wire       c64_iec_data;
wire       c64_iec_atn;

wire       drive_iec_clk  = drive_iec_clk_o  & ext_iec_clk;
wire       drive_iec_data = drive_iec_data_o & ext_iec_data;

wire [7:0] drive_par_i;
wire       drive_stb_i;
wire [7:0] drive_par_o;
wire       drive_stb_o;
wire       drive_iec_clk_o;
wire       drive_iec_data_o;
wire       drive_reset = ~reset_n | status[6] | (load_c1581 & ioctl_download);

wire [7:0] drive_track[2];
wire [1:0] drive_we;
wire       disk_ready;

reg [1:0] drive_mounted = 0;
reg [1:0] old_img_mounted;

always @(posedge clk_sys) begin 
	old_img_mounted <= img_mounted;
	if(img_mounted[0]) drive_mounted[0] <= |img_size;
	if(img_mounted[1]) drive_mounted[1] <= |img_size;
end

wire mounted_0 = ~old_img_mounted[0] & img_mounted[0];
wire mounted_1 = ~old_img_mounted[1] & img_mounted[1];
wire img_readonly_wp = img_readonly | (mounted_0 & status[76]) | (mounted_1 & status[77]);

// One drive (#8, 1541 or 1581): two do not fit the Pocket's FPGA. Drive 9's ports read as idle.
wire [31:0] drv_sd_lba[1];
wire  [5:0] drv_sd_blk_cnt[1];
wire  [7:0] drv_sd_buff_din[1];
wire  [7:0] drv_track[1];
assign sd_lba[0] = drv_sd_lba[0];         assign sd_lba[1] = 32'd0;
assign sd_blk_cnt[0] = drv_sd_blk_cnt[0]; assign sd_blk_cnt[1] = 6'd0;
assign sd_buff_din[0] = drv_sd_buff_din[0]; assign sd_buff_din[1] = 8'h00;
assign drive_track[0] = drv_track[0];     assign drive_track[1] = 8'd0;
assign sd_rd[1] = 1'b0;
assign sd_wr[1] = 1'b0;
assign drive_led[1] = 1'b0;
assign drive_we[1] = 1'b0;

iec_drive #(.DRIVES(1)) iec_drive
(
	.clk(clk_sys),
	.reset(drive_reset | ((!status[58:57]) ? ~drive_mounted[0] : status[58])),

	.ce(drive_ce),

	.iec_atn_i(c64_iec_atn),
	.iec_data_i(c64_iec_data & ext_iec_data),
	.iec_clk_i(c64_iec_clk & ext_iec_clk),
	.iec_data_o(drive_iec_data_o),
	.iec_clk_o(drive_iec_clk_o),

	.pause(c64_pause),

	.img_mounted(img_mounted[0]),
	.img_size(img_size),
	.img_readonly(img_readonly_wp),
	.img_type(img_type),
	.drive_rpm(status[80:78]),
	.drive_wobble(status[81]),

	.led(drive_led[0]),
	.out_track(drv_track),
	.out_we(drive_we[0]),
	.disk_ready(disk_ready),

	.par_data_i(drive_par_i),
	.par_stb_i(drive_stb_i),
	.par_data_o(drive_par_o),
	.par_stb_o(drive_stb_o),

	.clk_sys(clk_sys),

	.sd_lba(drv_sd_lba),
	.sd_blk_cnt(drv_sd_blk_cnt),
	.sd_rd(sd_rd[0]),
	.sd_wr(sd_wr[0]),
	.sd_ack(sd_ack[0]),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(drv_sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.rom_addr(load_rom ? (ioctl_addr[15:0] - 16'h4000) : {1'b1,ioctl_addr[14:0]}),
	.rom_data(ioctl_data),
	.rom_wr(((load_rom && ioctl_addr[16:14]) || load_c1581) && ioctl_download && ioctl_wr),
	.rom_std(status[14]),

	.DDRAM_BUSY(DDRAM_BUSY),
	.DDRAM_BURSTCNT(drv_ddram_burstcnt),
	.DDRAM_ADDR(drv_ddram_addr),
	.DDRAM_DOUT(DDRAM_DOUT),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
	.DDRAM_RD(drv_ddram_rd),
	.DDRAM_WE(drv_ddram_we),
	.DDRAM_DIN(drv_ddram_din),
	.DDRAM_BE(drv_ddram_be)
	);

reg drive_ce;
always @(posedge clk_sys) begin
	int sum = 0;
	int msum;
	
	msum <= ntsc ? 32727264 : 31527954;

	drive_ce <= 0;
	sum = sum + 16000000;
	if(sum >= msum) begin
		sum = sum - msum;
		drive_ce <= 1;
	end
end

wire disk_parport = ~status[44];

reg disk_access;
always @(posedge clk_sys) begin
	reg c64_iec_clk_old, drive_iec_clk_old, drive_stb_i_old, drive_stb_o_old;
	integer to = 0;

	c64_iec_clk_old <= c64_iec_clk;
	drive_iec_clk_old <= drive_iec_clk;
	drive_stb_i_old <= drive_stb_i;
	drive_stb_o_old <= drive_stb_o;
	
	if(((c64_iec_clk_old != c64_iec_clk) || (drive_iec_clk_old != drive_iec_clk)) || 
		(disk_parport && ((drive_stb_i_old != drive_stb_i) || (drive_stb_o_old != drive_stb_o))))
	begin
		disk_access <= 1;
		to <= 16000000; // 0.5s
	end
	else if(to) to <= to - 1;
	else disk_access <= 0;
end

wire ext_iec_en   = status[25];
wire ext_iec_clk  = |snac_mode ? 1'b1 : (USER_IN[2] | ~ext_iec_en);
wire ext_iec_data = |snac_mode ? 1'b1 : (USER_IN[4] | ~ext_iec_en);


wire wide = 1'b0;


wire hsync;
wire vsync;
wire hblank;
wire vblank;
wire hsync_out;
wire vsync_out;

video_sync sync
(
	.clk32(clk_sys),
	.pause(c64_pause),
	.hsync(hsync),
	.vsync(vsync),
	.ntsc(ntsc),
	.wide(wide),
	.hsync_out(hsync_out),
	.vsync_out(vsync_out),
	.hblank(hblank),
	.vblank(vblank)
);


// OSD pause (status[42]) while the Pocket menu is open, switched at frame start
reg freeze = 0;
always @(posedge clk_sys) begin
	reg old_vs;
	old_vs <= vsync_out;
	if (~old_vs & vsync_out) freeze <= OSD_STATUS & status[42];
end

wire [63:0] dbg_ddram_data = 0, dbg_wr_data = 0;
wire [31:0] dbg_out_addr = 0, dbg_wr_addr = 0, dbg_base_addr = 32'h06000000;
wire        dbg_valid = 0, dbg_wr_valid = 0;

// Drive Overlay display:
//  - three modes: on activity (default), if enabled, debug and off
//  - color coded: green for idle (only shows in "if enabled" and "debug" mode)
//                 yellow for (read) activity (via drive led)
//                 red for write activity (covers writes to disk & flushing to sd)
//  - track number: Full tracks and half tracks (e.g. 33.5)
//  - drive number: (#8, #9)
//  - auto adjusts for pal/ntsc
//
// debug mode captures DDRAM reads/writes:
//  - reads displayed on the left (green), writes on the right (yellow)
//  - rolling buffer (top 8 lines) shows the last 8 reads/writes and addresses
//  - base address captures (botoom 8 lines) shows 8 read/writes starting at base address
//  - base address can be changed in real time with cursor keys (left, right, up, down)
//  - captures live read/writes not memory content, so set address before you expect read/writes (!)
//
//
wire [2:0] drv_ovl_color;

reg [1:0] ce_sys_div = 0;
wire ce_sys = (ce_sys_div == 0);
always @(posedge clk_sys) ce_sys_div <= ce_sys_div + 1'd1;

drv_overlay drv_ovl (
	.clk(clk_sys),
	.ce(ce_sys),
	.hblank(hblank),
	.vblank(vblank),

	.drive_osd_mode(status[86:85]),
	.ntsc(ntsc),
	.drive_led(drive_led),
	.drive_mounted(drive_mounted),
	.drive_track_0(drive_track[0]),
	.drive_track_1(drive_track[1]),
	.drive_we(drive_we),

	.valid(dbg_valid),
	.addr(dbg_out_addr),
	.data(dbg_ddram_data),
	.wr_valid(dbg_wr_valid),
	.wr_addr(dbg_wr_addr),
	.wr_data(dbg_wr_data),
	.base_addr(dbg_base_addr),

	.pixel_color(drv_ovl_color)
);

reg [2:0] ovl_color;
always @(posedge clk_sys) begin
	ovl_color <= tape_ovl_color | drv_ovl_color;
	VGA_R  <= (ovl_color & 4) ? 8'hFF : ovl_color ? 8'h00 : r;
	VGA_G  <= (ovl_color & 2) ? 8'hFF : ovl_color ? 8'h00 : g;
	VGA_B  <= (ovl_color & 1) ? 8'hFF : ovl_color ? 8'h00 : b;
	VGA_HS <= hsync_out;
	VGA_VS <= vsync_out;
	VGA_HB <= hblank;
	VGA_VB <= vblank;
end

// No OPL2 Sound Expander: it does not fit next to the drive.
wire        opl_en = 1'b0;
wire [15:0] opl_out = 16'd0;
wire  [7:0] opl_dout = 8'h00;

reg ioe_we, iof_we;
always @(posedge clk_sys) begin
	reg old_ioe, old_iof;

	old_ioe <= IOE;
	ioe_we <= ~old_ioe & IOE & ram_we;

	old_iof <= IOF;
	iof_we <= ~old_iof & IOF & ram_we;
end

reg [11:0] sid_ld_addr = 0;
reg [15:0] sid_ld_data = 0;
reg        sid_ld_wr   = 0;
always @(posedge clk_sys) begin
	sid_ld_wr <= 0;
	if(ioctl_wr && load_flt && ioctl_addr < 6144) begin
		if(ioctl_addr[0]) begin
			sid_ld_data[15:8] <= ioctl_data;
			sid_ld_addr <= ioctl_addr[12:1];
			sid_ld_wr <= 1;
		end
		else begin
			sid_ld_data[7:0] <= ioctl_data;
		end
	end
end

//DigiMax
reg [8:0] dac_l, dac_r;
always @(posedge clk_sys) begin
	reg [8:0] dac[4];
	reg [3:0] act;

	if(!status[41:40] || ~reset_n) begin
		dac <= '{0,0,0,0};
		act <= 0;
	end
	else if((status[41] ? iof_we : ioe_we) && ~c64_addr[2]) begin
		dac[c64_addr[1:0]] <= c64_data_out;
		if(c64_data_out) act[c64_addr[1:0]] <= 1;
	end

	// guess mono/stereo/4-chan modes
	if(act<2) begin
		dac_l <= dac[0] + dac[0];
		dac_r <= dac[0] + dac[0];
	end
	else if(act<3) begin
		dac_l <= dac[1] + dac[1];
		dac_r <= dac[0] + dac[0];
	end
	else begin
		dac_l <= dac[1] + dac[2];
		dac_r <= dac[0] + dac[3];
	end
end

localparam [3:0] comp_f1 = 4;
localparam [3:0] comp_a1 = 2;
localparam       comp_x1 = ((32767 * (comp_f1 - 1)) / ((comp_f1 * comp_a1) - 1)) + 1; // +1 to make sure it won't overflow
localparam       comp_b1 = comp_x1 * comp_a1;

function [15:0] compr; input [15:0] inp;
	reg [15:0] v, v1;
	begin
		v  = inp[15] ? (~inp) + 1'd1 : inp;
		v1 = (v < comp_x1[15:0]) ? (v * comp_a1) : (((v - comp_x1[15:0])/comp_f1) + comp_b1[15:0]);
		v  = v1;
		compr = inp[15] ? ~(v-1'd1) : v;
	end
endfunction

reg [15:0] alo,aro;
always @(posedge clk_sys) begin
	reg [16:0] alm,arm;
	reg [15:0] cout;
	reg [15:0] cin;
	
	cin  <= opl_out - {{3{opl_out[15]}},opl_out[15:3]};
	cout <= compr(cin);

	alm <= {cout[15],cout} + {audio_l[17],audio_l[17:2]} + {2'b0,dac_l,6'd0} + {cass_snd, 9'd0};
	arm <= {cout[15],cout} + {audio_r[17],audio_r[17:2]} + {2'b0,dac_r,6'd0} + {cass_snd, 9'd0};
	alo <= ^alm[16:15] ? {alm[16], {15{alm[15]}}} : alm[15:0];
	aro <= ^arm[16:15] ? {arm[16], {15{arm[15]}}} : arm[15:0];
end

assign AUDIO_L = alo;
assign AUDIO_R = aro;

//------------- TAP / C1530 Datassette -------------------

wire       cass_write;
wire       cass_motor;
wire       cass_sense;
wire       cass_read;
wire       cass_run;
wire       cass_finish;
wire       cass_snd = cass_read & ~cass_run & status[11] & ~cass_finish;

wire       tap_loaded;
wire [24:0] tap_play_addr;
wire [24:0] tap_last_addr;

wire [2:0] tape_ovl_color;

tape_subsystem tape
(
	.clk(clk_sys),
	.ce(ce_sys),
	.reset_n(reset_n),
	.hblank(hblank),
	.vblank(vblank),
	.ntsc(ntsc),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_data(ioctl_data),
	.load_tap(load_tap),
	.ioctl_wait(tape_ioctl_wait),

	.io_cycle(io_cycle),
	.sdram_data(sdram_data),

	.cmd_play(status[7] | tape_play),
	.cmd_stop(status[95] | tape_key_stop),
	.cmd_rew(status[93] | tape_key_rew),
	.cmd_ff(status[94] | tape_key_ff),
	.cmd_unload(status[23]),
	.cmd_counter_reset(status[91] | tape_key_counter_reset),
	.counter_enable(status[92]),
	.tape_autoplay_off(status[39]),
	.tape_autounload_off(status[96]),

	.cass_write(cass_write),
	.cass_motor(cass_motor),
	.cass_sense(cass_sense),
	.cass_read(cass_read),
	.cass_run(cass_run),
	.cass_finish(cass_finish),

	.tap_loaded(tap_loaded),
	.tap_play_addr(tap_play_addr),
	.tap_last_addr(tap_last_addr),

	.pixel_color(tape_ovl_color)
);

reg use_tape;
always @(posedge clk_sys) begin
	integer to = 0;

	if(to) to <= to - 1;
	else use_tape <= status[36];

	if(tap_loaded | ~cass_sense) begin
		use_tape <= 1;
		to <= 128000000; //4s
	end
end

reg [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + (cass_sense ? 4'd1 : 4'd8);
wire tape_led = tap_loaded && (act_cnt[26] ? (~(~cass_sense & cass_motor) && act_cnt[25:18] > act_cnt[7:0]) : act_cnt[25:18] <= act_cnt[7:0]);

wire tape_adc = 1'b0, tape_adc_act = 1'b0;

//------------- USER PORT -----------------

wire [7:0] pb_i, pb_o;
wire       pa2_i, pa2_o;
wire       pc2_n_o;
wire       flag2_n_i;
wire       sp2_i, sp2_o, sp1_o, sp1_i;
wire       cnt2_i, cnt2_o, cnt1_o, cnt1_i;

always_comb begin
	pa2_i       = 1;
	flag2_n_i   = 1;
	sp1_i       = 1;
	sp2_i       = 1;
	cnt1_i      = 1;
	cnt2_i      = 1;
	pb_i        = 8'hFF;
	UART_TXD    = 1;
	UART_RTS    = 0;
	UART_DTR    = 0;
	drive_par_i = 8'hFF;
	drive_stb_i = 1;

	if(disk_parport & disk_access) begin
		drive_par_i = pb_o;
		drive_stb_i = pc2_n_o;
		pb_i        = drive_par_o;
		flag2_n_i   = drive_stb_o;
	end
	else if(status[43]) begin
		UART_TXD  = pa2_o & uart_int;
		flag2_n_i = uart_rxd;
		sp2_i     = uart_rxd;
		pb_i[0]   = uart_rxd;
		UART_RTS  = ~pb_o[1] & uart_int;
		UART_DTR  = ~pb_o[2] & uart_int;
		pb_i[4]   = ~uart_dsr;
		pb_i[6]   = ~uart_cts;
		pb_i[7]   = ~uart_dsr;


		if(~status[51]) begin
			UART_TXD = pa2_o & sp1_o & uart_int;
			pb_i[7]  = cnt2_o;
			cnt2_i   = pb_o[7];

		end
	end
	else begin
		pb_i[5:0] = {!joyD_c64[6:4], !joyC_c64[6:4], pb_o[7] ? ~joyC_c64[3:0] : ~joyD_c64[3:0]};
	end
end

wire uart_int = ~status[33];

reg uart_rxd, uart_dsr, uart_cts;
always @(posedge clk_sys) begin
	reg rxd1, rxd2, dsr1, dsr2, cts1, cts2;

	rxd1 <= uart_int ? UART_RXD : USER_IN[0]; rxd2 <= rxd1; if(rxd1 == rxd2) uart_rxd <= rxd2;
	cts1 <= UART_CTS & uart_int; cts2 <= cts1; if(cts1 == cts2) uart_cts <= cts2;
	dsr1 <= UART_DSR & uart_int; dsr2 <= dsr1; if(dsr1 == dsr2) uart_dsr <= dsr2;
end

wire rtcF83_sda;
rtcF83 #(16000000, 0) rtcF83
(
	.clk(clk_sys),
	.ce(drive_ce),
	.reset(~reset_n | use_tape),
	.RTC(RTC),
	.scl_i(cass_write),
	.sda_i(cass_motor),
	.sda_o(rtcF83_sda)
);

reg use_rtc = 0;
always @(posedge clk_sys) begin
	reg [20:0] to = 0;

	if(to) to <= to - 1'd1;
	use_rtc <= |to;

	if(cass_write) to <= '1;
end

wire cass_rtc = ~(rtcF83_sda & use_rtc & cass_motor);

assign tape_loaded = tap_loaded;
assign disk_ready_out = disk_ready;

// The KERNAL waits for a key in its loop at $E5CD-$E5D5 (the same in the standard, Japanese
// and DolphinDOS kernals); at the BASIC prompt the CPU spends most of its time there.
// Measured over ~33 ms windows of clk_sys.
initial at_prompt = 1'b0;
always @(posedge clk_sys) begin
	reg [19:0] win = 0;
	reg [19:0] hits = 0;
	win <= win + 1'd1;
	if (c64_addr >= 16'hE5CD && c64_addr <= 16'hE5D5) hits <= hits + 1'd1;
	if (&win) begin
		at_prompt <= reset_n && hits > 20'd65536;
		hits <= 0;
	end
end

// $0302 (IMAIN) points here in every bundled ROM; a program that starts itself after LOAD never runs it
initial basic_main = 1'b0;
always @(posedge clk_sys) basic_main <= c64_addr == 16'hA483;


endmodule

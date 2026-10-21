// Full-system testbench: core_top (the Pocket top) with a model of the Analogue APF host/target
// command side, a 16-bit SDR SDRAM model and the real C64 machine. See README.md.
//
// Plusargs: +test=all|boot|prg|t64|crt|tap   (default all, in that order, one boot)
//           +dump_from=<us> +dump_to=<us>  FST (needs a TRACE=1 build) of the media / bridge / c64_top signals
//           +order=0|1                   boot order: 0 = reset-exit, datatable, all-complete (task text)
//                                                    1 = datatable, all-complete, reset-exit
//           +gap=<n>                     clk_74a cycles between bridge data words (default 2)
`timescale 1ps/1ps

module tb;

// ---------------------------------------------------------------- clocks / DUT
reg clk_74a = 0;
always #6734 clk_74a = ~clk_74a;          // 74.25 MHz
reg clk_74b = 0;

reg  [31:0] bridge_addr = 0;
reg         bridge_rd = 0, bridge_wr = 0;
reg  [31:0] bridge_wr_data = 0;
wire [31:0] bridge_rd_data;

wire [12:0] dram_a;
wire  [1:0] dram_ba, dram_dqm;
tri  [15:0] dram_dq;
wire        dram_clk, dram_cke, dram_ras_n, dram_cas_n, dram_we_n;

wire [21:16] cram0_a;
tri  [15:0]  cram0_dq;
wire         cram0_wait_w;
wire         cram0_clk, cram0_adv_n, cram0_cre, cram0_ce0_n, cram0_ce1_n, cram0_oe_n, cram0_we_n, cram0_ub_n, cram0_lb_n;
wire [21:16] cram1_a;
tri  [15:0]  cram1_dq;
wire         cram1_clk, cram1_adv_n, cram1_cre, cram1_ce0_n, cram1_ce1_n, cram1_oe_n, cram1_we_n, cram1_ub_n, cram1_lb_n;
wire [16:0]  sram_a;
tri  [15:0]  sram_dq;
wire         sram_oe_n, sram_we_n, sram_ub_n, sram_lb_n;

tri [7:0] cart_tran_bank2, cart_tran_bank3, cart_tran_bank1;
tri [7:4] cart_tran_bank0;
wire cart_tran_bank2_dir, cart_tran_bank3_dir, cart_tran_bank1_dir, cart_tran_bank0_dir;
tri cart_tran_pin30, cart_tran_pin31;
wire cart_tran_pin30_dir, cart_tran_pin31_dir, cart_pin30_pwroff_reset;
wire port_ir_tx, port_ir_rx_disable;
tri port_tran_si, port_tran_so, port_tran_sck, port_tran_sd;
wire port_tran_si_dir, port_tran_so_dir, port_tran_sck_dir, port_tran_sd_dir;
wire dbg_tx;
tri user1;
tri aux_sda;
wire aux_scl, vpll_feed;

wire [23:0] video_rgb;
wire video_rgb_clock, video_rgb_clock_90, video_de, video_skip, video_vs, video_hs;
wire audio_mclk, audio_dac, audio_lrck;
wire bridge_endian_little;

core_top dut (
	.clk_74a(clk_74a), .clk_74b(clk_74b),
	.cart_tran_bank2(cart_tran_bank2), .cart_tran_bank2_dir(cart_tran_bank2_dir),
	.cart_tran_bank3(cart_tran_bank3), .cart_tran_bank3_dir(cart_tran_bank3_dir),
	.cart_tran_bank1(cart_tran_bank1), .cart_tran_bank1_dir(cart_tran_bank1_dir),
	.cart_tran_bank0(cart_tran_bank0), .cart_tran_bank0_dir(cart_tran_bank0_dir),
	.cart_tran_pin30(cart_tran_pin30), .cart_tran_pin30_dir(cart_tran_pin30_dir),
	.cart_pin30_pwroff_reset(cart_pin30_pwroff_reset),
	.cart_tran_pin31(cart_tran_pin31), .cart_tran_pin31_dir(cart_tran_pin31_dir),
	.port_ir_rx(1'b0), .port_ir_tx(port_ir_tx), .port_ir_rx_disable(port_ir_rx_disable),
	.port_tran_si(port_tran_si), .port_tran_si_dir(port_tran_si_dir),
	.port_tran_so(port_tran_so), .port_tran_so_dir(port_tran_so_dir),
	.port_tran_sck(port_tran_sck), .port_tran_sck_dir(port_tran_sck_dir),
	.port_tran_sd(port_tran_sd), .port_tran_sd_dir(port_tran_sd_dir),
	.cram0_a(cram0_a), .cram0_dq(cram0_dq), .cram0_wait(cram0_wait_w), .cram0_clk(cram0_clk),
	.cram0_adv_n(cram0_adv_n), .cram0_cre(cram0_cre), .cram0_ce0_n(cram0_ce0_n), .cram0_ce1_n(cram0_ce1_n),
	.cram0_oe_n(cram0_oe_n), .cram0_we_n(cram0_we_n), .cram0_ub_n(cram0_ub_n), .cram0_lb_n(cram0_lb_n),
	.cram1_a(cram1_a), .cram1_dq(cram1_dq), .cram1_wait(1'b0), .cram1_clk(cram1_clk),
	.cram1_adv_n(cram1_adv_n), .cram1_cre(cram1_cre), .cram1_ce0_n(cram1_ce0_n), .cram1_ce1_n(cram1_ce1_n),
	.cram1_oe_n(cram1_oe_n), .cram1_we_n(cram1_we_n), .cram1_ub_n(cram1_ub_n), .cram1_lb_n(cram1_lb_n),
	.dram_a(dram_a), .dram_ba(dram_ba), .dram_dq(dram_dq), .dram_dqm(dram_dqm), .dram_clk(dram_clk),
	.dram_cke(dram_cke), .dram_ras_n(dram_ras_n), .dram_cas_n(dram_cas_n), .dram_we_n(dram_we_n),
	.sram_a(sram_a), .sram_dq(sram_dq), .sram_oe_n(sram_oe_n), .sram_we_n(sram_we_n),
	.sram_ub_n(sram_ub_n), .sram_lb_n(sram_lb_n),
	.vblank(1'b0),
	.dbg_tx(dbg_tx), .dbg_rx(1'b0),
	.user1(user1), .user2(1'b0),
	.aux_sda(aux_sda), .aux_scl(aux_scl),
	.vpll_feed(vpll_feed),
	.video_rgb(video_rgb), .video_rgb_clock(video_rgb_clock), .video_rgb_clock_90(video_rgb_clock_90),
	.video_de(video_de), .video_skip(video_skip), .video_vs(video_vs), .video_hs(video_hs),
	.audio_mclk(audio_mclk), .audio_adc(1'b0), .audio_dac(audio_dac), .audio_lrck(audio_lrck),
	.bridge_endian_little(bridge_endian_little),
	.bridge_addr(bridge_addr), .bridge_rd(bridge_rd), .bridge_rd_data(bridge_rd_data),
	.bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data),
	.cont1_key(32'd0), .cont2_key(32'd0), .cont3_key(32'd0), .cont4_key(32'd0),
	.cont1_joy(32'd0), .cont2_joy(32'd0), .cont3_joy(32'd0), .cont4_joy(32'd0),
	.cont1_trig(16'd0), .cont2_trig(16'd0), .cont3_trig(16'd0), .cont4_trig(16'd0)
);

sdram_model sdr (
	.clk(dram_clk), .cke(dram_cke), .cs_n(1'b0), .ras_n(dram_ras_n), .cas_n(dram_cas_n),
	.we_n(dram_we_n), .ba(dram_ba), .a(dram_a), .dqm(dram_dqm), .dq(dram_dq)
);

psram_model psr (
	.a(cram0_a), .dq(cram0_dq), .clk(cram0_clk), .adv_n(cram0_adv_n), .cre(cram0_cre), .ce0_n(cram0_ce0_n),
	.ce1_n(cram0_ce1_n), .oe_n(cram0_oe_n), .we_n(cram0_we_n), .ub_n(cram0_ub_n), .lb_n(cram0_lb_n), .wait_o(cram0_wait_w)
);

// ---------------------------------------------------------------- APF bridge model
integer GAP = 2;

task automatic apf_wr(input [31:0] a, input [31:0] d);
	begin
		@(negedge clk_74a); bridge_addr = a; bridge_wr_data = d; bridge_wr = 1;
		@(negedge clk_74a); bridge_wr = 0;
	end
endtask

task automatic apf_rd(input [31:0] a, output [31:0] d);
	begin
		@(negedge clk_74a); bridge_addr = a; bridge_rd = 1;
		@(negedge clk_74a); bridge_rd = 0;
		@(negedge clk_74a);
		d = bridge_rd_data;
	end
endtask

// host command: params to 0x20/0x24, command to 0x0, poll for 0x4F4B
task automatic apf_host(input [15:0] cmd, input [31:0] p0, input [31:0] p1);
	reg [31:0] r;
	integer n;
	begin
		apf_wr(32'hF8000020, p0);
		apf_wr(32'hF8000024, p1);
		apf_wr(32'hF8000000, {16'h434D, cmd});
		r = 0; n = 0;
		while (r[31:16] != 16'h4F4B && n < 1000) begin
			apf_rd(32'hF8000000, r);
			n = n + 1;
		end
		if (r[31:16] != 16'h4F4B) $display("[%0t] APF: host command %h did not complete (%h)", $time, cmd, r);
	end
endtask

// ---------------------------------------------------------------- files behind the data slots
reg [7:0] slot_data [0:5][0:1048575];
reg [7:0] filebuf [0:1048575];
integer   wr_cmds = 0, wr_bytes = 0;
integer   slot_len  [0:5];
integer   target_cmds = 0, target_bytes = 0;
integer   last_req_slot = -1, last_req_off = 0, last_req_len = 0;
integer   quiet = 0;

task automatic apf_set_slot(input integer id, input integer size);
	begin
		// datatable entry first (words {id}, {size}), then Data Slot Update (0x008A)
		apf_wr(32'hF8002000 + 8 * id, id);
		repeat (GAP) @(negedge clk_74a);
		apf_wr(32'hF8002000 + 8 * id + 4, size);
		repeat (GAP) @(negedge clk_74a);
		apf_host(16'h008A, id, size);
	end
endtask

// one poll of the target command register; serve it if there is a command
task automatic apf_poll_once;
	reg [31:0] t0, id, off, baddr, len, w;
	integer i, nw, b;
	begin
		apf_rd(32'hF8001000, t0);
		if (t0[31:16] == 16'h636D) begin
			case (t0[15:0])
			16'h0140: begin
				if (!quiet) $display("[%0t] APF: target ready-to-run (0140) acknowledged", $time);
				apf_wr(32'hF8001000, 32'h6F6B0000);
			end
			16'h0180: begin
				apf_rd(32'hF8001020, id);
				apf_rd(32'hF8001024, off);
				apf_rd(32'hF8001028, baddr);
				apf_rd(32'hF800102C, len);
				target_cmds = target_cmds + 1;
				last_req_slot = id; last_req_off = off; last_req_len = len;
				if (!quiet) $display("[%0t] APF: target read slot %0d offset %0d bridge %h length %0d", $time, id, off, baddr, len);
				apf_wr(32'hF8001000, 32'h62750000);
				nw = (len + 3) / 4;
				for (i = 0; i < nw; i = i + 1) begin
					w = 0;
					for (b = 0; b < 4; b = b + 1)
						if (i * 4 + b < len && off + i * 4 + b < slot_len[id])
							w[31 - 8 * b -: 8] = slot_data[id][off + i * 4 + b];
					apf_wr(baddr + 4 * i, w);
					repeat (GAP) @(negedge clk_74a);
				end
				target_bytes = target_bytes + len;
				apf_wr(32'hF8001000, 32'h6F6B0000);
			end
			16'h0184: begin
				apf_rd(32'hF8001020, id);
				apf_rd(32'hF8001024, off);
				apf_rd(32'hF8001028, baddr);
				apf_rd(32'hF800102C, len);
				wr_cmds = wr_cmds + 1;
				if (!quiet) $display("[%0t] APF: target WRITE slot %0d offset %0d bridge %h length %0d", $time, id, off, baddr, len);
				apf_wr(32'hF8001000, 32'h62750000);
				nw = (len + 3) / 4;
				for (i = 0; i < nw; i = i + 1) begin
					apf_rd(baddr + 4 * i, w);
					for (b = 0; b < 4; b = b + 1)
						if (i * 4 + b < len) slot_data[id][off + i * 4 + b] = w[31 - 8 * b -: 8];
				end
				if (off + len > slot_len[id]) slot_len[id] = off + len;
				wr_bytes = wr_bytes + len;
				apf_wr(32'hF8001000, 32'h6F6B0000);
			end
			default: begin
				$display("[%0t] APF: unhandled target command %h", $time, t0[15:0]);
				apf_wr(32'hF8001000, 32'h6F6B0001);
			end
			endcase
		end
	end
endtask

// poll the target interface for `us` microseconds of simulated time
task automatic apf_run_us(input integer us);
	realtime t_end;
	begin
		t_end = $realtime + us * 1000000.0;
		while ($realtime < t_end) begin
			apf_poll_once;
			repeat (50) @(negedge clk_74a);
		end
	end
endtask

// ---------------------------------------------------------------- monitors
integer ioctl_wr_cnt = 0, ioctl_dl_cnt = 0;
reg     ioctl_dl_d = 0;
reg     rw_d = 0, rn_d = 0, er_d = 0, im_d = 0, ss_d = 0, ca_d = 0, tl_d = 0;
integer reset_n_falls = 0, tape_loaded_cnt = 0;
realtime t_dl_rise, t_dl_fall, t_rw_rise, t_rw_fall, t_reset_fall, t_erase_start, t_erase_end, t_inj_start, t_inj_end, t_strk;
integer erase_ev = 0;
integer rdy_hits = 0;
reg [7:0] first_bytes [0:7];

always @(posedge dut.clk_sys) begin
	ioctl_dl_d <= dut.ioctl_download;
	if (dut.ioctl_wr) begin ioctl_wr_cnt <= ioctl_wr_cnt + 1; if (dut.ioctl_index == 8'h01 && !quiet) $display("[%0t] ioctl_wr addr=%0d data=%h load_addr=%h", $time, dut.ioctl_addr, dut.ioctl_data, dut.c64.ioctl_load_addr); end
	if (dut.ioctl_download && !ioctl_dl_d) begin
		ioctl_dl_cnt <= ioctl_dl_cnt + 1;
		ioctl_wr_cnt <= 0;
		t_dl_rise = $realtime;
		if (!quiet) $display("[%0t] ioctl_download rise, index %h", $time, dut.ioctl_index);
	end
	if (!dut.ioctl_download && ioctl_dl_d) begin
		t_dl_fall = $realtime;
		if (!quiet) $display("[%0t] ioctl_download fall, %0d ioctl_wr strobes, last addr %0d", $time, ioctl_wr_cnt, dut.ioctl_addr);
	end
	rw_d <= dut.c64.reset_wait; rn_d <= dut.c64.reset_n; er_d <= dut.c64.erasing; im_d <= dut.c64.inj_meminit;
	ss_d <= dut.c64.start_strk; ca_d <= dut.c64.cart_attached; tl_d <= dut.media.tape_loaded;
	if (dut.c64.reset_wait && !rw_d) begin t_rw_rise = $realtime; if (!quiet) $display("[%0t] reset_wait rise", $time); end
	if (!dut.c64.reset_wait && rw_d) begin t_rw_fall = $realtime; if (!quiet) $display("[%0t] reset_wait fall (c64_addr FFCF seen)", $time); end
	if (!dut.c64.reset_n && rn_d) begin reset_n_falls <= reset_n_falls + 1; t_reset_fall = $realtime; if (!quiet) $display("[%0t] c64 reset_n fall", $time); end
	if (dut.c64.reset_n && !rn_d) if (!quiet) $display("[%0t] c64 reset_n rise", $time);
	if (dut.c64.erasing && !er_d) begin t_erase_start = $realtime; if (!quiet) $display("[%0t] RAM erase start", $time); end
	if (!dut.c64.erasing && er_d) begin t_erase_end = $realtime; if (!quiet) $display("[%0t] RAM erase end", $time); end
	if (dut.c64.inj_meminit && !im_d) begin t_inj_start = $realtime; if (!quiet) $display("[%0t] inj_meminit start", $time); end
	if (!dut.c64.inj_meminit && im_d) begin t_inj_end = $realtime; if (!quiet) $display("[%0t] inj_meminit end", $time); end
	if (dut.c64.start_strk && !ss_d) begin t_strk = $realtime; if (!quiet) $display("[%0t] start_strk (RUN will be typed)", $time); end
	if (dut.c64.cart_attached != ca_d && !quiet) $display("[%0t] cart_attached = %b", $time, dut.c64.cart_attached);
	if (dut.media.tape_loaded) begin tape_loaded_cnt <= tape_loaded_cnt + 1; if (!quiet) $display("[%0t] media.tape_loaded pulse", $time); end
	if (dut.c64.c64_addr >= 16'hE5CD && dut.c64.c64_addr <= 16'hE5D5) rdy_hits <= rdy_hits + 1;
end

reg [5:0] st_d = 0;
integer upd_w = 0;
reg [3:0] tss_d = 0; reg [24:0] tla_d = 0; reg te_d = 0, trs_d = 0, tdl_d = 0;
always @(posedge dut.clk_sys) begin
	tss_d <= dut.c64.tape.tap_scanner.state; tla_d <= dut.c64.tape.tap_last_addr_r; te_d <= dut.c64.tape.tape_end; trs_d <= dut.c64.tape.tap_reset; tdl_d <= dut.c64.tape.tap_download;
	if (dut.c64.tape.tap_scanner.state != tss_d) $display("[%0t] tap_scanner.state %0d -> %0d", $time, tss_d, dut.c64.tape.tap_scanner.state);
	if (dut.c64.tape.tap_last_addr_r != tla_d && (dut.c64.tape.tap_last_addr_r == 0 || tla_d == 0)) $display("[%0t] tap_last_addr %h -> %h (tap_download=%b tape_end=%b reset_n=%b)", $time, tla_d, dut.c64.tape.tap_last_addr_r, dut.c64.tape.tap_download, dut.c64.tape.tape_end, dut.c64.tape.reset_n);
	if (dut.c64.tape.tape_end != te_d) $display("[%0t] tape_end -> %b", $time, dut.c64.tape.tape_end);
end
reg [5:0] pend_d = 0;
reg upd_d = 0, rq_d = 0;
always @(posedge dut.clk_74a) begin
	upd_d <= dut.dataslot_update; rq_d <= dut.target_dataslot_read;
	if (dut.dataslot_update) upd_w <= upd_w + 1;
	if (!dut.dataslot_update && upd_d) $display("[%0t] icb: dataslot_update was high for %0d clk_74a cycles", $time, upd_w);
	if (dut.dataslot_update && !upd_d) upd_w <= 1;
	if (dut.dataslot_update && !upd_d) $display("[%0t] icb: dataslot_update id=%0d size=%0d", $time, dut.dataslot_update_id, dut.dataslot_update_size);
	if (dut.target_dataslot_read && !rq_d) $display("[%0t] media: target_dataslot_read id=%0d off=%0d len=%0d", $time, dut.target_dataslot_id, dut.target_dataslot_slotoffset, dut.target_dataslot_length);
end
always @(posedge dut.clk_sys) begin
	st_d <= dut.media.state;
	pend_d <= dut.media.pending;
	if (dut.media.pending != pend_d) $display("[%0t] media.pending %b -> %b", $time, pend_d, dut.media.pending);
	if (dut.media.state != st_d && !quiet && (dut.media.state == 1 || dut.media.state == 4 || dut.media.state == 8 || dut.media.state == 9 ||
	    dut.media.state == 11 || dut.media.state == 21 || dut.media.state == 22 || dut.media.state == 25 || dut.media.state == 26 ||
	    dut.media.state == 28 || dut.media.state == 30))
		$display("[%0t] media.state %0d -> %0d (slot %0d)", $time, st_d, dut.media.state, dut.media.slot);
end

integer dbg_n = 0;
reg [15:0] dbg_last = 0;
always @(posedge dut.clk_sys) if ($realtime > 109_700_000_000.0 && dbg_n < 0 && dut.c64.c64_addr != dbg_last && dut.c64.ram_ce) begin
	dbg_last <= dut.c64.c64_addr; dbg_n <= dbg_n + 1;
	$display("DBG %0t addr=%h we=%b dout=%h din=%h", $time, dut.c64.c64_addr, dut.c64.ram_we, dut.c64.c64_data_out, dut.c64.c64_data_in);
end

// ---------------------------------------------------------------- checks
integer fails = 0, passes = 0;
task automatic check(input cond, input [8*72-1:0] what);
	begin
		if (cond) begin passes = passes + 1; $display("  PASS  %0s", what); end
		else begin fails = fails + 1; $display("  FAIL  %0s", what); end
	end
endtask

function [7:0] pk(input [24:0] a);
	pk = sdr.peek8(a);
endfunction

function screen_has_ready;
	input dummy;
	integer a, j;
	reg ok;
	begin
		screen_has_ready = 0;
		for (a = 16'h0400; a < 16'h0400 + 1000 - 6; a = a + 1) begin
			ok = 1;
			if (pk(a + 0) !== 8'h12) ok = 0;
			if (pk(a + 1) !== 8'h05) ok = 0;
			if (pk(a + 2) !== 8'h01) ok = 0;
			if (pk(a + 3) !== 8'h04) ok = 0;
			if (pk(a + 4) !== 8'h19) ok = 0;
			if (pk(a + 5) !== 8'h2E) ok = 0;
			if (ok) screen_has_ready = 1;
		end
	end
endfunction

task automatic dump_screen;
	integer r, c;
	reg [7:0] b;
	reg [8*40-1:0] line;
	begin
		for (r = 0; r < 25; r = r + 1) begin
			for (c = 0; c < 40; c = c + 1) begin
				b = pk(25'h400 + r * 40 + c);
				b = b & 8'h7F;
				if (b >= 1 && b <= 26) b = b + 8'h40;
				else if (b == 0) b = 8'h40;
				else if (b < 8'h20 || b > 8'h5F) b = 8'h2E;
				line[8*(39-c) +: 8] = b;
			end
			$display("   |%0s|", line);
		end
	end
endtask

integer sd_rd_cnt = 0, sd_wr_cnt = 0;
always @(posedge dut.clk_sys) begin
	if (|dut.sd_rd) sd_rd_cnt <= sd_rd_cnt + 1;
	if (|dut.sd_wr) sd_wr_cnt <= sd_wr_cnt + 1;
end
reg show_screen = 0;
integer hb = 0;
always #1_000_000_000_000 if (show_screen) begin $display("[%0t] screen, sd_rd cycles %0d sd_wr cycles %0d:", $time, sd_rd_cnt, sd_wr_cnt); dump_screen; end

task automatic dump_state(input [8*40-1:0] tag);
	begin
		$display("--- state dump (%0s) at %0t ---", tag, $time);
		$display("  c64_media.state=%0d slot=%0d pending=%b req_busy=%b req_t=%b ack_t_s=%b estate=%0d",
			dut.media.state, dut.media.slot, dut.media.pending, dut.media.req_busy, dut.media.req_t, dut.media.ack_t_s, dut.media.estate);
		$display("  size_74[0..5]=%0d %0d %0d %0d %0d %0d fsize=%0d foff=%0d clen=%0d ci=%0d",
			dut.media.size_74[0], dut.media.size_74[1], dut.media.size_74[2], dut.media.size_74[3], dut.media.size_74[4], dut.media.size_74[5],
			dut.media.fsize, dut.media.foff, dut.media.clen, dut.media.ci);
		$display("  ioctl_wait=%b (ioctl_req_wr=%b reset_wait=%b tape_ioctl_wait=%b) ioctl_download=%b ioctl_addr=%0d",
			dut.ioctl_wait, dut.c64.ioctl_req_wr, dut.c64.reset_wait, dut.c64.tape_ioctl_wait, dut.ioctl_download, dut.ioctl_addr);
		$display("  c64 reset_n=%b reset_counter-sensitive: erasing=%b inj_meminit=%b c64_addr=%h cart_attached=%b",
			dut.c64.reset_n, dut.c64.erasing, dut.c64.inj_meminit, dut.c64.c64_addr, dut.c64.cart_attached);
		$display("  icb tstate=%0d target_0=%h ack=%b done=%b  hstate=%0d", dut.icb.tstate, dut.icb.target_0,
			dut.icb.target_dataslot_ack, dut.icb.target_dataslot_done, dut.icb.hstate);
		dump_screen;
		$display("  SDRAM model: errors=%0d active=%0d read=%0d write=%0d refresh=%0d", sdr.err, sdr.n_active, sdr.n_read, sdr.n_write, sdr.n_refresh);
	end
endtask

// ---------------------------------------------------------------- file builders
task automatic build_prg(input integer slot, input integer nops, input [7:0] sig0, input [7:0] sig1);
	integer n, i;
	reg [7:0] code [0:63];
	begin
		n = 0;
		code[n]=8'h01; n=n+1; code[n]=8'h08; n=n+1;                       // load address $0801
		code[n]=8'h0B; n=n+1; code[n]=8'h08; n=n+1;                       // next line
		code[n]=8'h0A; n=n+1; code[n]=8'h00; n=n+1;                       // line 10
		code[n]=8'h9E; n=n+1;                                              // SYS
		code[n]="2"; n=n+1; code[n]="0"; n=n+1; code[n]="6"; n=n+1; code[n]="1"; n=n+1;
		code[n]=8'h00; n=n+1; code[n]=8'h00; n=n+1; code[n]=8'h00; n=n+1; // eol, end of program
		code[n]=8'hA9; n=n+1; code[n]=sig0; n=n+1;                         // LDA #sig0
		code[n]=8'h8D; n=n+1; code[n]=8'h00; n=n+1; code[n]=8'hC0; n=n+1; // STA $C000
		code[n]=8'hA9; n=n+1; code[n]=sig1; n=n+1;                         // LDA #sig1
		code[n]=8'h8D; n=n+1; code[n]=8'h01; n=n+1; code[n]=8'hC0; n=n+1; // STA $C001
		code[n]=8'hA9; n=n+1; code[n]=8'h05; n=n+1;                        // LDA #5 (green)
		code[n]=8'h8D; n=n+1; code[n]=8'h20; n=n+1; code[n]=8'hD0; n=n+1; // STA $D020
		code[n]=8'h4C; n=n+1; code[n]=8'h1C; n=n+1; code[n]=8'h08; n=n+1; // JMP $081C
		for (i = 0; i < nops; i = i + 1) begin code[n]=8'hEA; n=n+1; end
		for (i = 0; i < n; i = i + 1) slot_data[slot][i] = code[i];
		slot_len[slot] = n;
	end
endtask

task automatic build_crt(input integer slot);
	integer i, n;
	reg [8*16-1:0] magic;
	reg [8*4-1:0] chip;
	begin
		for (i = 0; i < 8192 + 64 + 16; i = i + 1) slot_data[slot][i] = 8'h00;
		magic = "C64 CARTRIDGE   ";
		for (i = 0; i < 16; i = i + 1) slot_data[slot][i] = magic[8*(15-i) +: 8];
		slot_data[slot][16]=0; slot_data[slot][17]=0; slot_data[slot][18]=0; slot_data[slot][19]=8'h40; // header length
		slot_data[slot][20]=1; slot_data[slot][21]=0;                    // version 1.0
		slot_data[slot][22]=0; slot_data[slot][23]=0;                    // hardware type 0 (normal)
		slot_data[slot][24]=0; slot_data[slot][25]=1;                    // EXROM=0, GAME=1
		slot_data[slot][26]=0;
		slot_data[slot][32]="T"; slot_data[slot][33]="E"; slot_data[slot][34]="S"; slot_data[slot][35]="T";
		n = 64;
		slot_data[slot][n+0]="C"; slot_data[slot][n+1]="H"; slot_data[slot][n+2]="I"; slot_data[slot][n+3]="P";
		slot_data[slot][n+4]=0; slot_data[slot][n+5]=0; slot_data[slot][n+6]=8'h20; slot_data[slot][n+7]=8'h10; // 0x2010
		slot_data[slot][n+8]=0; slot_data[slot][n+9]=0;                  // ROM
		slot_data[slot][n+10]=0; slot_data[slot][n+11]=0;                // bank 0
		slot_data[slot][n+12]=8'h80; slot_data[slot][n+13]=8'h00;        // load address $8000
		slot_data[slot][n+14]=8'h20; slot_data[slot][n+15]=8'h00;        // size $2000
		n = 80;
		for (i = 0; i < 8192; i = i + 1) slot_data[slot][n+i] = 8'hFF;
		slot_data[slot][n+0]=8'h09; slot_data[slot][n+1]=8'h80;          // cold start $8009
		slot_data[slot][n+2]=8'h09; slot_data[slot][n+3]=8'h80;          // warm start
		slot_data[slot][n+4]=8'hC3; slot_data[slot][n+5]=8'hC2; slot_data[slot][n+6]=8'hCD; slot_data[slot][n+7]=8'h38; slot_data[slot][n+8]=8'h30; // CBM80
		slot_data[slot][n+9]=8'hA9;  slot_data[slot][n+10]=8'hAA;        // LDA #$AA
		slot_data[slot][n+11]=8'h8D; slot_data[slot][n+12]=8'h00; slot_data[slot][n+13]=8'hC0; // STA $C000
		slot_data[slot][n+14]=8'hA9; slot_data[slot][n+15]=8'h55;        // LDA #$55
		slot_data[slot][n+16]=8'h8D; slot_data[slot][n+17]=8'h01; slot_data[slot][n+18]=8'hC0; // STA $C001
		slot_data[slot][n+19]=8'hA9; slot_data[slot][n+20]=8'h05;        // LDA #5
		slot_data[slot][n+21]=8'h8D; slot_data[slot][n+22]=8'h20; slot_data[slot][n+23]=8'hD0; // STA $D020
		slot_data[slot][n+24]=8'h4C; slot_data[slot][n+25]=8'h18; slot_data[slot][n+26]=8'h80; // JMP $8018
		slot_len[slot] = 80 + 8192;
	end
endtask

task automatic build_tap(input integer slot, input integer ndata);
	integer i;
	reg [8*12-1:0] magic;
	begin
		magic = "C64-TAPE-RAW";
		for (i = 0; i < 12; i = i + 1) slot_data[slot][i] = magic[8*(11-i) +: 8];
		slot_data[slot][12] = 1; slot_data[slot][13] = 0; slot_data[slot][14] = 0; slot_data[slot][15] = 0;
		slot_data[slot][16] = ndata[7:0]; slot_data[slot][17] = ndata[15:8]; slot_data[slot][18] = 0; slot_data[slot][19] = 0;
		for (i = 0; i < ndata; i = i + 1) slot_data[slot][20 + i] = 8'hC0 + ((i * 7) % 63);
		slot_len[slot] = 20 + ndata;
	end
endtask

// the same program as build_prg, wrapped in a T64 in slot 0 with an end address that runs far past the file
task automatic build_t64(input integer slot, input integer nops, input [7:0] sig0, input [7:0] sig1);
	integer n, i, plen;
	reg [7:0] pay [0:63];
	reg [8*19-1:0] magic;
	begin
		build_prg(slot, nops, sig0, sig1);
		plen = slot_len[slot] - 2;
		for (i = 0; i < plen; i = i + 1) pay[i] = slot_data[slot][2 + i];
		for (i = 0; i < 'h60; i = i + 1) slot_data[slot][i] = 8'h00;
		magic = "C64 tape image file";
		for (i = 0; i < 19; i = i + 1) slot_data[slot][i] = magic[8*(18-i) +: 8];
		slot_data[slot]['h20] = 8'h01; slot_data[slot]['h21] = 8'h01;      // version
		slot_data[slot]['h22] = 8'h01; slot_data[slot]['h24] = 8'h01;      // max / used entries
		slot_data[slot]['h40] = 8'h01; slot_data[slot]['h41] = 8'h82;      // used, PRG
		slot_data[slot]['h42] = 8'h01; slot_data[slot]['h43] = 8'h08;      // start $0801
		slot_data[slot]['h44] = 8'hC6; slot_data[slot]['h45] = 8'hC3;      // end $C3C6 (wrong)
		slot_data[slot]['h48] = 8'h60;                                      // data at $60
		for (i = 0; i < plen; i = i + 1) slot_data[slot]['h60 + i] = pay[i];
		slot_len[slot] = 'h60 + plen;
	end
endtask

// ---------------------------------------------------------------- test bodies
integer i_, j_, dl_before;
reg tap_seen = 0;
always @(posedge dut.clk_sys) if (dut.c64.tap_loaded) tap_seen <= 1;
integer bad;
realtime t0;

task automatic wait_c64_ms(input integer ms, input integer stop_on_sig);
	integer k;
	begin
		for (k = 0; k < ms; k = k + 1) begin
			apf_run_us(1000);
			if (stop_on_sig && pk(25'hC000) == sig_a && pk(25'hC001) == sig_b) k = ms;
		end
	end
endtask

reg [7:0] sig_a, sig_b;

task automatic verify_ram(input integer slot, input integer first, input integer base, input [8*72-1:0] tag);
	integer k;
	integer bad2;
	begin
		bad2 = 0;
		for (k = first; k < slot_len[slot]; k = k + 1)
			if (pk(base + k - first) !== slot_data[slot][k]) begin
				if (bad2 < 40) $display("    mismatch at %h: ram %h expected %h", base + k - first, pk(base + k - first), slot_data[slot][k]);
				bad2 = bad2 + 1;
			end
		check(bad2 == 0, tag);
	end
endtask

task automatic abort_if_idle(input integer dl0);
	begin
		repeat (50) apf_run_us(1000);
		if (ioctl_dl_cnt == dl0) begin
			dump_state("nothing started 50 ms after the pick");
			check(0, "download started within 50 ms of the pick");
			$display("\n== SUMMARY: %0d checks passed, %0d failed; SDRAM model: %0d protocol errors ==", passes, fails, sdr.err);
			$finish;
		end
	end
endtask

task automatic test_boot;
	integer k;
	begin
		$display("== TEST 1: boot to BASIC READY ==");
		t0 = $realtime;
		for (k = 0; k < 4000 && !screen_has_ready(0); k = k + 1) apf_run_us(1000);
		if (screen_has_ready(0)) $display("   READY. on screen after %0.3f ms of sim time", $realtime / 1e9);
		else dump_state("no READY");
		check(screen_has_ready(0), "READY. found in screen RAM ($0400..$07E7)");
		apf_run_us(60000);
		check(rdy_hits > 1000, "CPU executes the kernal editor loop $E5CD-$E5D5");
		check(sdr.err == 0, "no SDRAM protocol errors so far");
		$display("   PLL locked at 20 us; c64 at_prompt=%b basic_main=%b", dut.c64.at_prompt, dut.c64.basic_main);
	end
endtask

task automatic test_prg(input integer nops, input [7:0] s0, input [7:0] s1, input [8*72-1:0] tag);
	integer k, wr0;
	realtime tpick;
	begin
		$display("== TEST 2: PRG (%0s) ==", tag);
		build_prg(0, nops, s0, s1);
		sig_a = s0; sig_b = s1;
		$display("   program size %0d bytes (mod 4 = %0d)", slot_len[0], slot_len[0] % 4);
		wr0 = ioctl_wr_cnt;
		sdr.trace_wr = 1;
		tpick = $realtime;
		apf_set_slot(0, slot_len[0]);
		$display("[%0t] PRG picked (datatable + 0x008A, size %0d)", $time, slot_len[0]);
		repeat (50) apf_run_us(1000);
		if (ioctl_dl_cnt == 0) begin
			dump_state("nothing started 50 ms after the pick");
			check(0, "download started within 50 ms of the pick");
			$display("\n== SUMMARY: %0d checks passed, %0d failed; SDRAM model: %0d protocol errors ==", passes, fails, sdr.err);
			$finish;
		end
		// wait for the download to finish
		for (k = 0; k < 600 && !(t_dl_fall > tpick && !dut.c64.inj_meminit && !dut.ioctl_download); k = k + 1) apf_run_us(1000);
		$display("   download finished %0.3f ms after the pick (ioctl_wr strobes %0d, size %0d)", ($realtime - tpick) / 1e9, ioctl_wr_cnt, slot_len[0]);
		check(ioctl_wr_cnt == slot_len[0], "c64_media produced exactly size ioctl_wr strobes");
		check(target_bytes >= slot_len[0], "APF served the full file");
		// RAM contents (load address $0801, skip the 2 byte header)
		verify_ram(0, 2, 16'h0801, "PRG bytes in SDRAM at $0801");
		// RUN typed and program executed
		for (k = 0; k < 4000 && !(pk(25'hC000) == s0 && pk(25'hC001) == s1); k = k + 1) apf_run_us(1000);
		check(t_strk > tpick, "start_strk (RUN typed) after the load");
		check(pk(25'hC000) == s0 && pk(25'hC001) == s1, "program ran: signature at $C000/$C001");
		$display("   C000=%h C001=%h; timeline after the pick: reset_wait %0.1f..%0.1f ms, erase %0.1f..%0.1f ms, inj %0.1f..%0.1f ms, RUN at %0.1f ms",
			pk(25'hC000), pk(25'hC001), (t_rw_rise - tpick) / 1e9, (t_rw_fall - tpick) / 1e9, (t_erase_start - tpick) / 1e9,
			(t_erase_end - tpick) / 1e9, (t_inj_start - tpick) / 1e9, (t_inj_end - tpick) / 1e9, (t_strk - tpick) / 1e9);
		if (!(pk(25'hC000) == s0 && pk(25'hC001) == s1)) dump_state("PRG failed");
		check(sdr.err == 0, "no SDRAM protocol errors");
	end
endtask

task automatic test_t64(input integer nops, input [7:0] s0, input [7:0] s1, input [8*72-1:0] tag);
	integer k, wr0;
	realtime tpick;
	begin
		$display("== TEST: T64 in the Program slot (%0s) ==", tag);
		build_t64(0, nops, s0, s1);
		sig_a = s0; sig_b = s1;
		$display("   program size %0d bytes (mod 4 = %0d)", slot_len[0], slot_len[0] % 4);
		wr0 = ioctl_wr_cnt;
		sdr.trace_wr = 1;
		tpick = $realtime;
		apf_set_slot(0, slot_len[0]);
		$display("[%0t] PRG picked (datatable + 0x008A, size %0d)", $time, slot_len[0]);
		repeat (50) apf_run_us(1000);
		if (ioctl_dl_cnt == 0) begin
			dump_state("nothing started 50 ms after the pick");
			check(0, "download started within 50 ms of the pick");
			$display("\n== SUMMARY: %0d checks passed, %0d failed; SDRAM model: %0d protocol errors ==", passes, fails, sdr.err);
			$finish;
		end
		// wait for the download to finish
		for (k = 0; k < 600 && !(t_dl_fall > tpick && !dut.c64.inj_meminit && !dut.ioctl_download); k = k + 1) apf_run_us(1000);
		$display("   download finished %0.3f ms after the pick (ioctl_wr strobes %0d, size %0d)", ($realtime - tpick) / 1e9, ioctl_wr_cnt, slot_len[0]);
		check(ioctl_wr_cnt == slot_len[0] - 'h60 + 2, "c64_media produced load address + payload ioctl_wr strobes");
		check(target_bytes >= slot_len[0], "APF served the full file");
		// RAM contents (load address $0801, skip the 2 byte header)
		verify_ram(0, 'h60, 16'h0801, "T64 payload in SDRAM at $0801");
		// RUN typed and program executed
		for (k = 0; k < 4000 && !(pk(25'hC000) == s0 && pk(25'hC001) == s1); k = k + 1) apf_run_us(1000);
		check(t_strk > tpick, "start_strk (RUN typed) after the load");
		check(pk(25'hC000) == s0 && pk(25'hC001) == s1, "program ran: signature at $C000/$C001");
		$display("   C000=%h C001=%h; timeline after the pick: reset_wait %0.1f..%0.1f ms, erase %0.1f..%0.1f ms, inj %0.1f..%0.1f ms, RUN at %0.1f ms",
			pk(25'hC000), pk(25'hC001), (t_rw_rise - tpick) / 1e9, (t_rw_fall - tpick) / 1e9, (t_erase_start - tpick) / 1e9,
			(t_erase_end - tpick) / 1e9, (t_inj_start - tpick) / 1e9, (t_inj_end - tpick) / 1e9, (t_strk - tpick) / 1e9);
		if (!(pk(25'hC000) == s0 && pk(25'hC001) == s1)) dump_state("T64 failed");
		check(sdr.err == 0, "no SDRAM protocol errors");
	end
endtask

task automatic test_crt;
	integer k;
	realtime tpick;
	begin
		$display("== TEST 3: CRT ==");
		build_crt(1);
		sig_a = 8'hAA; sig_b = 8'h55;
		// make sure the signature is not left over from a program
		sdr.poke8(25'hC000, 8'h00); sdr.poke8(25'hC001, 8'h00);
		tpick = $realtime;
		dl_before = ioctl_dl_cnt;
		apf_set_slot(1, slot_len[1]);
		$display("[%0t] CRT picked (size %0d)", $time, slot_len[1]);
		abort_if_idle(dl_before);
		for (k = 0; k < 4000 && !(dut.c64.cart_attached && !dut.ioctl_download && dut.media.state == 6'd1) ; k = k + 1) apf_run_us(1000);
		check(dut.c64.cart_attached, "cartridge attached");
		check(dut.c64.cart_id == 0 && dut.c64.cart_exrom == 0 && dut.c64.cart_game == 1, "header parsed: type 0, EXROM 0, GAME 1");
		verify_ram(1, 80, 25'h200000, "CHIP data in SDRAM at CRT_ADDR");
		for (k = 0; k < 4000 && !(pk(25'hC000) == 8'hAA && pk(25'hC001) == 8'h55); k = k + 1) apf_run_us(1000);
		check(pk(25'hC000) == 8'hAA && pk(25'hC001) == 8'h55, "cartridge code ran: signature at $C000/$C001");
		if (!(pk(25'hC000) == 8'hAA && pk(25'hC001) == 8'h55)) dump_state("CRT failed");
		check(sdr.err == 0, "no SDRAM protocol errors");
	end
endtask

task automatic test_tap;
	integer k, tl0, dl0;
	begin
		$display("== TEST 4: TAP ==");
		build_tap(4, 13983);   // ~28 s of tape: shorter tapes unload at once (tape_subsystem.sv:245)
		tl0 = tape_loaded_cnt; dl0 = ioctl_dl_cnt;
		$display("   (tap_seen so far %b)", tap_seen);
		apf_set_slot(4, slot_len[4]);
		$display("[%0t] TAP picked (size %0d)", $time, slot_len[4]);
		abort_if_idle(dl0);
		for (k = 0; k < 4000 && !(tape_loaded_cnt > tl0); k = k + 1) apf_run_us(1000);
		check(tape_loaded_cnt > tl0, "c64_media pulsed tape_loaded");
		if (!(tape_loaded_cnt > tl0)) dump_state("TAP failed");
		verify_ram(4, 0, 25'h400000, "TAP bytes in SDRAM at $400000");
		for (k = 0; k < 400 && !tap_seen; k = k + 1) apf_run_us(1000);
		$display("   tape: last_addr=%h ready_gated=%b tap_ready=%b scanner.state=%0d busy=%b tape_end=%b cmd_unload=%b reset_n=%b map_max=%0d",
			dut.c64.tape.tap_last_addr_r, dut.c64.tape.tap_ready_gated, dut.c64.tape.tap_ready, dut.c64.tape.tap_scanner.state,
			dut.c64.tape.tap_scanner.busy, dut.c64.tape.tape_end, dut.c64.tape.cmd_unload, dut.c64.tape.reset_n, dut.c64.tape.tap_scanner.map_max);
		check(tap_seen, "tape_subsystem raised tap_loaded after the scan (it unloads again at end of tape)");
		check(sdr.err == 0, "no SDRAM protocol errors");
	end
endtask

always #100_000_000 $fflush;   // every 100 us of sim time
always #50_000_000_000 $display("[%0t] heartbeat: c64_addr=%h reset_n=%b media.state=%0d autostart.state=%0d key=%h at_prompt=%b disk_ready=%b drive_led=%b", $time, dut.c64.c64_addr, dut.c64.reset_n, dut.media.state, dut.autostart.state, dut.autostart.key, dut.c64_at_prompt, dut.c64_disk_ready, dut.c64.drive_led[0]);


// ---------------------------------------------------------------- disk and NTSC tests
`include "disk.vh"
integer mount_cnt = 0, sys_cnt = 0;
realtime t_mount, t_wr_last;
integer  wr_bytes_d = 0;
always @(posedge dut.clk_sys) begin
	sys_cnt <= sys_cnt + 1;
	if (dut.img_mounted[0]) begin mount_cnt <= mount_cnt + 1; t_mount = $realtime; end
end
always @(posedge dut.clk_74a) if (wr_bytes != wr_bytes_d) begin wr_bytes_d <= wr_bytes; t_wr_last = $realtime; end

task automatic load_hex(input integer slot, input string fname, input integer size);
	integer k;
	begin
		$readmemh(fname, filebuf);
		for (k = 0; k < size; k = k + 1) slot_data[slot][k] = filebuf[k];
		slot_len[slot] = size;
	end
endtask

// image in PSRAM (drive 8 at byte 0) against a reference file
task automatic check_psram_image(input string fname, input integer size, input [8*72-1:0] tag);
	integer k, bad2;
	begin
		$readmemh(fname, filebuf);
		bad2 = 0;
		for (k = 0; k < size; k = k + 1)
			if (psr.peek8(k) !== filebuf[k]) begin
				if (bad2 < 8) $display("    PSRAM mismatch at %0d: have %h expected %h", k, psr.peek8(k), filebuf[k]);
				bad2 = bad2 + 1;
			end
		check(bad2 == 0, tag);
	end
endtask

// kind: 0 D64 picked at the prompt, 1 G64, 2 D64 + write-back, 3 D64 found by the boot datatable scan, 4 D81
task automatic test_disk(input integer kind);
	integer k, size, m0, found, w0, lastsec;
	realtime tpick, tsig, tdone;
	string f, ref_f;
	reg [7:0] pat [0:15];
	reg [7:0] orig [0:174847];
	begin
		for (k = 0; k < 16; k = k + 1) pat[k] = k[7:0] ^ 8'h5A;
		case (kind)
		0, 3: begin f = "work/disk/run.d64.hex"; size = `D64_SIZE; ref_f = "work/disk/run.g64_ref.hex"; end
		1:    begin f = "work/disk/run.g64.hex"; size = `G64_SIZE; ref_f = "work/disk/run.g64_ref.hex"; end
		2:    begin f = "work/disk/wb.d64.hex";  size = `D64_SIZE; ref_f = "work/disk/wb.g64_ref.hex"; end
		default: begin f = "work/disk/run.d81.hex"; size = `D81_SIZE; ref_f = ""; end
		endcase
		$display("== TEST: disk kind %0d (%0s, %0d bytes) ==", kind, f, size);
		sig_a = 8'hAA; sig_b = 8'h55;
		m0 = mount_cnt;
		tpick = $realtime;
		if (kind == 3) begin
			$display("   image present in the datatable at boot (persisted disk)");
		end else begin
			test_boot;
			load_hex(2, f, size);
			tpick = $realtime;
			apf_set_slot(2, size);
			$display("[%0t] disk picked (slot 2, size %0d)", $time, size);
		end
		if (kind == 3) tpick = 0.0;
		// mount: the file is read and converted / copied into PSRAM, then img_mounted pulses
		for (k = 0; k < 20000 && !(mount_cnt > m0); k = k + 1) apf_run_us(1000);
		$display("   img_mounted after %0.1f ms (size %0d type %b)", (t_mount - tpick) / 1e9, dut.img_size, dut.img_type);
		check(mount_cnt > m0, "img_mounted pulsed");
		check(dut.img_size == size, "img_size is the file size");
		if (kind != 4) check_psram_image(ref_f, (kind == 1) ? size : `G64_SIZE, "G64 image in PSRAM equals sim/gcr_ref.py synth_g64 / the file");
		if (kind == 4) check(dut.img_type == 2'b11, "img_type = 1581");
		// autostart: LOAD"*",8,1 then RUN, the first PRG loads over IEC and runs
		if (kind == 2) begin
			for (k = 0; k < 600 && !(pk(25'hC002) == 8'h77); k = k + 1) apf_run_us(100000);
			tsig = $realtime;
			$display("   program finished its SAVE %0.2f s after the mount (C000=%h C001=%h C002=%h C003=%h)", (tsig - t_mount) / 1e12, pk(25'hC000), pk(25'hC001), pk(25'hC002), pk(25'hC003));
			check(pk(25'hC000) == 8'hAA && pk(25'hC001) == 8'h55, "disk program loaded and ran (signature)");
			check(pk(25'hC002) == 8'h77, "SAVE returned");
			check(pk(25'hC003) == 8'h00, "SAVE reported no error (carry clear)");
			// the flush happens ~0.5 s after the drive stops writing
			for (k = 0; k < 400 && !(wr_cmds > 0 && ($realtime - t_wr_last) > 1.5e12); k = k + 1) apf_run_us(100000);
			$display("   write-back: %0d Dataslot Write commands, %0d bytes, last at %0.2f s after the SAVE returned", wr_cmds, wr_bytes, (t_wr_last - tsig) / 1e12);
			check(wr_cmds > 0, "c64_media wrote back to the D64 file");
			// compare with the original image
			$readmemh("work/disk/wb.d64.hex", filebuf);
			found = 0; w0 = 0; lastsec = -1;
			for (k = 0; k < `D64_SIZE; k = k + 1) if (slot_data[2][k] !== filebuf[k]) begin
				if (k / 256 != lastsec) begin
					if (found < 12) $display("    D64 sector changed: file offset %0d (sector index %0d)", k, k / 256);
					found = found + 1;
					lastsec = k / 256;
				end
				w0 = w0 + 1;
			end
			$display("   %0d bytes differ from the original D64 in %0d sector(s)", w0, found);
			// search the saved data (16 bytes, byte i = i ^ $5A)
			found = 0;
			for (k = 0; k < `D64_SIZE - 16; k = k + 1) begin
				if (slot_data[2][k] == pat[0] && slot_data[2][k+1] == pat[1] && slot_data[2][k+7] == pat[7] && slot_data[2][k+15] == pat[15]) begin
					found = found + 1;
					$display("    saved data found at D64 offset %0d (track/sector index %0d, offset in sector %0d)", k, k / 256, k % 256);
				end
			end
			check(found == 1, "the 16 saved bytes are in the D64 file");
			// directory: 2nd entry "OUT"
			found = 0;
			for (k = 0; k < 8; k = k + 1)
				if (slot_data[2][(357+1)*256 + 32*k + 5] == "O" && slot_data[2][(357+1)*256 + 32*k + 6] == "U" && slot_data[2][(357+1)*256 + 32*k + 7] == "T")
					found = found + 1;
			check(found == 1, "directory has the file OUT");
			check(slot_data[2][(357+1)*256 + 32 + 2] == 8'h82 || slot_data[2][(357+1)*256 + 2] == 8'h82, "directory entry is a closed PRG");
		end else begin
			for (k = 0; k < 1200 && !(pk(25'hC000) == 8'hAA && pk(25'hC001) == 8'h55); k = k + 1) apf_run_us(100000);
			tsig = $realtime;
			$display("   signature seen %0.2f s after the mount, %0.2f s after the pick", (tsig - t_mount) / 1e12, (tsig - tpick) / 1e12);
			check(pk(25'hC000) == 8'hAA && pk(25'hC001) == 8'h55, "first PRG on the disk loaded over IEC and ran (signature)");
		end
		if (!(pk(25'hC000) == 8'hAA && pk(25'hC001) == 8'h55)) dump_state("disk test failed");
		check(sdr.err == 0, "no SDRAM protocol errors");
		check(psr.err == 0, "no PSRAM protocol errors");
	end
endtask

task automatic measure_clk(output real mhz);
	integer n0;
	realtime t0_;
	begin
		n0 = sys_cnt; t0_ = $realtime;
		apf_run_us(200);
		mhz = (sys_cnt - n0) / (($realtime - t0_) / 1e6);
	end
endtask

task automatic test_ntsc;
	integer k;
	real f0, f1;
	realtime tsw, trs;
	begin
		$display("== TEST: NTSC ==");
		measure_clk(f0);
		$display("   clk_sys before: %0.3f MHz", f0);
		check(f0 > 31.4 && f0 < 31.7, "PAL clk_sys is 31.53 MHz");
		tsw = $realtime;
		apf_wr(32'h8000000C, 1);                 // interact.json Video = NTSC
		for (k = 0; k < 600 && !(dut.pll.reconfigs > 0 && dut.pll_locked); k = k + 1) apf_run_us(1000);
		$display("   PLL reconfigured %0.1f ms after the register write", ($realtime - tsw) / 1e9);
		check(dut.pll.reconfigs > 0, "PLL reconfiguration sequence ran");
		check(dut.ntsc_r == 1'b1, "core_top ntsc_r follows the Video register");
		measure_clk(f1);
		$display("   clk_sys after: %0.3f MHz", f1);
		check(f1 > 32.6 && f1 < 32.85, "NTSC clk_sys is 32.73 MHz");
		check(dut.c64.ntsc == 1'b1, "c64_top runs NTSC");
		check(reset_n_falls >= 2, "the C64 was reset when the standard changed");
		trs = $realtime;
		for (k = 0; k < 4000 && !screen_has_ready(0); k = k + 1) apf_run_us(1000);
		$display("   READY. on screen %0.1f ms after the PLL change", ($realtime - trs) / 1e9);
		check(screen_has_ready(0), "READY. found in screen RAM in NTSC");
		apf_run_us(60000);
		check(rdy_hits > 1000, "CPU executes the kernal editor loop");
		test_prg(3, 8'hAA, 8'h55, "NTSC size%4==3");
		check(sdr.err == 0, "no SDRAM protocol errors");
	end
endtask

// ---------------------------------------------------------------- main
string testsel;
integer order;
reg [63:0] dumpwin;
integer dump_from, dump_to;

initial begin
	if (!$value$plusargs("test=%s", testsel)) testsel = "all";
	if (!$value$plusargs("order=%d", order)) order = 0;
	if (!$value$plusargs("gap=%d", GAP)) GAP = 2;
	begin integer scr; if ($value$plusargs("screen=%d", scr)) show_screen = scr != 0; end
	if ($value$plusargs("dump_from=%d", dump_from) && $value$plusargs("dump_to=%d", dump_to)) begin
		#(dump_from * 1000000);
		$dumpfile("work/system.fst");
		$dumpvars(0, tb.dut.media);
		$dumpvars(0, tb.dut.icb);
		$dumpvars(1, tb.dut.c64);
		$dumpvars(0, tb.sdr);
		$dumpon;
		#((dump_to - dump_from) * 1000000);
		$dumpoff;
		$dumpflush;
	end
end

initial begin
	for (i_ = 0; i_ < 6; i_ = i_ + 1) slot_len[i_] = 0;
	// global watchdog (simulated time)
	fork begin #(64'd60_000_000_000_000); $display("WATCHDOG: simulation limit reached"); dump_state("watchdog"); $finish; end join_none

	if (testsel == "dboot") load_hex(2, "work/disk/run.d64.hex", `D64_SIZE);
	$display("== APF boot (order %0d) ==", order);
	repeat (20) @(negedge clk_74a);
	// the core announces itself (PLL locked) with the ready-to-run target command; the host side
	// first asks for status while the core boots
	apf_run_us(30);
	if (order == 0) begin
		apf_host(16'h0010, 0, 0);          // reset enter
		apf_host(16'h0011, 0, 0);          // reset exit
	end
	// datatable: one {id}/{size} pair per slot, no files chosen yet
	for (i_ = 0; i_ < 6; i_ = i_ + 1) begin
		apf_wr(32'hF8002000 + 8 * i_, i_);          repeat (GAP) @(negedge clk_74a);
		apf_wr(32'hF8002000 + 8 * i_ + 4, (i_ == 2 && testsel == "dboot") ? `D64_SIZE : 0);       repeat (GAP) @(negedge clk_74a);
	end
	apf_host(16'h008F, 0, 0);               // data slot update complete
	if (order == 1) begin
		apf_host(16'h0010, 0, 0);
		apf_host(16'h0011, 0, 0);
	end
	$display("[%0t] APF boot sequence done (reset_n=%b)", $time, dut.reset_n);

	if (testsel == "ntsc") test_ntsc;
	if (testsel == "disk") test_disk(0);
	if (testsel == "g64") test_disk(1);
	if (testsel == "wb") test_disk(2);
	if (testsel == "dboot") test_disk(3);
	if (testsel == "d81") test_disk(4);
	if (testsel == "all" || testsel == "boot" || testsel == "prg" || testsel == "t64" || testsel == "crt" || testsel == "tap")
		test_boot;
	if (fails == 0 && (testsel == "all" || testsel == "prg")) begin
		test_prg(3, 8'hAA, 8'h55, "size%4==3");
		test_prg(0, 8'hC3, 8'h3C, "size%4==0");
	end
	if (fails == 0 && (testsel == "all" || testsel == "t64")) test_t64(3, 8'h64, 8'h5A, "wrong end address");
	if (fails == 0 && (testsel == "all" || testsel == "crt")) test_crt;
	if (fails == 0 && (testsel == "all" || testsel == "tap")) test_tap;

	$display("\n== SUMMARY: %0d checks passed, %0d failed; SDRAM model: %0d protocol errors, PSRAM model: %0d ==", passes, fails, sdr.err, psr.err);
	$finish;
end

endmodule

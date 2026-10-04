// media_tb.sv - c64_media + ddram_psram against models of APF, the PSRAM and the C64
//
// run_media.py writes the slot files and checks what this bench dumps:
//   prg      a PRG picked from the menu streams into ioctl (with ioctl_wait)
//   d64      a D64 mounts as a G64 in PSRAM, read back through the DDRAM port
//   d64wb    a 1541 track flush is decoded back into the D64's sectors
//   g64      a G64 is copied to PSRAM (drive 9) and a track flush is written back
//   d81      1581 sectors are read and written
`timescale 1ns/1ps
`default_nettype none
module media_tb;
	reg clk_74a = 0, clk_sys = 0;
	always #6.734 clk_74a = ~clk_74a;
	always #15.86 clk_sys = ~clk_sys;

	reg [8*256-1:0] dir;
	integer sz[6];
	integer sz_prg = 0, sz_d8 = 0, sz_d9 = 0;
	reg [7:0] slot0[65536];
	reg [7:0] slot2[1048576];
	reg [7:0] slot3[1048576];

	function automatic [7:0] slot_rd(input integer id, input integer a);
		slot_rd = id == 0 ? slot0[a] : id == 2 ? slot2[a] : id == 3 ? slot3[a] : 8'h00;
	endfunction

	/* ---------------- APF model (clk_74a) ---------------- */
	reg  [31:0] bridge_addr = 0;
	reg         bridge_wr = 0;
	reg  [31:0] bridge_wr_data = 0;
	wire [31:0] bridge_rd_data;
	wire        t_read, t_write;
	wire [15:0] t_id;
	wire [31:0] t_off, t_baddr, t_len;
	reg         t_done = 1;
	reg         dataslot_update = 0;
	reg  [15:0] dataslot_update_id = 0;
	reg  [31:0] dataslot_update_size = 0;
	reg         dataslot_allcomplete = 0;
	wire  [9:0] datatable_addr;
	reg  [31:0] dt_q1, datatable_q;
	always @(posedge clk_74a) begin dt_q1 <= 32'd0; datatable_q <= dt_q1; end   // empty table
	integer n_cmds = 0;

	always @(posedge clk_74a) begin
		integer i, k;
		reg [31:0] w;
		if (t_read) begin
			t_done <= 0;
			n_cmds = n_cmds + 1;
			repeat (20) @(posedge clk_74a);
			for (i = 0; i < t_len; i = i + 4) begin
				w = 0;
				for (k = 0; k < 4; k = k + 1) w = {w[23:0], slot_rd(t_id, t_off + i + k)};
				bridge_addr <= t_baddr + i;
				bridge_wr_data <= w;
				bridge_wr <= 1;
				@(posedge clk_74a);
				bridge_wr <= 0;
				@(posedge clk_74a);
			end
			repeat (10) @(posedge clk_74a);
			t_done <= 1;
		end
		if (t_write) begin
			t_done <= 0;
			n_cmds = n_cmds + 1;
			repeat (20) @(posedge clk_74a);
			for (i = 0; i < t_len; i = i + 4) begin
				bridge_addr <= t_baddr + i;
				repeat (3) @(posedge clk_74a);
				w = bridge_rd_data;
				for (k = 0; k < 4; k = k + 1)
					if (i + k < t_len) begin
						if (t_id == 2) slot2[t_off + i + k] = w[31 - k*8 -: 8];
						if (t_id == 3) slot3[t_off + i + k] = w[31 - k*8 -: 8];
					end
			end
			repeat (10) @(posedge clk_74a);
			t_done <= 1;
		end
	end

	task automatic pick(input integer id, input integer size);
		@(posedge clk_74a);
		dataslot_update_id <= id;
		dataslot_update_size <= size;
		dataslot_update <= 1;
		@(posedge clk_74a);
		dataslot_update <= 0;
	endtask

	/* ---------------- DUT ---------------- */
	wire        ioctl_download, ioctl_wr;
	wire  [7:0] ioctl_index, ioctl_data;
	wire [24:0] ioctl_addr;
	wire [31:0] ioctl_file_ext;
	reg         ioctl_wait = 0;
	reg  [31:0] sd_lba[2];
	reg   [1:0] sd_rd = 0, sd_wr = 0;
	wire  [1:0] sd_ack;
	wire [13:0] sd_buff_addr;
	wire  [7:0] sd_buff_dout;
	reg   [7:0] sd_buff_din[2];
	wire        sd_buff_wr;
	wire  [1:0] img_mounted;
	wire [31:0] img_size;
	wire  [1:0] img_type;
	wire        ld_start, ld_we, ld_ack;
	wire [21:0] ld_addr;
	wire  [7:0] ld_wdata;
	wire [15:0] ld_rdata;

	c64_media media (
		.clk_74a(clk_74a), .clk_sys(clk_sys),
		.bridge_addr(bridge_addr), .bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data), .bridge_rd_data(bridge_rd_data),
		.target_dataslot_read(t_read), .target_dataslot_write(t_write), .target_dataslot_id(t_id),
		.target_dataslot_slotoffset(t_off), .target_dataslot_bridgeaddr(t_baddr), .target_dataslot_length(t_len),
		.target_dataslot_done(t_done),
		.dataslot_update(dataslot_update), .dataslot_update_id(dataslot_update_id), .dataslot_update_size(dataslot_update_size),
		.dataslot_allcomplete(dataslot_allcomplete), .datatable_addr(datatable_addr), .datatable_q(datatable_q),
		.ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr),
		.ioctl_data(ioctl_data), .ioctl_file_ext(ioctl_file_ext), .ioctl_wait(ioctl_wait),
		.sd_lba(sd_lba), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack), .sd_buff_addr(sd_buff_addr),
		.sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din), .sd_buff_wr(sd_buff_wr),
		.img_mounted(img_mounted), .img_size(img_size), .img_type(img_type),
		.ld_start(ld_start), .ld_we(ld_we), .ld_addr(ld_addr), .ld_wdata(ld_wdata), .ld_rdata(ld_rdata), .ld_ack(ld_ack),
		.busy());

	reg         DDRAM_RD = 0, DDRAM_WE = 0;
	reg   [7:0] DDRAM_BURSTCNT = 0, DDRAM_BE = 0;
	reg  [28:0] DDRAM_ADDR = 0;
	reg  [63:0] DDRAM_DIN = 0;
	wire        DDRAM_BUSY, DDRAM_DOUT_READY;
	wire [63:0] DDRAM_DOUT;
	wire [21:16] cram_a;
	wire [15:0] cram_dq;
	wire        cram_adv_n, cram_ce0_n, cram_ce1_n, cram_oe_n, cram_we_n, cram_ub_n, cram_lb_n;

	ddram_psram ddram (
		.clk(clk_sys), .reset(1'b0),
		.DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR), .DDRAM_DOUT(DDRAM_DOUT),
		.DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD), .DDRAM_WE(DDRAM_WE), .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE),
		.ld_start(ld_start), .ld_we(ld_we), .ld_addr(ld_addr), .ld_wdata(ld_wdata), .ld_rdata(ld_rdata), .ld_ack(ld_ack),
		.cram_a(cram_a), .cram_dq(cram_dq), .cram_wait(1'b0), .cram_clk(), .cram_adv_n(cram_adv_n), .cram_cre(),
		.cram_ce0_n(cram_ce0_n), .cram_ce1_n(cram_ce1_n), .cram_oe_n(cram_oe_n), .cram_we_n(cram_we_n),
		.cram_ub_n(cram_ub_n), .cram_lb_n(cram_lb_n));

	/* ---------------- PSRAM model (async mode, address/data muxed) ---------------- */
	reg  [15:0] pmem[2097152];
	reg  [21:0] paddr;
	reg  [15:0] wlat;
	reg         wub, wlb, wact = 0;
	always @(posedge cram_adv_n) if (!cram_ce0_n) paddr <= {cram_a, cram_dq};
	always @(*) if (!cram_ce0_n && !cram_we_n && cram_adv_n && cram_dq !== 16'hzzzz) begin
		wlat = cram_dq; wub = cram_ub_n; wlb = cram_lb_n; wact = 1;
	end
	always @(posedge cram_we_n) if (wact) begin
		if (!wlb) pmem[paddr[20:0]][7:0]  = wlat[7:0];
		if (!wub) pmem[paddr[20:0]][15:8] = wlat[15:8];
		wact = 0;
	end
	assign #5 cram_dq = (!cram_ce0_n && !cram_oe_n && cram_we_n) ? pmem[paddr[20:0]] : 16'hzzzz;

	/* ---------------- C64 model ---------------- */
	integer fio;
	integer wait_cnt = 0, nbytes = 0;
	always @(posedge clk_sys) begin
		if (ioctl_wr) begin
			$fwrite(fio, "%02x %06x %02x\n", ioctl_index, ioctl_addr, ioctl_data);
			nbytes = nbytes + 1;
			// the first PRG byte waits for the kernal (reset_wait), the rest for an io_cycle
			wait_cnt = (nbytes == 1) ? 3000 : 8 + (nbytes * 13) % 40;
		end
		if (wait_cnt > 0) wait_cnt = wait_cnt - 1;
		ioctl_wait <= wait_cnt > 0;
	end

	// the drives' buffers: 1-clock registered read, as c1541_track's bg buffer
	reg [7:0] bg[16384];
	always @(posedge clk_sys) begin sd_buff_din[0] <= bg[sd_buff_addr]; sd_buff_din[1] <= bg[sd_buff_addr]; end
	reg [7:0] rd81[512];
	always @(posedge clk_sys) if (sd_buff_wr) rd81[sd_buff_addr[8:0]] <= sd_buff_dout;

	task automatic sd_req(input integer drv, input integer lba, input integer write);
		@(posedge clk_sys);
		sd_lba[drv] <= lba;
		if (write) sd_wr[drv] <= 1; else sd_rd[drv] <= 1;
		@(posedge clk_sys);
		while (!sd_ack[drv]) @(posedge clk_sys);
		sd_wr[drv] <= 0; sd_rd[drv] <= 0;
		while (sd_ack[drv]) @(posedge clk_sys);
		repeat (4) @(posedge clk_sys);
	endtask

	// wait for drive drv's mount pulse; check the type
	task automatic wait_mount(input integer drv, input integer typ);
		while (!img_mounted[drv]) @(posedge clk_sys);
		if (img_type !== typ[1:0]) begin $display("FAIL mount drive %0d type %b", drv, img_type); end
		else $display("mounted drive %0d type %b size %0d", drv, img_type, img_size);
		while (img_mounted[drv]) @(posedge clk_sys);
	endtask

	// read n bytes of drive drv's image through the DDRAM port, as the 1541 does
	task automatic ddram_dump(input integer drv, input integer n, input [8*256-1:0] fname);
		integer f, q, b, cnt;
		f = $fopen(fname, "w");
		for (q = 0; q * 8 < n; q = q + cnt) begin
			cnt = 32;
			@(posedge clk_sys);
			while (DDRAM_BUSY) @(posedge clk_sys);
			DDRAM_ADDR <= 29'h06000000 + (drv ? 29'h40000 : 0) + q;
			DDRAM_BURSTCNT <= cnt;
			DDRAM_RD <= 1;
			@(posedge clk_sys);
			DDRAM_RD <= 0;
			for (b = 0; b < cnt; b = b + 1) begin
				@(posedge clk_sys);
				while (!DDRAM_DOUT_READY) @(posedge clk_sys);
				$fwrite(f, "%016x\n", DDRAM_DOUT);
			end
		end
		$fclose(f);
	endtask

	initial begin
		integer i;
		void'($value$plusargs("dir=%s", dir));
		for (i = 0; i < 6; i = i + 1) sz[i] = 0;
		void'($value$plusargs("prg=%d", sz_prg)); sz[0] = sz_prg;
		void'($value$plusargs("d8=%d", sz_d8));   sz[2] = sz_d8;
		void'($value$plusargs("d9=%d", sz_d9));   sz[3] = sz_d9;
		$readmemh({dir, "/slot0.hex"}, slot0);
		$readmemh({dir, "/slot2.hex"}, slot2);
		$readmemh({dir, "/slot3.hex"}, slot3);
		fio = $fopen({dir, "/ioctl.txt"}, "w");
		sd_lba[0] = 0; sd_lba[1] = 0;

		repeat (50) @(posedge clk_74a);
		dataslot_allcomplete <= 1;
		repeat (400) @(posedge clk_74a);   // datatable scan (empty)

		// ---- prg ----
		pick(0, sz[0]);
		@(posedge clk_sys);
		while (!ioctl_download) @(posedge clk_sys);
		while (ioctl_download) @(posedge clk_sys);
		$fclose(fio);
		$display("prg: %0d bytes", nbytes);

		// ---- d64 on drive 8 ----
		pick(2, sz[2]);
		wait_mount(0, 1);
		ddram_dump(0, 340000, {dir, "/d64_ddram.hex"});

		// ---- d64 write-back: run_media.py put the flushed track in bg.hex ----
		$readmemh({dir, "/bg_d64.hex"}, bg);
		sd_req(0, 34, 1);                 // half-track 34 = track 18
		repeat (2000) @(posedge clk_74a);
		$writememh({dir, "/slot2_d64.hex"}, slot2, 0, sz[2] - 1);
		$display("d64wb done");

		// ---- g64 on drive 9 ----
		pick(3, sz[3]);
		wait_mount(1, 1);
		ddram_dump(1, sz[3], {dir, "/g64_ddram.hex"});
		$readmemh({dir, "/bg_g64.hex"}, bg);
		sd_req(1, 0, 1);                  // half-track 0 = track 1
		$display("g64wb done");

		// ---- d81 on drive 8 ----
		$readmemh({dir, "/slot2_d81.hex"}, slot2);
		pick(2, 819200);
		wait_mount(0, 3);
		sd_req(0, 20, 0);                 // read 256-byte blocks 20, 21
		$writememh({dir, "/rd81.hex"}, rd81);
		$readmemh({dir, "/bg_d81.hex"}, bg);
		sd_req(0, 40, 1);                 // write blocks 40, 41
		$display("d81 done");

		repeat (2000) @(posedge clk_74a);
		$writememh({dir, "/slot2_out.hex"}, slot2, 0, 819199);
		$writememh({dir, "/slot3_out.hex"}, slot3, 0, sz[3] - 1);
		$display("commands: %0d", n_cmds);
		$finish;
	end

	initial begin
		#2_000_000_000;
		$display("FAIL timeout");
		$finish;
	end
endmodule
`default_nettype wire

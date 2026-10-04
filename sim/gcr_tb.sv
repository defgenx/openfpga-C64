// gcr_tb.sv - gcr_synth against Main_MiSTer's algorithm, gcr_decode on rotated tracks
//
// run_gcr.py writes the vectors and checks the results:
//   +trk=<hex>   track data (sector * 256)        -> synth output to +out=<hex>
//   +buf=<hex>   drive buffer (length + GCR)      -> decoded sectors to +sec=<hex>, mask to +mask=<hex>
`timescale 1ns/1ps
module gcr_tb;
	reg clk = 0;
	always #15.8 clk = ~clk;

	integer track, nsec, id0, id1, tsize;
	reg [7:0] trk[8192];
	reg [7:0] buff[16384];
	reg [8*256-1:0] f_trk, f_out, f_buf, f_sec, f_mask;
	integer fo, i;

	// ---- synth ----
	reg        gs_start = 0;
	wire       gs_busy;
	wire [12:0] rb_addr;
	reg  [7:0] rb_q1, rb_q;
	wire       strobe;
	wire [7:0] obyte;
	reg        done = 0;
	always @(posedge clk) begin rb_q1 <= trk[rb_addr]; rb_q <= rb_q1; end

	gcr_synth dut_s (.clk(clk), .start(gs_start), .track(track[5:0]), .nsec(nsec[4:0]),
		.id0(id0[7:0]), .id1(id1[7:0]), .busy(gs_busy), .rb_addr(rb_addr), .rb_q(rb_q),
		.out_strobe(strobe), .out_byte(obyte), .out_done(done));

	// sink acknowledges after a variable delay
	integer n_out = 0, lat = 0;
	always @(posedge clk) begin
		done <= 0;
		if (strobe && !done) begin
			if (lat == 0) begin
				$fwrite(fo, "%02x\n", obyte);
				n_out = n_out + 1;
				done <= 1;
				lat = (n_out * 7) % 4;
			end else lat = lat - 1;
		end
	end

	// ---- decode ----
	reg        gd_start = 0;
	wire       gd_busy;
	wire [13:0] sb_addr;
	reg  [7:0] sb_q1, sb_q;
	wire       wb_we;
	wire [12:0] wb_addr;
	wire [7:0] wb_data;
	wire [20:0] valid;
	reg  [7:0] secs[8192];
	always @(posedge clk) begin sb_q1 <= buff[sb_addr]; sb_q <= sb_q1; end
	always @(posedge clk) if (wb_we) secs[wb_addr] <= wb_data;

	gcr_decode dut_d (.clk(clk), .start(gd_start), .track_size(tsize[13:0]), .nsec(nsec[4:0]),
		.busy(gd_busy), .sb_addr(sb_addr), .sb_q(sb_q), .wb_we(wb_we), .wb_addr(wb_addr),
		.wb_data(wb_data), .valid(valid));

	initial begin
		if (!$value$plusargs("track=%d", track)) track = 1;
		if (!$value$plusargs("nsec=%d", nsec)) nsec = 21;
		if (!$value$plusargs("id0=%d", id0)) id0 = 0;
		if (!$value$plusargs("id1=%d", id1)) id1 = 0;
		if ($value$plusargs("trk=%s", f_trk)) begin
			$readmemh(f_trk, trk);
			void'($value$plusargs("out=%s", f_out));
			fo = $fopen(f_out, "w");
			@(posedge clk) gs_start <= 1;
			@(posedge clk) gs_start <= 0;
			@(posedge clk);
			while (gs_busy || strobe) @(posedge clk);
			$fclose(fo);
		end
		if ($value$plusargs("buf=%s", f_buf)) begin
			$readmemh(f_buf, buff);
			tsize = {buff[1], buff[0]};
			for (i = 0; i < 8192; i = i + 1) secs[i] = 8'h00;
			@(posedge clk) gd_start <= 1;
			@(posedge clk) gd_start <= 0;
			@(posedge clk);
			while (gd_busy) @(posedge clk);
			void'($value$plusargs("sec=%s", f_sec));
			void'($value$plusargs("mask=%s", f_mask));
			$writememh(f_sec, secs, 0, nsec * 256 - 1);
			fo = $fopen(f_mask, "w");
			$fwrite(fo, "%06x\n", valid);
			$fclose(fo);
		end
		$finish;
	end
endmodule

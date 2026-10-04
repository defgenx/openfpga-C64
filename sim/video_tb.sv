// video_tb.sv - c64_video fed with a VIC-II trace recorded by vic/tb_vic.vhd
//
// The trace is C64_MiSTer's own VIC and video_sync (text screen, border 14,
// background 6). For both border settings this checks every line and frame of the
// window, the scaler slot word, HS/VS never sharing a clock, and - the alignment
// test - that the 320x200 window holds no border pixel while the full one does.
`timescale 1ns/1ps
module video_tb;
	reg clk = 0;
	always #15.86 clk = ~clk;

	reg  [8*256-1:0] tracefile, ppmfile;
	integer ntsc, borders, tf, pf, r;
	reg  [7:0] line_s;
	reg  [3:0] flags, col;

	wire [23:0] rgb;
	wire de, skip, hs, vs;
	reg  [7:0] cr;

	c64_video dut (.clk(clk), .ntsc(ntsc[0]), .borders(borders[0]),
		.r(cr), .g(cr), .b(cr), .hblank(flags[0]), .vblank(flags[1]), .vsync(flags[2]),
		.video_rgb(rgb), .video_de(de), .video_skip(skip), .video_hs(hs), .video_vs(vs));

	integer W, H, SLOT;
	integer px = 0, lines = 0, frames = 0, good = 0, errors = 0, fb = 0, fg = 0;
	reg de_d = 0, seen_vs = 0, ppm_on = 0, ppm_done = 0;
	initial begin
		void'($value$plusargs("trace=%s", tracefile));
		void'($value$plusargs("ppm=%s", ppmfile));
		if (!$value$plusargs("ntsc=%d", ntsc)) ntsc = 0;
		if (!$value$plusargs("borders=%d", borders)) borders = 1;
		W = borders ? (ntsc ? 404 : 382) : 320;
		H = borders ? (ntsc ? 250 : 270) : 200;
		SLOT = ntsc * 2 + (borders ? 0 : 1);
		flags = 4'b0011; col = 0; cr = 0;
		tf = $fopen(tracefile, "r");
		pf = 0;
		while (!$feof(tf)) begin
			r = $fscanf(tf, "%1h%1h\n", flags, col);
			cr = {col, 4'h0};
			@(posedge clk);
		end
		$display("%s %s: %0d complete frames checked, %0d errors",
			ntsc ? "NTSC" : "PAL ", borders ? "borders   " : "no borders", good, errors);
		if (good < 1 || errors != 0) $display("FAIL");
		$finish;
	end

	// a frame runs from one VS to the next; the first one in the trace is partial
	always @(posedge clk) begin
		if (hs && vs) begin $display("HS and VS on the same clock"); errors = errors + 1; end
		if (vs) begin
			if (seen_vs) begin
				frames = frames + 1;
				if (lines != H) begin $display("frame %0d: %0d lines, expected %0d", frames, lines, H); errors = errors + 1; end
				// display window: 320x200 of background colour; borders mode also shows border colour
				else if (fg != 64000 || (borders ? fb != W * H - 64000 : fb != 0)) begin
					$display("frame %0d: %0d background / %0d border pixels", frames, fg, fb); errors = errors + 1;
				end else good = good + 1;
				if (ppm_on) begin $fclose(pf); ppm_on = 0; ppm_done = 1; end
			end
			if (seen_vs && !ppm_on && !ppm_done) begin
				pf = $fopen(ppmfile, "w");
				ppm_on = 1;
				$fwrite(pf, "P3\n%0d %0d\n255\n", W, H);
			end
			seen_vs = 1;
			lines = 0; fb = 0; fg = 0;
		end
		if (de && !skip) begin
			px = px + 1;
			if (rgb[23:16] == 8'he0) fb = fb + 1;
			if (rgb[23:16] == 8'h60 || rgb[23:16] == 8'h10) fg = fg + 1;   // background or text
			if (ppm_on) $fwrite(pf, "%0d %0d %0d\n", rgb[23:16], rgb[15:8], rgb[7:0]);
		end
		if (de_d && !de) begin
			if (px != W) begin $display("line %0d: %0d pixels, expected %0d", lines, px, W); errors = errors + 1; end
			if (rgb !== {8'h00, SLOT[2:0], 13'h0}) begin $display("line %0d: slot word %h", lines, rgb); errors = errors + 1; end
			lines = lines + 1;
			px = 0;
		end
		de_d = de;
	end
endmodule

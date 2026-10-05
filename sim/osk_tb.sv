// osk_tb.sv - renders osk_overlay on a 382x270 C64 frame (borders view) to PPM:
//   osk_frame.ppm   keyboard shown, cursor on RS, SHIFT latched, PORT 2 badge
//   load_frame.ppm  loading screen, LOADING DISK 42%
`timescale 1ns/1ps
module osk_tb;
	reg clk = 0;
	always #5 clk = ~clk;
	localparam W = 382, H = 270;
	reg  [23:0] in_rgb;
	reg in_de = 0, in_skip = 0, in_hs = 0, in_vs = 0;
	reg loading = 0;
	wire [23:0] rgb;
	wire de, skip, hs, vs;
	osk_overlay #(.FONT_FILE("../src/fpga/core/osk_font.hex")) dut (.clk(clk), .visible(!loading), .cur_row(3'd2), .cur_col(4'd0),
		.mods(3'b010), .badge(!loading), .badge_mode(3'd4), .loading(loading), .load_kind(3'd2), .load_pct(12'h042),
		.in_rgb(in_rgb), .in_de(in_de), .in_skip(in_skip), .in_hs(in_hs), .in_vs(in_vs),
		.video_rgb(rgb), .video_de(de), .video_skip(skip), .video_hs(hs), .video_vs(vs));

	integer f, x, y, k, frame;
	reg rec = 0;
	always @(posedge clk) if (rec && de && !skip) $fwrite(f, "%0d %0d %0d\n", rgb[23:16], rgb[15:8], rgb[7:0]);
	task send_frame;
		begin
			@(posedge clk) in_vs <= 1; @(posedge clk) in_vs <= 0;
			for (y = 0; y < H; y = y + 1) begin
				@(posedge clk) in_hs <= 1; @(posedge clk) in_hs <= 0;
				repeat (20) @(posedge clk);
				for (x = 0; x < W; x = x + 1) for (k = 0; k < 4; k = k + 1) begin
					@(posedge clk);
					in_de <= 1; in_skip <= k != 0;
					// C64 light blue border, blue screen
					in_rgb <= (x >= 32 && x < 352 && y >= 34 && y < 234) ? 24'h40318D : 24'h7869C4;
				end
				@(posedge clk) in_de <= 0;
				repeat (40) @(posedge clk);
			end
		end
	endtask
	initial begin
		for (frame = 0; frame < 2; frame = frame + 1) begin
			loading = frame;
			send_frame;                 // geometry measured from this frame
			f = $fopen(frame ? "video/load_frame.ppm" : "video/osk_frame.ppm", "w");
			$fwrite(f, "P3\n%0d %0d\n255\n", W, H);
			rec = 1; send_frame; repeat (5) @(posedge clk); rec = 0;
			$fclose(f);
		end
		$finish;
	end
endmodule

//
// c64_video.sv - C64 video (clk_sys, one pixel per 4 clocks) to the APF scaler
//
// The APF video clock is clk_sys; the 3 clocks between pixels are video_skip.
// Pixels are sampled 2 clocks after the hblank fall and every 4 clocks after
// that. Windows are fixed, counted from video_sync's blanking edges, so the DE
// geometry is the same every frame. Numbers come from sim/vic; see docs/video.md.
//

`default_nettype none

module c64_video (
	input  wire        clk,         // clk_sys, also the APF video clock
	input  wire        ntsc,
	input  wire        borders,     // 1: whole visible area, 0: the 320x200 display window

	input  wire  [7:0] r,
	input  wire  [7:0] g,
	input  wire  [7:0] b,
	input  wire        hblank,
	input  wire        vblank,
	input  wire        vsync,

	output reg  [23:0] video_rgb,
	output reg         video_de,
	output reg         video_skip,
	output reg         video_hs,
	output reg         video_vs
);

// Scaler slots, in video.json order
localparam [2:0] SLOT_PAL_BORDER  = 3'd0;
localparam [2:0] SLOT_PAL_FULL    = 3'd1;
localparam [2:0] SLOT_NTSC_BORDER = 3'd2;
localparam [2:0] SLOT_NTSC_FULL   = 3'd3;

// window in pixels from the hblank fall / lines from the vblank fall
reg  [8:0] x0, w;
reg  [8:0] y0, h;
reg  [2:0] slot;
reg        ntsc_f, borders_f;   // latched per frame

always @(*) begin
	case ({ntsc_f, borders_f})
		2'b01: begin x0 = 9'd0;  w = 9'd382; y0 = 9'd0;  h = 9'd270; slot = SLOT_PAL_BORDER;  end
		2'b00: begin x0 = 9'd32; w = 9'd320; y0 = 9'd34; h = 9'd200; slot = SLOT_PAL_FULL;    end
		2'b11: begin x0 = 9'd0;  w = 9'd404; y0 = 9'd0;  h = 9'd250; slot = SLOT_NTSC_BORDER; end
		default: begin x0 = 9'd43; w = 9'd320; y0 = 9'd25; h = 9'd200; slot = SLOT_NTSC_FULL; end
	endcase
end

reg  [1:0] sub;
reg  [8:0] px, py;
reg        sampling;            // in_win a line's active area
reg        hb_d, vb_d, vs_d;

wire hb_fall = hb_d & ~hblank;
wire hb_rise = ~hb_d & hblank;
wire vb_fall = vb_d & ~vblank;
wire vs_rise = ~vs_d & vsync;

wire sample = sampling && !hblank && sub == 2'd1;  // 2 clocks after the hblank fall, then every 4
wire in_x   = (px >= x0) && (px < x0 + w);
wire in_y   = (py >= y0) && (py < y0 + h) && !vblank;
wire in_win = sample && in_x && in_y;
reg  span;                      // the last sampled pixel was in_win the window
wire de     = sample ? (in_x && in_y) : span;

always @(posedge clk) begin
	hb_d <= hblank;
	vb_d <= vblank;
	vs_d <= vsync;

	sub <= sub + 2'd1;
	if (hb_fall) begin
		sub <= 2'd0;
		px <= 9'd0;
		sampling <= 1'b1;
	end
	if (hb_rise) begin
		sampling <= 1'b0;
		span <= 1'b0;
		if (!vblank) py <= py + 9'd1;
	end
	if (vb_fall) py <= 9'd0;
	if (sample) begin
		px <= px + 9'd1;
		span <= in_x && in_y;
	end

	if (vs_rise) begin
		ntsc_f <= ntsc;
		borders_f <= borders;
	end

	// HS at the hblank fall and VS at the vsync rise never share a clock
	video_hs   <= hb_fall;
	video_vs   <= vs_rise;
	video_de   <= de;
	video_skip <= de && !sample;

	if (in_win)
		video_rgb <= {r, g, b};
	else if (video_de && !de)
		video_rgb <= {8'h00, slot, 13'h0000};   // end of line: scaler slot select
	else if (!de)
		video_rgb <= 24'h000000;
end

endmodule

`default_nettype wire

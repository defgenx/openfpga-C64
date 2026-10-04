// hid_tb.sv - hid_c64: key make/break events and mouse reports
`timescale 1ns/1ps
module hid_tb;
	reg clk = 0;
	always #15.86 clk = ~clk;
	reg        kbd_present = 0;
	reg [47:0] kbd_codes = 0;
	reg  [7:0] kbd_mods = 0;
	reg [79:0] pad_keys = 0;
	reg        mev = 0;
	reg signed [15:0] dx = 0, dy = 0;
	reg  [1:0] mbtn = 0;
	wire [10:0] key;
	wire [24:0] mouse;
	hid_c64 #(.EVENT_GAP(64)) dut (.clk(clk), .reset(1'b0), .kbd_present(kbd_present), .kbd_codes(kbd_codes),
		.kbd_mods(kbd_mods), .pad_keys(pad_keys), .mouse_event(mev), .mouse_dx(dx), .mouse_dy(dy),
		.mouse_buttons(mbtn), .ps2_key(key), .ps2_mouse(mouse));

	integer errors = 0, n = 0;
	reg [8:0] got[32];
	reg       gotp[32];
	reg key_t = 0;
	always @(posedge clk) if (key[10] != key_t) begin
		key_t <= key[10]; got[n] = key[8:0]; gotp[n] = key[9]; n = n + 1;
	end
	task expect_ev(input integer i, input pressed, input [8:0] code);
		if (n <= i || gotp[i] !== pressed || got[i] !== code) begin
			$display("event %0d: got %b %h, expected %b %h", i, gotp[i], got[i], pressed, code); errors = errors + 1;
		end
	endtask

	initial begin
		repeat (100) @(posedge clk);
		pad_keys[79:72] = 8'h29;             // Esc -> RUN/STOP (76)
		repeat (3000) @(posedge clk);
		kbd_present = 1; kbd_mods = 8'h02;   // left shift (12)
		kbd_codes[7:0] = 8'h4A;              // Home -> E0 6C
		repeat (3000) @(posedge clk);
		pad_keys = 0; kbd_codes = 0; kbd_mods = 0;
		repeat (6000) @(posedge clk);
		expect_ev(0, 1, 9'h076);
		if (n != 6) begin $display("%0d events, expected 6", n); errors = errors + 1; end
		// the two makes may come in either order, then three breaks
		if (!((got[1] == 9'h012 && got[2] == 9'h16C) || (got[1] == 9'h16C && got[2] == 9'h012)) || !gotp[1] || !gotp[2]) begin
			$display("shift/home makes wrong"); errors = errors + 1; end
		if (gotp[3] || gotp[4] || gotp[5]) begin $display("missing breaks"); errors = errors + 1; end

		// mouse: +100 right, 40 down -> reports of at most 31, Y up positive
		@(posedge clk) begin dx <= 100; dy <= 40; mev <= 1; end
		@(posedge clk) mev <= 0;
		repeat (2000) @(posedge clk);
		$display("hid: %0d errors", errors);
		if (errors) $display("FAIL");
		$finish;
	end

	integer sx = 0, sy = 0;
	reg mt = 0;
	always @(posedge clk) if (mouse[24] != mt) begin
		mt <= mouse[24];
		sx = sx + $signed(mouse[15:8]); sy = sy + $signed(mouse[23:16]);
		if ($signed(mouse[15:8]) > 31 || $signed(mouse[15:8]) < -31) begin $display("mouse step too big"); errors = errors + 1; end
	end
	final if (sx != 100 || sy != -40) $display("FAIL mouse total %0d %0d", sx, sy);
endmodule

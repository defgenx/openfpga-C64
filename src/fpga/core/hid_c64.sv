//
// hid_c64.sv - Dock USB keyboard / mouse and pad-generated keys to MiSTer's
// ps2_key / ps2_mouse words, which C64_MiSTer's fpga64_keyboard and c1351 decode
//
// ps2_key:   [10] toggles per event, [9] pressed, [8] E0 prefix, [7:0] set 2 code
// ps2_mouse: [24] toggles per report, [23:16] Y (+ = up), [15:8] X, [1:0] buttons
// Key mapping follows fpga64_keyboard.vhd; see docs/input.md.
//

`default_nettype none

module hid_c64 #(
	parameter EVENT_GAP = 32768        // clocks between events (~1 ms)
) (
	input  wire        clk,
	input  wire        reset,

	// Dock keyboard: 6 HID usages + modifier byte, valid when kbd_present
	input  wire        kbd_present,
	input  wire [47:0] kbd_codes,
	input  wire  [7:0] kbd_mods,
	// keys from the pad mapping and the on-screen keyboard (10 HID usages, 0 = none)
	input  wire [79:0] pad_keys,

	// relative mouse motion; pulses on a new report
	input  wire        mouse_event,
	input  wire signed [15:0] mouse_dx,   // + = right
	input  wire signed [15:0] mouse_dy,   // + = down (HID convention)
	input  wire  [1:0] mouse_buttons,     // {right, left}

	output reg  [10:0] ps2_key,
	output reg  [24:0] ps2_mouse
);

/* ------------------------------------------------------------------------ */
/* HID usage -> PS/2 set 2 (bit 8 = E0 prefix, 0 = unmapped)                */
/* ------------------------------------------------------------------------ */

function [8:0] hid2ps2(input [7:0] u);
	case (u)
		8'h04: hid2ps2 = 9'h01C; 8'h05: hid2ps2 = 9'h032; 8'h06: hid2ps2 = 9'h021; 8'h07: hid2ps2 = 9'h023;
		8'h08: hid2ps2 = 9'h024; 8'h09: hid2ps2 = 9'h02B; 8'h0A: hid2ps2 = 9'h034; 8'h0B: hid2ps2 = 9'h033;
		8'h0C: hid2ps2 = 9'h043; 8'h0D: hid2ps2 = 9'h03B; 8'h0E: hid2ps2 = 9'h042; 8'h0F: hid2ps2 = 9'h04B;
		8'h10: hid2ps2 = 9'h03A; 8'h11: hid2ps2 = 9'h031; 8'h12: hid2ps2 = 9'h044; 8'h13: hid2ps2 = 9'h04D;
		8'h14: hid2ps2 = 9'h015; 8'h15: hid2ps2 = 9'h02D; 8'h16: hid2ps2 = 9'h01B; 8'h17: hid2ps2 = 9'h02C;
		8'h18: hid2ps2 = 9'h03C; 8'h19: hid2ps2 = 9'h02A; 8'h1A: hid2ps2 = 9'h01D; 8'h1B: hid2ps2 = 9'h022;
		8'h1C: hid2ps2 = 9'h035; 8'h1D: hid2ps2 = 9'h01A;
		8'h1E: hid2ps2 = 9'h016; 8'h1F: hid2ps2 = 9'h01E; 8'h20: hid2ps2 = 9'h026; 8'h21: hid2ps2 = 9'h025;
		8'h22: hid2ps2 = 9'h02E; 8'h23: hid2ps2 = 9'h036; 8'h24: hid2ps2 = 9'h03D; 8'h25: hid2ps2 = 9'h03E;
		8'h26: hid2ps2 = 9'h046; 8'h27: hid2ps2 = 9'h045;
		8'h28: hid2ps2 = 9'h05A; // return
		8'h29: hid2ps2 = 9'h076; // esc        -> RUN/STOP
		8'h2A: hid2ps2 = 9'h066; // backspace  -> INST/DEL
		8'h2B: hid2ps2 = 9'h00D; // tab        -> C=
		8'h2C: hid2ps2 = 9'h029; // space
		8'h2D: hid2ps2 = 9'h04E; // -          -> -
		8'h2E: hid2ps2 = 9'h055; // =          -> +
		8'h2F: hid2ps2 = 9'h054; // [          -> @
		8'h30: hid2ps2 = 9'h05B; // ]          -> *
		8'h31: hid2ps2 = 9'h05D; // \          -> pound
		8'h32: hid2ps2 = 9'h05D;
		8'h33: hid2ps2 = 9'h04C; // ;          -> :
		8'h34: hid2ps2 = 9'h052; // '          -> ;
		8'h35: hid2ps2 = 9'h00E; // `          -> left arrow
		8'h36: hid2ps2 = 9'h041; 8'h37: hid2ps2 = 9'h049; 8'h38: hid2ps2 = 9'h04A;
		8'h39: hid2ps2 = 9'h058; // caps lock  -> SHIFT LOCK
		8'h3A: hid2ps2 = 9'h005; 8'h3B: hid2ps2 = 9'h006; 8'h3C: hid2ps2 = 9'h004; 8'h3D: hid2ps2 = 9'h00C;
		8'h3E: hid2ps2 = 9'h003; 8'h3F: hid2ps2 = 9'h00B; 8'h40: hid2ps2 = 9'h083; 8'h41: hid2ps2 = 9'h00A;
		8'h42: hid2ps2 = 9'h001; // F9         -> up arrow
		8'h43: hid2ps2 = 9'h009; // F10        -> =
		8'h44: hid2ps2 = 9'h078; // F11        -> RESTORE
		8'h49: hid2ps2 = 9'h170; // insert     -> INST
		8'h4A: hid2ps2 = 9'h16C; // home       -> CLR/HOME
		8'h4B: hid2ps2 = 9'h17D; // page up    -> tape play
		8'h4C: hid2ps2 = 9'h171; // delete     -> DEL
		8'h4D: hid2ps2 = 9'h169; // end        -> =
		8'h4E: hid2ps2 = 9'h17A; // page down  -> up arrow
		8'h4F: hid2ps2 = 9'h174; 8'h50: hid2ps2 = 9'h16B; 8'h51: hid2ps2 = 9'h172; 8'h52: hid2ps2 = 9'h175;
		8'h54: hid2ps2 = 9'h04A; 8'h55: hid2ps2 = 9'h07C; 8'h56: hid2ps2 = 9'h07B; 8'h57: hid2ps2 = 9'h079;
		8'h58: hid2ps2 = 9'h05A; // keypad enter
		8'h59: hid2ps2 = 9'h069; 8'h5A: hid2ps2 = 9'h072; 8'h5B: hid2ps2 = 9'h07A; 8'h5C: hid2ps2 = 9'h06B;
		8'h5D: hid2ps2 = 9'h073; 8'h5E: hid2ps2 = 9'h074; 8'h5F: hid2ps2 = 9'h06C; 8'h60: hid2ps2 = 9'h075;
		8'h61: hid2ps2 = 9'h07D; 8'h62: hid2ps2 = 9'h070; 8'h63: hid2ps2 = 9'h071;
		// modifier bits are presented as usages E0-E7
		8'hE0: hid2ps2 = 9'h014; // ctrl       -> CTRL
		8'hE1: hid2ps2 = 9'h012; // shift
		8'hE2: hid2ps2 = 9'h011; // alt        -> C=
		8'hE3: hid2ps2 = 9'h11F; // gui        -> tape key modifier
		8'hE4: hid2ps2 = 9'h114;
		8'hE5: hid2ps2 = 9'h059;
		8'hE6: hid2ps2 = 9'h111;
		default: hid2ps2 = 9'h000;
	endcase
endfunction

/* ------------------------------------------------------------------------ */
/* Keyboard: the current key set is compared with the keys already sent,    */
/* one pair per clock, and each difference becomes a make or break event.   */
/* ------------------------------------------------------------------------ */

localparam N = 24; // 6 dock keys + 8 modifiers + 10 pad/OSK keys

wire [7:0] cur[N];
genvar gi;
generate
	for (gi = 0; gi < 6; gi = gi + 1) begin : g_codes
		assign cur[gi] = kbd_present ? kbd_codes[gi*8 +: 8] : 8'h00;
	end
	for (gi = 0; gi < 8; gi = gi + 1) begin : g_mods
		assign cur[6+gi] = (kbd_present && kbd_mods[gi]) ? (8'hE0 + 8'(gi)) : 8'h00;
	end
	for (gi = 0; gi < 10; gi = gi + 1) begin : g_pad
		assign cur[14+gi] = pad_keys[gi*8 +: 8];
	end
endgenerate

reg  [7:0] sent[N];          // keys whose make event has been sent

localparam [1:0] K_REL = 2'd0, K_NEW = 2'd1, K_GAP = 2'd2;
reg  [1:0] kstate;
reg  [4:0] ki, kj;
reg        hit;
reg [15:0] gap;

initial begin
	integer i;
	ps2_key = 11'd0;
	for (i = 0; i < N; i = i + 1) sent[i] = 8'h00;
	kstate = K_REL; ki = 5'd0; kj = 5'd0; hit = 1'b0; gap = 16'd0;
end

always @(posedge clk) begin
	integer i;
	reg [8:0] code;

	if (reset) begin
		for (i = 0; i < N; i = i + 1) sent[i] <= 8'h00;
		kstate <= K_REL;
		ki <= 5'd0; kj <= 5'd0; hit <= 1'b0;
	end else case (kstate)
	// a sent key that is no longer held -> break
	K_REL: begin
		if (sent[ki] != 8'h00 && cur[kj] == sent[ki]) hit <= 1'b1;
		kj <= kj + 5'd1;
		if (kj == 5'(N - 1)) begin
			kj <= 5'd0;
			hit <= 1'b0;
			if (sent[ki] != 8'h00 && !hit && cur[kj] != sent[ki]) begin
				code = hid2ps2(sent[ki]);
				sent[ki] <= 8'h00;
				ps2_key <= {~ps2_key[10], 1'b0, code};
				gap <= 16'd0;
				kstate <= K_GAP;
			end else if (ki == 5'(N - 1)) begin
				ki <= 5'd0;
				kstate <= K_NEW;
			end else
				ki <= ki + 5'd1;
		end
	end
	// a held key that has not been sent -> make
	K_NEW: begin
		if (cur[ki] != 8'h00 && sent[kj] == cur[ki]) hit <= 1'b1;
		kj <= kj + 5'd1;
		if (kj == 5'(N - 1)) begin
			kj <= 5'd0;
			hit <= 1'b0;
			code = hid2ps2(cur[ki]);
			if (cur[ki] != 8'h00 && code != 9'h000 && !hit && sent[kj] != cur[ki]) begin
				sent[ki] <= cur[ki];
				ps2_key <= {~ps2_key[10], 1'b1, code};
				gap <= 16'd0;
				kstate <= K_GAP;
			end else if (ki == 5'(N - 1)) begin
				ki <= 5'd0;
				kstate <= K_REL;
			end else
				ki <= ki + 5'd1;
		end
	end
	// pace events; then rescan from the start
	default: begin
		gap <= gap + 16'd1;
		if (gap == 16'(EVENT_GAP - 1)) begin
			ki <= 5'd0;
			kj <= 5'd0;
			kstate <= K_REL;
		end
	end
	endcase
end

/* ------------------------------------------------------------------------ */
/* Mouse: accumulate motion, report at most once per EVENT_GAP              */
/* ------------------------------------------------------------------------ */

localparam signed [15:0] STEP_MAX = 16'sd31;   // c1351 adds 6 bits per report

reg signed [15:0] acc_x, acc_y;
reg  [1:0] btn_sent;
reg [15:0] mgap;

function signed [15:0] clamp(input signed [15:0] v, input signed [15:0] lim);
	clamp = (v > lim) ? lim : (v < -lim) ? -lim : v;
endfunction

initial begin
	ps2_mouse = 25'd0;
	acc_x = 0; acc_y = 0; btn_sent = 2'b00; mgap = 16'd0;
end

always @(posedge clk) begin
	reg signed [15:0] nx, ny, sx, sy;
	if (reset) begin
		acc_x <= 0; acc_y <= 0;
		btn_sent <= 2'b00;
		mgap <= 16'd0;
	end else begin
		nx = acc_x; ny = acc_y;
		if (mouse_event) begin
			nx = clamp(acc_x + mouse_dx, 16'sd1024);
			ny = clamp(acc_y + mouse_dy, 16'sd1024);
		end
		if (mgap != 16'd0) mgap <= mgap - 16'd1;
		else if (nx != 0 || ny != 0 || mouse_buttons != btn_sent) begin
			sx = clamp(nx, STEP_MAX);
			sy = clamp(ny, STEP_MAX);
			nx = nx - sx;
			ny = ny - sy;
			ps2_mouse <= {~ps2_mouse[24], 8'(-sy), 8'(sx), 6'd0, mouse_buttons};
			btn_sent <= mouse_buttons;
			mgap <= 16'(EVENT_GAP - 1);
		end
		acc_x <= nx;
		acc_y <= ny;
	end
end

endmodule

`default_nettype wire

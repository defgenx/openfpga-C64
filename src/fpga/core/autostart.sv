//
// autostart.sv - type the LOAD / RUN commands for a disk or tape picked at the BASIC prompt
//
// A disk or tape picked from the Pocket menu arms a request. If the C64 reaches the
// BASIC prompt within ARM_TIME (it may still be booting), the commands are typed:
//   disk: LOAD"*",8,1 <RETURN>, then RUN <RETURN> once BASIC's prompt is back (not when the
//         loaded program started itself and waits for a key: RUN would be typed into it)
//   tape: SHIFT + RUN/STOP (the KERNAL loads and runs the first program)
// A disk swapped in during a game never sees the prompt, so it is only inserted.
// Keys are HID usages for hid_c64; see docs/input.md.
//

`default_nettype none

module autostart #(
	parameter integer CLK_HZ = 31_527_954
) (
	input  wire        clk,
	input  wire        reset,          // the C64 is being reset: forget the request
	input  wire        enable,

	input  wire        disk_inserted,  // pulse
	input  wire        tape_loaded,    // pulse
	input  wire        at_prompt,      // the KERNAL is waiting for a key
	input  wire        basic_main,     // BASIC's direct-mode main loop ran
	input  wire        disk_ready,     // keys are ignored while a disk is being swapped

	output reg   [7:0] key,            // HID usage held down, 0 = none
	output reg         shift,
	output wire        busy
);

localparam integer ARM_TIME  = CLK_HZ * 8;      // boot + disk mount can take a few seconds
localparam integer SETTLE    = CLK_HZ / 4;      // the prompt must be stable this long
localparam integer KEY_HOLD  = CLK_HZ / 16;     // > 3 KERNAL keyboard scans
localparam integer KEY_GAP   = CLK_HZ / 16;
localparam integer SHIFT_LEAD = CLK_HZ / 64;    // > hid_c64's event gap
localparam integer LOAD_WAIT = CLK_HZ * 120;    // give up on a load after 2 minutes

// typed text: {shift, usage}, 0 ends a string
function [8:0] text(input [4:0] i);
	case (i)
		// LOAD"*",8,1<RETURN>
		5'd0:  text = 9'h00F; 5'd1:  text = 9'h012; 5'd2:  text = 9'h004; 5'd3:  text = 9'h007;
		5'd4:  text = 9'h11F; 5'd5:  text = 9'h030; 5'd6:  text = 9'h11F; 5'd7:  text = 9'h036;
		5'd8:  text = 9'h025; 5'd9:  text = 9'h036; 5'd10: text = 9'h01E; 5'd11: text = 9'h028;
		5'd12: text = 9'h000;
		// RUN<RETURN>
		5'd13: text = 9'h015; 5'd14: text = 9'h018; 5'd15: text = 9'h011; 5'd16: text = 9'h028;
		5'd17: text = 9'h000;
		// SHIFT + RUN/STOP
		5'd18: text = 9'h129; 5'd19: text = 9'h000;
		default: text = 9'h000;
	endcase
endfunction
localparam [4:0] T_LOAD = 5'd0, T_RUN = 5'd13, T_TAPE = 5'd18;

localparam [2:0] S_IDLE = 3'd0, S_ARMED = 3'd1, S_TYPE = 3'd2, S_GAP = 3'd3, S_LOADING = 3'd4;

reg  [2:0] state = S_IDLE;
reg  [4:0] pos;
reg        is_disk;            // after the LOAD line, RUN follows
reg        load_started;
reg        main_seen;          // BASIC's main loop ran after the load started
reg [31:0] timer;
reg [31:0] settle;
reg [31:0] ready_settle;
wire [8:0] cur_text  = text(pos);
wire [8:0] next_text = text(pos + 5'd1);

assign busy = state == S_TYPE || state == S_GAP;

// at_prompt held for SETTLE
wire prompt_stable = at_prompt && settle >= SETTLE;
// disk_ready held for SETTLE since the insert: it only drops a few clocks after disk_inserted
wire ready_stable = disk_ready && ready_settle >= SETTLE;

initial begin key = 8'h00; shift = 1'b0; end

always @(posedge clk) begin
	settle <= at_prompt ? (settle < SETTLE ? settle + 1 : settle) : 32'd0;
	ready_settle <= disk_ready && !disk_inserted ? (ready_settle < SETTLE ? ready_settle + 1 : ready_settle) : 32'd0;

	if (reset || !enable) begin
		state <= S_IDLE;
		key <= 8'h00;
		shift <= 1'b0;
	end else begin
		// a new disk or tape restarts the sequence
		if (disk_inserted || tape_loaded) begin
			is_disk <= disk_inserted;
			timer <= 32'd0;
			key <= 8'h00;
			shift <= 1'b0;
			state <= S_ARMED;
		end else case (state)
		S_IDLE: ;

		S_ARMED: begin
			timer <= timer + 1;
			if (timer >= ARM_TIME) state <= S_IDLE;
			else if (prompt_stable && ready_stable) begin
				pos <= is_disk ? T_LOAD : T_TAPE;
				timer <= 32'd0;
				state <= S_TYPE;
			end
		end

		// SHIFT first (so the KERNAL never sees the key without it), then the key for
		// KEY_HOLD; both are released for KEY_GAP
		S_TYPE: begin
			timer <= timer + 1;
			if (timer == 0) shift <= cur_text[8];
			if (timer == SHIFT_LEAD) key <= cur_text[7:0];
			if (timer >= SHIFT_LEAD + KEY_HOLD) begin
				key <= 8'h00;
				shift <= 1'b0;
				timer <= 32'd0;
				state <= S_GAP;
			end
		end

		S_GAP: begin
			timer <= timer + 1;
			if (timer >= KEY_GAP) begin
				timer <= 32'd0;
				if (next_text != 9'h000) begin
					pos <= pos + 5'd1;
					state <= S_TYPE;
				end else if (is_disk && pos < T_RUN) begin
					load_started <= 1'b0;
					state <= S_LOADING;
				end else
					state <= S_IDLE;
			end
		end

		// the prompt goes away while the program loads, and comes back when it is loaded
		S_LOADING: begin
			timer <= timer + 1;
			if (!at_prompt) load_started <= 1'b1;
			if (!load_started) main_seen <= 1'b0;
			else if (basic_main) main_seen <= 1'b1;
			if (timer >= LOAD_WAIT) state <= S_IDLE;
			else if (load_started && prompt_stable) begin
				pos <= T_RUN;
				timer <= 32'd0;
				state <= main_seen ? S_TYPE : S_IDLE;
			end
		end

		default: state <= S_IDLE;
		endcase
	end
end

endmodule

`default_nettype wire

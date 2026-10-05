// autostart_tb.sv - autostart types LOAD"*",8,1 / RUN for a disk at the prompt,
// SHIFT+RUN/STOP for a tape, and nothing for a disk swapped in during a game
`timescale 1ns/1ps
module autostart_tb;
	reg clk = 0;
	always #5 clk = ~clk;
	reg disk = 0, tape = 0, prompt = 0, ready = 1;
	wire [7:0] key;
	wire shift;
	autostart #(.CLK_HZ(4000)) dut (.clk(clk), .reset(1'b0), .enable(1'b1), .disk_inserted(disk),
		.tape_loaded(tape), .at_prompt(prompt), .disk_ready(ready), .key(key), .shift(shift), .busy());

	reg [8*64-1:0] typed = 0;
	integer n = 0, errors = 0;
	reg [7:0] key_d = 0;
	// HID usage -> the character it types on the C64
	function [7:0] ch(input [7:0] u, input s);
		case (u)
			8'h0F: ch = "L"; 8'h12: ch = "O"; 8'h04: ch = "A"; 8'h07: ch = "D"; 8'h15: ch = "R";
			8'h18: ch = "U"; 8'h11: ch = "N"; 8'h1F: ch = s ? "\"" : "2"; 8'h30: ch = "*";
			8'h36: ch = ","; 8'h25: ch = "8"; 8'h1E: ch = "1"; 8'h28: ch = "|";
			8'h29: ch = s ? "^" : "!";       // ^ = SHIFT+RUN/STOP
			default: ch = "?";
		endcase
	endfunction
	always @(posedge clk) begin
		key_d <= key;
		if (key != 0 && key_d == 0) begin if (key == 8'h1F && !shift) errors = errors + 1; typed = {typed[8*63-1:0], ch(key, shift)}; n = n + 1; end
	end
	task expect_typed(input [8*64-1:0] want, input [8*32-1:0] what);
		if (typed !== want) begin $display("FAIL %0s: typed \"%0s\"", what, typed); errors = errors + 1; end
		else $display("%0s: typed \"%0s\"", what, typed);
		typed = 0;
	endtask

	initial begin
		// disk picked while booting: typed once the prompt appears
		@(posedge clk) disk = 1; @(posedge clk) disk = 0;
		repeat (3000) @(posedge clk);
		prompt = 1;
		repeat (30000) @(posedge clk);          // LOAD typed; the drive loads
		prompt = 0;
		repeat (5000) @(posedge clk);
		prompt = 1;                               // READY.
		repeat (20000) @(posedge clk);
		expect_typed("LOAD\"*\",8,1|RUN|", "disk at the prompt");

		// a disk swapped in during a game: no prompt, nothing typed
		prompt = 0;
		@(posedge clk) disk = 1; @(posedge clk) disk = 0;
		repeat (60000) @(posedge clk);
		expect_typed("", "disk swap in a game");

		// tape at the prompt
		prompt = 1;
		@(posedge clk) tape = 1; @(posedge clk) tape = 0;
		repeat (10000) @(posedge clk);
		expect_typed("^", "tape at the prompt");
		if (errors) $display("autostart: FAIL"); else $display("autostart: all OK");
		$finish;
	end
endmodule

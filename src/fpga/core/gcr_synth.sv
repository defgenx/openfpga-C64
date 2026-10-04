//
// gcr_synth.sv - one D64 track to 1541 GCR bytes
//
// The FPGA side of Main_MiSTer's c64_synthesize_gcr_track() (support/c64/c64.cpp),
// which the Pocket has no ARM to run. Byte for byte the same output: per sector
//   5 x FF, header GCR (08 chk sec trk id1 id0 0F 0F), 9 x 55,
//   5 x FF, data GCR (07, 256 bytes, chk, 00, 00), gap x 55
// with gap 8 / 17 / 12 / 9 by speed zone. Sector data is read from the track
// buffer at sector*256 (q valid two clocks after the address).
//

`default_nettype none

module gcr_synth (
	input  wire        clk,
	input  wire        start,        // pulse; parameters stable until done
	input  wire  [5:0] track,        // 1-based track number
	input  wire  [4:0] nsec,
	input  wire  [7:0] id0,          // disk id bytes from $165A2 / $165A3
	input  wire  [7:0] id1,
	output reg         busy,

	output reg  [12:0] rb_addr,
	input  wire  [7:0] rb_q,

	output reg         out_strobe,   // out_byte valid; hold until out_done
	output reg   [7:0] out_byte,
	input  wire        out_done
);

function [4:0] gcr5(input [3:0] n);
	case (n)
		4'h0: gcr5 = 5'h0A; 4'h1: gcr5 = 5'h0B; 4'h2: gcr5 = 5'h12; 4'h3: gcr5 = 5'h13;
		4'h4: gcr5 = 5'h0E; 4'h5: gcr5 = 5'h0F; 4'h6: gcr5 = 5'h16; 4'h7: gcr5 = 5'h17;
		4'h8: gcr5 = 5'h09; 4'h9: gcr5 = 5'h19; 4'hA: gcr5 = 5'h1A; 4'hB: gcr5 = 5'h1B;
		4'hC: gcr5 = 5'h0D; 4'hD: gcr5 = 5'h1D; 4'hE: gcr5 = 5'h1E; default: gcr5 = 5'h15;
	endcase
endfunction

function [9:0] gcr10(input [7:0] b);
	gcr10 = {gcr5(b[7:4]), gcr5(b[3:0])};
endfunction

// items of one sector
localparam [2:0] I_SYNC1 = 3'd0, I_HDR1 = 3'd1, I_HDR2 = 3'd2, I_GAP1 = 3'd3,
                 I_SYNC2 = 3'd4, I_DATA = 3'd5, I_GAP2 = 3'd6;

localparam [2:0] S_IDLE = 3'd0, S_ITEM = 3'd1, S_RAW = 3'd2, S_FETCH = 3'd3, S_WAIT = 3'd4,
                 S_EMIT = 3'd5, S_NEXT = 3'd6;

reg  [2:0] state = S_IDLE;
reg  [2:0] item;
reg  [4:0] sec;
reg  [4:0] raw_left;
reg  [7:0] raw_val;
reg  [6:0] group;            // data group 0..64
reg  [1:0] k;                // byte within a group
reg  [1:0] wait_cnt;
reg  [7:0] grp[4];
reg  [7:0] cksum;
reg [39:0] gcr;
reg  [2:0] emit_left;

wire [4:0] gap = (track < 6'd18) ? 5'd8 : (track < 6'd25) ? 5'd17 : (track < 6'd31) ? 5'd12 : 5'd9;
wire [8:0] dpos = {group, k};         // position in the 260-byte data block

initial busy = 1'b0;

always @(posedge clk) begin
	case (state)
	S_IDLE: begin
		out_strobe <= 1'b0;
		if (start) begin
			busy <= 1'b1;
			sec <= 5'd0;
			item <= I_SYNC1;
			state <= S_ITEM;
		end
	end

	S_ITEM: begin
		k <= 2'd0;
		group <= 7'd0;
		case (item)
			I_SYNC1, I_SYNC2: begin raw_val <= 8'hFF; raw_left <= 5'd5; state <= S_RAW; end
			I_GAP1:           begin raw_val <= 8'h55; raw_left <= 5'd9; state <= S_RAW; end
			I_GAP2:           begin raw_val <= 8'h55; raw_left <= gap;  state <= S_RAW; end
			I_HDR1: begin
				grp[0] <= 8'h08;
				grp[1] <= {3'd0, sec} ^ {2'd0, track} ^ id0 ^ id1;
				grp[2] <= {3'd0, sec};
				grp[3] <= {2'd0, track};
				state <= S_EMIT;
				gcr <= {gcr10(8'h08), gcr10({3'd0, sec} ^ {2'd0, track} ^ id0 ^ id1), gcr10({3'd0, sec}), gcr10({2'd0, track})};
				emit_left <= 3'd5;
			end
			I_HDR2: begin
				gcr <= {gcr10(id1), gcr10(id0), gcr10(8'h0F), gcr10(8'h0F)};
				emit_left <= 3'd5;
				state <= S_EMIT;
			end
			default: begin   // I_DATA
				cksum <= 8'h00;
				emit_left <= 3'd0;
				state <= S_FETCH;
			end
		endcase
	end

	S_RAW: begin
		if (!out_strobe) begin
			out_byte <= raw_val;
			out_strobe <= 1'b1;
		end else if (out_done) begin
			out_strobe <= 1'b0;
			raw_left <= raw_left - 5'd1;
			if (raw_left == 5'd1) state <= S_NEXT;
		end
	end

	// data block: gather 4 bytes, then emit their 5 GCR bytes
	S_FETCH: begin
		if (dpos >= 9'd1 && dpos <= 9'd256) begin
			rb_addr <= {sec, 8'd0} + {4'd0, dpos - 9'd1};
			wait_cnt <= 2'd0;
			state <= S_WAIT;
		end else begin
			grp[k] <= (dpos == 9'd0) ? 8'h07 : (dpos == 9'd257) ? cksum : 8'h00;
			k <= k + 2'd1;
			if (k == 2'd3) state <= S_EMIT;
		end
	end

	S_WAIT: begin
		wait_cnt <= wait_cnt + 2'd1;
		if (wait_cnt == 2'd2) begin
			grp[k] <= rb_q;
			cksum <= cksum ^ rb_q;
			k <= k + 2'd1;
			state <= (k == 2'd3) ? S_EMIT : S_FETCH;
		end
	end

	S_EMIT: begin
		if (item == I_DATA && emit_left == 3'd0) begin
			// a data group just gathered: build it (grp[3] lands this clock for the last fetch)
			gcr <= {gcr10(grp[0]), gcr10(grp[1]), gcr10(grp[2]), gcr10(grp[3])};
			emit_left <= 3'd5;
		end else if (!out_strobe) begin
			out_byte <= gcr[39:32];
			out_strobe <= 1'b1;
		end else if (out_done) begin
			out_strobe <= 1'b0;
			gcr <= {gcr[31:0], 8'h00};
			emit_left <= emit_left - 3'd1;
			if (emit_left == 3'd1) begin
				if (item == I_DATA && group != 7'd64) begin
					group <= group + 7'd1;
					emit_left <= 3'd0;
					state <= S_FETCH;
				end else
					state <= S_NEXT;
			end
		end
	end

	S_NEXT: begin
		if (item == I_GAP2) begin
			item <= I_SYNC1;
			sec <= sec + 5'd1;
			if (sec + 5'd1 == nsec) begin
				busy <= 1'b0;
				state <= S_IDLE;
			end else
				state <= S_ITEM;
		end else begin
			item <= item + 3'd1;
			state <= S_ITEM;
		end
	end

	default: state <= S_IDLE;
	endcase
end

endmodule

`default_nettype wire

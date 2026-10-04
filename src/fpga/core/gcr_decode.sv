//
// gcr_decode.sv - a written-back 1541 GCR track to D64 sectors
//
// The FPGA side of the D64 branch of Main_MiSTer's c64_writeGCR(). The track buffer
// holds a 2-byte length and the GCR bytes; the track is circular, so it is scanned
// twice to see every sector whole. A sync is 10 or more 1 bits; the block after it
// is a header (08, chk, sector, ...) or a data block (07, 256 bytes, ...), which
// belongs to the last header seen. Unlike MiSTer, sectors that are not found are
// reported missing (valid bit low) instead of being written as zeros.
//

`default_nettype none

module gcr_decode (
	input  wire        clk,
	input  wire        start,          // pulse; parameters stable until done
	input  wire [13:0] track_size,     // GCR bytes, at buffer offsets 2..track_size+1
	input  wire  [4:0] nsec,
	output reg         busy,

	output reg  [13:0] sb_addr,
	input  wire  [7:0] sb_q,           // valid two clocks after sb_addr

	output reg         wb_we,
	output reg  [12:0] wb_addr,        // sector * 256 + byte
	output reg   [7:0] wb_data,
	output reg  [20:0] valid
);

function [3:0] nib(input [4:0] c);
	case (c)
		5'h0A: nib = 4'h0; 5'h0B: nib = 4'h1; 5'h12: nib = 4'h2; 5'h13: nib = 4'h3;
		5'h0E: nib = 4'h4; 5'h0F: nib = 4'h5; 5'h16: nib = 4'h6; 5'h17: nib = 4'h7;
		5'h09: nib = 4'h8; 5'h19: nib = 4'h9; 5'h1A: nib = 4'hA; 5'h1B: nib = 4'hB;
		5'h0D: nib = 4'hC; 5'h1D: nib = 4'hD; 5'h1E: nib = 4'hE; 5'h15: nib = 4'hF;
		default: nib = 4'h0;
	endcase
endfunction

localparam [1:0] S_IDLE = 2'd0, S_FETCH = 2'd1, S_BITS = 2'd2;
localparam [1:0] B_NONE = 2'd0, B_HDR = 2'd1, B_DATA = 2'd2;

reg  [1:0] state = S_IDLE;
reg [13:0] boff;               // byte offset in the track, wraps at track_size
reg        second;             // in the second revolution
reg  [1:0] wcnt;
reg  [7:0] byte_r;
reg  [2:0] bitn;
reg  [3:0] ones;
reg        collecting;
reg  [9:0] sh;
reg  [3:0] nbits;
reg  [8:0] j;                  // byte index within the block
reg  [1:0] blk;
reg  [4:0] hdr_sec;
reg        hdr_valid;

wire       bit_in = byte_r[3'd7 - bitn];
wire [9:0] sh_n = {sh[8:0], bit_in};
wire [7:0] dec  = {nib(sh_n[9:5]), nib(sh_n[4:0])};

initial busy = 1'b0;

always @(posedge clk) begin
	wb_we <= 1'b0;

	case (state)
	S_IDLE: if (start) begin
		busy <= 1'b1;
		boff <= 14'd0;
		second <= 1'b0;
		ones <= 4'd0;
		collecting <= 1'b0;
		hdr_valid <= 1'b0;
		valid <= 21'd0;
		wcnt <= 2'd0;
		sb_addr <= 14'd2;
		state <= S_FETCH;
	end

	S_FETCH: begin
		wcnt <= wcnt + 2'd1;
		if (wcnt == 2'd2) begin
			byte_r <= sb_q;
			bitn <= 3'd0;
			wcnt <= 2'd0;
			state <= S_BITS;
		end
	end

	S_BITS: begin
		bitn <= bitn + 3'd1;

		// sync detection runs all the time; valid GCR never has 10 ones in a row
		if (bit_in) begin
			if (ones != 4'd15) ones <= ones + 4'd1;
			if (ones == 4'd9) collecting <= 1'b0;   // inside a sync: drop any block
		end else begin
			ones <= 4'd0;
			if (ones >= 4'd10) begin
				collecting <= 1'b1;
				sh <= 10'd0;
				nbits <= 4'd1;
				j <= 9'd0;
			end
		end

		if (collecting && !(bit_in && ones == 4'd9)) begin
			sh <= sh_n;
			nbits <= nbits + 4'd1;
			if (nbits == 4'd9) begin
				nbits <= 4'd0;
				j <= j + 9'd1;
				if (j == 9'd0) begin
					blk <= (dec == 8'h08) ? B_HDR : (dec == 8'h07 && hdr_valid) ? B_DATA : B_NONE;
					if (dec != 8'h08 && !(dec == 8'h07 && hdr_valid)) collecting <= 1'b0;
				end else if (blk == B_HDR) begin
					if (j == 9'd2) begin
						hdr_sec <= dec[4:0];
						hdr_valid <= dec < {3'd0, nsec};
						collecting <= 1'b0;
					end
				end else begin   // B_DATA: bytes 1..256
					wb_we <= 1'b1;
					wb_addr <= {hdr_sec, j[7:0] - 8'd1};
					wb_data <= dec;
					if (j == 9'd256) begin
						valid[hdr_sec] <= 1'b1;
						hdr_valid <= 1'b0;
						collecting <= 1'b0;
					end
				end
			end
		end

		if (bitn == 3'd7) begin
			if (boff + 14'd1 == track_size) begin
				boff <= 14'd0;
				second <= 1'b1;
				sb_addr <= 14'd2;
				if (second) begin
					busy <= 1'b0;
					state <= S_IDLE;
				end else
					state <= S_FETCH;
			end else begin
				boff <= boff + 14'd1;
				sb_addr <= boff + 14'd3;
				state <= S_FETCH;
			end
		end
	end

	default: state <= S_IDLE;
	endcase
end

endmodule

`default_nettype wire

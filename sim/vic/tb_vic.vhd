-- tb_vic.vhd - measure the VIC-II picture in video_sync's blanking coordinates
--
-- Runs C64_MiSTer's video_vicii_656x and video_sync with fpga64_sid_iec's clock
-- enables, sets up a text screen (DEN, border 14, background 6) and reports, per
-- frame, the active area (hblank/vblank low) and where the display window sits in
-- it. Also writes frame.ppm (active area only). Generic NTSC selects 6567R8.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_vic is
	generic (NTSC : integer := 0; TRACE : integer := 0);
end entity;

architecture sim of tb_vic is
	signal clk      : std_logic := '0';
	signal cyc      : unsigned(4 downto 0) := (others => '0');
	signal phi      : std_logic := '0';
	signal enaData  : std_logic := '0';
	signal enaPixel : std_logic := '0';
	signal reset    : std_logic := '1';
	signal cs, we   : std_logic := '0';
	signal areg     : unsigned(5 downto 0) := (others => '0');
	signal dreg     : unsigned(7 downto 0) := (others => '0');
	signal hsync, vsync : std_logic;
	signal colorIndex : unsigned(3 downto 0);
	signal hs_o, vs_o, hblank, vblank : std_logic;
	signal ntsc_s : std_logic;
	signal done : boolean := false;
begin
	ntsc_s <= '1' when NTSC = 1 else '0';
	clk <= not clk after 15.86 ns when not done;

	process(clk) begin
		if rising_edge(clk) then
			cyc <= cyc + 1;
			-- fpga64_sid_iec: phi0 high for CYCLE_CPU0..CPUF (16..31)
			if cyc = 15 then phi <= '1'; end if;
			if cyc = 31 then phi <= '0'; end if;
			enaData <= '0';
			if cyc = 14 or cyc = 30 then enaData <= '1'; end if;   -- CYCLE_VIC2, CYCLE_CPUE
			enaPixel <= '0';
			if cyc(1 downto 0) = "10" then enaPixel <= '1'; end if; -- every 4th: 2, 6, ... 30
		end if;
	end process;

	-- register writes in CPU half cycles
	process
		procedure wr(a : integer; d : integer) is
		begin
			wait until rising_edge(clk) and cyc = 29;
			areg <= to_unsigned(a, 6); dreg <= to_unsigned(d, 8); cs <= '1'; we <= '1';
			wait until rising_edge(clk) and cyc = 31;
			cs <= '0'; we <= '0';
		end procedure;
	begin
		wait for 2 us;
		wait until rising_edge(clk) and cyc = 31;
		reset <= '0';
		wr(16#11#, 16#1B#);  -- DEN, 25 rows, yscroll 3
		wr(16#16#, 16#C8#);  -- 40 columns
		wr(16#18#, 16#14#);
		wr(16#20#, 14);      -- border light blue
		wr(16#21#, 6);       -- background blue
		wait;
	end process;

	vic: entity work.video_vicii_656x
	generic map (registeredAddress => true, emulateRefresh => true, emulateLightpen => true, emulateGraphics => true)
	port map (
		clk => clk, phi => phi, enaData => enaData, enaPixel => enaPixel,
		baSync => '0', ba => open, ba_dma => open,
		mode6569 => not ntsc_s, mode6567old => '0', mode6567R8 => ntsc_s, mode6572 => '0',
		turbo_en => '0', turbo_state => open, variant => "00",
		reset => reset, cs => cs, we => we, lp_n => '1',
		aRegisters => areg, diRegisters => dreg,
		di => x"20", diColor => x"1", do => open,
		vicAddr => open, irq_n => open,
		hSync => hsync, vSync => vsync, colorIndex => colorIndex,
		debugX => open, debugY => open, vicRefresh => open, addrValid => open);

	vs: entity work.video_sync
	port map (clk32 => clk, pause => '0', hsync => hsync, vsync => vsync, ntsc => ntsc_s, wide => '0',
	          hsync_out => hs_o, vsync_out => vs_o, hblank => hblank, vblank => vblank);

	-- measure: x counts pixels (every 4th clock, phase 2 after the hblank fall),
	-- y counts lines from the vblank fall
	process(clk)
		variable x, y : integer := 0;
		variable sub : integer := 0;
		variable hb_d, vb_d, vs_d : std_logic := '1';
		variable frame : integer := 0;
		variable w_max, h_cnt : integer := 0;
		variable win_x0, win_x1, win_y0, win_y1 : integer := -1;
		variable l : line;
		file f : text;
		variable opened : boolean := false;
		variable rgb : string(1 to 3);
		variable vs_line, vs_x : integer := -1;
		variable hs_x : integer := -1;
	begin
		if rising_edge(clk) then
			sub := sub + 1;
			if hb_d = '1' and hblank = '0' then
				sub := 0; x := 0;
			end if;
			if hb_d = '0' and hblank = '1' then
				if x > w_max then w_max := x; end if;
				if vblank = '0' then y := y + 1; end if;
			end if;
			if vb_d = '1' and vblank = '0' then
				y := 0;
			end if;
			if vs_d = '0' and vs_o = '1' then
				vs_line := y; vs_x := x;
			end if;
			if vb_d = '0' and vblank = '1' then
				frame := frame + 1;
				write(l, string'("frame ")); write(l, frame);
				write(l, string'(" active ")); write(l, w_max); write(l, string'("x")); write(l, y);
				write(l, string'(" window x ")); write(l, win_x0); write(l, string'("..")); write(l, win_x1);
				write(l, string'(" y ")); write(l, win_y0); write(l, string'("..")); write(l, win_y1);
				writeline(output, l);
				if opened then file_close(f); opened := false; end if;
				if frame = 5 then done <= true; end if;
				w_max := 0; win_x0 := -1; win_x1 := -1; win_y0 := -1; win_y1 := -1;
				if frame = 2 then
					file_open(f, "frame.ppm", write_mode);
					opened := true;
				end if;
			end if;
			if sub = 2 and hblank = '0' and vblank = '0' then
				if colorIndex = 6 or colorIndex = 1 then
					if win_x0 < 0 or x < win_x0 then win_x0 := x; end if;
					if x > win_x1 then win_x1 := x; end if;
					if win_y0 < 0 then win_y0 := y; end if;
					win_y1 := y;
				end if;
				if opened then
					if colorIndex = 14 then rgb := (character'val(108), character'val(94), character'val(181));
					elsif colorIndex = 6 then rgb := (character'val(53), character'val(40), character'val(121));
					else rgb := (character'val(255), character'val(255), character'val(255)); end if;
					write(l, rgb); 
					writeline(f, l);
				end if;
				x := x + 1;
				sub := -2;
			end if;
			hb_d := hblank; vb_d := vblank; vs_d := vs_o;
		end if;
	end process;
	-- per-clock trace for c64_video_tb: one line "<flags><colour>", flags = vs<<2 | vb<<1 | hb
	g_trace: if TRACE = 1 generate
		process(clk)
			file tf : text open write_mode is "trace.txt";
			variable l : line;
			variable vb_d : std_logic := '0';
			variable frames : integer := 0;
			constant hexd : string(1 to 16) := "0123456789abcdef";
		begin
			if rising_edge(clk) and not done then
				if vb_d = '0' and vblank = '1' then frames := frames + 1; end if;
				vb_d := vblank;
				if frames >= 1 then
					write(l, hexd(1 + to_integer(unsigned'(vs_o & vblank & hblank))));
					write(l, hexd(1 + to_integer(colorIndex)));
					writeline(tf, l);
				end if;
			end if;
		end process;
	end generate;
end architecture;

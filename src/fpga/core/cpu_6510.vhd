-- -----------------------------------------------------------------------
--
--                                 FPGA 64
--
--     A fully functional commodore 64 implementation in a single FPGA
--
-- -----------------------------------------------------------------------
-- Copyright 2005-2008 by Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
-- -----------------------------------------------------------------------
--
-- 6510 wrapper for 65xx core
-- Adds 8 bit I/O port mapped at addresses $0000 to $0001
--
-- -----------------------------------------------------------------------
-- C64_MiSTer's rtl/cpu_6510.vhd (submodule fe6dfe5) with the STOP check fix: docs/architecture.md,
-- "DolphinDOS STOP check". Keep in step with the original.
-- -----------------------------------------------------------------------

library IEEE;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL;

-- -----------------------------------------------------------------------

entity cpu_6510 is
	port (
		clk     : in  std_logic;
		enable  : in  std_logic;
		reset   : in  std_logic;
		nmi_n   : in  std_logic;
		nmi_ack : out std_logic;
		irq_n   : in  std_logic;
		rdy     : in  std_logic;

		di      : in  unsigned(7 downto 0);
		do      : out unsigned(7 downto 0);
		addr    : out unsigned(15 downto 0);
		we      : out std_logic;

		diIO    : in  unsigned(7 downto 0);
		doIO    : out unsigned(7 downto 0)
	);
end cpu_6510;

-- -----------------------------------------------------------------------

architecture rtl of cpu_6510 is
	signal localA : std_logic_vector(23 downto 0);
	signal localDi : std_logic_vector(7 downto 0);
	signal localDo : std_logic_vector(7 downto 0);
	signal localWe : std_logic;

	signal currentIO : std_logic_vector(7 downto 0);
	signal ioDir : std_logic_vector(7 downto 0);
	signal ioData : std_logic_vector(7 downto 0);
	
	signal accessIO : std_logic;

	-- BIT $91 from the kernal ROM: op = opcode $24 read at opA, arg = then $91 read at opA+1
	signal bit91_op  : std_logic := '0';
	signal bit91_arg : std_logic := '0';
	signal bit91_opA : std_logic_vector(15 downto 0);
	signal stop_fix  : std_logic;
	signal di_fix    : std_logic_vector(7 downto 0);
begin

	cpu: work.T65
	port map(
		Mode    => "00",
		Res_n   => not reset,
		Enable  => enable,
		Clk     => clk,
		Rdy     => rdy,
		Abort_n => '1',
		IRQ_n   => irq_n,
		NMI_n   => nmi_n,
		SO_n    => '1',
		R_W_n   => localWe,
		A       => localA,
		DI      => localDi,
		DO      => localDo,
		NMI_ack => nmi_ack
	);

	accessIO <= '1' when localA(15 downto 1) = X"000"&"000" else '0';
	-- that BIT reads $00 at $0091 as $80 (STOP not pressed); any other value passes through
	stop_fix <= '1' when bit91_arg = '1' and localA(15 downto 0) = X"0091" and di(6 downto 0) = "0000000" else '0';
	di_fix   <= std_logic_vector(di(7 downto 0)) or (stop_fix & "0000000");
	localDi  <= localDo when localWe = '0' else di_fix when accessIO = '0' else ioDir when localA(0) = '0' else currentIO;

	process(clk)
	begin
		if rising_edge(clk) then
			if accessIO = '1' then
				if localWe = '0' and enable = '1' then
					if localA(0) = '0' then
						ioDir <= localDo;
					else
						ioData <= localDo;
					end if;
				end if;
			end if;

			currentIO <= (ioData and ioDir) or (std_logic_vector(diIO) and not ioDir);

			-- a bus cycle completes when enable = 1 and (rdy = 1 or it writes), as in T65
			if enable = '1' and (rdy = '1' or localWe = '0') then
				bit91_op <= '0';
				bit91_arg <= '0';
				if localWe = '1' then
					if localA(15 downto 13) = "111" and currentIO(1) = '1' and di = X"24" then
						bit91_op <= '1';
					end if;
					if bit91_op = '1' and unsigned(localA(15 downto 0)) = unsigned(bit91_opA) + 1 and di = X"91" then
						bit91_arg <= '1';
					end if;
				end if;
				bit91_opA <= localA(15 downto 0);
			end if;

			if reset = '1' then
				ioDir <= (others => '0');
				ioData <= (others => '1');
				currentIO <= "00111111";  -- upper two bits are unused; ensure that the KERNAL is able to set Zero Page address $01 to $37 by default
				bit91_op <= '0';
				bit91_arg <= '0';
			end if;
		end if;
	end process;

	-- Cunnect zee wires
	addr <= unsigned(localA(15 downto 0));
	do <= unsigned(localDo);
	we <= not localWe;
	doIO <= unsigned(currentIO);
end architecture;

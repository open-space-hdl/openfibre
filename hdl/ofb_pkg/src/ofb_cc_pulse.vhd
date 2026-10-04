---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Pulse clock domain crossing with single-cycle output pulses: olo_ft_cc_pulse (TMR-hardened)
-- followed by a rising-edge detector, because olo_ft_cc_pulse stretches every output pulse to
-- SyncStages_g - 1 cycles. Input pulses of one bit must be at least 2 * SyncStages_g + 2 output
-- clock cycles apart (see the olo_ft_cc_pulse documentation).
--
-- Documentation: hdl/ofb_pkg/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library olo;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_cc_pulse is
    generic (
        NumPulses_g : positive := 1
    );
    port (
        -- Input clock domain
        In_Clk    : in    std_logic;
        In_Rst    : in    std_logic := '0';
        In_Pulse  : in    std_logic_vector(NumPulses_g-1 downto 0);
        -- Output clock domain
        Out_Clk   : in    std_logic;
        Out_Rst   : in    std_logic := '0';
        Out_Pulse : out   std_logic_vector(NumPulses_g-1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_cc_pulse is

    signal Stretched : std_logic_vector(NumPulses_g-1 downto 0);
    signal Last      : std_logic_vector(NumPulses_g-1 downto 0);

begin

    i_cc : entity olo.olo_ft_cc_pulse
        generic map (
            NumPulses_g => NumPulses_g
        )
        port map (
            In_Clk    => In_Clk,
            In_RstIn  => In_Rst,
            In_Pulse  => In_Pulse,
            Out_Clk   => Out_Clk,
            Out_RstIn => Out_Rst,
            Out_Pulse => Stretched
        );

    p_edge : process (Out_Clk) is
    begin
        if rising_edge(Out_Clk) then
            Last <= Stretched;
            if Out_Rst = '1' then
                Last <= (others => '0');
            end if;
        end if;
    end process;

    Out_Pulse <= Stretched and not Last;

end architecture;

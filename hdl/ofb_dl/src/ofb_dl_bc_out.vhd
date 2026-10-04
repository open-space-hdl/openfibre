---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Broadcast output buffer of the Data Link layer (DT-3): buffer from the user clock to the core
-- clock, Broadcast Bandwidth Credit Counter (ECSS 5.7.5) and LATE flag (ECSS 5.3.8.4j).
--
-- Documentation: hdl/ofb_dl/docs/architecture.md (section 3.2)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.ofb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_dl_bc_out is
    generic (
        Depth_g : positive := 4
    );
    port (
        -- User clock side
        UserClk         : in    std_logic;
        UserRst         : in    std_logic;
        In_Data         : in    std_logic_vector(63 downto 0);
        In_Channel      : in    Char_t;
        In_Type         : in    Char_t;
        In_Delayed      : in    std_logic;
        In_Valid        : in    std_logic;
        In_Ready        : out   std_logic;
        EccInj_Valid    : in    std_logic := '0'; -- Error injection into the next message (UserClk)
        EccInj_Double   : in    std_logic := '0';
        -- Core clock side
        Clk             : in    std_logic;
        Rst             : in    std_logic;
        Ctrl_LinkReset  : in    std_logic;
        Ctrl_LaneActive : in    std_logic; -- At least one lane is active
        Ctrl_Recovery   : in    std_logic; -- Error recovery in progress
        Cfg_BcInterval  : in    std_logic_vector(15 downto 0); -- Words per broadcast credit
        Ev_WordSent     : in    std_logic; -- A word was passed to the Multi-Lane layer
        Ev_BcSent       : in    std_logic; -- A broadcast frame was sent
        Out_Data        : out   std_logic_vector(63 downto 0);
        Out_Channel     : out   Char_t;
        Out_Type        : out   Char_t;
        Out_Delayed     : out   std_logic;
        Out_Late        : out   std_logic;
        Out_Valid       : out   std_logic;
        Out_Ready       : in    std_logic;
        Bc_Credit       : out   std_logic; -- Broadcast Bandwidth Credit Counter greater than zero
        Ev_EccSec       : out   std_logic; -- ECC events of the messages read (core clock)
        Ev_EccDed       : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_dl_bc_out is

    constant CreditLimit_c : natural := 256;

    signal FifoIn   : std_logic_vector(80 downto 0);
    signal FifoOut  : std_logic_vector(80 downto 0);
    signal OutValid : std_logic;
    signal FifoSec  : std_logic;
    signal FifoDed  : std_logic;
    signal Late     : std_logic;
    signal Credit   : natural range 0 to CreditLimit_c;
    signal Interval : unsigned(15 downto 0);

begin

    FifoIn <= In_Delayed & In_Type & In_Channel & In_Data;

    i_fifo : entity olo.olo_ft_fifo_async
        generic map (
            Width_g => 81,
            Depth_g => Depth_g
        )
        port map (
            In_Clk            => UserClk,
            In_Rst            => UserRst,
            In_Data           => FifoIn,
            In_Valid          => In_Valid,
            In_Ready          => In_Ready,
            Out_Clk           => Clk,
            Out_Rst           => Rst,
            Out_Data          => FifoOut,
            Out_Valid         => OutValid,
            Out_Ready         => Out_Ready,
            Out_EccSec        => FifoSec,
            Out_EccDed        => FifoDed,
            In_ErrInj_BitFlip => eccInjPattern(eccCodewordWidth(81), EccInj_Double),
            In_ErrInj_Valid   => EccInj_Valid
        );

    Ev_EccSec <= FifoSec and OutValid and Out_Ready;
    Ev_EccDed <= FifoDed and OutValid and Out_Ready;

    Out_Data    <= FifoOut(63 downto 0);
    Out_Channel <= FifoOut(71 downto 64);
    Out_Type    <= FifoOut(79 downto 72);
    Out_Delayed <= FifoOut(80);
    Out_Late    <= Late;
    Out_Valid   <= OutValid;
    Bc_Credit   <= '1' when Credit > 0 else '0';

    p_core : process (Clk) is
        variable Credit_v : natural range 0 to CreditLimit_c + 1;
    begin
        if rising_edge(Clk) then
            -- Broadcast Bandwidth Credit Counter: + 1 per interval, - 1 per broadcast frame sent
            Credit_v := Credit;
            if Ev_WordSent = '1' and unsigned(Cfg_BcInterval) /= 0 then
                if Interval >= unsigned(Cfg_BcInterval) - 1 then
                    Interval <= (others => '0');
                    Credit_v := Credit_v + 1;
                else
                    Interval <= Interval + 1;
                end if;
            end if;
            if Ev_BcSent = '1' and Credit_v > 0 then
                Credit_v := Credit_v - 1;
            end if;
            if Credit_v > CreditLimit_c then
                Credit_v := CreditLimit_c;
            end if;
            Credit <= Credit_v;

            -- LATE: messages that wait while no lane is active or during error recovery
            if OutValid = '1' and (Ctrl_LaneActive = '0' or Ctrl_Recovery = '1') then
                Late <= '1';
            elsif OutValid = '0' then
                Late <= '0';
            end if;

            if Rst = '1' or Ctrl_LinkReset = '1' then
                Credit   <= 0;
                Interval <= (others => '0');
            end if;
            if Rst = '1' then
                Late <= '0';
            end if;
        end if;
    end process;

end architecture;

---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Broadcast input buffer of the Data Link layer (DR-7): accepted broadcast messages from the core
-- clock to the user clock; a message that finds the buffer full is discarded.
--
-- Documentation: hdl/ofb_dl/docs/architecture.md (section 3.10)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library olo;

library work;
    use work.ofb_pkg.all;
    use work.ofb_dl_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_dl_bc_in is
    generic (
        Depth_g : positive := 4
    );
    port (
        -- Core clock side
        Clk          : in    std_logic;
        Rst          : in    std_logic;
        In_Data      : in    std_logic_vector(63 downto 0);
        In_Channel   : in    Char_t;
        In_Type      : in    Char_t;
        In_Delayed   : in    std_logic;
        In_Late      : in    std_logic;
        In_Valid     : in    std_logic;
        Ev_Discard   : out   std_logic;
        -- User clock side
        UserClk      : in    std_logic;
        UserRst      : in    std_logic;
        Out_Data     : out   std_logic_vector(63 downto 0);
        Out_Channel  : out   Char_t;
        Out_Type     : out   Char_t;
        Out_Delayed  : out   std_logic;
        Out_Late     : out   std_logic;
        Out_Valid    : out   std_logic;
        Out_Ready    : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_dl_bc_in is

    signal FifoIn  : std_logic_vector(BcWidth_c-1 downto 0);
    signal FifoOut : std_logic_vector(BcWidth_c-1 downto 0);
    signal InReady : std_logic;

begin

    FifoIn     <= In_Late & In_Delayed & In_Type & In_Channel & In_Data;
    Ev_Discard <= In_Valid and not InReady;

    i_fifo : entity olo.olo_ft_fifo_async
        generic map (
            Width_g => BcWidth_c,
            Depth_g => Depth_g
        )
        port map (
            In_Clk    => Clk,
            In_Rst    => Rst,
            In_Data   => FifoIn,
            In_Valid  => In_Valid,
            In_Ready  => InReady,
            Out_Clk   => UserClk,
            Out_Rst   => UserRst,
            Out_Data  => FifoOut,
            Out_Valid => Out_Valid,
            Out_Ready => Out_Ready
        );

    Out_Data    <= FifoOut(63 downto 0);
    Out_Channel <= FifoOut(71 downto 64);
    Out_Type    <= FifoOut(79 downto 72);
    Out_Delayed <= FifoOut(80);
    Out_Late    <= FifoOut(81);

end architecture;

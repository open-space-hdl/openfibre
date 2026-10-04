---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Receive frame buffer of the Data Link layer (DR-5): stores the data words of the current frame,
-- passes accepted frames to the input VC buffers and discards the others (ECSS 5.7.6.7a, b).
--
-- Documentation: hdl/ofb_dl/docs/architecture.md (section 3.8)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

library work;
    use work.ofb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_dl_rx_buf is
    generic (
        NumVc_g : positive range 1 to 32 := 8;
        Depth_g : positive               := 128
    );
    port (
        -- Control Ports
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        Ctrl_LinkReset : in    std_logic;
        -- Data frame words from the receive checks
        Fr_Data        : in    Word_t;
        Fr_K           : in    WordK_t;
        Fr_Vc          : in    std_logic_vector(4 downto 0);
        Fr_Valid       : in    std_logic;
        Fr_Commit      : in    std_logic;
        Fr_Drop        : in    std_logic;
        -- Words to the input VC buffers (no back-pressure: a full buffer is an overflow)
        Vc_Data        : out   Word_t;
        Vc_K           : out   WordK_t;
        Vc_Valid       : out   std_logic_vector(NumVc_g-1 downto 0);
        Vc_Ready       : in    std_logic_vector(NumVc_g-1 downto 0);
        -- Overflow of an input VC buffer (one cycle per VC), overflow of the frame buffer
        Ev_VcOverflow  : out   std_logic_vector(NumVc_g-1 downto 0);
        Ev_BufOverflow : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_dl_rx_buf is

    constant Width_c : positive := 32 + 4 + 5;

    -- Held last word of the current frame
    signal HeldData  : std_logic_vector(Width_c-1 downto 0);
    signal HeldValid : std_logic;

    signal FifoRst    : std_logic;
    signal InData     : std_logic_vector(Width_c-1 downto 0);
    signal InValid    : std_logic;
    signal InLast     : std_logic;
    signal InDrop     : std_logic;
    signal InReady    : std_logic;
    signal OutData    : std_logic_vector(Width_c-1 downto 0);
    signal OutValid   : std_logic;
    signal OutVc      : natural range 0 to 31;

begin

    -----------------------------------------------------------------------------------------------
    -- Hold the last word: written as a normal word with the next word, with Last on commit, with
    -- Last and Drop on drop
    -----------------------------------------------------------------------------------------------
    p_hold : process (Clk) is
    begin
        if rising_edge(Clk) then
            if Fr_Valid = '1' then
                HeldData  <= Fr_Vc & Fr_K & Fr_Data;
                HeldValid <= '1';
            elsif Fr_Commit = '1' or Fr_Drop = '1' then
                HeldValid <= '0';
            end if;
            if Rst = '1' or Ctrl_LinkReset = '1' then
                HeldValid <= '0';
            end if;
        end if;
    end process;

    InData  <= HeldData;
    InValid <= HeldValid and (Fr_Valid or Fr_Commit or Fr_Drop);
    InLast  <= Fr_Commit or Fr_Drop;
    InDrop  <= Fr_Drop;

    -- The frame buffer never back-pressures: a word that does not fit is an overflow
    Ev_BufOverflow <= InValid and not InReady;

    FifoRst <= Rst or Ctrl_LinkReset;

    i_fifo : entity olo.olo_ft_fifo_packet
        generic map (
            Width_g      => Width_c,
            Depth_g      => Depth_g,
            FeatureSet_g => "DROP_ONLY"
        )
        port map (
            Clk       => Clk,
            Rst       => FifoRst,
            In_Valid  => InValid,
            In_Ready  => InReady,
            In_Data   => InData,
            In_Last   => InLast,
            In_Drop   => InDrop,
            Out_Valid => OutValid,
            Out_Ready => '1',
            Out_Data  => OutData
        );

    -----------------------------------------------------------------------------------------------
    -- Distribution to the input VC buffers
    -----------------------------------------------------------------------------------------------
    OutVc   <= to_integer(unsigned(OutData(40 downto 36)));
    Vc_Data <= OutData(31 downto 0);
    Vc_K    <= OutData(35 downto 32);

    p_demux : process (all) is
    begin
        Vc_Valid      <= (others => '0');
        Ev_VcOverflow <= (others => '0');
        if OutValid = '1' then
            if OutVc < NumVc_g then
                Vc_Valid(OutVc) <= '1';
                if Vc_Ready(OutVc) = '0' then
                    Ev_VcOverflow(OutVc) <= '1';
                end if;
            end if;
        end if;
    end process;

end architecture;

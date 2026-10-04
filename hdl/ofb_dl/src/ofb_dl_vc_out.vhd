---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Output VC buffer of the Data Link layer (DT-1, DT-2): buffer from the user clock to the core
-- clock with the link reset rules of ECSS 5.7.2.2g, FCT credit counter (ECSS 5.7.3.1) and the data
-- segment ready indication.
--
-- Documentation: hdl/ofb_dl/docs/architecture.md (section 3.1)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_base_pkg_math.all;
    use olo.olo_base_pkg_logic.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_dl_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_dl_vc_out is
    generic (
        Depth_g       : positive := 128; -- Words, at least 64
        CreditWidth_g : positive := 12
    );
    port (
        -- User clock side
        UserClk           : in    std_logic;
        UserRst           : in    std_logic;
        In_Data           : in    Word_t;
        In_K              : in    WordK_t;
        In_Valid          : in    std_logic;
        In_Ready          : out   std_logic;
        -- Core clock side
        Clk               : in    std_logic;
        Rst               : in    std_logic;
        Ctrl_LinkReset    : in    std_logic;
        -- FCT received for this VC
        Fct_Valid         : in    std_logic;
        Fct_Mult          : in    std_logic_vector(2 downto 0);
        -- Data segment
        Seg_Ready         : out   std_logic;
        Seg_Words         : out   std_logic_vector(6 downto 0);
        Rd_Data           : out   Word_t;
        Rd_K              : out   WordK_t;
        Rd_Valid          : out   std_logic;
        Rd_Ready          : in    std_logic;
        -- Status
        Stat_HasCredit    : out   std_logic;
        Stat_Empty        : out   std_logic;
        Ev_CreditOverflow : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_dl_vc_out is

    constant LevelWidth_c : positive := log2ceil(Depth_g + 1);
    constant EopWidth_c   : positive := LevelWidth_c + 1;
    constant CreditMax_c  : natural  := 2**CreditWidth_g - 1;

    signal FifoIn     : std_logic_vector(35 downto 0);
    signal FifoOut    : std_logic_vector(35 downto 0);
    signal FifoInVld  : std_logic;
    signal FifoInRdy  : std_logic;
    signal FifoOutRst : std_logic;
    signal UsrRstOut  : std_logic;
    signal OutValid   : std_logic;
    signal OutFull    : std_logic;
    signal OutLevel   : std_logic_vector(LevelWidth_c-1 downto 0);

    -- User side
    signal LastEnd  : std_logic;
    signal Spill    : std_logic;
    signal EopWr    : unsigned(EopWidth_c-1 downto 0);
    signal EopWrGry : std_logic_vector(EopWidth_c-1 downto 0);

    -- Core side (the crossed count is delayed further, so that it never runs ahead of the level of the
    -- buffer: an EOP is only seen once the words before it are counted in the level)
    type EopDelay_t is array (0 to 3) of std_logic_vector(EopWidth_c-1 downto 0);

    signal EopSync : std_logic_vector(EopWidth_c-1 downto 0);
    signal EopDly  : EopDelay_t;
    signal EopRd   : unsigned(EopWidth_c-1 downto 0);
    signal Credit  : unsigned(CreditWidth_g-1 downto 0);

begin

    -----------------------------------------------------------------------------------------------
    -- User side: spill after link reset, count of the words with EOP or EEP
    -----------------------------------------------------------------------------------------------
    FifoIn    <= In_K & In_Data;
    FifoInVld <= In_Valid and not Spill;
    In_Ready  <= '1' when Spill = '1' else FifoInRdy;

    p_user : process (UserClk) is
    begin
        if rising_edge(UserClk) then
            if In_Valid = '1' and Spill = '1' then
                -- Discard up to and including the next word with EOP or EEP
                if wordHasEnd(In_Data, In_K) then
                    Spill   <= '0';
                    LastEnd <= '1';
                end if;
            elsif In_Valid = '1' and FifoInRdy = '1' then
                if wordLastIsEnd(In_Data, In_K) then
                    LastEnd <= '1';
                else
                    LastEnd <= '0';
                end if;
                if wordHasEnd(In_Data, In_K) then
                    EopWr <= EopWr + 1;
                end if;
            end if;
            -- Link reset (buffer reset seen on the user side)
            if UsrRstOut = '1' then
                EopWr <= (others => '0');
                if LastEnd = '0' then
                    Spill <= '1';
                end if;
            end if;
            if UserRst = '1' then
                LastEnd <= '1';
                Spill   <= '0';
                EopWr   <= (others => '0');
            end if;
        end if;
    end process;

    EopWrGry <= binaryToGray(std_logic_vector(EopWr));

    i_eop_cc : entity olo.olo_ft_cc_bits
        generic map (
            Width_g      => EopWidth_c,
            SyncStages_g => 4
        )
        port map (
            In_Clk   => UserClk,
            In_Rst   => UserRst,
            In_Data  => EopWrGry,
            Out_Clk  => Clk,
            Out_Rst  => Rst,
            Out_Data => EopSync
        );

    -----------------------------------------------------------------------------------------------
    -- Buffer
    -----------------------------------------------------------------------------------------------
    FifoOutRst <= Rst or Ctrl_LinkReset;

    i_fifo : entity olo.olo_ft_fifo_async
        generic map (
            Width_g         => 36,
            Depth_g         => Depth_g,
            ReadyRstState_g => '0'
        )
        port map (
            In_Clk    => UserClk,
            In_Rst    => UserRst,
            In_RstOut => UsrRstOut,
            In_Data   => FifoIn,
            In_Valid  => FifoInVld,
            In_Ready  => FifoInRdy,
            Out_Clk   => Clk,
            Out_Rst   => FifoOutRst,
            Out_Data  => FifoOut,
            Out_Valid => OutValid,
            Out_Ready => Rd_Ready,
            Out_Full  => OutFull,
            Out_Level => OutLevel
        );

    Rd_Data  <= FifoOut(31 downto 0);
    Rd_K     <= FifoOut(35 downto 32);
    Rd_Valid <= OutValid;

    -----------------------------------------------------------------------------------------------
    -- Core side: credit, end-of-packet count, segment
    -----------------------------------------------------------------------------------------------
    p_core : process (Clk) is
        variable Sum_v : unsigned(CreditWidth_g+1 downto 0);
    begin
        if rising_edge(Clk) then
            Ev_CreditOverflow <= '0';
            Sum_v             := resize(Credit, Sum_v'length);
            if Fct_Valid = '1' then
                Sum_v := Sum_v + shift_left(resize(unsigned(Fct_Mult), Sum_v'length) + 1, 6);
                if Sum_v > CreditMax_c then
                    Sum_v             := to_unsigned(CreditMax_c, Sum_v'length);
                    Ev_CreditOverflow <= '1';
                end if;
            end if;
            if OutValid = '1' and Rd_Ready = '1' then
                Sum_v := Sum_v - 1;
                if wordHasEnd(FifoOut(31 downto 0), FifoOut(35 downto 32)) then
                    EopRd <= EopRd + 1;
                end if;
            end if;
            Credit <= resize(Sum_v, CreditWidth_g);
            EopDly <= EopSync & EopDly(0 to EopDly'high-1);
            if Rst = '1' or Ctrl_LinkReset = '1' then
                Credit            <= (others => '0');
                EopRd             <= (others => '0');
                EopDly            <= (others => (others => '0'));
                Ev_CreditOverflow <= '0';
            end if;
        end if;
    end process;

    p_seg : process (all) is
        variable Level_v : natural;
        variable Words_v : natural;
        variable Eop_v   : boolean;
    begin
        Level_v := to_integer(unsigned(OutLevel));
        Eop_v   := unsigned(grayToBinary(EopDly(EopDly'high))) /= EopRd;
        Words_v := minimum(Level_v, MaxFrameWords_c);
        Words_v := minimum(Words_v, to_integer(Credit));
        if Credit > 0 and Level_v > 0 and (Level_v >= MaxFrameWords_c or Eop_v or OutFull = '1') then
            Seg_Ready <= '1';
        else
            Seg_Ready <= '0';
        end if;
        Seg_Words <= std_logic_vector(to_unsigned(Words_v, 7));
    end process;

    Stat_HasCredit <= '1' when Credit > 0 else '0';
    Stat_Empty     <= '1' when unsigned(OutLevel) = 0 else '0';

end architecture;

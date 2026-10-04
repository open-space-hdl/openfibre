---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Output VC buffer of the Data Link layer (DT-1, DT-2): buffer of beats (rows of NumLanes_g words)
-- from the user clock to the core clock with the link reset rules of ECSS 5.7.2.2g, FCT credit
-- counter in words (ECSS 5.7.3.1) and the data segment ready indication.
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
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_dl_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_dl_vc_out is
    generic (
        NumLanes_g    : positive range 1 to 4 := 1;
        Depth_g       : positive              := 128; -- Beats, at least 64 words
        CreditWidth_g : positive              := 12
    );
    port (
        -- User clock side
        UserClk           : in    std_logic;
        UserRst           : in    std_logic;
        In_Data           : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        In_K              : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        In_Valid          : in    std_logic;
        In_Ready          : out   std_logic;
        Cfg_Continuous    : in    std_logic                    := '0'; -- Continuous mode (UserClk)
        Ctrl_LaneActive   : in    std_logic                    := '1'; -- A lane is active (UserClk)
        EccInj_Valid      : in    std_logic                    := '0'; -- Error injection into the next beat (UserClk)
        EccInj_Double     : in    std_logic                    := '0';
        -- Core clock side
        Clk               : in    std_logic;
        Rst               : in    std_logic;
        Ctrl_LinkReset    : in    std_logic;
        Cfg_SegRows       : in    std_logic_vector(6 downto 0) := "1000000"; -- Rows per data segment
        -- FCT received for this VC
        Fct_Valid         : in    std_logic;
        Fct_Mult          : in    std_logic_vector(2 downto 0);
        -- Data segment
        Seg_Ready         : out   std_logic;
        Seg_Rows          : out   std_logic_vector(6 downto 0);
        Rd_Data           : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        Rd_K              : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        Rd_Valid          : out   std_logic;
        Rd_Ready          : in    std_logic;
        Rd_Flushed        : out   std_logic; -- The buffer was reset (link reset or continuous mode flush)
        -- Status
        Stat_HasCredit    : out   std_logic;
        Stat_Empty        : out   std_logic;
        Ev_CreditOverflow : out   std_logic;
        Ev_EccSec         : out   std_logic; -- Corrected single error in a beat read
        Ev_EccDed         : out   std_logic  -- Uncorrectable double error in a beat read
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_dl_vc_out is

    constant N_c          : positive := NumLanes_g;
    constant Width_c      : positive := 36 * N_c;
    constant LevelWidth_c : positive := log2ceil(Depth_g + 1);
    constant EopWidth_c   : positive := LevelWidth_c + 1;
    constant CreditMax_c  : natural  := 2**CreditWidth_g - 1;

    signal FifoIn     : std_logic_vector(Width_c-1 downto 0);
    signal FifoOut    : std_logic_vector(Width_c-1 downto 0);
    signal FifoInVld  : std_logic;
    signal FifoInRdy  : std_logic;
    signal FifoOutRst : std_logic;
    signal FifoInRst  : std_logic;
    signal UsrRstOut  : std_logic;
    signal OutRstOut  : std_logic;
    signal InLevel    : std_logic_vector(LevelWidth_c-1 downto 0);
    signal InEmpty    : std_logic;
    signal OutValid   : std_logic;
    signal OutFull    : std_logic;
    signal OutLevel   : std_logic_vector(LevelWidth_c-1 downto 0);
    signal FifoSec    : std_logic;
    signal FifoDed    : std_logic;

    -- User side
    signal LastEnd  : std_logic;
    signal Spill    : std_logic;
    signal CmFlush  : std_logic;
    signal CmWait   : std_logic;
    signal EepPend  : std_logic;
    signal EepOnly  : std_logic;
    signal EepWrite : std_logic;

    -- Beat after the spill: words of the discarded packet replaced by Fill words
    signal SpData   : std_logic_vector(32*N_c-1 downto 0);
    signal SpK      : std_logic_vector(4*N_c-1 downto 0);
    signal SpAll    : std_logic; -- All words of the beat are discarded
    signal SpEnd    : std_logic; -- The discarded packet ends in this beat
    signal BeatEnd  : std_logic; -- The beat contains an EOP or EEP
    signal BeatLast : std_logic; -- The last character of the beat is an EOP, EEP or Fill

    -- EEP followed by Fills
    signal BeatEep : std_logic_vector(Width_c-1 downto 0);

    signal EopWr    : unsigned(EopWidth_c-1 downto 0);
    signal EopWrGry : std_logic_vector(EopWidth_c-1 downto 0);

    -- Core side (the crossed count is delayed further, so that it never runs ahead of the level of the
    -- buffer: an EOP is only seen once the beats before it are counted in the level)
    type EopDelay_t is array (0 to 3) of std_logic_vector(EopWidth_c-1 downto 0);

    signal EopSync : std_logic_vector(EopWidth_c-1 downto 0);
    signal EopDly  : EopDelay_t;
    signal EopRd   : unsigned(EopWidth_c-1 downto 0);
    signal Credit  : unsigned(CreditWidth_g-1 downto 0);

begin

    -----------------------------------------------------------------------------------------------
    -- User side: spill after link reset, continuous mode, count of the beats with EOP or EEP
    -----------------------------------------------------------------------------------------------
    p_beat : process (all) is
        variable Spill_v : boolean;
        variable End_v   : boolean;
        variable Data_v  : Word_t;
        variable K_v     : WordK_t;
    begin
        Spill_v := Spill = '1';
        SpAll   <= '1';
        SpEnd   <= '0';
        BeatEnd <= '0';
        SpData  <= In_Data;
        SpK     <= In_K;
        BeatEep <= (others => '1');

        for i in 0 to N_c-1 loop
            Data_v := rowWord(In_Data, i);
            K_v    := rowKflags(In_K, i);
            End_v  := wordHasEnd(Data_v, K_v);
            if End_v and not Spill_v then
                BeatEnd <= '1';
            end if;
            if Spill_v then
                -- Discard up to and including the word with the next EOP or EEP (ECSS 5.7.10a.3)
                SpData(32*i+31 downto 32*i) <= WordFill_c;
                SpK(4*i+3 downto 4*i)       <= "1111";
                if End_v then
                    Spill_v := false;
                    SpEnd   <= '1';
                end if;
            else
                SpAll <= '0';
            end if;
            if i = 0 then
                BeatEep(31 downto 0) <= WordFill_c(31 downto 8) & CharEep_c;
            else
                BeatEep(32*i+31 downto 32*i) <= WordFill_c;
            end if;
        end loop;

        if wordLastIsEnd(rowWord(In_Data, N_c-1), rowKflags(In_K, N_c-1)) then
            BeatLast <= '1';
        else
            BeatLast <= '0';
        end if;
    end process;

    EepWrite  <= EepPend and not CmWait and FifoInRdy;
    FifoIn    <= BeatEep when EepWrite = '1' else SpK & SpData;
    FifoInVld <= EepWrite or (In_Valid and not SpAll and not CmWait and not EepPend);
    FifoInRst <= UserRst or CmFlush;

    p_ready : process (all) is
    begin
        if CmWait = '1' or (Spill = '1' and SpAll = '1') then
            -- Beats of a discarded packet, beats during a flush in continuous mode
            In_Ready <= '1';
        elsif EepPend = '1' then
            In_Ready <= '0';
        else
            In_Ready <= FifoInRdy;
        end if;
    end process;

    p_user : process (UserClk) is
        variable Full_v   : boolean;
        variable NoLane_v : boolean;
    begin
        if rising_edge(UserClk) then
            CmFlush <= '0';
            -- Continuous mode: flush when the buffer is about to be full or no lane is active
            Full_v   := In_Valid = '1' and unsigned(InLevel) >= Depth_g - 1;
            NoLane_v := Ctrl_LaneActive = '0' and InEmpty = '0' and EepOnly = '0';
            if Cfg_Continuous = '1' and CmWait = '0' and EepPend = '0' and (Full_v or NoLane_v) then
                CmFlush <= '1';
                CmWait  <= '1';
                EepPend <= '1';
                Spill   <= not LastEnd;
                LastEnd <= '1';
            elsif In_Valid = '1' and Spill = '1' and SpAll = '1' then
                -- The whole beat belongs to the discarded packet
                if SpEnd = '1' then
                    Spill   <= '0';
                    LastEnd <= '1';
                end if;
            elsif In_Valid = '1' and FifoInRdy = '1' and CmWait = '0' and EepPend = '0' then
                Spill   <= '0';
                EepOnly <= '0';
                LastEnd <= BeatLast;
                if BeatEnd = '1' then
                    EopWr <= EopWr + 1;
                end if;
            end if;
            -- End of the flush: buffer ready again, then the EEP
            if CmWait = '1' and CmFlush = '0' and UsrRstOut = '0' and FifoInRdy = '1' then
                CmWait <= '0';
            end if;
            if EepWrite = '1' then
                EepPend <= '0';
                EepOnly <= '1';
                EopWr   <= EopWr + 1;
            end if;
            -- Buffer reset seen on the user side (link reset or flush)
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
                CmFlush <= '0';
                CmWait  <= '0';
                EepPend <= '0';
                EepOnly <= '0';
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
            Width_g         => Width_c,
            Depth_g         => Depth_g,
            ReadyRstState_g => '0'
        )
        port map (
            In_Clk            => UserClk,
            In_Rst            => FifoInRst,
            In_RstOut         => UsrRstOut,
            In_Data           => FifoIn,
            In_Valid          => FifoInVld,
            In_Ready          => FifoInRdy,
            In_Empty          => InEmpty,
            In_Level          => InLevel,
            Out_Clk           => Clk,
            Out_Rst           => FifoOutRst,
            Out_RstOut        => OutRstOut,
            Out_Data          => FifoOut,
            Out_Valid         => OutValid,
            Out_Ready         => Rd_Ready,
            Out_Full          => OutFull,
            Out_Level         => OutLevel,
            Out_EccSec        => FifoSec,
            Out_EccDed        => FifoDed,
            In_ErrInj_BitFlip => eccInjPattern(eccCodewordWidth(Width_c), EccInj_Double),
            In_ErrInj_Valid   => EccInj_Valid
        );

    -- ECC events of the beats read (MG-3)
    Ev_EccSec <= FifoSec and OutValid and Rd_Ready;
    Ev_EccDed <= FifoDed and OutValid and Rd_Ready;

    Rd_Data    <= FifoOut(32*N_c-1 downto 0);
    Rd_K       <= FifoOut(36*N_c-1 downto 32*N_c);
    Rd_Valid   <= OutValid;
    Rd_Flushed <= OutRstOut;

    -----------------------------------------------------------------------------------------------
    -- Core side: credit in words, end-of-packet count, segment
    -----------------------------------------------------------------------------------------------
    p_core : process (Clk) is
        variable Sum_v : unsigned(CreditWidth_g+1 downto 0);
        variable End_v : boolean;
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
                -- One row of N words (ECSS 5.7.3.1f); the segment never exceeds the credit
                if Sum_v >= N_c then
                    Sum_v := Sum_v - N_c;
                end if;
                End_v := false;

                for i in 0 to N_c-1 loop
                    if wordHasEnd(rowWord(FifoOut, i), rowKflags(FifoOut(36*N_c-1 downto 32*N_c), i)) then
                        End_v := true;
                    end if;
                end loop;

                if End_v then
                    EopRd <= EopRd + 1;
                end if;
            end if;
            Credit <= resize(Sum_v, CreditWidth_g);
            EopDly <= EopSync & EopDly(0 to EopDly'high-1);
            -- Buffer reset seen on the read side (link reset or continuous mode flush)
            if OutRstOut = '1' then
                EopRd  <= (others => '0');
                EopDly <= (others => (others => '0'));
            end if;
            if Rst = '1' or Ctrl_LinkReset = '1' then
                Credit            <= (others => '0');
                EopRd             <= (others => '0');
                EopDly            <= (others => (others => '0'));
                Ev_CreditOverflow <= '0';
            end if;
        end if;
    end process;

    p_seg : process (all) is
        variable Level_v  : natural;
        variable Rows_v   : natural;
        variable Max_v    : natural;
        variable Credit_v : natural;
        variable Eop_v    : boolean;
    begin
        Level_v  := to_integer(unsigned(OutLevel));
        Max_v    := to_integer(unsigned(Cfg_SegRows));
        Credit_v := to_integer(Credit) / N_c;
        Eop_v    := unsigned(grayToBinary(EopDly(EopDly'high))) /= EopRd;
        Rows_v   := minimum(Level_v, Max_v);
        Rows_v   := minimum(Rows_v, Credit_v);
        if Credit_v > 0 and Level_v > 0 and (Level_v >= Max_v or Eop_v or OutFull = '1') then
            Seg_Ready <= '1';
        else
            Seg_Ready <= '0';
        end if;
        Seg_Rows <= std_logic_vector(to_unsigned(Rows_v, 7));
    end process;

    Stat_HasCredit <= '1' when Credit >= N_c else '0';
    Stat_Empty     <= '1' when unsigned(OutLevel) = 0 else '0';

end architecture;

---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Input VC buffer of the Data Link layer (DR-6): buffer from the core clock to the user clock that
-- stores the received words without gaps in NumLanes_g banks, beats of NumLanes_g words to the user
-- (a beat ends after an EOP or EEP), FCT requests for the space of the buffer (ECSS 5.7.3.2) and the
-- EEP after link reset (ECSS 5.7.2.3d). A beat with an uncorrectable error (DED) is replaced by an EEP
-- and the rest of its packet is discarded.
--
-- Documentation: hdl/ofb_dl/docs/architecture.md (section 3.9)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_base_pkg_attribute.all;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_dl_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_dl_vc_in is
    generic (
        NumLanes_g : positive range 1 to 4 := 1;
        Depth_g    : positive              := 256 -- Words, multiple of 64 x NumLanes_g
    );
    port (
        -- Core clock side
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        Ctrl_LinkReset : in    std_logic;
        Cfg_FctMult    : in    std_logic_vector(2 downto 0)            := "000"; -- M - 1
        In_Data        : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        In_K           : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        In_Mask        : in    std_logic_vector(NumLanes_g-1 downto 0) := (others => '1');
        In_Valid       : in    std_logic;
        In_Ready       : out   std_logic;
        EccInj_Valid   : in    std_logic                               := '0'; -- Error injection into the next word of bank 0
        EccInj_Double  : in    std_logic                               := '0';
        Fct_Req        : out   std_logic; -- At least one FCT is to be sent
        Fct_Ack        : in    std_logic; -- One FCT was taken for sending
        -- User clock side
        UserClk        : in    std_logic;
        UserRst        : in    std_logic;
        Out_Data       : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        Out_K          : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        Out_Valid      : out   std_logic;
        Out_Ready      : in    std_logic;
        Ev_EccSec      : out   std_logic; -- Corrected single error in a word read (UserClk)
        Ev_EccDed      : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_dl_vc_in is

    constant N_c        : positive := NumLanes_g;
    constant Blocks_c   : positive := Depth_g / MaxFrameWords_c;
    constant GuardCyc_c : positive := 16;

    -- Bank index (at least one bit wide, the value stays below N_c)
    subtype Bank_t is natural range 0 to 3;

    type BankData_t is array (0 to N_c-1) of std_logic_vector(35 downto 0);
    type BankStage_t is array (0 to N_c-1) of std_logic_vector(38 downto 0);
    type Words_t is array (0 to N_c-1) of Word_t;
    type Ks_t is array (0 to N_c-1) of WordK_t;

    signal FifoRst   : std_logic;
    signal BankIn    : BankData_t;
    signal BankInVld : std_logic_vector(N_c-1 downto 0);
    signal BankInRdy : std_logic_vector(N_c-1 downto 0);
    signal FifoOut   : BankData_t;
    signal FifoVld   : std_logic_vector(N_c-1 downto 0);
    signal FifoRdy   : std_logic_vector(N_c-1 downto 0);
    signal FifoSec   : std_logic_vector(N_c-1 downto 0);
    signal FifoDed   : std_logic_vector(N_c-1 downto 0);
    signal StageIn   : BankStage_t;
    signal StageOut  : BankStage_t;
    signal BankOut   : BankData_t;
    signal BankVld   : std_logic_vector(N_c-1 downto 0);
    signal BankRdy   : std_logic_vector(N_c-1 downto 0);
    signal UsrRstIn  : std_logic_vector(N_c-1 downto 0);
    signal BankDed   : std_logic_vector(N_c-1 downto 0);
    signal BankEnd   : std_logic_vector(N_c-1 downto 0); -- The word holds an EOP or EEP
    signal BankLEnd  : std_logic_vector(N_c-1 downto 0); -- Character 3 is an EOP, EEP or Fill
    signal FifoEnd   : std_logic_vector(N_c-1 downto 0);
    signal FifoLEnd  : std_logic_vector(N_c-1 downto 0);
    signal StageRst  : std_logic_vector(N_c-1 downto 0);
    signal BankInj   : std_logic_vector(N_c-1 downto 0);

    -- Core side
    signal WrBank  : Bank_t;
    signal Pending : natural range 0 to Blocks_c;
    signal Guard   : natural range 0 to GuardCyc_c;
    signal BlkCore : std_logic;

    -- User side
    signal RdSel     : std_logic_vector(N_c-1 downto 0); -- One-hot: bank of the first word of the next beat
    signal LastEnd   : std_logic;
    signal Inject    : std_logic;
    signal RdCnt     : natural range 0 to MaxFrameWords_c-1;
    signal BlkUser   : std_logic;
    signal BankAvl   : std_logic_vector(N_c-1 downto 0); -- The stage of the bank holds a word
    signal PosVld    : std_logic_vector(N_c-1 downto 0); -- Per beat position: a word is available
    signal PosEnd    : std_logic_vector(N_c-1 downto 0); -- Per beat position: the word holds an EOP or EEP
    signal PosLEnd   : std_logic_vector(N_c-1 downto 0); -- Per beat position: character 3 is an EOP, EEP or Fill
    signal PosDed    : std_logic_vector(N_c-1 downto 0); -- Per beat position: uncorrectable error
    signal PosData   : std_logic_vector(32*N_c-1 downto 0);
    signal PosK      : std_logic_vector(4*N_c-1 downto 0);
    signal Take      : std_logic_vector(N_c-1 downto 0); -- Beat positions whose word belongs to the beat
    signal TakeLast  : std_logic_vector(N_c-1 downto 0); -- One-hot: last position of the beat
    signal TakeCnt   : natural range 0 to N_c; -- Number of words of the beat
    signal Go        : std_logic; -- The beat is read (to the Network layer or discarded)
    signal BeatData  : std_logic_vector(32*N_c-1 downto 0);
    signal BeatK     : std_logic_vector(4*N_c-1 downto 0);
    signal BeatValid : std_logic;
    signal BeatLast  : std_logic;
    signal BeatEnd   : std_logic; -- The beat ends with an EOP or EEP
    signal BeatDed   : std_logic; -- A word of the beat has an uncorrectable error
    signal Discard   : std_logic; -- Rest of a packet after a DED: words read and discarded

    -- The beat decision stays separate from the next-state logic of the read position and the counters (timing)
    attribute keep of Take          : signal is Keep_SuppressChanges_c;
    attribute keep of BeatValid     : signal is Keep_SuppressChanges_c;
    attribute keep of BankRdy       : signal is Keep_SuppressChanges_c;
    attribute syn_keep of Take      : signal is SynKeep_SuppressChanges_c;
    attribute syn_keep of BeatValid : signal is SynKeep_SuppressChanges_c;
    attribute syn_keep of BankRdy   : signal is SynKeep_SuppressChanges_c;

begin

    assert Depth_g mod (MaxFrameWords_c * N_c) = 0
        report "ofb_dl_vc_in: Depth_g must be a multiple of 64 x NumLanes_g"
        severity failure;

    -----------------------------------------------------------------------------------------------
    -- Core side: the words of a row go to the banks in turn, starting at the next bank
    -----------------------------------------------------------------------------------------------
    FifoRst <= Rst or Ctrl_LinkReset;

    p_write : process (all) is
        variable Words_v : Words_t;
        variable Ks_v    : Ks_t;
        variable Cnt_v   : natural range 0 to N_c;
        variable Idx_v   : natural;
        variable Rdy_v   : std_logic;
    begin
        -- Words of the row from word 0 upwards
        Cnt_v   := 0;
        Words_v := (others => (others => '0'));
        Ks_v    := (others => (others => '0'));

        for i in 0 to N_c-1 loop
            if In_Mask(i) = '1' then
                Words_v(Cnt_v) := rowWord(In_Data, i);
                Ks_v(Cnt_v)    := rowKflags(In_K, i);
                Cnt_v          := Cnt_v + 1;
            end if;
        end loop;

        Rdy_v := '1';

        for b in 0 to N_c-1 loop
            Idx_v        := (b + N_c - WrBank) mod N_c;
            BankIn(b)    <= Ks_v(Idx_v) & Words_v(Idx_v);
            BankInVld(b) <= '0';
            if Idx_v < Cnt_v then
                BankInVld(b) <= In_Valid;
                if BankInRdy(b) = '0' then
                    Rdy_v := '0';
                end if;
            end if;
        end loop;

        In_Ready <= Rdy_v;
    end process;

    p_wr_bank : process (Clk) is
    begin
        if rising_edge(Clk) then
            if In_Valid = '1' then
                WrBank <= (WrBank + countMask(In_Mask)) mod N_c;
            end if;
            if Rst = '1' or Ctrl_LinkReset = '1' then
                WrBank <= 0;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Banks
    -----------------------------------------------------------------------------------------------
    g_bank : for b in 0 to N_c-1 generate

        -- Injection into bank 0 only (b is a constant: one branch is unreachable)
        -- coverage off
        BankInj(b) <= EccInj_Valid when b = 0 else '0';
        -- coverage on

        i_fifo : entity olo.olo_ft_fifo_async
            generic map (
                Width_g => 36,
                Depth_g => Depth_g / N_c
            )
            port map (
                In_Clk            => Clk,
                In_Rst            => FifoRst,
                In_Data           => BankIn(b),
                In_Valid          => BankInVld(b),
                In_Ready          => BankInRdy(b),
                Out_Clk           => UserClk,
                Out_Rst           => UserRst,
                Out_RstOut        => UsrRstIn(b),
                Out_Data          => FifoOut(b),
                Out_Valid         => FifoVld(b),
                Out_Ready         => FifoRdy(b),
                Out_EccSec        => FifoSec(b),
                Out_EccDed        => FifoDed(b),
                In_ErrInj_BitFlip => eccInjPattern(eccCodewordWidth(36), EccInj_Double),
                In_ErrInj_Valid   => BankInj(b)
            );

        -- Register stage after the bank: the beat logic below works on registers, and the read of the
        -- bank RAM does not depend on the words of the other banks (timing). The end flags of the word are
        -- decoded before the stage, so that the beat logic works on single bits (timing). Reset with the buffer
        -- and with the user reset, which is asserted from the start (the buffer reset needs clock edges)
        FifoEnd(b)  <= '1' when wordHasEnd(FifoOut(b)(31 downto 0), FifoOut(b)(35 downto 32)) else '0';
        FifoLEnd(b) <= '1' when wordLastIsEnd(FifoOut(b)(31 downto 0), FifoOut(b)(35 downto 32)) else '0';
        StageIn(b)  <= FifoLEnd(b) & FifoEnd(b) & FifoDed(b) & FifoOut(b);
        StageRst(b) <= UsrRstIn(b) or UserRst;

        i_stage : entity olo.olo_base_pl_stage
            generic map (
                Width_g => 39
            )
            port map (
                Clk       => UserClk,
                Rst       => StageRst(b),
                In_Valid  => FifoVld(b),
                In_Ready  => FifoRdy(b),
                In_Data   => StageIn(b),
                Out_Valid => BankVld(b),
                Out_Ready => BankRdy(b),
                Out_Data  => StageOut(b)
            );

        BankOut(b)  <= StageOut(b)(35 downto 0);
        BankDed(b)  <= StageOut(b)(36);
        BankEnd(b)  <= StageOut(b)(37);
        BankLEnd(b) <= StageOut(b)(38);
        -- Not '1' instead of '0': a stage without its first reset (simulation) holds no word
        BankAvl(b) <= '1' when BankVld(b) = '1' else '0';

    end generate;

    -----------------------------------------------------------------------------------------------
    -- User side: beats of N words from the banks; a beat ends after an EOP or EEP (Fill words up to
    -- N words); EEP after link reset; count of the words read. Beat position i holds the word of the
    -- bank i places after RdSel. The read position is one-hot and all decisions are AND-OR terms of
    -- flag bits without arithmetic, so that the beat logic is flat (timing of the user clock)
    -----------------------------------------------------------------------------------------------
    p_pos : process (all) is
        variable Vld_v  : std_logic_vector(N_c-1 downto 0);
        variable End_v  : std_logic_vector(N_c-1 downto 0);
        variable LEnd_v : std_logic_vector(N_c-1 downto 0);
        variable Ded_v  : std_logic_vector(N_c-1 downto 0);
        variable Data_v : std_logic_vector(32*N_c-1 downto 0);
        variable K_v    : std_logic_vector(4*N_c-1 downto 0);
        variable Bank_v : Bank_t;
    begin
        Vld_v  := (others => '0');
        End_v  := (others => '0');
        LEnd_v := (others => '0');
        Ded_v  := (others => '0');
        Data_v := (others => '0');
        K_v    := (others => '0');

        for i in 0 to N_c-1 loop

            for s in 0 to N_c-1 loop
                -- Bank at position i when the beat starts at bank s (constant)
                Bank_v                      := (s + i) mod N_c;
                Vld_v(i)                    := Vld_v(i) or (RdSel(s) and BankAvl(Bank_v));
                End_v(i)                    := End_v(i) or (RdSel(s) and BankEnd(Bank_v));
                LEnd_v(i)                   := LEnd_v(i) or (RdSel(s) and BankLEnd(Bank_v));
                Ded_v(i)                    := Ded_v(i) or (RdSel(s) and BankDed(Bank_v));
                Data_v(32*i+31 downto 32*i) := Data_v(32*i+31 downto 32*i) or
                                               (BankOut(Bank_v)(31 downto 0) and (31 downto 0 => RdSel(s)));
                K_v(4*i+3 downto 4*i)       := K_v(4*i+3 downto 4*i) or
                                               (BankOut(Bank_v)(35 downto 32) and (3 downto 0 => RdSel(s)));
            end loop;

        end loop;

        PosVld  <= Vld_v;
        PosEnd  <= End_v;
        PosLEnd <= LEnd_v;
        PosDed  <= Ded_v;
        PosData <= Data_v;
        PosK    <= K_v;
    end process;

    -- Position i belongs to the beat when the words of positions 0 to i are available and none of
    -- positions 0 to i-1 ends a packet
    p_take : process (all) is
        variable Take_v : std_logic;
    begin

        for i in 0 to N_c-1 loop
            Take_v := '1';

            for j in 0 to i loop
                Take_v := Take_v and PosVld(j);
            end loop;

            for j in 0 to i-1 loop
                Take_v := Take_v and not PosEnd(j);
            end loop;

            Take(i) <= Take_v;
        end loop;

    end process;

    p_beat : process (all) is
        variable TakeX_v : std_logic_vector(N_c downto 0);
        variable End_v   : std_logic;
        variable Ded_v   : std_logic;
        variable Last_v  : std_logic;
    begin
        -- One position more: the position after the last one is not taken
        TakeX_v := '0' & Take;
        End_v   := '0';
        Ded_v   := '0';
        Last_v  := '0';

        for i in 0 to N_c-1 loop
            End_v := End_v or (Take(i) and PosEnd(i));
            Ded_v := Ded_v or (Take(i) and PosDed(i));
            -- Last character read: of the last word of the beat
            Last_v      := Last_v or (Take(i) and not TakeX_v(i+1) and PosLEnd(i));
            TakeLast(i) <= Take(i) and not TakeX_v(i+1);
            -- Positions without a word of the beat are Fill words
            BeatData(32*i+31 downto 32*i) <= (PosData(32*i+31 downto 32*i) and (31 downto 0 => Take(i))) or
                                             (WordFill_c and (31 downto 0 => not Take(i)));
            BeatK(4*i+3 downto 4*i)       <= PosK(4*i+3 downto 4*i) or (3 downto 0 => not Take(i));
        end loop;

        BeatEnd   <= End_v;
        BeatDed   <= Ded_v;
        BeatLast  <= Last_v;
        BeatValid <= Take(N_c-1) or End_v;
    end process;

    -- The beat is read: to the Network layer or discarded
    Go <= BeatValid and (Out_Ready or Discard) and not Inject;

    -- Banks read with the beat: bank b is at position i when RdSel marks the bank i places before b
    p_rd : process (all) is
        variable Sel_v : std_logic;
    begin

        for b in 0 to N_c-1 loop
            Sel_v := '0';

            for i in 0 to N_c-1 loop
                Sel_v := Sel_v or (RdSel((b - i + N_c) mod N_c) and Take(i));
            end loop;

            BankRdy(b) <= Go and Sel_v;
        end loop;

    end process;

    -- Number of words of the beat (the positions taken are a prefix)
    p_cnt : process (all) is
        variable Cnt_v : natural range 0 to N_c;
    begin
        Cnt_v := 0;

        for i in 0 to N_c-1 loop
            if Take(i) = '1' then
                Cnt_v := i + 1;
            end if;
        end loop;

        TakeCnt <= Cnt_v;
    end process;

    p_user : process (UserClk) is
        variable Cnt_v : natural;
        variable Sel_v : std_logic_vector(N_c-1 downto 0);
    begin
        if rising_edge(UserClk) then
            BlkUser <= '0';
            if Inject = '1' then
                if Out_Ready = '1' then
                    Inject  <= '0';
                    LastEnd <= '1';
                end if;
            elsif Go = '1' then
                LastEnd <= BeatLast;
                if Discard = '1' then
                    -- Rest of a packet with an uncorrectable error: discarded up to its end
                    LastEnd <= '1';
                    if BeatEnd = '1' then
                        Discard <= '0';
                    end if;
                elsif BeatDed = '1' then
                    -- The EEP was sent instead of the beat
                    LastEnd <= '1';
                    if BeatEnd = '0' then
                        Discard <= '1';
                    end if;
                end if;
                -- Next beat from the bank after the last word of this beat
                Sel_v := (others => '0');

                for b in 0 to N_c-1 loop

                    for i in 0 to N_c-1 loop
                        Sel_v(b) := Sel_v(b) or (TakeLast(i) and RdSel((b - i - 1 + N_c) mod N_c));
                    end loop;

                end loop;

                RdSel <= Sel_v;
                Cnt_v := RdCnt + TakeCnt;
                if Cnt_v >= MaxFrameWords_c then
                    RdCnt   <= Cnt_v - MaxFrameWords_c;
                    BlkUser <= '1';
                else
                    RdCnt <= Cnt_v;
                end if;
            end if;
            -- Link reset (buffer reset seen on the user side)
            if UsrRstIn(0) = '1' then
                RdCnt   <= 0;
                RdSel   <= (0 => '1', others => '0');
                Discard <= '0';
                if LastEnd = '0' then
                    -- One EEP, also when the reset lasts several cycles
                    Inject  <= '1';
                    LastEnd <= '1';
                end if;
            end if;
            if UserRst = '1' then
                Discard <= '0';
                LastEnd <= '1';
                Inject  <= '0';
                RdCnt   <= 0;
                RdSel   <= (0 => '1', others => '0');
                BlkUser <= '0';
            end if;
        end if;
    end process;

    p_out : process (all) is
    begin
        Out_Data  <= BeatData;
        Out_K     <= BeatK;
        Out_Valid <= BeatValid;
        if Discard = '1' then
            Out_Valid <= '0';
        elsif BeatDed = '1' then
            -- Beat with an uncorrectable error: EEP followed by Fills (DL-ED-02)
            Out_K <= (others => '1');

            for i in 0 to N_c-1 loop
                if i = 0 then
                    Out_Data(31 downto 0) <= WordFill_c(31 downto 8) & CharEep_c;
                else
                    Out_Data(32*i+31 downto 32*i) <= WordFill_c;
                end if;
            end loop;

        end if;
        if Inject = '1' then
            -- EEP followed by Fills
            Out_K     <= (others => '1');
            Out_Valid <= '1';

            for i in 0 to N_c-1 loop
                if i = 0 then
                    Out_Data(31 downto 0) <= WordFill_c(31 downto 8) & CharEep_c;
                else
                    Out_Data(32*i+31 downto 32*i) <= WordFill_c;
                end if;
            end loop;

        end if;
    end process;

    -- ECC events of the words read from the banks (MG-3)
    Ev_EccSec <= '1' when (FifoSec and FifoVld and FifoRdy) /= (FifoSec'range => '0') else '0';
    Ev_EccDed <= '1' when (FifoDed and FifoVld and FifoRdy) /= (FifoDed'range => '0') else '0';

    -- One-cycle pulse per 64 words read
    i_blk_cc : entity work.ofb_cc_pulse
        port map (
            In_Clk       => UserClk,
            In_Rst       => UserRst,
            In_Pulse(0)  => BlkUser,
            Out_Clk      => Clk,
            Out_Rst      => Rst,
            Out_Pulse(0) => BlkCore
        );

    -----------------------------------------------------------------------------------------------
    -- Core side: FCTs to send, each for M blocks of 64 words
    -----------------------------------------------------------------------------------------------
    p_fct : process (Clk) is
        variable Inc_v  : boolean;
        variable Dec_v  : boolean;
        variable Mult_v : natural range 1 to 8;
    begin
        if rising_edge(Clk) then
            Mult_v := to_integer(unsigned(Cfg_FctMult)) + 1;
            Inc_v  := BlkCore = '1' and Guard = 0;
            Dec_v  := Fct_Ack = '1' and Pending >= Mult_v;
            if Inc_v and not Dec_v and Pending < Blocks_c then
                Pending <= Pending + 1;
            elsif Dec_v and not Inc_v then
                Pending <= Pending - Mult_v;
            elsif Dec_v and Inc_v then
                Pending <= Pending + 1 - Mult_v;
            end if;
            if Guard > 0 then
                Guard <= Guard - 1;
            end if;
            -- After link reset the whole buffer is free; pulses of words read before are ignored
            if Rst = '1' or Ctrl_LinkReset = '1' then
                Pending <= Blocks_c;
                Guard   <= GuardCyc_c;
            end if;
        end if;
    end process;

    Fct_Req <= '1' when Pending >= to_integer(unsigned(Cfg_FctMult)) + 1 else '0';

end architecture;

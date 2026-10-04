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
-- EEP after link reset (ECSS 5.7.2.3d).
--
-- Documentation: hdl/ofb_dl/docs/architecture.md (section 3.9)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

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
        Fct_Req        : out   std_logic; -- At least one FCT is to be sent
        Fct_Ack        : in    std_logic; -- One FCT was taken for sending
        -- User clock side
        UserClk        : in    std_logic;
        UserRst        : in    std_logic;
        Out_Data       : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        Out_K          : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        Out_Valid      : out   std_logic;
        Out_Ready      : in    std_logic
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
    type Words_t is array (0 to N_c-1) of Word_t;
    type Ks_t is array (0 to N_c-1) of WordK_t;

    signal FifoRst   : std_logic;
    signal BankIn    : BankData_t;
    signal BankInVld : std_logic_vector(N_c-1 downto 0);
    signal BankInRdy : std_logic_vector(N_c-1 downto 0);
    signal BankOut   : BankData_t;
    signal BankVld   : std_logic_vector(N_c-1 downto 0);
    signal BankRdy   : std_logic_vector(N_c-1 downto 0);
    signal UsrRstIn  : std_logic_vector(N_c-1 downto 0);

    -- Core side
    signal WrBank  : Bank_t;
    signal Pending : natural range 0 to Blocks_c;
    signal Guard   : natural range 0 to GuardCyc_c;
    signal BlkCore : std_logic;

    -- User side
    signal RdBank    : Bank_t;
    signal LastEnd   : std_logic;
    signal Inject    : std_logic;
    signal RdCnt     : natural range 0 to MaxFrameWords_c-1;
    signal BlkUser   : std_logic;
    signal BeatData  : std_logic_vector(32*N_c-1 downto 0);
    signal BeatK     : std_logic_vector(4*N_c-1 downto 0);
    signal BeatValid : std_logic;
    signal BeatCnt   : natural range 0 to N_c;
    signal BeatLast  : std_logic;

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

        i_fifo : entity olo.olo_ft_fifo_async
            generic map (
                Width_g => 36,
                Depth_g => Depth_g / N_c
            )
            port map (
                In_Clk     => Clk,
                In_Rst     => FifoRst,
                In_Data    => BankIn(b),
                In_Valid   => BankInVld(b),
                In_Ready   => BankInRdy(b),
                Out_Clk    => UserClk,
                Out_Rst    => UserRst,
                Out_RstOut => UsrRstIn(b),
                Out_Data   => BankOut(b),
                Out_Valid  => BankVld(b),
                Out_Ready  => BankRdy(b)
            );

    end generate;

    -----------------------------------------------------------------------------------------------
    -- User side: beats of N words from the banks; a beat ends after an EOP or EEP (Fill words up to
    -- N words); EEP after link reset; count of the words read
    -----------------------------------------------------------------------------------------------
    p_beat : process (all) is
        variable Avail_v : boolean;
        variable Ended_v : boolean;
        variable Cnt_v   : natural range 0 to N_c;
        variable Bank_v  : Bank_t;
        variable Word_v  : Word_t;
        variable K_v     : WordK_t;
    begin
        BeatData <= (others => '1');
        BeatK    <= (others => '1');
        Avail_v  := true;
        Ended_v  := false;
        Cnt_v    := 0;

        for i in 0 to N_c-1 loop
            BeatData(32*i+31 downto 32*i) <= WordFill_c;
            Bank_v                        := (RdBank + i) mod N_c;
            if BankVld(Bank_v) = '0' then
                Avail_v := false;
            end if;
            if Avail_v and not Ended_v then
                Word_v                        := BankOut(Bank_v)(31 downto 0);
                K_v                           := BankOut(Bank_v)(35 downto 32);
                BeatData(32*i+31 downto 32*i) <= Word_v;
                BeatK(4*i+3 downto 4*i)       <= K_v;
                Cnt_v                         := i + 1;
                if wordHasEnd(Word_v, K_v) then
                    Ended_v := true;
                end if;
            end if;
        end loop;

        BeatCnt   <= Cnt_v;
        BeatValid <= '0';
        if Ended_v or Cnt_v = N_c then
            BeatValid <= '1';
        end if;
        -- Last character read: of the last word of the beat taken from the banks
        BeatLast <= '0';
        if Cnt_v > 0 then
            Bank_v := (RdBank + Cnt_v - 1) mod N_c;
            if wordLastIsEnd(BankOut(Bank_v)(31 downto 0), BankOut(Bank_v)(35 downto 32)) then
                BeatLast <= '1';
            end if;
        end if;
    end process;

    -- Banks read with the beat
    p_rd : process (all) is
        variable Idx_v : natural;
    begin

        for b in 0 to N_c-1 loop
            Idx_v      := (b + N_c - RdBank) mod N_c;
            BankRdy(b) <= '0';
            if Out_Ready = '1' and Inject = '0' and BeatValid = '1' and Idx_v < BeatCnt then
                BankRdy(b) <= '1';
            end if;
        end loop;

    end process;

    p_user : process (UserClk) is
        variable Cnt_v : natural;
    begin
        if rising_edge(UserClk) then
            BlkUser <= '0';
            if Inject = '1' then
                if Out_Ready = '1' then
                    Inject  <= '0';
                    LastEnd <= '1';
                end if;
            elsif BeatValid = '1' and Out_Ready = '1' then
                LastEnd <= BeatLast;
                RdBank  <= (RdBank + BeatCnt) mod N_c;
                Cnt_v   := RdCnt + BeatCnt;
                if Cnt_v >= MaxFrameWords_c then
                    RdCnt   <= Cnt_v - MaxFrameWords_c;
                    BlkUser <= '1';
                else
                    RdCnt <= Cnt_v;
                end if;
            end if;
            -- Link reset (buffer reset seen on the user side)
            if UsrRstIn(0) = '1' then
                RdCnt  <= 0;
                RdBank <= 0;
                if LastEnd = '0' then
                    -- One EEP, also when the reset lasts several cycles
                    Inject  <= '1';
                    LastEnd <= '1';
                end if;
            end if;
            if UserRst = '1' then
                LastEnd <= '1';
                Inject  <= '0';
                RdCnt   <= 0;
                RdBank  <= 0;
                BlkUser <= '0';
            end if;
        end if;
    end process;

    p_out : process (all) is
    begin
        Out_Data  <= BeatData;
        Out_K     <= BeatK;
        Out_Valid <= BeatValid;
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

    -- One-cycle pulse per 64 words read (olo_ft_cc_pulse alone stretches the pulse to 2 cycles)
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

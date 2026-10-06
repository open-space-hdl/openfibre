---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Lane receiver (LN-3): word synchronisation, receive synchronisation state machine, RXERR words,
-- detection of the lane control words, RXERR word counter and filtering of the words passed to
-- the Multi-Lane layer.
--
-- Documentation: hdl/ofb_lane/docs/architecture.md (section 2.3)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.ofb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_lane_rx is
    generic (
        RxErrLeakWords_g : positive := 16384
    );
    port (
        -- Control Ports
        Clk                 : in    std_logic;
        Rst                 : in    std_logic;
        -- Control from the lane initialisation state machine
        Ctrl_SyncReset      : in    std_logic; -- LaneReset or receiver / CDR disabled: LostSync
        Ctrl_Active         : in    std_logic; -- Lane in the Active state
        Ctrl_RxErrClear     : in    std_logic; -- Clear the RXERR word counter
        -- Decoded symbols from the Physical adapter
        In_Data             : in    Word_t;
        In_K                : in    WordK_t;
        In_CodeErr          : in    WordK_t;
        In_DispErr          : in    WordK_t;
        In_Valid            : in    std_logic;
        -- Words to the Multi-Lane layer
        Out_Data            : out   Word_t;
        Out_K               : out   WordK_t;
        Out_Valid           : out   std_logic;
        -- Events of the received words (one cycle, aligned with each other)
        Ev_Word             : out   std_logic;
        Ev_RxErr            : out   std_logic;
        Ev_Init1            : out   std_logic;
        Ev_Init2            : out   std_logic;
        Ev_InvInit1         : out   std_logic;
        Ev_InvInit2         : out   std_logic;
        Ev_Init3            : out   std_logic;
        Ev_Standby          : out   std_logic;
        Ev_LostSignal       : out   std_logic;
        Ev_Comma            : out   std_logic;
        Ev_Skip             : out   std_logic;
        Ev_Param            : out   Char_t;    -- Fourth character of INIT3, STANDBY, LOST_SIGNAL
        -- RXERR word counter
        Stat_RxErrCount     : out   Char_t;
        Stat_RxErrOverflow  : out   std_logic; -- Counter reached 255 (level until cleared)
        Ev_RxErrOverflow    : out   std_logic  -- Counter reached 255 (one cycle)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_lane_rx is

    type SyncFsm_t is (LostSync_s, CheckSync_s, Ready_s);

    type Chars_t is array (0 to 3) of Char_t;

    type TwoProcess_r is record
        -- Stage 1: input register, symbols with an error replaced by K0.0
        S1Data     : Word_t;
        S1K        : WordK_t;
        S1Err      : WordK_t;
        S1Valid    : std_logic;
        -- Stage 2: word alignment
        PrevData   : Word_t;
        PrevK      : WordK_t;
        PrevErr    : WordK_t;
        Offset     : natural range 0 to 3;
        S2Data     : Word_t;
        S2K        : WordK_t;
        S2Err      : std_logic;
        S2Realign  : std_logic;
        S2Valid    : std_logic;
        -- Stage 3: receive synchronisation, error rule (word held for one word)
        SyncState  : SyncFsm_t;
        ErrCnt     : natural range 0 to 5;
        HeldData   : Word_t;
        HeldK      : WordK_t;
        HeldRxErr  : std_logic;
        HeldValid  : std_logic;
        S3Data     : Word_t;
        S3K        : WordK_t;
        S3RxErr    : std_logic;
        S3Valid    : std_logic;
        -- Stage 4: decode, events, output
        OutData    : Word_t;
        OutK       : WordK_t;
        OutValid   : std_logic;
        ActiveLast : std_logic;
        EvWord     : std_logic;
        EvRxErr    : std_logic;
        EvInit1    : std_logic;
        EvInit2    : std_logic;
        EvInvInit1 : std_logic;
        EvInvInit2 : std_logic;
        EvInit3    : std_logic;
        EvStandby  : std_logic;
        EvLostSig  : std_logic;
        EvComma    : std_logic;
        EvSkip     : std_logic;
        EvParam    : Char_t;
        -- RXERR word counter
        ErrCount   : unsigned(7 downto 0);
        Overflow   : std_logic;
        EvOverflow : std_logic;
        LeakCnt    : natural range 0 to RxErrLeakWords_g-1;
    end record;

    signal r, r_next : TwoProcess_r;

    function toChars (data : Word_t) return Chars_t is
        variable Chars_v : Chars_t;
    begin

        for i in 0 to 3 loop
            Chars_v(i) := data(8*i+7 downto 8*i);
        end loop;

        return Chars_v;
    end function;

begin

    -----------------------------------------------------------------------------------------------
    -- Combinational Process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v           : TwoProcess_r;
        variable Cur_v       : Chars_t;
        variable Prev_v      : Chars_t;
        variable CommaPos_v  : integer range -1 to 3;
        variable Idx_v       : natural range 0 to 6;
        variable Bad_v       : boolean;
        variable WordData_v  : Word_t;
        variable WordRxErr_v : std_logic;
        variable IsLane_v    : boolean;
        variable ToRxErr_v   : boolean;
        variable Inc_v       : boolean;
        variable Dec_v       : boolean;
    begin
        -- Hold variables stable
        v := r;

        -------------------------------------------------------------------------------------------
        -- Stage 1: input register (ECSS 5.5.7j, k: a symbol in error becomes Rx Error, K0.0)
        -------------------------------------------------------------------------------------------
        v.S1Valid := In_Valid;
        v.S1Data  := In_Data;
        v.S1K     := In_K;
        v.S1Err   := In_CodeErr or In_DispErr;

        for i in 0 to 3 loop
            if (In_CodeErr(i) or In_DispErr(i)) = '1' then
                v.S1Data(8*i+7 downto 8*i) := K0_0_c;
                v.S1K(i)                   := '1';
            end if;
        end loop;

        -------------------------------------------------------------------------------------------
        -- Stage 2: word alignment (ECSS 5.5.7)
        -------------------------------------------------------------------------------------------
        v.S2Valid := '0';
        if r.S1Valid = '1' then
            Cur_v  := toChars(r.S1Data);
            Prev_v := toChars(r.PrevData);
            -- Lowest position of a comma (K28.5 or K28.7) in the newest input word
            CommaPos_v := -1;

            for i in 3 downto 0 loop
                if r.S1K(i) = '1' and r.S1Err(i) = '0' and (Cur_v(i) = K28_5_c or Cur_v(i) = K28_7_c) then
                    CommaPos_v := i;
                end if;
            end loop;

            -- Aligned word from the previous and the current input word, starting at Offset
            for j in 0 to 3 loop
                Idx_v := r.Offset + j;
                if Idx_v < 4 then
                    v.S2Data(8*j+7 downto 8*j) := Prev_v(Idx_v);
                    v.S2K(j)                   := r.PrevK(Idx_v);
                else
                    v.S2Data(8*j+7 downto 8*j) := Cur_v(Idx_v-4);
                    v.S2K(j)                   := r.S1K(Idx_v-4);
                end if;
            end loop;

            v.S2Err := '0';

            for j in 0 to 3 loop
                Idx_v := r.Offset + j;
                if Idx_v < 4 then
                    v.S2Err := v.S2Err or r.PrevErr(Idx_v);
                else
                    v.S2Err := v.S2Err or r.S1Err(Idx_v-4);
                end if;
            end loop;

            -- A comma at another position than the current word boundary realigns the words
            v.S2Realign := '0';
            if CommaPos_v >= 0 and CommaPos_v /= r.Offset then
                v.S2Realign := '1';
                v.Offset    := CommaPos_v;
            end if;
            v.S2Valid  := '1';
            v.PrevData := r.S1Data;
            v.PrevK    := r.S1K;
            v.PrevErr  := r.S1Err;
        end if;

        -------------------------------------------------------------------------------------------
        -- Stage 3: receive synchronisation state machine (ECSS 5.5.8) and RXERR words
        -------------------------------------------------------------------------------------------
        v.S3Valid := '0';
        if r.S2Valid = '1' then
            Bad_v       := r.S2Err = '1' or r.S2Realign = '1';
            WordRxErr_v := '0';

            case r.SyncState is
                when LostSync_s =>
                    -- Every word is RXERR; a comma word starts the synchronisation check
                    WordRxErr_v := '1';
                    if not Bad_v and r.S2K(0) = '1' and
                       (r.S2Data(7 downto 0) = K28_5_c or r.S2Data(7 downto 0) = K28_7_c) then
                        v.SyncState := CheckSync_s;
                        v.ErrCnt    := 0;
                    end if;
                when CheckSync_s =>
                    if r.S2Realign = '1' then
                        v.SyncState := LostSync_s;
                    elsif r.S2Err = '1' then
                        if r.ErrCnt = 4 then
                            v.SyncState := LostSync_s;
                        else
                            v.ErrCnt := r.ErrCnt + 1;
                        end if;
                    else
                        v.SyncState := Ready_s;
                    end if;
                when Ready_s =>
                    if r.S2Realign = '1' then
                        v.SyncState := LostSync_s;
                    elsif r.S2Err = '1' then
                        v.SyncState := CheckSync_s;
                        v.ErrCnt    := 1;
                    end if;
                -- coverage off
                when others =>
                    v.SyncState := LostSync_s;
                -- coverage on
            end case;

            -- ECSS 5.5.7i, l: a realigned word or a word with an Rx Error symbol becomes RXERR; an Rx
            -- Error symbol also turns the previous word into RXERR
            if Bad_v then
                WordRxErr_v := '1';
            end if;
            if r.S2Err = '1' then
                v.HeldRxErr := '1';
            end if;
            -- Output the held word, hold the new one
            v.S3Data    := r.HeldData;
            v.S3K       := r.HeldK;
            v.S3RxErr   := v.HeldRxErr;
            v.S3Valid   := r.HeldValid;
            v.HeldData  := r.S2Data;
            v.HeldK     := r.S2K;
            v.HeldRxErr := WordRxErr_v;
            v.HeldValid := '1';
        end if;

        -------------------------------------------------------------------------------------------
        -- Stage 4: lane control word detection (ECSS 5.3.3), events, filtering (ECSS 5.5.2.11b)
        -------------------------------------------------------------------------------------------
        v.EvWord     := '0';
        v.EvRxErr    := '0';
        v.EvInit1    := '0';
        v.EvInit2    := '0';
        v.EvInvInit1 := '0';
        v.EvInvInit2 := '0';
        v.EvInit3    := '0';
        v.EvStandby  := '0';
        v.EvLostSig  := '0';
        v.EvComma    := '0';
        v.EvSkip     := '0';
        v.OutValid   := '0';
        v.EvOverflow := '0';
        Inc_v        := false;
        Dec_v        := false;
        if r.S3Valid = '1' then
            WordData_v := r.S3Data;
            v.EvWord   := '1';
            IsLane_v   := false;
            ToRxErr_v  := false;
            v.EvParam  := WordData_v(31 downto 24);
            if r.S3RxErr = '1' then
                v.EvRxErr := '1';
            elsif r.S3K = KCtrl_c then
                -- Comma K28.7 (ECSS 5.5.2.10e.8)
                if WordData_v(7 downto 0) = K28_7_c then
                    v.EvComma := '1';
                end if;
                if WordData_v = WordSkip_c then
                    v.EvSkip := '1';
                    IsLane_v := true;
                elsif WordData_v = WordIdle_c then
                    IsLane_v := true;
                elsif WordData_v = WordInit1_c then
                    v.EvInit1 := '1';
                    IsLane_v  := true;
                    ToRxErr_v := true;
                elsif WordData_v = WordInit2_c then
                    v.EvInit2 := '1';
                    IsLane_v  := true;
                elsif WordData_v = WordInvInit1_c then
                    v.EvInvInit1 := '1';
                    IsLane_v     := true;
                elsif WordData_v = WordInvInit2_c then
                    v.EvInvInit2 := '1';
                    IsLane_v     := true;
                elsif WordData_v(23 downto 0) = SymInit3_c & SymLlcw_c & K28_5_c then
                    v.EvInit3 := '1';
                    IsLane_v  := true;
                elsif WordData_v(23 downto 0) = SymStandby_c & SymLlcw_c & K28_7_c then
                    v.EvStandby := '1';
                    IsLane_v    := true;
                    ToRxErr_v   := true;
                elsif WordData_v(23 downto 0) = SymLostSignal_c & SymLlcw_c & K28_7_c then
                    v.EvLostSig := '1';
                    IsLane_v    := true;
                    ToRxErr_v   := true;
                end if;
            end if;

            -- Words passed to the Multi-Lane layer in Active (lane control words filtered,
            -- INIT1, STANDBY and LOST_SIGNAL passed as RXERR, ECSS 5.5.2.11b.5, b.8, b.9)
            if Ctrl_Active = '1' then
                if r.S3RxErr = '1' or ToRxErr_v then
                    v.OutData  := WordRxErr_c;
                    v.OutK     := KCtrl_c;
                    v.OutValid := '1';
                elsif not IsLane_v then
                    v.OutData  := WordData_v;
                    v.OutK     := r.S3K;
                    v.OutValid := '1';
                end if;

                -- RXERR word counter (ECSS 5.5.2.11b.6, b.7)
                Inc_v := r.S3RxErr = '1';
                if r.LeakCnt = RxErrLeakWords_g-1 then
                    v.LeakCnt := 0;
                    Dec_v     := true;
                else
                    v.LeakCnt := r.LeakCnt + 1;
                end if;
            end if;
        end if;

        -- At least one RXERR is passed up when Active is left (ECSS 5.5.2.11e.7)
        v.ActiveLast := Ctrl_Active;
        if r.ActiveLast = '1' and Ctrl_Active = '0' then
            v.OutData  := WordRxErr_c;
            v.OutK     := KCtrl_c;
            v.OutValid := '1';
        end if;

        -- RXERR word counter: saturating, overflow at 255 (ECSS 5.5.2.11e.3)
        if Inc_v and not Dec_v then
            if r.ErrCount /= 255 then
                v.ErrCount := r.ErrCount + 1;
                if r.ErrCount = 254 then
                    v.Overflow   := '1';
                    v.EvOverflow := '1';
                end if;
            end if;
        elsif Dec_v and not Inc_v then
            if r.ErrCount /= 0 then
                v.ErrCount := r.ErrCount - 1;
            end if;
        end if;
        -- Cleared on LaneReset and in Connected only (ECSS 5.5.2.2b, 5.5.2.10b.7)
        if Ctrl_RxErrClear = '1' then
            v.ErrCount := (others => '0');
            v.Overflow := '0';
            v.LeakCnt  := 0;
        end if;

        -- LaneReset, receiver or CDR disabled: LostSync (ECSS 5.5.8.2a.1); words received before are
        -- discarded
        if Ctrl_SyncReset = '1' then
            v.SyncState := LostSync_s;
            v.S1Valid   := '0';
            v.PrevErr   := (others => '1');
            v.HeldValid := '0';
            v.S2Valid   := '0';
            v.S3Valid   := '0';
        end if;

        -- Apply to record
        r_next <= v;

    end process;

    -- Outputs
    Out_Data           <= r.OutData;
    Out_K              <= r.OutK;
    Out_Valid          <= r.OutValid;
    Ev_Word            <= r.EvWord;
    Ev_RxErr           <= r.EvRxErr;
    Ev_Init1           <= r.EvInit1;
    Ev_Init2           <= r.EvInit2;
    Ev_InvInit1        <= r.EvInvInit1;
    Ev_InvInit2        <= r.EvInvInit2;
    Ev_Init3           <= r.EvInit3;
    Ev_Standby         <= r.EvStandby;
    Ev_LostSignal      <= r.EvLostSig;
    Ev_Comma           <= r.EvComma;
    Ev_Skip            <= r.EvSkip;
    Ev_Param           <= r.EvParam;
    Stat_RxErrCount    <= std_logic_vector(r.ErrCount);
    Stat_RxErrOverflow <= r.Overflow;
    Ev_RxErrOverflow   <= r.EvOverflow;

    -----------------------------------------------------------------------------------------------
    -- Sequential Process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.S1Valid    <= '0';
                r.PrevData   <= (others => '0');
                r.PrevK      <= (others => '0');
                r.PrevErr    <= (others => '1');
                r.Offset     <= 0;
                r.S2Valid    <= '0';
                r.SyncState  <= LostSync_s;
                r.ErrCnt     <= 0;
                r.HeldValid  <= '0';
                r.HeldRxErr  <= '1';
                r.S3Valid    <= '0';
                r.OutValid   <= '0';
                r.ActiveLast <= '0';
                r.EvWord     <= '0';
                r.EvRxErr    <= '0';
                r.EvInit1    <= '0';
                r.EvInit2    <= '0';
                r.EvInvInit1 <= '0';
                r.EvInvInit2 <= '0';
                r.EvInit3    <= '0';
                r.EvStandby  <= '0';
                r.EvLostSig  <= '0';
                r.EvComma    <= '0';
                r.EvSkip     <= '0';
                r.ErrCount   <= (others => '0');
                r.Overflow   <= '0';
                r.EvOverflow <= '0';
                r.LeakCnt    <= 0;
            end if;
        end if;
    end process;

end architecture;

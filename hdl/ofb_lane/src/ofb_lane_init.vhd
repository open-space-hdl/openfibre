---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Lane initialisation and standby state machine (LN-1), ECSS-E-ST-50-11C clause 5.5.2.
--
-- Documentation: hdl/ofb_lane/docs/architecture.md (section 2.1)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_lane_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_lane_init is
    generic (
        ClkFrequency_g     : real     := 156.25e6;
        InitTimeoutWords_g : positive := 5000
    );
    port (
        -- Control Ports
        Clk                     : in    std_logic;
        Rst                     : in    std_logic;
        -- Management parameters
        Cfg_LaneStart           : in    std_logic;
        Cfg_AutoStart           : in    std_logic;
        Cfg_LaneReset           : in    std_logic;
        -- Lane control from the Multi-Lane layer
        Ctrl_LaneReset          : in    std_logic;
        Ctrl_TxOnly             : in    std_logic;
        Ctrl_RxOnly             : in    std_logic;
        Ctrl_FarEndActive       : in    std_logic;
        Ctrl_NearCapability     : in    Char_t;
        Ctrl_State              : out   LaneState_t;
        Ctrl_FarCapability      : out   Char_t;
        Ctrl_FarCapabilityValid : out   std_logic;
        -- Physical layer control
        Phy_NoSignal            : in    std_logic;
        Phy_TxEnable            : out   std_logic;
        Phy_RxEnable            : out   std_logic;
        Phy_CdrEnable           : out   std_logic;
        Phy_RxInvert            : out   std_logic;
        -- Lane transmitter (LN-2)
        Tx_Mode                 : out   TxMode_t;
        Tx_Capability           : out   Char_t;
        Tx_LosCause             : out   LosCause_t;
        Tx_Init3Sent            : in    std_logic;
        Tx_StandbySent          : in    std_logic;
        Tx_LostSignalSent       : in    std_logic;
        -- Lane receiver (LN-3)
        Rx_SyncReset            : out   std_logic;
        Rx_Active               : out   std_logic;
        Rx_ErrClear             : out   std_logic;
        Rx_Word                 : in    std_logic;
        Rx_RxErr                : in    std_logic;
        Rx_Init1                : in    std_logic;
        Rx_Init2                : in    std_logic;
        Rx_InvInit1             : in    std_logic;
        Rx_InvInit2             : in    std_logic;
        Rx_Init3                : in    std_logic;
        Rx_Standby              : in    std_logic;
        Rx_LostSignal           : in    std_logic;
        Rx_Comma                : in    std_logic;
        Rx_Skip                 : in    std_logic;
        Rx_Param                : in    Char_t;
        Rx_ErrOverflow          : in    std_logic;
        -- Status
        Stat_Timeout            : out   std_logic;
        Stat_RxPolarity         : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_lane_init is

    -- ClearLine lasts 2 us (ECSS 5.5.2.4b.1)
    constant ClearLineCycles_c : positive := integer(ceil(2.0e-6 * ClkFrequency_g));

    type LaneFsm_t is (
        ClearLine_s, Disabled_s, Wait_s, Started_s, InvertRxPolarity_s, Connecting_s,
        Connected_s, Active_s, PrepareStandby_s, LossOfSignal_s
    );

    type TwoProcess_r is record
        State       : LaneFsm_t;
        TimerCnt    : natural range 0 to ClearLineCycles_c-1;
        TimeoutCnt  : natural range 0 to InitTimeoutWords_g-1;
        TimeoutRun  : std_logic;
        WordCnt     : natural range 0 to 1023;
        SeenInit    : std_logic;
        InvInit1Cnt : natural range 0 to 3;
        InvInit2Cnt : natural range 0 to 3;
        Init2Cnt    : natural range 0 to 3;
        Init3Cnt    : natural range 0 to 3;
        Init3Cap    : Char_t;
        LostCnt     : natural range 0 to 3;
        StbyCnt     : natural range 0 to 3;
        Init3Sent   : natural range 0 to 3;
        SentCnt     : natural range 0 to 32;
        RxInvert    : std_logic;
        LosCause    : LosCause_t;
        FarCap      : Char_t;
        CapPassed   : std_logic;
        CapEvent    : std_logic;
        TimeoutEv   : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    -----------------------------------------------------------------------------------------------
    -- Combinational Process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v           : TwoProcess_r;
        variable LaneReset_v : boolean;
        variable NoSignal_v  : boolean;
        variable Timeout_v   : boolean;
        variable Ready1023_v : boolean;
        variable Stop3_v     : boolean;
    begin
        -- Hold variables stable
        v := r;

        -- Defaults
        v.CapEvent  := '0';
        v.TimeoutEv := '0';
        LaneReset_v := Cfg_LaneReset = '1' or Ctrl_LaneReset = '1';
        NoSignal_v  := Phy_NoSignal = '1' and Ctrl_TxOnly = '0';

        -------------------------------------------------------------------------------------------
        -- Reception counters, including the event of the current word
        -------------------------------------------------------------------------------------------
        if Rx_Word = '1' then
            if Rx_RxErr = '1' then
                -- "without any intervening RXERR control words"
                v.WordCnt     := 0;
                v.SeenInit    := '0';
                v.InvInit1Cnt := 0;
                v.InvInit2Cnt := 0;
                v.Init2Cnt    := 0;
                v.Init3Cnt    := 0;
            else
                if r.WordCnt /= 1023 then
                    v.WordCnt := r.WordCnt + 1;
                end if;
                if Rx_Init1 = '1' or Rx_Init2 = '1' then
                    v.SeenInit := '1';
                end if;
                if Rx_InvInit1 = '1' and r.InvInit1Cnt /= 3 then
                    v.InvInit1Cnt := r.InvInit1Cnt + 1;
                end if;
                if Rx_InvInit2 = '1' and r.InvInit2Cnt /= 3 then
                    v.InvInit2Cnt := r.InvInit2Cnt + 1;
                end if;
                if Rx_Init2 = '1' and r.Init2Cnt /= 3 then
                    v.Init2Cnt := r.Init2Cnt + 1;
                end if;
                -- INIT3 with the same initialisation parameters
                if Rx_Init3 = '1' then
                    if r.Init3Cnt /= 0 and Rx_Param = r.Init3Cap then
                        if r.Init3Cnt /= 3 then
                            v.Init3Cnt := r.Init3Cnt + 1;
                        end if;
                    else
                        v.Init3Cnt := 1;
                        v.Init3Cap := Rx_Param;
                    end if;
                end if;
            end if;
            -- Consecutive LOST_SIGNAL / STANDBY words; SKIP words are transparent
            if Rx_LostSignal = '1' then
                v.StbyCnt := 0;
                if r.LostCnt /= 3 then
                    v.LostCnt := r.LostCnt + 1;
                end if;
            elsif Rx_Standby = '1' then
                v.LostCnt := 0;
                if r.StbyCnt /= 3 then
                    v.StbyCnt := r.StbyCnt + 1;
                end if;
            elsif Rx_Skip = '0' then
                v.LostCnt := 0;
                v.StbyCnt := 0;
            end if;
        end if;

        -- Words sent
        if Tx_Init3Sent = '1' and r.Init3Sent /= 3 then
            v.Init3Sent := r.Init3Sent + 1;
        end if;
        if (Tx_StandbySent = '1' or Tx_LostSignalSent = '1') and r.SentCnt /= 32 then
            v.SentCnt := r.SentCnt + 1;
        end if;

        -- Initialisation timeout timer: time to send InitTimeoutWords_g words (ECSS 5.5.2.7b.1)
        Timeout_v := false;
        if r.TimeoutRun = '1' then
            if r.TimeoutCnt = InitTimeoutWords_g-1 then
                Timeout_v := true;
            else
                v.TimeoutCnt := r.TimeoutCnt + 1;
            end if;
        end if;

        Ready1023_v := v.WordCnt = 1023 and v.SeenInit = '1';
        Stop3_v     := v.LostCnt = 3 or v.StbyCnt = 3;

        -------------------------------------------------------------------------------------------
        -- State machine (ECSS 5.5.2, exit conditions in the order of the standard)
        -------------------------------------------------------------------------------------------
        case r.State is

            when ClearLine_s =>
                v.RxInvert := '0';
                if r.TimerCnt = ClearLineCycles_c-1 then
                    v.State := Disabled_s;
                else
                    v.TimerCnt := r.TimerCnt + 1;
                end if;

            when Disabled_s =>
                if LaneReset_v then
                    v.State := ClearLine_s;
                elsif Cfg_LaneStart = '1' or Cfg_AutoStart = '1' then
                    v.State := Wait_s;
                end if;

            when Wait_s =>
                if LaneReset_v then
                    v.State := ClearLine_s;
                elsif Cfg_LaneStart = '0' and Cfg_AutoStart = '0' then
                    v.State := Disabled_s;
                elsif Cfg_LaneStart = '1' or Phy_NoSignal = '0' then
                    v.State := Started_s;
                end if;

            when Started_s =>
                if LaneReset_v then
                    v.State := ClearLine_s;
                elsif Ctrl_FarEndActive = '1' or Ready1023_v then
                    v.State := Connecting_s;
                elsif v.InvInit1Cnt = 3 or v.InvInit2Cnt = 3 then
                    v.State := InvertRxPolarity_s;
                elsif Timeout_v then
                    v.State     := ClearLine_s;
                    v.TimeoutEv := '1';
                elsif Stop3_v then
                    v.State := ClearLine_s;
                end if;

            when InvertRxPolarity_s =>
                if LaneReset_v or NoSignal_v then
                    v.State := ClearLine_s;
                elsif Ctrl_FarEndActive = '1' or Ready1023_v then
                    v.State := Connecting_s;
                elsif Timeout_v then
                    v.State     := ClearLine_s;
                    v.TimeoutEv := '1';
                elsif Stop3_v then
                    v.State := ClearLine_s;
                end if;

            when Connecting_s =>
                if LaneReset_v or NoSignal_v then
                    v.State := ClearLine_s;
                elsif Ctrl_RxOnly = '1' or Ctrl_FarEndActive = '1' or v.Init2Cnt = 3 or v.Init3Cnt = 3 then
                    v.State := Connected_s;
                elsif Timeout_v then
                    v.State     := ClearLine_s;
                    v.TimeoutEv := '1';
                elsif Stop3_v then
                    v.State := ClearLine_s;
                end if;

            when Connected_s =>
                -- Pass the capability of three identical INIT3 once (ECSS 5.5.2.10b.6)
                if v.Init3Cnt = 3 and r.CapPassed = '0' then
                    v.CapPassed := '1';
                    v.CapEvent  := '1';
                    v.FarCap    := v.Init3Cap;
                end if;
                if LaneReset_v or NoSignal_v then
                    v.State := ClearLine_s;
                elsif Ctrl_RxOnly = '1' then
                    v.State := Active_s;
                elsif Ctrl_FarEndActive = '1' and v.Init3Sent /= 0 then
                    v.State := Active_s;
                elsif v.Init3Cnt = 3 and v.Init3Sent = 3 then
                    v.State := Active_s;
                elsif Timeout_v then
                    v.State     := ClearLine_s;
                    v.TimeoutEv := '1';
                elsif Stop3_v or Rx_Comma = '1' then
                    v.State := ClearLine_s;
                end if;

            when Active_s =>
                if LaneReset_v then
                    v.State := ClearLine_s;
                elsif NoSignal_v then
                    v.State    := LossOfSignal_s;
                    v.LosCause := LosCauseNoSignal_c;
                elsif Rx_ErrOverflow = '1' and Ctrl_TxOnly = '0' then
                    v.State    := LossOfSignal_s;
                    v.LosCause := LosCauseRxErr_c;
                elsif Rx_Word = '1' and Rx_Init1 = '1' and Ctrl_RxOnly = '0' then
                    v.State    := LossOfSignal_s;
                    v.LosCause := LosCauseInit1_c;
                elsif Cfg_LaneStart = '0' and Cfg_AutoStart = '0' then
                    v.State := PrepareStandby_s;
                elsif Stop3_v then
                    v.State := ClearLine_s;
                end if;

            when PrepareStandby_s | LossOfSignal_s =>
                if LaneReset_v or v.SentCnt = 32 or Stop3_v then
                    v.State := ClearLine_s;
                end if;

            -- coverage off
            when others =>
                v.State := ClearLine_s;
            -- coverage on

        end case;

        -------------------------------------------------------------------------------------------
        -- Actions on state entry
        -------------------------------------------------------------------------------------------
        if v.State /= r.State then
            v.Init3Sent := 0;
            v.SentCnt   := 0;
            v.TimerCnt  := 0;
            if v.State /= Connected_s then
                v.Init3Cnt := 0;
            end if;

            case v.State is
                when Started_s =>
                    -- Start the initialisation timeout timer
                    v.TimeoutRun  := '1';
                    v.TimeoutCnt  := 0;
                    v.WordCnt     := 0;
                    v.SeenInit    := '0';
                    v.InvInit1Cnt := 0;
                    v.InvInit2Cnt := 0;
                when InvertRxPolarity_s =>
                    v.RxInvert    := '1';
                    v.WordCnt     := 0;
                    v.SeenInit    := '0';
                    v.InvInit1Cnt := 0;
                    v.InvInit2Cnt := 0;
                when Connecting_s =>
                    v.Init2Cnt := 0;
                when Connected_s =>
                    v.CapPassed := '0';
                when ClearLine_s =>
                    -- Receiver off: consecutive LOST_SIGNAL / STANDBY words start again from zero
                    v.TimeoutRun := '0';
                    v.LostCnt    := 0;
                    v.StbyCnt    := 0;
                when Active_s | Disabled_s | Wait_s =>
                    v.TimeoutRun := '0';
                when others =>
                    null;
            end case;

        end if;

        -- Apply to record
        r_next <= v;

    end process;

    -----------------------------------------------------------------------------------------------
    -- Outputs
    -----------------------------------------------------------------------------------------------
    p_out : process (all) is
        variable State_v   : LaneState_t;
        variable Mode_v    : TxMode_t;
        variable Line_v    : boolean; -- Started to LossOfSignal: lane is using the line
        variable LaneRst_v : std_logic;
    begin
        Line_v := false;

        case r.State is
            when ClearLine_s =>
                State_v := LaneStateClearLine_c;
                Mode_v  := TxModeOff_c;
            when Disabled_s =>
                State_v := LaneStateDisabled_c;
                Mode_v  := TxModeOff_c;
            when Wait_s =>
                State_v := LaneStateWait_c;
                Mode_v  := TxModeOff_c;
            when Started_s =>
                State_v := LaneStateStarted_c;
                Mode_v  := TxModeInit1_c;
                Line_v  := true;
            when InvertRxPolarity_s =>
                State_v := LaneStateInvertRxPol_c;
                Mode_v  := TxModeInit1_c;
                Line_v  := true;
            when Connecting_s =>
                State_v := LaneStateConnecting_c;
                Mode_v  := TxModeInit2_c;
                Line_v  := true;
            when Connected_s =>
                State_v := LaneStateConnected_c;
                Mode_v  := TxModeInit3_c;
                Line_v  := true;
            when Active_s =>
                State_v := LaneStateActive_c;
                Mode_v  := TxModeActive_c;
                Line_v  := true;
            when PrepareStandby_s =>
                State_v := LaneStatePrepareStandby_c;
                Mode_v  := TxModeStandby_c;
                Line_v  := true;
            when LossOfSignal_s =>
                State_v := LaneStateLossOfSignal_c;
                Mode_v  := TxModeLostSignal_c;
                Line_v  := true;
            -- coverage off
            when others =>
                State_v := LaneStateClearLine_c;
                Mode_v  := TxModeOff_c;
            -- coverage on
        end case;

        LaneRst_v := Cfg_LaneReset or Ctrl_LaneReset;

        Ctrl_State <= State_v;
        Tx_Mode    <= Mode_v;

        -- ECSS 5.5.2.5b to 5.5.2.13d: transmitter disabled when RxOnly, receiver and CDR when TxOnly
        if Line_v then
            Phy_TxEnable  <= not Ctrl_RxOnly;
            Phy_RxEnable  <= not Ctrl_TxOnly;
            Phy_CdrEnable <= not Ctrl_TxOnly;
        elsif r.State = Wait_s then
            Phy_TxEnable  <= '0';
            Phy_RxEnable  <= not Ctrl_TxOnly; -- NoSignal detection
            Phy_CdrEnable <= '0';
        else
            Phy_TxEnable  <= '0';
            Phy_RxEnable  <= '0';
            Phy_CdrEnable <= '0';
        end if;

        -- LostSync while the CDR is disabled or on LaneReset
        if Line_v and Ctrl_TxOnly = '0' and LaneRst_v = '0' then
            Rx_SyncReset <= '0';
        else
            Rx_SyncReset <= '1';
        end if;

        if r.State = Active_s then
            Rx_Active <= '1';
        else
            Rx_Active <= '0';
        end if;

        -- RXERR word counter cleared on LaneReset and in Connected (ECSS 5.5.2.2b, 5.5.2.10b.7)
        if LaneRst_v = '1' or r.State = Connected_s then
            Rx_ErrClear <= '1';
        else
            Rx_ErrClear <= '0';
        end if;
    end process;

    -- INIT3 capability with the INIT3LaneStart flag of this lane (ECSS 5.3.3.8g)
    p_cap : process (all) is
        variable Cap_v : Char_t;
    begin
        Cap_v                 := Ctrl_NearCapability;
        Cap_v(CapLaneStart_c) := Cfg_LaneStart;
        Tx_Capability         <= Cap_v;
    end process;

    Tx_LosCause             <= r.LosCause;
    Phy_RxInvert            <= r.RxInvert;
    Ctrl_FarCapability      <= r.FarCap;
    Ctrl_FarCapabilityValid <= r.CapEvent;
    Stat_Timeout            <= r.TimeoutEv;
    Stat_RxPolarity         <= r.RxInvert;

    -----------------------------------------------------------------------------------------------
    -- Sequential Process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.State       <= ClearLine_s;
                r.TimerCnt    <= 0;
                r.TimeoutCnt  <= 0;
                r.TimeoutRun  <= '0';
                r.WordCnt     <= 0;
                r.SeenInit    <= '0';
                r.InvInit1Cnt <= 0;
                r.InvInit2Cnt <= 0;
                r.Init2Cnt    <= 0;
                r.Init3Cnt    <= 0;
                r.Init3Cap    <= (others => '0');
                r.LostCnt     <= 0;
                r.StbyCnt     <= 0;
                r.Init3Sent   <= 0;
                r.SentCnt     <= 0;
                r.RxInvert    <= '0';
                r.LosCause    <= LosCauseNoSignal_c;
                r.FarCap      <= (others => '0');
                r.CapPassed   <= '0';
                r.CapEvent    <= '0';
                r.TimeoutEv   <= '0';
            end if;
        end if;
    end process;

end architecture;

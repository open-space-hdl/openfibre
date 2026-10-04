---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the Lane layer: two ofb_lane instances (A and B) connected through the
-- behavioural Physical adapter model, AXI-Stream VVCs for the transmit words and monitors that
-- check the received words and collect the status.
--
-- Documentation: hdl/ofb_lane/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_lane_pkg.all;
    use work.ofb_lane_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_lane_th is
    generic (
        SkipIntervalWords_g : positive := 5000;
        RxErrLeakWords_g    : positive := 16384
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_lane_th is

    constant ClkPeriod_c : time := 6.4 ns; -- 156.25 MHz, 6.25 Gbit/s with 32-bit words

    signal Clk : std_logic := '0';
    signal Rst : std_logic := '1';

    type WordArray_t is array (0 to 1) of Word_t;
    type KArray_t is array (0 to 1) of WordK_t;
    type BitArray_t is array (0 to 1) of std_logic;
    type StateArray_t is array (0 to 1) of LaneState_t;
    type CharArray_t is array (0 to 1) of Char_t;

    signal TxData                       : WordArray_t;
    signal RxData                       : WordArray_t;
    signal PhyTxData                    : WordArray_t;
    signal PhyRxData                    : WordArray_t;
    signal TxK                          : KArray_t;
    signal RxK                          : KArray_t;
    signal PhyTxK                       : KArray_t;
    signal PhyRxK                       : KArray_t;
    signal PhyRxCode, PhyRxDisp         : KArray_t;
    signal TxValid                      : BitArray_t;
    signal TxReady                      : BitArray_t;
    signal RxValid                      : BitArray_t;
    signal PhyRxValid, NoSignal         : BitArray_t;
    signal TxEnable                     : BitArray_t;
    signal RxEnable                     : BitArray_t;
    signal CdrEnable                    : BitArray_t;
    signal RxInvert                     : BitArray_t;
    signal State                        : StateArray_t;
    signal RxErrCount                   : CharArray_t;
    signal FarCap                       : CharArray_t;
    signal CtrlFarCap                   : CharArray_t;
    signal FarStbyReason, FarLostReason : CharArray_t;
    signal Overflow                     : BitArray_t;
    signal Timeout                      : BitArray_t;
    signal FarStby                      : BitArray_t;
    signal FarLost                      : BitArray_t;
    signal CapValid, RxPolarity         : BitArray_t;

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    Clk <= not Clk after ClkPeriod_c / 2;

    p_rst : process is
    begin
        Rst <= '1';
        wait for 20 * ClkPeriod_c;
        wait until rising_edge(Clk);
        Rst <= '0';
        wait;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Lane ends A (0) and B (1)
    -----------------------------------------------------------------------------------------------
    g_lane : for i in 0 to 1 generate

        i_vvc_tx : entity work.ofb_tb_axis_master
            generic map (
                InstanceIdx_g => VvcTxA_c + i,
                DataWidth_g   => 32,
                UserWidth_g   => 4
            )
            port map (
                Clk       => Clk,
                Out_Data  => TxData(i),
                Out_User  => TxK(i),
                Out_Keep  => open,
                Out_Last  => open,
                Out_Valid => TxValid(i),
                Out_Ready => TxReady(i)
            );

        i_dut : entity work.ofb_lane
            generic map (
                ClkFrequency_g      => 156.25e6,
                SkipIntervalWords_g => SkipIntervalWords_g,
                RxErrLeakWords_g    => RxErrLeakWords_g
            )
            port map (
                Clk                      => Clk,
                Rst                      => Rst,
                TxWord_Data              => TxData(i),
                TxWord_K                 => TxK(i),
                TxWord_Valid             => TxValid(i),
                TxWord_Ready             => TxReady(i),
                RxWord_Data              => RxData(i),
                RxWord_K                 => RxK(i),
                RxWord_Valid             => RxValid(i),
                Ctrl_LaneReset           => LaneCfg(i).CtrlLaneReset,
                Ctrl_TxOnly              => LaneCfg(i).TxOnly,
                Ctrl_RxOnly              => LaneCfg(i).RxOnly,
                Ctrl_FarEndActive        => LaneCfg(i).FarEndActive,
                Ctrl_NearCapability      => LaneCfg(i).NearCapability,
                Ctrl_State               => open,
                Ctrl_FarCapability       => CtrlFarCap(i),
                Ctrl_FarCapabilityValid  => CapValid(i),
                PhyTx_Data               => PhyTxData(i),
                PhyTx_K                  => PhyTxK(i),
                PhyRx_Data               => PhyRxData(i),
                PhyRx_K                  => PhyRxK(i),
                PhyRx_CodeErr            => PhyRxCode(i),
                PhyRx_DispErr            => PhyRxDisp(i),
                PhyRx_Valid              => PhyRxValid(i),
                Phy_TxEnable             => TxEnable(i),
                Phy_RxEnable             => RxEnable(i),
                Phy_CdrEnable            => CdrEnable(i),
                Phy_RxInvert             => RxInvert(i),
                Phy_NoSignal             => NoSignal(i),
                Cfg_LaneStart            => LaneCfg(i).LaneStart,
                Cfg_AutoStart            => LaneCfg(i).AutoStart,
                Cfg_LaneReset            => LaneCfg(i).LaneReset,
                Cfg_NearLoopback         => LaneCfg(i).NearLoopback,
                Cfg_FarLoopback          => LaneCfg(i).FarLoopback,
                Cfg_StandbyReason        => LaneCfg(i).StandbyReason,
                Stat_State               => State(i),
                Stat_RxErrCount          => RxErrCount(i),
                Stat_RxErrOverflow       => Overflow(i),
                Stat_Timeout             => Timeout(i),
                Stat_FarStandby          => FarStby(i),
                Stat_FarStandbyReason    => FarStbyReason(i),
                Stat_FarLostSignal       => FarLost(i),
                Stat_FarLostSignalReason => FarLostReason(i),
                Stat_FarCapability       => FarCap(i),
                Stat_RxPolarity          => RxPolarity(i)
            );

        -- Monitor: received words, status, events
        p_monitor : process (Clk) is
            variable Stat_v      : LaneStat_t;
            variable SkipGap_v   : natural     := 0;
            variable SeenSkip_v  : boolean     := false;
            variable Word_v      : std_logic_vector(35 downto 0);
            variable Init_v      : boolean     := true;
            variable LastState_v : LaneState_t := LaneStateClearLine_c;
        begin
            if rising_edge(Clk) then
                if Init_v then
                    Stat_v := (State => LaneStateClearLine_c,
                               RxErrCount => x"00",
                               RxPolarity => '0',
                               FarCapability => x"00",
                               CtrlFarCap => x"00",
                               TimeoutCnt => 0,
                               OverflowCnt => 0,
                               FarStandbyCnt => 0,
                               FarStandbyReason => x"00",
                               FarLostCnt => 0,
                               FarLostReason => x"00",
                               CapEventCnt => 0,
                               RxWordCnt => 0,
                               RxErrWordCnt => 0,
                               SkipCnt => 0,
                               SkipGapMin => natural'high,
                               SkipGapMax => 0,
                               ActiveCnt => 0,
                               TxEnable => '0');
                    Init_v := false;
                end if;
                if Rst = '0' then
                    -- Words passed to the Multi-Lane layer
                    if RxValid(i) = '1' then
                        Stat_v.RxWordCnt := Stat_v.RxWordCnt + 1;
                        Word_v           := RxK(i) & RxData(i);
                        if RxK(i) = KCtrl_c and RxData(i) = WordRxErr_c then
                            Stat_v.RxErrWordCnt := Stat_v.RxErrWordCnt + 1;
                        end if;
                        if LaneCfg(i).SbCheck then
                            RxSb_v.check_received(i + 1, Word_v);
                        end if;
                    end if;
                    -- SKIP interval at the Physical adapter
                    if PhyTxK(i) = KCtrl_c and PhyTxData(i) = WordSkip_c then
                        Stat_v.SkipCnt := Stat_v.SkipCnt + 1;
                        if SeenSkip_v then
                            if SkipGap_v < Stat_v.SkipGapMin then
                                Stat_v.SkipGapMin := SkipGap_v;
                            end if;
                            if SkipGap_v > Stat_v.SkipGapMax then
                                Stat_v.SkipGapMax := SkipGap_v;
                            end if;
                        end if;
                        SeenSkip_v := true;
                        SkipGap_v  := 0;
                    elsif State(i) = LaneStateActive_c then
                        SkipGap_v := SkipGap_v + 1;
                    else
                        SeenSkip_v := false;
                        SkipGap_v  := 0;
                    end if;
                    -- Events
                    if Timeout(i) = '1' then
                        Stat_v.TimeoutCnt := Stat_v.TimeoutCnt + 1;
                    end if;
                    if Overflow(i) = '1' then
                        Stat_v.OverflowCnt := Stat_v.OverflowCnt + 1;
                    end if;
                    if FarStby(i) = '1' then
                        Stat_v.FarStandbyCnt    := Stat_v.FarStandbyCnt + 1;
                        Stat_v.FarStandbyReason := FarStbyReason(i);
                    end if;
                    if FarLost(i) = '1' then
                        Stat_v.FarLostCnt    := Stat_v.FarLostCnt + 1;
                        Stat_v.FarLostReason := FarLostReason(i);
                    end if;
                    if CapValid(i) = '1' then
                        Stat_v.CapEventCnt := Stat_v.CapEventCnt + 1;
                        Stat_v.CtrlFarCap  := CtrlFarCap(i);
                    end if;
                    if State(i) = LaneStateActive_c and LastState_v /= LaneStateActive_c then
                        Stat_v.ActiveCnt := Stat_v.ActiveCnt + 1;
                    end if;
                    LastState_v := State(i);
                end if;
                Stat_v.State         := State(i);
                Stat_v.RxErrCount    := RxErrCount(i);
                Stat_v.RxPolarity    := RxPolarity(i);
                Stat_v.FarCapability := FarCap(i);
                Stat_v.TxEnable      := TxEnable(i);
                LaneStat(i)          <= Stat_v;
            end if;
        end process;

    end generate;

    -----------------------------------------------------------------------------------------------
    -- Lane: behavioural Physical adapters and channel
    -----------------------------------------------------------------------------------------------
    i_pa : entity work.ofb_tb_pa_model
        generic map (
            Instance_g => 0
        )
        port map (
            Clk          => Clk,
            A_Tx_Data    => PhyTxData(0),
            A_Tx_K       => PhyTxK(0),
            A_TxEnable   => TxEnable(0),
            A_RxEnable   => RxEnable(0),
            A_CdrEnable  => CdrEnable(0),
            A_RxInvert   => RxInvert(0),
            A_Rx_Data    => PhyRxData(0),
            A_Rx_K       => PhyRxK(0),
            A_Rx_CodeErr => PhyRxCode(0),
            A_Rx_DispErr => PhyRxDisp(0),
            A_Rx_Valid   => PhyRxValid(0),
            A_NoSignal   => NoSignal(0),
            B_Tx_Data    => PhyTxData(1),
            B_Tx_K       => PhyTxK(1),
            B_TxEnable   => TxEnable(1),
            B_RxEnable   => RxEnable(1),
            B_CdrEnable  => CdrEnable(1),
            B_RxInvert   => RxInvert(1),
            B_Rx_Data    => PhyRxData(1),
            B_Rx_K       => PhyRxK(1),
            B_Rx_CodeErr => PhyRxCode(1),
            B_Rx_DispErr => PhyRxDisp(1),
            B_Rx_Valid   => PhyRxValid(1),
            B_NoSignal   => NoSignal(1)
        );

end architecture;

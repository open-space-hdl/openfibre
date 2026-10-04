---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the Multi-Lane layer: two ends A (0) and B (1), each an ofb_multilane with one
-- ofb_lane, connected through the behavioural Physical adapter model; AXI-Stream VVCs for the
-- transmit rows, logs of the received rows and collection of the status.
--
-- Documentation: hdl/ofb_multilane/docs/verification_plan.md

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
    use work.ofb_ml_pkg.all;
    use work.ofb_multilane_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_multilane_th is
    port (
        Clk : out   std_logic;
        Rst : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_multilane_th is

    constant ClkPeriod_c : time := 6.4 ns;

    signal ClkI : std_logic := '0';
    signal RstI : std_logic := '1';

    type WordArray_t is array (0 to 1) of Word_t;
    type KArray_t is array (0 to 1) of WordK_t;
    type BitArray_t is array (0 to 1) of std_logic;
    type StateArray_t is array (0 to 1) of LaneState_t;
    type CharArray_t is array (0 to 1) of Char_t;
    type AlignArray_t is array (0 to 1) of AlignState_t;

    -- Data Link side
    signal TxRowData   : WordArray_t;
    signal TxRowK      : KArray_t;
    signal TxRowValid  : BitArray_t;
    signal TxRowReady  : BitArray_t;
    signal RxRowData   : WordArray_t;
    signal RxRowK      : KArray_t;
    signal RxRowCrcErr : BitArray_t;
    signal RxRowValid  : BitArray_t;
    signal FarCap      : CharArray_t;
    signal FarCapValid : BitArray_t;
    signal LaneActive  : BitArray_t;
    signal DataSending : BitArray_t;
    signal DataRecv    : BitArray_t;
    signal AlignState  : AlignArray_t;

    -- Multi-Lane to Lane
    signal LaneTxData    : WordArray_t;
    signal LaneTxK       : KArray_t;
    signal LaneTxValid   : BitArray_t;
    signal LaneTxReady   : BitArray_t;
    signal LaneRxData    : WordArray_t;
    signal LaneRxK       : KArray_t;
    signal LaneRxValid   : BitArray_t;
    signal LaneReset     : BitArray_t;
    signal LaneTxOnly    : BitArray_t;
    signal LaneRxOnly    : BitArray_t;
    signal LaneFarActive : BitArray_t;
    signal LaneNearCap   : CharArray_t;
    signal LaneState     : StateArray_t;
    signal LaneFarCap    : CharArray_t;
    signal LaneCapValid  : BitArray_t;

    -- Lane to Physical adapter
    signal PhyTxData  : WordArray_t;
    signal PhyTxK     : KArray_t;
    signal PhyRxData  : WordArray_t;
    signal PhyRxK     : KArray_t;
    signal PhyRxCode  : KArray_t;
    signal PhyRxDisp  : KArray_t;
    signal PhyRxValid : BitArray_t;
    signal NoSignal   : BitArray_t;
    signal TxEnable   : BitArray_t;
    signal RxEnable   : BitArray_t;
    signal CdrEnable  : BitArray_t;
    signal RxInvert   : BitArray_t;

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    ClkI <= not ClkI after ClkPeriod_c / 2;
    Clk  <= ClkI;
    Rst  <= RstI;

    p_rst : process is
    begin
        RstI <= '1';
        wait for 20 * ClkPeriod_c;
        wait until rising_edge(ClkI);
        RstI <= '0';
        wait;
    end process;

    g_end : for i in 0 to 1 generate

        i_vvc_tx : entity work.ofb_tb_axis_master
            generic map (
                InstanceIdx_g => VvcA_c + i,
                DataWidth_g   => 32,
                UserWidth_g   => 4
            )
            port map (
                Clk       => ClkI,
                Out_Data  => TxRowData(i),
                Out_User  => TxRowK(i),
                Out_Keep  => open,
                Out_Last  => open,
                Out_Valid => TxRowValid(i),
                Out_Ready => TxRowReady(i)
            );

        i_ml : entity work.ofb_multilane
            generic map (
                NumLanes_g => 1
            )
            port map (
                Clk                        => ClkI,
                Rst                        => RstI,
                TxRow_Data                 => TxRowData(i),
                TxRow_K                    => TxRowK(i),
                TxRow_Valid                => TxRowValid(i),
                TxRow_Ready                => TxRowReady(i),
                RxRow_Data                 => RxRowData(i),
                RxRow_K                    => RxRowK(i),
                RxRow_Mask                 => open,
                RxRow_CrcErr               => RxRowCrcErr(i),
                RxRow_Valid                => RxRowValid(i),
                Dl_LinkReset               => MlCfg(i).LinkReset,
                Dl_LaneReset               => MlCfg(i).LaneReset,
                Dl_NearCapability          => MlCfg(i).NearCapability,
                Dl_FarCapability           => FarCap(i),
                Dl_FarCapabilityValid      => FarCapValid(i),
                Dl_LaneActive              => LaneActive(i),
                LaneTx_Data                => LaneTxData(i),
                LaneTx_K                   => LaneTxK(i),
                LaneTx_Valid(0)            => LaneTxValid(i),
                LaneTx_Ready(0)            => LaneTxReady(i),
                LaneRx_Data                => LaneRxData(i),
                LaneRx_K                   => LaneRxK(i),
                LaneRx_Valid(0)            => LaneRxValid(i),
                Lane_Reset(0)              => LaneReset(i),
                Lane_TxOnly(0)             => LaneTxOnly(i),
                Lane_RxOnly(0)             => LaneRxOnly(i),
                Lane_FarEndActive(0)       => LaneFarActive(i),
                Lane_NearCapability        => LaneNearCap(i),
                Lane_State                 => LaneState(i),
                Lane_FarCapability         => LaneFarCap(i),
                Lane_FarCapabilityValid(0) => LaneCapValid(i),
                Stat_DataSendingLanes(0)   => DataSending(i),
                Stat_DataReceivingLanes(0) => DataRecv(i),
                Stat_AlignState            => AlignState(i)
            );

        i_lane : entity work.ofb_lane
            port map (
                Clk                      => ClkI,
                Rst                      => RstI,
                TxWord_Data              => LaneTxData(i),
                TxWord_K                 => LaneTxK(i),
                TxWord_Valid             => LaneTxValid(i),
                TxWord_Ready             => LaneTxReady(i),
                RxWord_Data              => LaneRxData(i),
                RxWord_K                 => LaneRxK(i),
                RxWord_Valid             => LaneRxValid(i),
                Ctrl_LaneReset           => LaneReset(i),
                Ctrl_TxOnly              => LaneTxOnly(i),
                Ctrl_RxOnly              => LaneRxOnly(i),
                Ctrl_FarEndActive        => LaneFarActive(i),
                Ctrl_NearCapability      => LaneNearCap(i),
                Ctrl_State               => LaneState(i),
                Ctrl_FarCapability       => LaneFarCap(i),
                Ctrl_FarCapabilityValid  => LaneCapValid(i),
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
                Cfg_LaneStart            => MlCfg(i).LaneStart,
                Cfg_AutoStart            => MlCfg(i).AutoStart,
                Cfg_LaneReset            => '0',
                Stat_State               => open,
                Stat_RxErrCount          => open,
                Stat_RxErrOverflow       => open,
                Stat_Timeout             => open,
                Stat_FarStandby          => open,
                Stat_FarStandbyReason    => open,
                Stat_FarLostSignal       => open,
                Stat_FarLostSignalReason => open,
                Stat_FarCapability       => open,
                Stat_RxPolarity          => open
            );

        -- Monitor: received rows, status, events
        p_monitor : process (ClkI) is
            variable Stat_v      : MlStat_t;
            variable Init_v      : boolean     := true;
            variable LastState_v : LaneState_t := LaneStateClearLine_c;
            variable Ctrl_v      : std_logic_vector(3 downto 0);
        begin
            if rising_edge(ClkI) then
                if Init_v then
                    Stat_v := (LaneState => LaneStateClearLine_c,
                               LaneActive => '0',
                               FarCapability => x"00",
                               FarCapCnt => 0,
                               LaneCtrl => "0000",
                               LaneCtrlSeen => "0000",
                               LaneNearCap => x"00",
                               DataSending => '0',
                               DataReceiving => '0',
                               AlignState => AlignNotReady_c,
                               ActiveCnt => 0);
                    Init_v := false;
                end if;
                if RstI = '0' then
                    if RxRowValid(i) = '1' then
                        if i = 0 then
                            RxLogA_v.push(RxRowK(i) & RxRowData(i), RxRowCrcErr(i));
                        else
                            RxLogB_v.push(RxRowK(i) & RxRowData(i), RxRowCrcErr(i));
                        end if;
                    end if;
                    if FarCapValid(i) = '1' then
                        Stat_v.FarCapCnt := Stat_v.FarCapCnt + 1;
                    end if;
                    if LaneState(i) = LaneStateActive_c and LastState_v /= LaneStateActive_c then
                        Stat_v.ActiveCnt := Stat_v.ActiveCnt + 1;
                    end if;
                    LastState_v         := LaneState(i);
                    Ctrl_v              := LaneReset(i) & LaneTxOnly(i) & LaneRxOnly(i) & LaneFarActive(i);
                    Stat_v.LaneCtrlSeen := Stat_v.LaneCtrlSeen or Ctrl_v;
                    Stat_v.LaneCtrl     := Ctrl_v;
                end if;
                Stat_v.LaneState     := LaneState(i);
                Stat_v.LaneActive    := LaneActive(i);
                Stat_v.FarCapability := FarCap(i);
                Stat_v.LaneNearCap   := LaneNearCap(i);
                Stat_v.DataSending   := DataSending(i);
                Stat_v.DataReceiving := DataRecv(i);
                Stat_v.AlignState    := AlignState(i);
                MlStat(i)            <= Stat_v;
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
            Clk          => ClkI,
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

---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Lane layer of OpenFibre for one lane (ECSS-E-ST-50-11C clause 5.5): lane initialisation (LN-1),
-- transmitter (LN-2), receiver (LN-3) and parallel loopback (LN-4).
--
-- Documentation: hdl/ofb_lane/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_lane_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_lane is
    generic (
        ClkFrequency_g      : real                  := 156.25e6;
        InitTimeoutWords_g  : positive              := 5000;
        InitPrbsWords_g     : natural range 0 to 64 := 64;
        SkipIntervalWords_g : positive              := 5000;
        SkipExternal_g      : boolean               := false; -- SKIP on Ctrl_SkipReq (multi-lane)
        RxErrLeakWords_g    : positive              := 16384
    );
    port (
        -- Control Ports
        Clk                      : in    std_logic;
        Rst                      : in    std_logic;
        -- Words from / to the Multi-Lane layer
        TxWord_Data              : in    Word_t;
        TxWord_K                 : in    WordK_t;
        TxWord_Valid             : in    std_logic;
        TxWord_Ready             : out   std_logic;
        RxWord_Data              : out   Word_t;
        RxWord_K                 : out   WordK_t;
        RxWord_Valid             : out   std_logic;
        -- Lane control from / to the Multi-Lane layer
        Ctrl_LaneReset           : in    std_logic := '0';
        Ctrl_SkipReq             : in    std_logic := '0';
        Ctrl_TxOnly              : in    std_logic := '0';
        Ctrl_RxOnly              : in    std_logic := '0';
        Ctrl_FarEndActive        : in    std_logic := '0';
        Ctrl_NearCapability      : in    Char_t;
        Ctrl_State               : out   LaneState_t;
        Ctrl_FarCapability       : out   Char_t;
        Ctrl_FarCapabilityValid  : out   std_logic;
        -- Physical adapter: symbols and control
        PhyTx_Data               : out   Word_t;
        PhyTx_K                  : out   WordK_t;
        PhyRx_Data               : in    Word_t;
        PhyRx_K                  : in    WordK_t;
        PhyRx_CodeErr            : in    WordK_t;
        PhyRx_DispErr            : in    WordK_t;
        PhyRx_Valid              : in    std_logic;
        Phy_TxEnable             : out   std_logic;
        Phy_RxEnable             : out   std_logic;
        Phy_CdrEnable            : out   std_logic;
        Phy_RxInvert             : out   std_logic;
        Phy_NoSignal             : in    std_logic;
        -- Management parameters
        Cfg_LaneStart            : in    std_logic;
        Cfg_AutoStart            : in    std_logic;
        Cfg_LaneReset            : in    std_logic;
        Cfg_NearLoopback         : in    std_logic := '0';
        Cfg_FarLoopback          : in    std_logic := '0';
        Cfg_StandbyReason        : in    Char_t    := (others => '0');
        -- Status (events are one clock cycle long)
        Stat_State               : out   LaneState_t;
        Stat_RxErrCount          : out   Char_t;
        Stat_RxErrOverflow       : out   std_logic;
        Stat_Timeout             : out   std_logic;
        Stat_FarStandby          : out   std_logic;
        Stat_FarStandbyReason    : out   Char_t;
        Stat_FarLostSignal       : out   std_logic;
        Stat_FarLostSignalReason : out   Char_t;
        Stat_FarCapability       : out   Char_t;
        Stat_RxPolarity          : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture struct of ofb_lane is

    -- LN-1 to LN-2
    signal TxMode       : TxMode_t;
    signal TxCapability : Char_t;
    signal TxLosCause   : LosCause_t;
    signal Init3Sent    : std_logic;
    signal StandbySent  : std_logic;
    signal LostSent     : std_logic;

    -- LN-2 / LN-3 to LN-4
    signal LaneTxData    : Word_t;
    signal LaneTxK       : WordK_t;
    signal LaneRxData    : Word_t;
    signal LaneRxK       : WordK_t;
    signal LaneRxCodeErr : WordK_t;
    signal LaneRxDispErr : WordK_t;
    signal LaneRxValid   : std_logic;

    -- LN-1 to LN-3
    signal SyncReset : std_logic;
    signal Active    : std_logic;
    signal ErrClear  : std_logic;

    -- LN-3 to LN-1
    signal EvWord      : std_logic;
    signal EvRxErr     : std_logic;
    signal EvInit1     : std_logic;
    signal EvInit2     : std_logic;
    signal EvInvInit1  : std_logic;
    signal EvInvInit2  : std_logic;
    signal EvInit3     : std_logic;
    signal EvStandby   : std_logic;
    signal EvLostSig   : std_logic;
    signal EvComma     : std_logic;
    signal EvSkip      : std_logic;
    signal EvParam     : Char_t;
    signal ErrOverflow : std_logic;

    signal NoSignal : std_logic;
    signal State    : LaneState_t;
    signal FarCap   : Char_t;

begin

    -- The line is not used during the near-end parallel loopback
    NoSignal <= Phy_NoSignal and not Cfg_NearLoopback;

    -----------------------------------------------------------------------------------------------
    -- LN-1: lane initialisation
    -----------------------------------------------------------------------------------------------
    i_init : entity work.ofb_lane_init
        generic map (
            ClkFrequency_g     => ClkFrequency_g,
            InitTimeoutWords_g => InitTimeoutWords_g
        )
        port map (
            Clk                     => Clk,
            Rst                     => Rst,
            Cfg_LaneStart           => Cfg_LaneStart,
            Cfg_AutoStart           => Cfg_AutoStart,
            Cfg_LaneReset           => Cfg_LaneReset,
            Ctrl_LaneReset          => Ctrl_LaneReset,
            Ctrl_TxOnly             => Ctrl_TxOnly,
            Ctrl_RxOnly             => Ctrl_RxOnly,
            Ctrl_FarEndActive       => Ctrl_FarEndActive,
            Ctrl_NearCapability     => Ctrl_NearCapability,
            Ctrl_State              => State,
            Ctrl_FarCapability      => FarCap,
            Ctrl_FarCapabilityValid => Ctrl_FarCapabilityValid,
            Phy_NoSignal            => NoSignal,
            Phy_TxEnable            => Phy_TxEnable,
            Phy_RxEnable            => Phy_RxEnable,
            Phy_CdrEnable           => Phy_CdrEnable,
            Phy_RxInvert            => Phy_RxInvert,
            Tx_Mode                 => TxMode,
            Tx_Capability           => TxCapability,
            Tx_LosCause             => TxLosCause,
            Tx_Init3Sent            => Init3Sent,
            Tx_StandbySent          => StandbySent,
            Tx_LostSignalSent       => LostSent,
            Rx_SyncReset            => SyncReset,
            Rx_Active               => Active,
            Rx_ErrClear             => ErrClear,
            Rx_Word                 => EvWord,
            Rx_RxErr                => EvRxErr,
            Rx_Init1                => EvInit1,
            Rx_Init2                => EvInit2,
            Rx_InvInit1             => EvInvInit1,
            Rx_InvInit2             => EvInvInit2,
            Rx_Init3                => EvInit3,
            Rx_Standby              => EvStandby,
            Rx_LostSignal           => EvLostSig,
            Rx_Comma                => EvComma,
            Rx_Skip                 => EvSkip,
            Rx_Param                => EvParam,
            Rx_ErrOverflow          => ErrOverflow,
            Stat_Timeout            => Stat_Timeout,
            Stat_RxPolarity         => Stat_RxPolarity
        );

    Ctrl_State         <= State;
    Stat_State         <= State;
    Ctrl_FarCapability <= FarCap;
    Stat_FarCapability <= FarCap;

    -----------------------------------------------------------------------------------------------
    -- LN-2: lane transmitter
    -----------------------------------------------------------------------------------------------
    i_tx : entity work.ofb_lane_tx
        generic map (
            InitPrbsWords_g     => InitPrbsWords_g,
            SkipIntervalWords_g => SkipIntervalWords_g,
            SkipExternal_g      => SkipExternal_g
        )
        port map (
            Clk                => Clk,
            Rst                => Rst,
            Ctrl_Mode          => TxMode,
            Ctrl_SkipReq       => Ctrl_SkipReq,
            Ctrl_Capability    => TxCapability,
            Ctrl_LosCause      => TxLosCause,
            Ctrl_StandbyReason => Cfg_StandbyReason,
            In_Data            => TxWord_Data,
            In_K               => TxWord_K,
            In_Valid           => TxWord_Valid,
            In_Ready           => TxWord_Ready,
            Out_Data           => LaneTxData,
            Out_K              => LaneTxK,
            Ev_Init3Sent       => Init3Sent,
            Ev_StandbySent     => StandbySent,
            Ev_LostSignalSent  => LostSent
        );

    -----------------------------------------------------------------------------------------------
    -- LN-3: lane receiver
    -----------------------------------------------------------------------------------------------
    i_rx : entity work.ofb_lane_rx
        generic map (
            RxErrLeakWords_g => RxErrLeakWords_g
        )
        port map (
            Clk                => Clk,
            Rst                => Rst,
            Ctrl_SyncReset     => SyncReset,
            Ctrl_Active        => Active,
            Ctrl_RxErrClear    => ErrClear,
            In_Data            => LaneRxData,
            In_K               => LaneRxK,
            In_CodeErr         => LaneRxCodeErr,
            In_DispErr         => LaneRxDispErr,
            In_Valid           => LaneRxValid,
            Out_Data           => RxWord_Data,
            Out_K              => RxWord_K,
            Out_Valid          => RxWord_Valid,
            Ev_Word            => EvWord,
            Ev_RxErr           => EvRxErr,
            Ev_Init1           => EvInit1,
            Ev_Init2           => EvInit2,
            Ev_InvInit1        => EvInvInit1,
            Ev_InvInit2        => EvInvInit2,
            Ev_Init3           => EvInit3,
            Ev_Standby         => EvStandby,
            Ev_LostSignal      => EvLostSig,
            Ev_Comma           => EvComma,
            Ev_Skip            => EvSkip,
            Ev_Param           => EvParam,
            Stat_RxErrCount    => Stat_RxErrCount,
            Stat_RxErrOverflow => ErrOverflow,
            Ev_RxErrOverflow   => Stat_RxErrOverflow
        );

    Stat_FarStandby          <= EvStandby;
    Stat_FarStandbyReason    <= EvParam;
    Stat_FarLostSignal       <= EvLostSig;
    Stat_FarLostSignalReason <= EvParam;

    -----------------------------------------------------------------------------------------------
    -- LN-4: parallel loopback
    -----------------------------------------------------------------------------------------------
    i_loopback : entity work.ofb_lane_loopback
        port map (
            Cfg_NearLoopback => Cfg_NearLoopback,
            Cfg_FarLoopback  => Cfg_FarLoopback,
            LaneTx_Data      => LaneTxData,
            LaneTx_K         => LaneTxK,
            LaneRx_Data      => LaneRxData,
            LaneRx_K         => LaneRxK,
            LaneRx_CodeErr   => LaneRxCodeErr,
            LaneRx_DispErr   => LaneRxDispErr,
            LaneRx_Valid     => LaneRxValid,
            PhyTx_Data       => PhyTx_Data,
            PhyTx_K          => PhyTx_K,
            PhyRx_Data       => PhyRx_Data,
            PhyRx_K          => PhyRx_K,
            PhyRx_CodeErr    => PhyRx_CodeErr,
            PhyRx_DispErr    => PhyRx_DispErr,
            PhyRx_Valid      => PhyRx_Valid
        );

end architecture;

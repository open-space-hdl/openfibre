---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- OpenFibre core: SpaceFibre node interface (ECSS-E-ST-50-11C) from the AXI4-Stream ports of the
-- virtual channels and broadcast messages down to the symbol stream of the Physical adapters, with
-- the Management Information Base on AXI4-Lite. This issue implements one lane.
--
-- Documentation: hdl/ofb_core/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library olo;

library work;
    use work.ofb_pkg.all;
    use work.ofb_lane_pkg.all;
    use work.ofb_ml_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_core is
    generic (
        NumVc_g          : positive range 1 to 32 := 8;
        NumLanes_g       : positive range 1 to 4  := 1;
        LaneClkFreq_g    : real                   := 156.25e6;
        VcOutDepth_g     : positive               := 128;
        VcInDepth_g      : positive               := 256;
        ErbWords_g       : positive               := 512;
        InitPrbsWords_g  : natural range 0 to 64  := 64
    );
    port (
        -- Asynchronous reset (high active), clocks
        Rst               : in    std_logic;
        UserClk           : in    std_logic;
        CoreClk           : in    std_logic;
        LaneClk           : in    std_logic;
        MgmtClk           : in    std_logic;
        -- Virtual channels (UserClk, TUSER: K flag per character)
        S_Vc_TData        : in    std_logic_vector(32*NumVc_g-1 downto 0);
        S_Vc_TUser        : in    std_logic_vector(4*NumVc_g-1 downto 0);
        S_Vc_TValid       : in    std_logic_vector(NumVc_g-1 downto 0);
        S_Vc_TReady       : out   std_logic_vector(NumVc_g-1 downto 0);
        M_Vc_TData        : out   std_logic_vector(32*NumVc_g-1 downto 0);
        M_Vc_TUser        : out   std_logic_vector(4*NumVc_g-1 downto 0);
        M_Vc_TValid       : out   std_logic_vector(NumVc_g-1 downto 0);
        M_Vc_TReady       : in    std_logic_vector(NumVc_g-1 downto 0);
        -- Broadcast messages (UserClk, TUSER: channel 7:0, B_TYPE 15:8, DELAYED 16, LATE 17)
        S_Bc_TData        : in    std_logic_vector(63 downto 0);
        S_Bc_TUser        : in    std_logic_vector(16 downto 0);
        S_Bc_TValid       : in    std_logic;
        S_Bc_TReady       : out   std_logic;
        M_Bc_TData        : out   std_logic_vector(63 downto 0);
        M_Bc_TUser        : out   std_logic_vector(17 downto 0);
        M_Bc_TValid       : out   std_logic;
        M_Bc_TReady       : in    std_logic;
        -- SCHEDULE.request (UserClk)
        S_Sched_Slot      : in    std_logic_vector(5 downto 0) := (others => '0');
        S_Sched_Valid     : in    std_logic                    := '0';
        -- Management Information Base (MgmtClk)
        S_AxiLite_ArAddr  : in    std_logic_vector(11 downto 0);
        S_AxiLite_ArValid : in    std_logic;
        S_AxiLite_ArReady : out   std_logic;
        S_AxiLite_AwAddr  : in    std_logic_vector(11 downto 0);
        S_AxiLite_AwValid : in    std_logic;
        S_AxiLite_AwReady : out   std_logic;
        S_AxiLite_WData   : in    std_logic_vector(31 downto 0);
        S_AxiLite_WStrb   : in    std_logic_vector(3 downto 0);
        S_AxiLite_WValid  : in    std_logic;
        S_AxiLite_WReady  : out   std_logic;
        S_AxiLite_BResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_BValid  : out   std_logic;
        S_AxiLite_BReady  : in    std_logic;
        S_AxiLite_RData   : out   std_logic_vector(31 downto 0);
        S_AxiLite_RResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_RValid  : out   std_logic;
        S_AxiLite_RReady  : in    std_logic;
        Irq               : out   std_logic;
        -- Physical adapters (LaneClk): symbol streams and control per lane
        PhyTx_Data        : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        PhyTx_K           : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        PhyRx_Data        : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        PhyRx_K           : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        PhyRx_CodeErr     : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        PhyRx_DispErr     : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        PhyRx_Valid       : in    std_logic_vector(NumLanes_g-1 downto 0);
        Phy_TxEnable      : out   std_logic_vector(NumLanes_g-1 downto 0);
        Phy_RxEnable      : out   std_logic_vector(NumLanes_g-1 downto 0);
        Phy_CdrEnable     : out   std_logic_vector(NumLanes_g-1 downto 0);
        Phy_RxInvert      : out   std_logic_vector(NumLanes_g-1 downto 0);
        Phy_NoSignal      : in    std_logic_vector(NumLanes_g-1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_core is

    -- Resets per domain
    signal UserRst : std_logic;
    signal CoreRst : std_logic;
    signal LaneRst : std_logic;
    signal MgmtRst : std_logic;

    -- Network interface to Data Link layer
    signal TxVcData   : std_logic_vector(32*NumVc_g-1 downto 0);
    signal TxVcK      : std_logic_vector(4*NumVc_g-1 downto 0);
    signal TxVcValid  : std_logic_vector(NumVc_g-1 downto 0);
    signal TxVcReady  : std_logic_vector(NumVc_g-1 downto 0);
    signal RxVcData   : std_logic_vector(32*NumVc_g-1 downto 0);
    signal RxVcK      : std_logic_vector(4*NumVc_g-1 downto 0);
    signal RxVcValid  : std_logic_vector(NumVc_g-1 downto 0);
    signal RxVcReady  : std_logic_vector(NumVc_g-1 downto 0);
    signal TxBcData   : std_logic_vector(63 downto 0);
    signal TxBcCh     : Char_t;
    signal TxBcType   : Char_t;
    signal TxBcDel    : std_logic;
    signal TxBcValid  : std_logic;
    signal TxBcReady  : std_logic;
    signal RxBcData   : std_logic_vector(63 downto 0);
    signal RxBcCh     : Char_t;
    signal RxBcType   : Char_t;
    signal RxBcDel    : std_logic;
    signal RxBcLate   : std_logic;
    signal RxBcValid  : std_logic;
    signal RxBcReady  : std_logic;
    signal NiFrameErr : std_logic_vector(NumVc_g-1 downto 0);
    signal SchedSlot  : std_logic_vector(5 downto 0);
    signal SchedValid : std_logic;
    signal RegWr      : std_logic;
    signal RegAddr    : std_logic_vector(11 downto 0);
    signal RegData    : std_logic_vector(31 downto 0);
    signal StBwOver   : std_logic_vector(NumVc_g-1 downto 0);
    signal StBwUnder  : std_logic_vector(NumVc_g-1 downto 0);
    signal StTimeSlot : std_logic_vector(5 downto 0);

    -- Data Link layer to crossing
    signal DlTxData  : std_logic_vector(32*NumLanes_g-1 downto 0);
    signal DlTxK     : std_logic_vector(4*NumLanes_g-1 downto 0);
    signal DlTxMask  : std_logic_vector(NumLanes_g-1 downto 0);
    signal DlTxRepl  : std_logic;
    signal DlTxValid : std_logic;
    signal DlTxReady : std_logic;
    signal DlRxData  : std_logic_vector(32*NumLanes_g-1 downto 0);
    signal DlRxK     : std_logic_vector(4*NumLanes_g-1 downto 0);
    signal DlRxMask  : std_logic_vector(NumLanes_g-1 downto 0);
    signal DlRxCrc   : std_logic;
    signal DlRxValid : std_logic;
    signal DlLinkRst : std_logic;
    signal DlLaneRst : std_logic;
    signal DlNearCap : Char_t;
    signal DlFarCap  : Char_t;
    signal DlFarCapV : std_logic;
    signal DlFarIdle : std_logic;
    signal DlActive  : std_logic;

    -- Crossing to Multi-Lane layer
    signal MlTxData  : std_logic_vector(32*NumLanes_g-1 downto 0);
    signal MlTxK     : std_logic_vector(4*NumLanes_g-1 downto 0);
    signal MlTxMask  : std_logic_vector(NumLanes_g-1 downto 0);
    signal MlTxRepl  : std_logic;
    signal MlTxValid : std_logic;
    signal MlTxReady : std_logic;
    signal MlRxData  : std_logic_vector(32*NumLanes_g-1 downto 0);
    signal MlRxK     : std_logic_vector(4*NumLanes_g-1 downto 0);
    signal MlRxMask  : std_logic_vector(NumLanes_g-1 downto 0);
    signal MlRxCrc   : std_logic;
    signal MlRxValid : std_logic;
    signal MlLinkRst : std_logic;
    signal MlLaneRst : std_logic;
    signal MlNearCap : Char_t;
    signal MlFarCap  : Char_t;
    signal MlFarCapV : std_logic;
    signal MlFarIdle : std_logic;
    signal MlActive  : std_logic;

    -- Multi-Lane layer to Lane layers
    signal LaneTxData  : std_logic_vector(32*NumLanes_g-1 downto 0);
    signal LaneTxK     : std_logic_vector(4*NumLanes_g-1 downto 0);
    signal LaneTxValid : std_logic_vector(NumLanes_g-1 downto 0);
    signal LaneTxReady : std_logic_vector(NumLanes_g-1 downto 0);
    signal LaneRxData  : std_logic_vector(32*NumLanes_g-1 downto 0);
    signal LaneRxK     : std_logic_vector(4*NumLanes_g-1 downto 0);
    signal LaneRxValid : std_logic_vector(NumLanes_g-1 downto 0);
    signal LaneReset   : std_logic_vector(NumLanes_g-1 downto 0);
    signal LaneTxOnly  : std_logic_vector(NumLanes_g-1 downto 0);
    signal LaneRxOnly  : std_logic_vector(NumLanes_g-1 downto 0);
    signal LaneFarAct  : std_logic_vector(NumLanes_g-1 downto 0);
    signal LaneNearCap : std_logic_vector(8*NumLanes_g-1 downto 0);
    signal LaneState   : std_logic_vector(4*NumLanes_g-1 downto 0);
    signal LaneFarCap  : std_logic_vector(8*NumLanes_g-1 downto 0);
    signal LaneCapV    : std_logic_vector(NumLanes_g-1 downto 0);
    signal DataSending : std_logic_vector(NumLanes_g-1 downto 0);
    signal DataRecv    : std_logic_vector(NumLanes_g-1 downto 0);
    signal AlignState  : AlignState_t;

    -- Data Link layer configuration and status
    signal CfgScrambled : std_logic;
    signal CfgBcInt     : std_logic_vector(15 downto 0);
    signal CfgLinkRst   : std_logic;
    signal CfgIfRst     : std_logic;
    signal StLinkState  : std_logic_vector(1 downto 0);
    signal StRxErrState : std_logic_vector(1 downto 0);
    signal StWordId     : std_logic_vector(2 downto 0);
    signal StErbEmpty   : std_logic;
    signal StHasCredit  : std_logic_vector(NumVc_g-1 downto 0);
    signal EvCrc16      : std_logic;
    signal EvCrc8       : std_logic;
    signal EvFrame      : std_logic;
    signal EvSeq        : std_logic;
    signal EvRetry      : std_logic;
    signal EvProt       : std_logic;
    signal EvFarRst     : std_logic;
    signal EvBcDisc     : std_logic;
    signal EvInOvf      : std_logic_vector(NumVc_g-1 downto 0);
    signal EvCrOvf      : std_logic_vector(NumVc_g-1 downto 0);

    -- Lane configuration and status
    signal CfgLaneStart : std_logic_vector(NumLanes_g-1 downto 0);
    signal CfgAutoStart : std_logic_vector(NumLanes_g-1 downto 0);
    signal CfgLaneReset : std_logic_vector(NumLanes_g-1 downto 0);
    signal CfgNearLb    : std_logic_vector(NumLanes_g-1 downto 0);
    signal CfgFarLb     : std_logic_vector(NumLanes_g-1 downto 0);
    signal CfgReason    : std_logic_vector(8*NumLanes_g-1 downto 0);
    signal StLaneState  : std_logic_vector(4*NumLanes_g-1 downto 0);
    signal StRxErrCount : std_logic_vector(8*NumLanes_g-1 downto 0);
    signal StRxPolarity : std_logic_vector(NumLanes_g-1 downto 0);
    signal StFarCap     : std_logic_vector(8*NumLanes_g-1 downto 0);
    signal StStbyReason : std_logic_vector(8*NumLanes_g-1 downto 0);
    signal StLostReason : std_logic_vector(8*NumLanes_g-1 downto 0);
    signal EvRxErrOvf   : std_logic_vector(NumLanes_g-1 downto 0);
    signal EvTimeout    : std_logic_vector(NumLanes_g-1 downto 0);
    signal EvFarStby    : std_logic_vector(NumLanes_g-1 downto 0);
    signal EvFarLost    : std_logic_vector(NumLanes_g-1 downto 0);

begin

    assert NumLanes_g = 1
        report "ofb_core: only NumLanes_g = 1 is implemented"
        severity failure;

    -----------------------------------------------------------------------------------------------
    -- Resets per clock domain (MG-4)
    -----------------------------------------------------------------------------------------------
    i_rst_user : entity olo.olo_base_reset_gen
        port map (
            Clk    => UserClk,
            RstOut => UserRst,
            RstIn  => Rst
        );

    i_rst_core : entity olo.olo_base_reset_gen
        port map (
            Clk    => CoreClk,
            RstOut => CoreRst,
            RstIn  => Rst
        );

    i_rst_lane : entity olo.olo_base_reset_gen
        port map (
            Clk    => LaneClk,
            RstOut => LaneRst,
            RstIn  => Rst
        );

    i_rst_mgmt : entity olo.olo_base_reset_gen
        port map (
            Clk    => MgmtClk,
            RstOut => MgmtRst,
            RstIn  => Rst
        );

    -----------------------------------------------------------------------------------------------
    -- Network interface
    -----------------------------------------------------------------------------------------------
    i_ni : entity work.ofb_ni
        generic map (
            NumVc_g => NumVc_g
        )
        port map (
            Clk           => UserClk,
            Rst           => UserRst,
            S_Vc_TData    => S_Vc_TData,
            S_Vc_TUser    => S_Vc_TUser,
            S_Vc_TValid   => S_Vc_TValid,
            S_Vc_TReady   => S_Vc_TReady,
            M_Vc_TData    => M_Vc_TData,
            M_Vc_TUser    => M_Vc_TUser,
            M_Vc_TValid   => M_Vc_TValid,
            M_Vc_TReady   => M_Vc_TReady,
            S_Bc_TData    => S_Bc_TData,
            S_Bc_TUser    => S_Bc_TUser,
            S_Bc_TValid   => S_Bc_TValid,
            S_Bc_TReady   => S_Bc_TReady,
            M_Bc_TData    => M_Bc_TData,
            M_Bc_TUser    => M_Bc_TUser,
            M_Bc_TValid   => M_Bc_TValid,
            M_Bc_TReady   => M_Bc_TReady,
            S_Sched_Slot  => S_Sched_Slot,
            S_Sched_Valid => S_Sched_Valid,
            TxVc_Data     => TxVcData,
            TxVc_K        => TxVcK,
            TxVc_Valid    => TxVcValid,
            TxVc_Ready    => TxVcReady,
            RxVc_Data     => RxVcData,
            RxVc_K        => RxVcK,
            RxVc_Valid    => RxVcValid,
            RxVc_Ready    => RxVcReady,
            TxBc_Data     => TxBcData,
            TxBc_Channel  => TxBcCh,
            TxBc_Type     => TxBcType,
            TxBc_Delayed  => TxBcDel,
            TxBc_Valid    => TxBcValid,
            TxBc_Ready    => TxBcReady,
            RxBc_Data     => RxBcData,
            RxBc_Channel  => RxBcCh,
            RxBc_Type     => RxBcType,
            RxBc_Delayed  => RxBcDel,
            RxBc_Late     => RxBcLate,
            RxBc_Valid    => RxBcValid,
            RxBc_Ready    => RxBcReady,
            TxSched_Slot  => SchedSlot,
            TxSched_Valid => SchedValid,
            Ev_FrameErr   => NiFrameErr
        );

    -----------------------------------------------------------------------------------------------
    -- Data Link layer
    -----------------------------------------------------------------------------------------------
    i_dl : entity work.ofb_dl
        generic map (
            NumVc_g      => NumVc_g,
            NumLanes_g   => NumLanes_g,
            VcOutDepth_g => VcOutDepth_g,
            VcInDepth_g  => VcInDepth_g,
            ErbWords_g   => ErbWords_g
        )
        port map (
            Clk                   => CoreClk,
            Rst                   => CoreRst,
            UserClk               => UserClk,
            UserRst               => UserRst,
            TxVc_Data             => TxVcData,
            TxVc_K                => TxVcK,
            TxVc_Valid            => TxVcValid,
            TxVc_Ready            => TxVcReady,
            RxVc_Data             => RxVcData,
            RxVc_K                => RxVcK,
            RxVc_Valid            => RxVcValid,
            RxVc_Ready            => RxVcReady,
            TxBc_Data             => TxBcData,
            TxBc_Channel          => TxBcCh,
            TxBc_Type             => TxBcType,
            TxBc_Delayed          => TxBcDel,
            TxBc_Valid            => TxBcValid,
            TxBc_Ready            => TxBcReady,
            RxBc_Data             => RxBcData,
            RxBc_Channel          => RxBcCh,
            RxBc_Type             => RxBcType,
            RxBc_Delayed          => RxBcDel,
            RxBc_Late             => RxBcLate,
            RxBc_Valid            => RxBcValid,
            RxBc_Ready            => RxBcReady,
            Sched_TimeSlot        => SchedSlot,
            Sched_Valid           => SchedValid,
            TxRow_Data            => DlTxData,
            TxRow_K               => DlTxK,
            TxRow_Mask            => DlTxMask,
            TxRow_Replicate       => DlTxRepl,
            TxRow_Valid           => DlTxValid,
            TxRow_Ready           => DlTxReady,
            RxRow_Data            => DlRxData,
            RxRow_K               => DlRxK,
            RxRow_Mask            => DlRxMask,
            RxRow_CrcErr          => DlRxCrc,
            RxRow_Valid           => DlRxValid,
            Ml_LinkReset          => DlLinkRst,
            Ml_LaneReset          => DlLaneRst,
            Ml_NearCapability     => DlNearCap,
            Ml_FarCapability      => DlFarCap,
            Ml_FarCapabilityValid => DlFarCapV,
            Ml_FarCapabilityIdle  => DlFarIdle,
            Ml_LaneActive         => DlActive,
            Cfg_DataScrambled     => CfgScrambled,
            Cfg_LinkReset         => CfgLinkRst,
            Cfg_InterfaceReset    => CfgIfRst,
            Cfg_BcInterval        => CfgBcInt,
            Reg_Wr                => RegWr,
            Reg_Addr              => RegAddr,
            Reg_Data              => RegData,
            Stat_HasCredit        => StHasCredit,
            Ev_CreditOverflow     => EvCrOvf,
            Ev_InputOverflow      => EvInOvf,
            Ev_Crc16Err           => EvCrc16,
            Ev_Crc8Err            => EvCrc8,
            Ev_FrameErr           => EvFrame,
            Ev_SeqErr             => EvSeq,
            Ev_Retry              => EvRetry,
            Ev_ProtocolError      => EvProt,
            Ev_FarEndLinkReset    => EvFarRst,
            Ev_BcDiscard          => EvBcDisc,
            Ctrl_ConfigReset      => open,
            Stat_ErbEmpty         => StErbEmpty,
            Stat_LinkResetState   => StLinkState,
            Stat_RxErrState       => StRxErrState,
            Stat_WordIdState      => StWordId,
            Stat_BwOver           => StBwOver,
            Stat_BwUnder          => StBwUnder,
            Stat_TimeSlot         => StTimeSlot
        );

    -----------------------------------------------------------------------------------------------
    -- Crossing between the core clock and the lane clock
    -----------------------------------------------------------------------------------------------
    i_cc : entity work.ofb_core_cc
        generic map (
            NumLanes_g => NumLanes_g
        )
        port map (
            CoreClk               => CoreClk,
            CoreRst               => CoreRst,
            Dl_TxRow_Data         => DlTxData,
            Dl_TxRow_K            => DlTxK,
            Dl_TxRow_Mask         => DlTxMask,
            Dl_TxRow_Replicate    => DlTxRepl,
            Dl_TxRow_Valid        => DlTxValid,
            Dl_TxRow_Ready        => DlTxReady,
            Dl_RxRow_Data         => DlRxData,
            Dl_RxRow_K            => DlRxK,
            Dl_RxRow_Mask         => DlRxMask,
            Dl_RxRow_CrcErr       => DlRxCrc,
            Dl_RxRow_Valid        => DlRxValid,
            Dl_LinkReset          => DlLinkRst,
            Dl_LaneReset          => DlLaneRst,
            Dl_NearCapability     => DlNearCap,
            Dl_FarCapability      => DlFarCap,
            Dl_FarCapabilityValid => DlFarCapV,
            Dl_FarCapabilityIdle  => DlFarIdle,
            Dl_LaneActive         => DlActive,
            LaneClk               => LaneClk,
            LaneRst               => LaneRst,
            Ml_TxRow_Data         => MlTxData,
            Ml_TxRow_K            => MlTxK,
            Ml_TxRow_Mask         => MlTxMask,
            Ml_TxRow_Replicate    => MlTxRepl,
            Ml_TxRow_Valid        => MlTxValid,
            Ml_TxRow_Ready        => MlTxReady,
            Ml_RxRow_Data         => MlRxData,
            Ml_RxRow_K            => MlRxK,
            Ml_RxRow_Mask         => MlRxMask,
            Ml_RxRow_CrcErr       => MlRxCrc,
            Ml_RxRow_Valid        => MlRxValid,
            Ml_LinkReset          => MlLinkRst,
            Ml_LaneReset          => MlLaneRst,
            Ml_NearCapability     => MlNearCap,
            Ml_FarCapability      => MlFarCap,
            Ml_FarCapabilityValid => MlFarCapV,
            Ml_FarCapabilityIdle  => MlFarIdle,
            Ml_LaneActive         => MlActive,
            Ev_RxOverflow         => open
        );

    -----------------------------------------------------------------------------------------------
    -- Multi-Lane layer
    -----------------------------------------------------------------------------------------------
    i_ml : entity work.ofb_multilane
        generic map (
            NumLanes_g => NumLanes_g
        )
        port map (
            Clk                     => LaneClk,
            Rst                     => LaneRst,
            TxRow_Data              => MlTxData,
            TxRow_K                 => MlTxK,
            TxRow_Mask              => MlTxMask,
            TxRow_Replicate         => MlTxRepl,
            TxRow_Valid             => MlTxValid,
            TxRow_Ready             => MlTxReady,
            RxRow_Data              => MlRxData,
            RxRow_K                 => MlRxK,
            RxRow_Mask              => MlRxMask,
            RxRow_CrcErr            => MlRxCrc,
            RxRow_Valid             => MlRxValid,
            Dl_LinkReset            => MlLinkRst,
            Dl_LaneReset            => MlLaneRst,
            Dl_NearCapability       => MlNearCap,
            Dl_FarCapability        => MlFarCap,
            Dl_FarCapabilityValid   => MlFarCapV,
            Dl_FarCapabilityIdle    => MlFarIdle,
            Dl_LaneActive           => MlActive,
            LaneTx_Data             => LaneTxData,
            LaneTx_K                => LaneTxK,
            LaneTx_Valid            => LaneTxValid,
            LaneTx_Ready            => LaneTxReady,
            LaneRx_Data             => LaneRxData,
            LaneRx_K                => LaneRxK,
            LaneRx_Valid            => LaneRxValid,
            Lane_Reset              => LaneReset,
            Lane_TxOnly             => LaneTxOnly,
            Lane_RxOnly             => LaneRxOnly,
            Lane_FarEndActive       => LaneFarAct,
            Lane_NearCapability     => LaneNearCap,
            Lane_State              => LaneState,
            Lane_FarCapability      => LaneFarCap,
            Lane_FarCapabilityValid => LaneCapV,
            Stat_DataSendingLanes   => DataSending,
            Stat_DataReceivingLanes => DataRecv,
            Stat_AlignState         => AlignState
        );

    -----------------------------------------------------------------------------------------------
    -- Lane layers
    -----------------------------------------------------------------------------------------------
    g_lane : for i in 0 to NumLanes_g-1 generate

        i_lane : entity work.ofb_lane
            generic map (
                ClkFrequency_g  => LaneClkFreq_g,
                InitPrbsWords_g => InitPrbsWords_g
            )
            port map (
                Clk                      => LaneClk,
                Rst                      => LaneRst,
                TxWord_Data              => LaneTxData(32*i+31 downto 32*i),
                TxWord_K                 => LaneTxK(4*i+3 downto 4*i),
                TxWord_Valid             => LaneTxValid(i),
                TxWord_Ready             => LaneTxReady(i),
                RxWord_Data              => LaneRxData(32*i+31 downto 32*i),
                RxWord_K                 => LaneRxK(4*i+3 downto 4*i),
                RxWord_Valid             => LaneRxValid(i),
                Ctrl_LaneReset           => LaneReset(i),
                Ctrl_TxOnly              => LaneTxOnly(i),
                Ctrl_RxOnly              => LaneRxOnly(i),
                Ctrl_FarEndActive        => LaneFarAct(i),
                Ctrl_NearCapability      => LaneNearCap(8*i+7 downto 8*i),
                Ctrl_State               => LaneState(4*i+3 downto 4*i),
                Ctrl_FarCapability       => LaneFarCap(8*i+7 downto 8*i),
                Ctrl_FarCapabilityValid  => LaneCapV(i),
                PhyTx_Data               => PhyTx_Data(32*i+31 downto 32*i),
                PhyTx_K                  => PhyTx_K(4*i+3 downto 4*i),
                PhyRx_Data               => PhyRx_Data(32*i+31 downto 32*i),
                PhyRx_K                  => PhyRx_K(4*i+3 downto 4*i),
                PhyRx_CodeErr            => PhyRx_CodeErr(4*i+3 downto 4*i),
                PhyRx_DispErr            => PhyRx_DispErr(4*i+3 downto 4*i),
                PhyRx_Valid              => PhyRx_Valid(i),
                Phy_TxEnable             => Phy_TxEnable(i),
                Phy_RxEnable             => Phy_RxEnable(i),
                Phy_CdrEnable            => Phy_CdrEnable(i),
                Phy_RxInvert             => Phy_RxInvert(i),
                Phy_NoSignal             => Phy_NoSignal(i),
                Cfg_LaneStart            => CfgLaneStart(i),
                Cfg_AutoStart            => CfgAutoStart(i),
                Cfg_LaneReset            => CfgLaneReset(i),
                Cfg_NearLoopback         => CfgNearLb(i),
                Cfg_FarLoopback          => CfgFarLb(i),
                Cfg_StandbyReason        => CfgReason(8*i+7 downto 8*i),
                Stat_State               => StLaneState(4*i+3 downto 4*i),
                Stat_RxErrCount          => StRxErrCount(8*i+7 downto 8*i),
                Stat_RxErrOverflow       => EvRxErrOvf(i),
                Stat_Timeout             => EvTimeout(i),
                Stat_FarStandby          => EvFarStby(i),
                Stat_FarStandbyReason    => StStbyReason(8*i+7 downto 8*i),
                Stat_FarLostSignal       => EvFarLost(i),
                Stat_FarLostSignalReason => StLostReason(8*i+7 downto 8*i),
                Stat_FarCapability       => StFarCap(8*i+7 downto 8*i),
                Stat_RxPolarity          => StRxPolarity(i)
            );

    end generate;

    -----------------------------------------------------------------------------------------------
    -- Management Information Base
    -----------------------------------------------------------------------------------------------
    i_mib : entity work.ofb_mib
        generic map (
            NumVc_g    => NumVc_g,
            NumLanes_g => NumLanes_g
        )
        port map (
            Clk                   => MgmtClk,
            Rst                   => MgmtRst,
            S_AxiLite_ArAddr      => S_AxiLite_ArAddr,
            S_AxiLite_ArValid     => S_AxiLite_ArValid,
            S_AxiLite_ArReady     => S_AxiLite_ArReady,
            S_AxiLite_AwAddr      => S_AxiLite_AwAddr,
            S_AxiLite_AwValid     => S_AxiLite_AwValid,
            S_AxiLite_AwReady     => S_AxiLite_AwReady,
            S_AxiLite_WData       => S_AxiLite_WData,
            S_AxiLite_WStrb       => S_AxiLite_WStrb,
            S_AxiLite_WValid      => S_AxiLite_WValid,
            S_AxiLite_WReady      => S_AxiLite_WReady,
            S_AxiLite_BResp       => S_AxiLite_BResp,
            S_AxiLite_BValid      => S_AxiLite_BValid,
            S_AxiLite_BReady      => S_AxiLite_BReady,
            S_AxiLite_RData       => S_AxiLite_RData,
            S_AxiLite_RResp       => S_AxiLite_RResp,
            S_AxiLite_RValid      => S_AxiLite_RValid,
            S_AxiLite_RReady      => S_AxiLite_RReady,
            Irq                   => Irq,
            CoreClk               => CoreClk,
            CoreRst               => CoreRst,
            Dl_DataScrambled      => CfgScrambled,
            Dl_BcInterval         => CfgBcInt,
            Dl_LinkReset          => CfgLinkRst,
            Dl_InterfaceReset     => CfgIfRst,
            Dl_LinkResetState     => StLinkState,
            Dl_RxErrState         => StRxErrState,
            Dl_WordIdState        => StWordId,
            Dl_ErbEmpty           => StErbEmpty,
            Dl_HasCredit          => StHasCredit,
            Dl_EvCrc16Err         => EvCrc16,
            Dl_EvCrc8Err          => EvCrc8,
            Dl_EvFrameErr         => EvFrame,
            Dl_EvSeqErr           => EvSeq,
            Dl_EvRetry            => EvRetry,
            Dl_EvProtocolError    => EvProt,
            Dl_EvFarEndLinkReset  => EvFarRst,
            Dl_EvBcDiscard        => EvBcDisc,
            Dl_EvInputOverflow    => EvInOvf,
            Dl_EvCreditOverflow   => EvCrOvf,
            Dl_BwOver             => StBwOver,
            Dl_BwUnder            => StBwUnder,
            Dl_TimeSlot           => StTimeSlot,
            Dl_RegWr              => RegWr,
            Dl_RegAddr            => RegAddr,
            Dl_RegData            => RegData,
            LaneClk               => LaneClk,
            LaneRst               => LaneRst,
            Lane_Start            => CfgLaneStart,
            Lane_AutoStart        => CfgAutoStart,
            Lane_Reset            => CfgLaneReset,
            Lane_NearLoopback     => CfgNearLb,
            Lane_FarLoopback      => CfgFarLb,
            Lane_StandbyReason    => CfgReason,
            Lane_State            => StLaneState,
            Lane_RxPolarity       => StRxPolarity,
            Lane_NoSignal         => Phy_NoSignal,
            Lane_RxErrCount       => StRxErrCount,
            Lane_FarCapability    => StFarCap,
            Lane_FarStandbyReason => StStbyReason,
            Lane_FarLostReason    => StLostReason,
            Lane_EvRxErrOverflow  => EvRxErrOvf,
            Lane_EvTimeout        => EvTimeout,
            Lane_EvFarStandby     => EvFarStby,
            Lane_EvFarLostSignal  => EvFarLost,
            Ml_DataSending        => DataSending,
            Ml_DataReceiving      => DataRecv,
            Ml_AlignState         => AlignState,
            UserClk               => UserClk,
            UserRst               => UserRst,
            Ni_EvFrameErr         => NiFrameErr
        );

end architecture;

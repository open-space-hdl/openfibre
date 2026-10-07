---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Management Information Base of OpenFibre (MG-1, MG-2, ECSS 5.9): register file with AXI4-Lite
-- access, crossings to and from the clock domains of the layers, sticky error flags, event
-- counters and interrupt.
--
-- Documentation: hdl/ofb_mib/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_regs_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_mib is
    generic (
        NumVc_g    : positive range 1 to 32 := 8;
        NumLanes_g : positive range 1 to 4  := 1;
        NumPrio_g  : positive range 2 to 16 := 4
    );
    port (
        -- Management clock domain
        Clk                    : in    std_logic;
        Rst                    : in    std_logic;
        S_AxiLite_ArAddr       : in    std_logic_vector(11 downto 0);
        S_AxiLite_ArValid      : in    std_logic;
        S_AxiLite_ArReady      : out   std_logic;
        S_AxiLite_AwAddr       : in    std_logic_vector(11 downto 0);
        S_AxiLite_AwValid      : in    std_logic;
        S_AxiLite_AwReady      : out   std_logic;
        S_AxiLite_WData        : in    std_logic_vector(31 downto 0);
        S_AxiLite_WStrb        : in    std_logic_vector(3 downto 0);
        S_AxiLite_WValid       : in    std_logic;
        S_AxiLite_WReady       : out   std_logic;
        S_AxiLite_BResp        : out   std_logic_vector(1 downto 0);
        S_AxiLite_BValid       : out   std_logic;
        S_AxiLite_BReady       : in    std_logic;
        S_AxiLite_RData        : out   std_logic_vector(31 downto 0);
        S_AxiLite_RResp        : out   std_logic_vector(1 downto 0);
        S_AxiLite_RValid       : out   std_logic;
        S_AxiLite_RReady       : in    std_logic;
        Irq                    : out   std_logic;
        -- Core clock domain: Data Link layer
        CoreClk                : in    std_logic;
        CoreRst                : in    std_logic;
        Dl_DataScrambled       : out   std_logic;
        Dl_BcInterval          : out   std_logic_vector(15 downto 0);
        Dl_LinkReset           : out   std_logic;
        Dl_InterfaceReset      : out   std_logic;
        Dl_LinkResetState      : in    std_logic_vector(1 downto 0);
        Dl_RxErrState          : in    std_logic_vector(1 downto 0);
        Dl_WordIdState         : in    std_logic_vector(2 downto 0);
        Dl_ErbEmpty            : in    std_logic;
        Dl_HasCredit           : in    std_logic_vector(NumVc_g-1 downto 0);
        Dl_EvCrc16Err          : in    std_logic;
        Dl_EvCrc8Err           : in    std_logic;
        Dl_EvFrameErr          : in    std_logic;
        Dl_EvSeqErr            : in    std_logic;
        Dl_EvRetry             : in    std_logic;
        Dl_EvProtocolError     : in    std_logic;
        Dl_EvFarEndLinkReset   : in    std_logic;
        Dl_EvBcDiscard         : in    std_logic;
        Dl_EvInputOverflow     : in    std_logic_vector(NumVc_g-1 downto 0);
        Dl_EvCreditOverflow    : in    std_logic_vector(NumVc_g-1 downto 0);
        Dl_BwOver              : in    std_logic_vector(NumVc_g-1 downto 0);
        Dl_BwUnder             : in    std_logic_vector(NumVc_g-1 downto 0);
        Dl_TimeSlot            : in    std_logic_vector(5 downto 0);
        Dl_RegWr               : out   std_logic; -- Register writes of the quality of service
        Dl_RegAddr             : out   std_logic_vector(11 downto 0);
        Dl_RegData             : out   std_logic_vector(31 downto 0);
        Dl_MaxDataLanes        : out   std_logic_vector(2 downto 0);
        -- Lane clock domain: Multi-Lane layer, Lane layers, Physical adapters
        LaneClk                : in    std_logic;
        LaneRst                : in    std_logic;
        Lane_Start             : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_AutoStart         : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_Reset             : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_NearLoopback      : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_FarLoopback       : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_StandbyReason     : out   std_logic_vector(8*NumLanes_g-1 downto 0);
        Phy_SerialNearLoopback : out   std_logic_vector(NumLanes_g-1 downto 0);
        Phy_SerialFarLoopback  : out   std_logic_vector(NumLanes_g-1 downto 0);
        -- PRBS test of the Physical adapters: patterns (0: off), single-cycle commands, checker status
        Phy_PrbsTxSel          : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        Phy_PrbsRxSel          : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        Phy_PrbsForceErr       : out   std_logic_vector(NumLanes_g-1 downto 0);
        Phy_PrbsCntReset       : out   std_logic_vector(NumLanes_g-1 downto 0);
        Phy_PrbsErr            : in    std_logic_vector(NumLanes_g-1 downto 0)      := (others => '0');
        Phy_PrbsLocked         : in    std_logic_vector(NumLanes_g-1 downto 0)      := (others => '0');
        Lane_State             : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        Lane_RxPolarity        : in    std_logic_vector(NumLanes_g-1 downto 0);
        Lane_NoSignal          : in    std_logic_vector(NumLanes_g-1 downto 0);
        Phy_BitSync            : in    std_logic_vector(NumLanes_g-1 downto 0)      := (others => '0');
        Lane_RxErrCount        : in    std_logic_vector(8*NumLanes_g-1 downto 0);
        Lane_FarCapability     : in    std_logic_vector(8*NumLanes_g-1 downto 0);
        Lane_FarStandbyReason  : in    std_logic_vector(8*NumLanes_g-1 downto 0);
        Lane_FarLostReason     : in    std_logic_vector(8*NumLanes_g-1 downto 0);
        Lane_EvRxErrOverflow   : in    std_logic_vector(NumLanes_g-1 downto 0);
        Lane_EvTimeout         : in    std_logic_vector(NumLanes_g-1 downto 0);
        Lane_EvFarStandby      : in    std_logic_vector(NumLanes_g-1 downto 0);
        Lane_EvFarLostSignal   : in    std_logic_vector(NumLanes_g-1 downto 0);
        Ml_DataSending         : in    std_logic_vector(NumLanes_g-1 downto 0);
        Ml_DataReceiving       : in    std_logic_vector(NumLanes_g-1 downto 0);
        Ml_AlignState          : in    std_logic_vector(1 downto 0);
        Ml_StatBypass          : in    std_logic                                    := '0';
        Ml_EvMisaligned        : in    std_logic                                    := '0';
        -- Receive row lost in the crossing to the core clock (lane clock, possible only with CoreClk slower
        -- than LaneClk)
        Ml_EvRxOverflow        : in    std_logic                                    := '0';
        Ml_TxEn                : out   std_logic_vector(NumLanes_g-1 downto 0);
        Ml_RxEn                : out   std_logic_vector(NumLanes_g-1 downto 0);
        Ml_MaxDataLanes        : out   std_logic_vector(2 downto 0);
        Ml_Bypass              : out   std_logic;
        -- User clock domain: Network interface
        UserClk                : in    std_logic;
        UserRst                : in    std_logic;
        Ni_EvFrameErr          : in    std_logic_vector(NumVc_g-1 downto 0);
        -- EDAC monitor (MG-3): SEC events in bits EccChannels_c-1:0, DED events above, in the
        -- domains of the read sides; injection commands (single, double) to the write sides
        Ecc_Core               : in    std_logic_vector(2*EccChannels_c-1 downto 0) := (others => '0');
        Ecc_User               : in    std_logic_vector(2*EccChannels_c-1 downto 0) := (others => '0');
        Ecc_Lane               : in    std_logic_vector(2*EccChannels_c-1 downto 0) := (others => '0');
        EccInj_Core            : out   std_logic_vector(2*EccChannels_c-1 downto 0);
        EccInj_User            : out   std_logic_vector(2*EccChannels_c-1 downto 0);
        EccInj_Lane            : out   std_logic_vector(2*EccChannels_c-1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_mib is

    constant Ch_c : positive := EccChannels_c;

    -- Widths of the crossing vectors
    constant CoreCfgW_c   : positive := 20;
    constant CoreStatW_c  : positive := 8 + 3 * NumVc_g + 6;
    constant CoreEvW_c    : positive := 8 + 2 * NumVc_g;
    constant LaneCfgW_c   : positive := 26;
    constant LaneStatW_c  : positive := 104;
    -- PRBS test: configuration bits of a lane (TX pattern, RX pattern, hold) and word counter width
    constant PrbsCfgW_c   : positive := 9;
    constant PrbsWordsW_c : positive := 48;

    type Cnt16Array_t is array (0 to NumLanes_g-1) of unsigned(15 downto 0);
    type Slv32Array_t is array (0 to NumVc_g-1) of std_logic_vector(31 downto 0);
    type Slv16Array_t is array (0 to NumVc_g-1) of std_logic_vector(15 downto 0);
    type LaneCtrlArray_t is array (0 to NumLanes_g-1) of std_logic_vector(LaneCfgW_c-PrbsCfgW_c-1 downto 0);
    type PrbsCtrlArray_t is array (0 to NumLanes_g-1) of std_logic_vector(PrbsCfgW_c-1 downto 0);
    type PrbsErrArray_t is array (0 to NumLanes_g-1) of unsigned(31 downto 0);
    type PrbsWordsArray_t is array (0 to NumLanes_g-1) of unsigned(PrbsWordsW_c-1 downto 0);

    -- Register bus
    signal RbAddr    : std_logic_vector(11 downto 0);
    signal RbWr      : std_logic;
    signal RbWrData  : std_logic_vector(31 downto 0);
    signal RbRd      : std_logic;
    signal RbRdData  : std_logic_vector(31 downto 0);
    signal RbRdValid : std_logic;

    -- Configuration registers
    signal DataScrambled : std_logic;
    signal BcInterval    : std_logic_vector(15 downto 0);
    signal LaneCtrl      : LaneCtrlArray_t;
    signal PrbsCtrl      : PrbsCtrlArray_t;
    signal PrbsCmd       : std_logic_vector(2*NumLanes_g-1 downto 0); -- Count reset, force error per lane
    signal MlMax         : std_logic_vector(2 downto 0);
    signal MlBypass      : std_logic;
    signal IrqMask       : std_logic_vector(31 downto 0);
    signal CmdLinkReset  : std_logic;
    -- Quality of service (copy of the registers of the Data Link layer)
    signal VcCfg         : Slv32Array_t;
    signal VcBw          : Slv16Array_t;
    signal VcSlotsLo     : Slv32Array_t;
    signal VcSlotsHi     : Slv32Array_t;
    signal IdleLimit     : std_logic_vector(31 downto 0);
    signal VcBwOver      : std_logic_vector(NumVc_g-1 downto 0);
    signal VcBwUnder     : std_logic_vector(NumVc_g-1 downto 0);
    signal QosWr         : std_logic;
    signal QosWrIn       : std_logic_vector(43 downto 0);
    signal QosWrOut      : std_logic_vector(43 downto 0);
    signal CmdIfReset    : std_logic;

    -- Sticky flags and counters
    signal DlErrors    : std_logic_vector(10 downto 0);
    signal VcInOvf     : std_logic_vector(NumVc_g-1 downto 0);
    signal VcCrOvf     : std_logic_vector(NumVc_g-1 downto 0);
    signal VcFrErr     : std_logic_vector(NumVc_g-1 downto 0);
    signal LaneEvents  : std_logic_vector(4*NumLanes_g-1 downto 0);
    signal Retries     : unsigned(31 downto 0);
    signal Crc16Cnt    : unsigned(15 downto 0);
    signal Crc8Cnt     : unsigned(15 downto 0);
    signal FrameCnt    : unsigned(15 downto 0);
    signal SeqCnt      : unsigned(15 downto 0);
    signal TimeoutCnt  : Cnt16Array_t;
    signal MisalignCnt : unsigned(15 downto 0);
    signal StatSettle  : natural range 0 to 31;

    -- Crossings
    signal CoreCfgIn  : std_logic_vector(CoreCfgW_c-1 downto 0);
    signal CoreCfgOut : std_logic_vector(CoreCfgW_c-1 downto 0);
    signal CoreStatIn : std_logic_vector(CoreStatW_c-1 downto 0);
    signal CoreStat   : std_logic_vector(CoreStatW_c-1 downto 0);
    signal CoreEvIn   : std_logic_vector(CoreEvW_c-1 downto 0);
    signal CoreEv     : std_logic_vector(CoreEvW_c-1 downto 0);
    signal LaneCfgIn  : std_logic_vector(LaneCfgW_c*NumLanes_g-1 downto 0);
    signal LaneCfgOut : std_logic_vector(LaneCfgW_c*NumLanes_g-1 downto 0);
    signal LaneStatIn : std_logic_vector(LaneStatW_c*NumLanes_g+2*NumLanes_g+2 downto 0);
    signal LaneStat   : std_logic_vector(LaneStatW_c*NumLanes_g+2*NumLanes_g+2 downto 0);
    signal LaneEvIn   : std_logic_vector(4*NumLanes_g+1 downto 0);
    signal LaneEv     : std_logic_vector(4*NumLanes_g+1 downto 0);
    signal MlCfgIn    : std_logic_vector(3 downto 0);
    signal MlCfgOut   : std_logic_vector(3 downto 0);
    signal PrbsCmdOut : std_logic_vector(2*NumLanes_g-1 downto 0);

    -- PRBS test counters (lane clock domain)
    signal PrbsErrCnt  : PrbsErrArray_t   := (others => (others => '0'));
    signal PrbsWordCnt : PrbsWordsArray_t := (others => (others => '0'));

    -- EDAC monitor
    type ChDomain_t is (DomUser, DomCore, DomLane, DomMgmt);
    type ChDomains_t is array (0 to EccChannels_c-1) of ChDomain_t;

    -- Write side of every channel (where errors are injected)
    constant WrDomain_c : ChDomains_t := (EccChVcOut_c => DomUser, EccChErb_c => DomCore,
                                          EccChFrameBuf_c => DomCore, EccChVcIn_c => DomCore,
                                          EccChBcOut_c => DomUser, EccChBcIn_c => DomCore,
                                          EccChCcTx_c => DomCore, EccChCcRx_c => DomLane,
                                          EccChCtrl_c => DomMgmt);

    signal EccCoreIn  : std_logic_vector(2*Ch_c-1 downto 0);
    signal EccCoreEv  : std_logic_vector(2*Ch_c-1 downto 0);
    signal EccUserEv  : std_logic_vector(2*Ch_c-1 downto 0);
    signal EccLaneEv  : std_logic_vector(2*Ch_c-1 downto 0);
    signal EccSec     : std_logic_vector(Ch_c-1 downto 0);
    signal EccDed     : std_logic_vector(Ch_c-1 downto 0);
    signal EccClr     : std_logic;
    signal EccSel     : std_logic_vector(3 downto 0);
    signal EccRdClr   : std_logic;
    signal EccSecCnt  : std_logic_vector(15 downto 0);
    signal EccDedCnt  : std_logic_vector(15 downto 0);
    signal EccDedStk  : std_logic_vector(Ch_c-1 downto 0);
    signal EccSecEvt  : std_logic;
    signal EccSecStk  : std_logic;
    signal EccInjCmd  : std_logic_vector(2*Ch_c-1 downto 0); -- Injection command of a channel
    signal EccInjMgmt : std_logic_vector(2*Ch_c-1 downto 0);
    signal EccInjToC  : std_logic_vector(2*Ch_c-1 downto 0);
    signal EccInjToU  : std_logic_vector(2*Ch_c-1 downto 0);
    signal EccInjToL  : std_logic_vector(2*Ch_c-1 downto 0);
    signal QosSec     : std_logic;
    signal QosDed     : std_logic;
    signal QosValid   : std_logic;
    signal UserEv     : std_logic_vector(NumVc_g-1 downto 0);

    function sat16 (cnt : unsigned(15 downto 0)) return unsigned is
    begin
        if cnt = x"FFFF" then
            return cnt;
        end if;
        return cnt + 1;
    end function;

begin

    -----------------------------------------------------------------------------------------------
    -- AXI4-Lite slave
    -----------------------------------------------------------------------------------------------
    i_axi : entity olo.olo_axi_lite_slave
        generic map (
            AxiAddrWidth_g => 12,
            AxiDataWidth_g => 32
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            S_AxiLite_ArAddr  => S_AxiLite_ArAddr,
            S_AxiLite_ArValid => S_AxiLite_ArValid,
            S_AxiLite_ArReady => S_AxiLite_ArReady,
            S_AxiLite_AwAddr  => S_AxiLite_AwAddr,
            S_AxiLite_AwValid => S_AxiLite_AwValid,
            S_AxiLite_AwReady => S_AxiLite_AwReady,
            S_AxiLite_WData   => S_AxiLite_WData,
            S_AxiLite_WStrb   => S_AxiLite_WStrb,
            S_AxiLite_WValid  => S_AxiLite_WValid,
            S_AxiLite_WReady  => S_AxiLite_WReady,
            S_AxiLite_BResp   => S_AxiLite_BResp,
            S_AxiLite_BValid  => S_AxiLite_BValid,
            S_AxiLite_BReady  => S_AxiLite_BReady,
            S_AxiLite_RData   => S_AxiLite_RData,
            S_AxiLite_RResp   => S_AxiLite_RResp,
            S_AxiLite_RValid  => S_AxiLite_RValid,
            S_AxiLite_RReady  => S_AxiLite_RReady,
            Rb_Addr           => RbAddr,
            Rb_Wr             => RbWr,
            Rb_ByteEna        => open,
            Rb_WrData         => RbWrData,
            Rb_Rd             => RbRd,
            Rb_RdData         => RbRdData,
            Rb_RdValid        => RbRdValid
        );

    -----------------------------------------------------------------------------------------------
    -- Register file: writes, sticky flags, counters
    -----------------------------------------------------------------------------------------------
    p_regs : process (Clk) is
        variable Addr_v : natural;
        variable Lane_v : integer;
        variable Reg_v  : natural;
        variable Vc_v   : natural;
    begin
        if rising_edge(Clk) then
            CmdLinkReset <= '0';
            CmdIfReset   <= '0';
            PrbsCmd      <= (others => '0');
            Addr_v       := to_integer(unsigned(RbAddr));
            Lane_v       := (Addr_v / RegLaneStride_c) - (RegLaneBase_c / RegLaneStride_c);
            Reg_v        := Addr_v mod RegLaneStride_c;

            -- Events: sticky flags and counters
            DlErrors(3 downto 0) <= DlErrors(3 downto 0) or CoreEv(3 downto 0);
            DlErrors(6 downto 4) <= DlErrors(6 downto 4) or CoreEv(7 downto 5);
            DlErrors(7)          <= DlErrors(7) or (or CoreEv(7 + NumVc_g downto 8));
            DlErrors(8)          <= DlErrors(8) or (or CoreEv(7 + 2 * NumVc_g downto 8 + NumVc_g));
            DlErrors(9)          <= DlErrors(9) or (or UserEv);
            DlErrors(10)         <= DlErrors(10) or LaneEv(4*NumLanes_g+1);
            VcInOvf              <= VcInOvf or CoreEv(7 + NumVc_g downto 8);
            VcCrOvf              <= VcCrOvf or CoreEv(7 + 2 * NumVc_g downto 8 + NumVc_g);
            VcFrErr              <= VcFrErr or UserEv;
            LaneEvents           <= LaneEvents or LaneEv(4*NumLanes_g-1 downto 0);
            -- Bandwidth flags once the status crossing has transferred a value after reset
            if StatSettle = 31 then
                VcBwOver  <= VcBwOver or CoreStat(7 + 2 * NumVc_g downto 8 + NumVc_g);
                VcBwUnder <= VcBwUnder or CoreStat(7 + 3 * NumVc_g downto 8 + 2 * NumVc_g);
            else
                StatSettle <= StatSettle + 1;
            end if;
            if CoreEv(0) = '1' then
                Crc16Cnt <= sat16(Crc16Cnt);
            end if;
            if CoreEv(1) = '1' then
                Crc8Cnt <= sat16(Crc8Cnt);
            end if;
            if CoreEv(2) = '1' then
                FrameCnt <= sat16(FrameCnt);
            end if;
            if CoreEv(3) = '1' then
                SeqCnt <= sat16(SeqCnt);
            end if;
            if CoreEv(4) = '1' and Retries /= x"FFFFFFFF" then
                Retries <= Retries + 1;
            end if;

            for i in 0 to NumLanes_g-1 loop
                if LaneEv(4*i+1) = '1' then
                    TimeoutCnt(i) <= sat16(TimeoutCnt(i));
                end if;
            end loop;

            if LaneEv(4*NumLanes_g) = '1' then
                MisalignCnt <= sat16(MisalignCnt);
            end if;

            -- Writes
            if RbWr = '1' then

                case Addr_v is
                    when RegDlCtrl_c =>
                        CmdLinkReset  <= RbWrData(DlCtrlLinkReset_c);
                        CmdIfReset    <= RbWrData(DlCtrlInterfaceReset_c);
                        DataScrambled <= RbWrData(DlCtrlDataScrambled_c);
                    when RegDlBcInterval_c =>
                        BcInterval <= RbWrData(15 downto 0);
                    when RegDlErrors_c =>
                        DlErrors <= DlErrors and not RbWrData(10 downto 0);
                    when RegDlRetries_c =>
                        Retries <= (others => '0');
                    when RegDlCrc16Count_c =>
                        Crc16Cnt <= (others => '0');
                    when RegDlCrc8Count_c =>
                        Crc8Cnt <= (others => '0');
                    when RegDlFrameCount_c =>
                        FrameCnt <= (others => '0');
                    when RegDlSeqCount_c =>
                        SeqCnt <= (others => '0');
                    when RegVcInputOverflow_c =>
                        VcInOvf <= VcInOvf and not RbWrData(NumVc_g-1 downto 0);
                    when RegVcCreditOverflow_c =>
                        VcCrOvf <= VcCrOvf and not RbWrData(NumVc_g-1 downto 0);
                    when RegVcFramingError_c =>
                        VcFrErr <= VcFrErr and not RbWrData(NumVc_g-1 downto 0);
                    when RegIrqMask_c =>
                        IrqMask <= RbWrData;
                    when RegVcBwOver_c =>
                        VcBwOver <= VcBwOver and not RbWrData(NumVc_g-1 downto 0);
                    when RegVcBwUnder_c =>
                        VcBwUnder <= VcBwUnder and not RbWrData(NumVc_g-1 downto 0);
                    when RegVcIdleLimit_c =>
                        IdleLimit <= RbWrData;
                    when RegMlCtrl_c =>
                        MlMax    <= RbWrData(2 downto 0);
                        MlBypass <= RbWrData(8);
                    when RegMlMisaligned_c =>
                        MisalignCnt <= (others => '0');
                    when RegEccStatus_c =>
                        EccSecStk <= '0';
                    when RegEccSelect_c =>
                        EccSel <= RbWrData(3 downto 0);
                    when others =>
                        if Addr_v >= RegVcBase_c and Addr_v < RegVcBase_c + RegVcStride_c * NumVc_g then
                            Vc_v := (Addr_v - RegVcBase_c) / RegVcStride_c;
                            if (Addr_v - RegVcBase_c) mod RegVcStride_c = RegVcCfgOfs_c then
                                VcCfg(Vc_v)(3 downto 0) <= RbWrData(3 downto 0);
                                VcCfg(Vc_v)(8)          <= RbWrData(8);
                                if Vc_v /= 0 then
                                    -- VN0 is always mapped to VC0 (ECSS 5.8.3bb)
                                    VcCfg(Vc_v)(21 downto 16) <= RbWrData(21 downto 16);
                                end if;
                            elsif (Addr_v - RegVcBase_c) mod RegVcStride_c = RegVcBandwidthOfs_c then
                                VcBw(Vc_v) <= RbWrData(15 downto 0);
                            elsif (Addr_v - RegVcBase_c) mod RegVcStride_c = RegVcSlotsLoOfs_c then
                                VcSlotsLo(Vc_v) <= RbWrData;
                            else
                                VcSlotsHi(Vc_v) <= RbWrData;
                            end if;
                        end if;
                        if Lane_v >= 0 and Lane_v < NumLanes_g then
                            if Reg_v = RegLaneCtrlOfs_c then
                                LaneCtrl(Lane_v) <= RbWrData(17 downto 16) & RbWrData(6 downto 5) & RbWrData(15 downto 8) &
                                                    RbWrData(4 downto 0);
                            elsif Reg_v = RegLaneEventsOfs_c then
                                LaneEvents(4*Lane_v+3 downto 4*Lane_v) <= LaneEvents(4*Lane_v+3 downto 4*Lane_v) and
                                                                          not RbWrData(3 downto 0);
                            elsif Reg_v = RegLaneTimeoutCountOfs_c then
                                TimeoutCnt(Lane_v) <= (others => '0');
                            elsif Reg_v = RegLanePrbsCtrlOfs_c then
                                PrbsCtrl(Lane_v)      <= RbWrData(8 downto 0);
                                PrbsCmd(2*Lane_v)     <= RbWrData(LanePrbsCtrlCountReset_c);
                                PrbsCmd(2*Lane_v + 1) <= RbWrData(LanePrbsCtrlForceError_c);
                            end if;
                        end if;
                end case;

            end if;

            -- Corrected ECC error seen (sticky, after the clear of a write in the same cycle)
            if EccSecEvt = '1' then
                EccSecStk <= '1';
            end if;

            -- Link Reset command: status of the Data Link, Multi-Lane and Lane layers cleared (ECSS 5.9.4e,
            -- the EDAC status is kept); Interface Reset: configuration reset
            if (RbWr = '1' and Addr_v = RegDlCtrl_c and RbWrData(DlCtrlLinkReset_c) = '1') then
                DlErrors    <= (others => '0');
                VcInOvf     <= (others => '0');
                VcCrOvf     <= (others => '0');
                VcFrErr     <= (others => '0');
                VcBwOver    <= (others => '0');
                VcBwUnder   <= (others => '0');
                Retries     <= (others => '0');
                Crc16Cnt    <= (others => '0');
                Crc8Cnt     <= (others => '0');
                FrameCnt    <= (others => '0');
                SeqCnt      <= (others => '0');
                LaneEvents  <= (others => '0');
                TimeoutCnt  <= (others => (others => '0'));
                MisalignCnt <= (others => '0');
            end if;
            if Rst = '1' or (RbWr = '1' and Addr_v = RegDlCtrl_c and RbWrData(DlCtrlInterfaceReset_c) = '1') then
                DataScrambled <= '1';
                BcInterval    <= RegDlBcIntervalReset_c(15 downto 0);
                IdleLimit     <= RegVcIdleLimitReset_c;
                VcSlotsLo     <= (others => (others => '1'));
                VcSlotsHi     <= (others => (others => '1'));

                for v in 0 to NumVc_g-1 loop
                    VcCfg(v)               <= (others => '0');
                    VcCfg(v)(3 downto 0)   <= std_logic_vector(to_unsigned(NumPrio_g - 1, 4));
                    VcCfg(v)(21 downto 16) <= std_logic_vector(to_unsigned(v, 6));
                    if v = 0 then
                        VcBw(v) <= x"0A00";
                    else
                        VcBw(v) <= x"FFFF";
                    end if;
                end loop;

                LaneCtrl <= (others => (others => '0'));
                PrbsCtrl <= (others => (others => '0'));
                MlMax    <= std_logic_vector(to_unsigned(NumLanes_g, 3));
                MlBypass <= '0';

                for i in 0 to NumLanes_g-1 loop
                    -- AutoStart, TxEn, RxEn
                    LaneCtrl(i)(1)  <= '1';
                    LaneCtrl(i)(13) <= '1';
                    LaneCtrl(i)(14) <= '1';
                end loop;

            end if;
            if Rst = '1' then
                CmdLinkReset <= '0';
                CmdIfReset   <= '0';
                PrbsCmd      <= (others => '0');
                IrqMask      <= (others => '0');
                DlErrors     <= (others => '0');
                VcInOvf      <= (others => '0');
                VcCrOvf      <= (others => '0');
                VcFrErr      <= (others => '0');
                LaneEvents   <= (others => '0');
                Retries      <= (others => '0');
                Crc16Cnt     <= (others => '0');
                Crc8Cnt      <= (others => '0');
                FrameCnt     <= (others => '0');
                SeqCnt       <= (others => '0');
                TimeoutCnt   <= (others => (others => '0'));
                MisalignCnt  <= (others => '0');
                EccSel       <= (others => '0');
                EccSecStk    <= '0';
                StatSettle   <= 0;
                VcBwOver     <= (others => '0');
                VcBwUnder    <= (others => '0');
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Register file: reads, interrupt
    -----------------------------------------------------------------------------------------------
    p_read : process (Clk) is
        variable Addr_v : natural;
        variable Lane_v : integer;
        variable Reg_v  : natural;
        variable Data_v : std_logic_vector(31 downto 0);
        variable Base_v : natural;
        variable Irq_v  : std_logic;
        variable Vc_v   : natural;
    begin
        if rising_edge(Clk) then
            RbRdValid <= RbRd;
            Addr_v    := to_integer(unsigned(RbAddr));
            Lane_v    := (Addr_v / RegLaneStride_c) - (RegLaneBase_c / RegLaneStride_c);
            Reg_v     := Addr_v mod RegLaneStride_c;
            Data_v    := (others => '0');

            case Addr_v is
                when RegId_c =>
                    Data_v := RegMapId_c;
                when RegGenerics_c =>
                    Data_v(7 downto 0)  := std_logic_vector(to_unsigned(NumVc_g, 8));
                    Data_v(11 downto 8) := std_logic_vector(to_unsigned(NumLanes_g, 4));
                when RegDlCtrl_c =>
                    Data_v(8) := DataScrambled;
                when RegDlBcInterval_c =>
                    Data_v(15 downto 0) := BcInterval;
                when RegDlStatus_c =>
                    Data_v(1 downto 0) := CoreStat(1 downto 0);
                    Data_v(3 downto 2) := CoreStat(3 downto 2);
                    Data_v(6 downto 4) := CoreStat(6 downto 4);
                    Data_v(8)          := CoreStat(7);
                when RegDlErrors_c =>
                    Data_v(10 downto 0) := DlErrors;
                when RegDlRetries_c =>
                    Data_v := std_logic_vector(Retries);
                when RegDlCrc16Count_c =>
                    Data_v(15 downto 0) := std_logic_vector(Crc16Cnt);
                when RegDlCrc8Count_c =>
                    Data_v(15 downto 0) := std_logic_vector(Crc8Cnt);
                when RegDlFrameCount_c =>
                    Data_v(15 downto 0) := std_logic_vector(FrameCnt);
                when RegDlSeqCount_c =>
                    Data_v(15 downto 0) := std_logic_vector(SeqCnt);
                when RegVcHasCredit_c =>
                    Data_v(NumVc_g-1 downto 0) := CoreStat(7 + NumVc_g downto 8);
                when RegVcInputOverflow_c =>
                    Data_v(NumVc_g-1 downto 0) := VcInOvf;
                when RegVcCreditOverflow_c =>
                    Data_v(NumVc_g-1 downto 0) := VcCrOvf;
                when RegVcFramingError_c =>
                    Data_v(NumVc_g-1 downto 0) := VcFrErr;
                when RegMlStatus_c =>
                    Base_v                        := LaneStatW_c * NumLanes_g;
                    Data_v(NumLanes_g-1 downto 0) := LaneStat(Base_v + NumLanes_g - 1 downto Base_v);
                    Data_v(NumLanes_g+3 downto 4) := LaneStat(Base_v + 2 * NumLanes_g - 1 downto Base_v + NumLanes_g);
                    Data_v(9 downto 8)            := LaneStat(Base_v + 2 * NumLanes_g + 1 downto Base_v + 2 * NumLanes_g);
                    Data_v(10)                    := LaneStat(Base_v + 2 * NumLanes_g + 2);
                when RegIrqMask_c =>
                    Data_v := IrqMask;
                when RegVcBwOver_c =>
                    Data_v(NumVc_g-1 downto 0) := VcBwOver;
                when RegVcBwUnder_c =>
                    Data_v(NumVc_g-1 downto 0) := VcBwUnder;
                when RegVcIdleLimit_c =>
                    Data_v := IdleLimit;
                when RegSchedStatus_c =>
                    Data_v(5 downto 0) := CoreStat(CoreStatW_c - 1 downto CoreStatW_c - 6);
                when RegMlCtrl_c =>
                    Data_v(2 downto 0) := MlMax;
                    Data_v(8)          := MlBypass;
                when RegMlMisaligned_c =>
                    Data_v(15 downto 0) := std_logic_vector(MisalignCnt);
                when RegEccStatus_c =>
                    Data_v(Ch_c-1 downto 0) := EccDedStk;
                    Data_v(16)              := EccSecStk;
                when RegEccSelect_c =>
                    Data_v(3 downto 0) := EccSel;
                when RegEccCount_c =>
                    Data_v(15 downto 0)  := EccSecCnt;
                    Data_v(31 downto 16) := EccDedCnt;
                when others =>
                    if Addr_v >= RegVcBase_c and Addr_v < RegVcBase_c + RegVcStride_c * NumVc_g then
                        Vc_v := (Addr_v - RegVcBase_c) / RegVcStride_c;
                        if (Addr_v - RegVcBase_c) mod RegVcStride_c = RegVcCfgOfs_c then
                            Data_v := VcCfg(Vc_v);
                        elsif (Addr_v - RegVcBase_c) mod RegVcStride_c = RegVcBandwidthOfs_c then
                            Data_v(15 downto 0) := VcBw(Vc_v);
                        elsif (Addr_v - RegVcBase_c) mod RegVcStride_c = RegVcSlotsLoOfs_c then
                            Data_v := VcSlotsLo(Vc_v);
                        else
                            Data_v := VcSlotsHi(Vc_v);
                        end if;
                    end if;
                    if Lane_v >= 0 and Lane_v < NumLanes_g then
                        Base_v := LaneStatW_c * Lane_v;
                        if Reg_v = RegLaneCtrlOfs_c then
                            Data_v(15 downto 8)  := LaneCtrl(Lane_v)(12 downto 5);
                            Data_v(6 downto 5)   := LaneCtrl(Lane_v)(14 downto 13);
                            Data_v(17 downto 16) := LaneCtrl(Lane_v)(16 downto 15);
                            Data_v(4 downto 0)   := LaneCtrl(Lane_v)(4 downto 0);
                        elsif Reg_v = RegLaneStatusOfs_c then
                            Data_v(5 downto 0)   := LaneStat(Base_v + 5 downto Base_v);
                            Data_v(6)            := LaneStat(Base_v + 38);
                            Data_v(7)            := LaneStat(Base_v + 39);
                            Data_v(15 downto 8)  := LaneStat(Base_v + 13 downto Base_v + 6);
                            Data_v(23 downto 16) := LaneStat(Base_v + 21 downto Base_v + 14);
                        elsif Reg_v = RegLaneEventsOfs_c then
                            Data_v(3 downto 0) := LaneEvents(4*Lane_v+3 downto 4*Lane_v);
                        elsif Reg_v = RegLaneReasonsOfs_c then
                            Data_v(15 downto 0) := LaneStat(Base_v + 37 downto Base_v + 22);
                        elsif Reg_v = RegLaneTimeoutCountOfs_c then
                            Data_v(15 downto 0) := std_logic_vector(TimeoutCnt(Lane_v));
                        elsif Reg_v = RegLanePrbsCtrlOfs_c then
                            Data_v(8 downto 0) := PrbsCtrl(Lane_v);
                        elsif Reg_v = RegLanePrbsErrorsOfs_c then
                            Data_v := LaneStat(Base_v + 71 downto Base_v + 40);
                        elsif Reg_v = RegLanePrbsWordsOfs_c then
                            Data_v := LaneStat(Base_v + 103 downto Base_v + 72);
                        end if;
                    end if;
            end case;

            RbRdData <= Data_v;

            -- Interrupt
            Irq_v := or (DlErrors and IrqMask(10 downto 0));
            -- EDAC: uncorrectable error (bit 24), corrected error (bit 25)
            if (or EccDedStk) = '1' and IrqMask(24) = '1' then
                Irq_v := '1';
            end if;
            if EccSecStk = '1' and IrqMask(25) = '1' then
                Irq_v := '1';
            end if;

            for i in 0 to NumLanes_g-1 loop
                Irq_v := Irq_v or (or (LaneEvents(4*i+3 downto 4*i) and IrqMask(19 downto 16)));
            end loop;

            Irq <= Irq_v;
            if Rst = '1' then
                RbRdValid <= '0';
                Irq       <= '0';
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Core clock domain
    -----------------------------------------------------------------------------------------------
    CoreCfgIn <= MlMax & DataScrambled & BcInterval;

    i_core_cfg : entity olo.olo_ft_cc_bits
        generic map (
            Width_g => CoreCfgW_c
        )
        port map (
            In_Clk   => Clk,
            In_Rst   => Rst,
            In_Data  => CoreCfgIn,
            Out_Clk  => CoreClk,
            Out_Rst  => CoreRst,
            Out_Data => CoreCfgOut
        );

    Dl_MaxDataLanes  <= CoreCfgOut(19 downto 17);
    Dl_DataScrambled <= CoreCfgOut(16);
    Dl_BcInterval    <= CoreCfgOut(15 downto 0);

    i_core_cmd : entity work.ofb_cc_pulse
        generic map (
            NumPulses_g => 2
        )
        port map (
            In_Clk       => Clk,
            In_Rst       => Rst,
            In_Pulse(0)  => CmdLinkReset,
            In_Pulse(1)  => CmdIfReset,
            Out_Clk      => CoreClk,
            Out_Rst      => CoreRst,
            Out_Pulse(0) => Dl_LinkReset,
            Out_Pulse(1) => Dl_InterfaceReset
        );

    -- Writes of the quality of service registers are forwarded to the Data Link layer
    p_qos_wr : process (all) is
        variable Addr_v : natural;
    begin
        Addr_v := to_integer(unsigned(RbAddr));
        QosWr  <= '0';
        if RbWr = '1' and (Addr_v = RegVcIdleLimit_c or (Addr_v >= RegVcBase_c and Addr_v < RegVcBase_c + RegVcStride_c * NumVc_g)) then
            QosWr <= '1';
        end if;
    end process;

    QosWrIn <= RbAddr & RbWrData;

    i_qos_wr : entity olo.olo_ft_fifo_async
        generic map (
            Width_g => 44,
            Depth_g => 16
        )
        port map (
            In_Clk            => Clk,
            In_Rst            => Rst,
            In_Data           => QosWrIn,
            In_Valid          => QosWr,
            Out_Clk           => CoreClk,
            Out_Rst           => CoreRst,
            Out_Data          => QosWrOut,
            Out_Valid         => QosValid,
            Out_Ready         => '1',
            Out_EccSec        => QosSec,
            Out_EccDed        => QosDed,
            In_ErrInj_BitFlip => eccInjPattern(eccCodewordWidth(44), EccInjMgmt(Ch_c + EccChCtrl_c)),
            In_ErrInj_Valid   => EccInjMgmt(EccChCtrl_c) or EccInjMgmt(Ch_c + EccChCtrl_c)
        );

    Dl_RegWr <= QosValid;

    Dl_RegAddr <= QosWrOut(43 downto 32);
    Dl_RegData <= QosWrOut(31 downto 0);

    CoreStatIn <= Dl_TimeSlot & Dl_BwUnder & Dl_BwOver & Dl_HasCredit & Dl_ErbEmpty & Dl_WordIdState & Dl_RxErrState &
                  Dl_LinkResetState;

    i_core_stat : entity olo.olo_ft_cc_status
        generic map (
            Width_g => CoreStatW_c
        )
        port map (
            In_Clk    => CoreClk,
            In_RstIn  => CoreRst,
            In_Data   => CoreStatIn,
            Out_Clk   => Clk,
            Out_RstIn => Rst,
            Out_Data  => CoreStat
        );

    CoreEvIn <= Dl_EvCreditOverflow & Dl_EvInputOverflow & Dl_EvBcDiscard & Dl_EvFarEndLinkReset & Dl_EvProtocolError &
                Dl_EvRetry & Dl_EvSeqErr & Dl_EvFrameErr & Dl_EvCrc8Err & Dl_EvCrc16Err;

    i_core_ev : entity work.ofb_cc_pulse
        generic map (
            NumPulses_g => CoreEvW_c
        )
        port map (
            In_Clk    => CoreClk,
            In_Rst    => CoreRst,
            In_Pulse  => CoreEvIn,
            Out_Clk   => Clk,
            Out_Rst   => Rst,
            Out_Pulse => CoreEv
        );

    -----------------------------------------------------------------------------------------------
    -- Lane clock domain
    -----------------------------------------------------------------------------------------------
    g_lane_cfg : for i in 0 to NumLanes_g-1 generate
        LaneCfgIn(LaneCfgW_c*i+LaneCfgW_c-1 downto LaneCfgW_c*i) <= PrbsCtrl(i) & LaneCtrl(i);
        Lane_Start(i)                                            <= LaneCfgOut(LaneCfgW_c*i);
        Lane_AutoStart(i)                                        <= LaneCfgOut(LaneCfgW_c*i+1);
        Lane_Reset(i)                                            <= LaneCfgOut(LaneCfgW_c*i+2);
        Lane_NearLoopback(i)                                     <= LaneCfgOut(LaneCfgW_c*i+3);
        Lane_FarLoopback(i)                                      <= LaneCfgOut(LaneCfgW_c*i+4);
        Lane_StandbyReason(8*i+7 downto 8*i)                     <= LaneCfgOut(LaneCfgW_c*i+12 downto LaneCfgW_c*i+5);
        Ml_TxEn(i)                                               <= LaneCfgOut(LaneCfgW_c*i+13);
        Ml_RxEn(i)                                               <= LaneCfgOut(LaneCfgW_c*i+14);
        Phy_SerialNearLoopback(i)                                <= LaneCfgOut(LaneCfgW_c*i+15);
        Phy_SerialFarLoopback(i)                                 <= LaneCfgOut(LaneCfgW_c*i+16);
        Phy_PrbsTxSel(4*i+3 downto 4*i)                          <= LaneCfgOut(LaneCfgW_c*i+20 downto LaneCfgW_c*i+17);
        Phy_PrbsRxSel(4*i+3 downto 4*i)                          <= LaneCfgOut(LaneCfgW_c*i+24 downto LaneCfgW_c*i+21);

    end generate;

    -- PRBS test commands: count reset and force error per lane
    i_prbs_cmd : entity work.ofb_cc_pulse
        generic map (
            NumPulses_g => 2 * NumLanes_g
        )
        port map (
            In_Clk    => Clk,
            In_Rst    => Rst,
            In_Pulse  => PrbsCmd,
            Out_Clk   => LaneClk,
            Out_Rst   => LaneRst,
            Out_Pulse => PrbsCmdOut
        );

    -- PRBS test counters: checked words and words with errors while the checker is on and not held
    p_prbs : process (LaneClk) is
        variable On_v : boolean;
    begin
        if rising_edge(LaneClk) then

            for i in 0 to NumLanes_g-1 loop
                On_v                := LaneCfgOut(LaneCfgW_c*i+24 downto LaneCfgW_c*i+21) /= "0000" and
                                       LaneCfgOut(LaneCfgW_c*i+25) = '0';
                Phy_PrbsCntReset(i) <= PrbsCmdOut(2*i);
                Phy_PrbsForceErr(i) <= PrbsCmdOut(2*i+1);
                if PrbsCmdOut(2*i) = '1' then
                    PrbsErrCnt(i)  <= (others => '0');
                    PrbsWordCnt(i) <= (others => '0');
                elsif On_v then
                    if PrbsWordCnt(i) /= (PrbsWordCnt(i)'range => '1') then
                        PrbsWordCnt(i) <= PrbsWordCnt(i) + 1;
                    end if;
                    if Phy_PrbsErr(i) = '1' and PrbsErrCnt(i) /= x"FFFFFFFF" then
                        PrbsErrCnt(i) <= PrbsErrCnt(i) + 1;
                    end if;
                end if;
            end loop;

            if LaneRst = '1' then
                PrbsErrCnt       <= (others => (others => '0'));
                PrbsWordCnt      <= (others => (others => '0'));
                Phy_PrbsCntReset <= (others => '0');
                Phy_PrbsForceErr <= (others => '0');
            end if;
        end if;
    end process;

    p_lane_vec : process (all) is
        variable Stat_v : std_logic_vector(LaneStatW_c-1 downto 0);
        variable Ev_v   : std_logic_vector(3 downto 0);
    begin

        for i in 0 to NumLanes_g-1 loop
            Stat_v := std_logic_vector(PrbsWordCnt(i)(PrbsWordsW_c-1 downto 16)) & std_logic_vector(PrbsErrCnt(i)) &
                      Phy_PrbsLocked(i) &
                      Phy_BitSync(i) & Lane_FarLostReason(8*i+7 downto 8*i) & Lane_FarStandbyReason(8*i+7 downto 8*i) &
                      Lane_FarCapability(8*i+7 downto 8*i) & Lane_RxErrCount(8*i+7 downto 8*i) &
                      Lane_NoSignal(i) & Lane_RxPolarity(i) & Lane_State(4*i+3 downto 4*i);

            Ev_v := Lane_EvFarLostSignal(i) & Lane_EvFarStandby(i) & Lane_EvTimeout(i) & Lane_EvRxErrOverflow(i);

            LaneStatIn(LaneStatW_c*i+LaneStatW_c-1 downto LaneStatW_c*i) <= Stat_v;
            LaneEvIn(4*i+3 downto 4*i)                                   <= Ev_v;
        end loop;

        LaneStatIn(LaneStatIn'high downto LaneStatW_c*NumLanes_g) <= Ml_StatBypass & Ml_AlignState & Ml_DataReceiving &
                                                                     Ml_DataSending;
        LaneEvIn(4*NumLanes_g)                                    <= Ml_EvMisaligned;
        LaneEvIn(4*NumLanes_g+1)                                  <= Ml_EvRxOverflow;
    end process;

    i_lane_cfg : entity olo.olo_ft_cc_bits
        generic map (
            Width_g => LaneCfgW_c * NumLanes_g
        )
        port map (
            In_Clk   => Clk,
            In_Rst   => Rst,
            In_Data  => LaneCfgIn,
            Out_Clk  => LaneClk,
            Out_Rst  => LaneRst,
            Out_Data => LaneCfgOut
        );

    i_lane_stat : entity olo.olo_ft_cc_status
        generic map (
            Width_g => LaneStatIn'length
        )
        port map (
            In_Clk    => LaneClk,
            In_RstIn  => LaneRst,
            In_Data   => LaneStatIn,
            Out_Clk   => Clk,
            Out_RstIn => Rst,
            Out_Data  => LaneStat
        );

    i_lane_ev : entity work.ofb_cc_pulse
        generic map (
            NumPulses_g => 4 * NumLanes_g + 2
        )
        port map (
            In_Clk    => LaneClk,
            In_Rst    => LaneRst,
            In_Pulse  => LaneEvIn,
            Out_Clk   => Clk,
            Out_Rst   => Rst,
            Out_Pulse => LaneEv
        );

    -- Multi-Lane configuration: maximum number of data-sending lanes, bypass
    MlCfgIn <= MlBypass & MlMax;

    i_ml_cfg : entity olo.olo_ft_cc_bits
        generic map (
            Width_g => 4
        )
        port map (
            In_Clk   => Clk,
            In_Rst   => Rst,
            In_Data  => MlCfgIn,
            Out_Clk  => LaneClk,
            Out_Rst  => LaneRst,
            Out_Data => MlCfgOut
        );

    Ml_MaxDataLanes <= MlCfgOut(2 downto 0);
    Ml_Bypass       <= MlCfgOut(3);

    -----------------------------------------------------------------------------------------------
    -- User clock domain
    -----------------------------------------------------------------------------------------------
    i_user_ev : entity work.ofb_cc_pulse
        generic map (
            NumPulses_g => NumVc_g
        )
        port map (
            In_Clk    => UserClk,
            In_Rst    => UserRst,
            In_Pulse  => Ni_EvFrameErr,
            Out_Clk   => Clk,
            Out_Rst   => Rst,
            Out_Pulse => UserEv
        );

    -----------------------------------------------------------------------------------------------
    -- EDAC monitor (MG-3)
    -----------------------------------------------------------------------------------------------
    -- Events of the core, user and lane domains (the QoS write FIFO of the MIB is read in the core
    -- domain, channel Ctrl)
    p_ecc_core_in : process (all) is
    begin
        EccCoreIn                     <= Ecc_Core;
        EccCoreIn(EccChCtrl_c)        <= Ecc_Core(EccChCtrl_c) or (QosSec and QosValid);
        EccCoreIn(Ch_c + EccChCtrl_c) <= Ecc_Core(Ch_c + EccChCtrl_c) or (QosDed and QosValid);
    end process;

    i_ecc_core_ev : entity work.ofb_cc_pulse
        generic map (
            NumPulses_g => 2 * Ch_c
        )
        port map (
            In_Clk    => CoreClk,
            In_Rst    => CoreRst,
            In_Pulse  => EccCoreIn,
            Out_Clk   => Clk,
            Out_Rst   => Rst,
            Out_Pulse => EccCoreEv
        );

    i_ecc_user_ev : entity work.ofb_cc_pulse
        generic map (
            NumPulses_g => 2 * Ch_c
        )
        port map (
            In_Clk    => UserClk,
            In_Rst    => UserRst,
            In_Pulse  => Ecc_User,
            Out_Clk   => Clk,
            Out_Rst   => Rst,
            Out_Pulse => EccUserEv
        );

    i_ecc_lane_ev : entity work.ofb_cc_pulse
        generic map (
            NumPulses_g => 2 * Ch_c
        )
        port map (
            In_Clk    => LaneClk,
            In_Rst    => LaneRst,
            In_Pulse  => Ecc_Lane,
            Out_Clk   => Clk,
            Out_Rst   => Rst,
            Out_Pulse => EccLaneEv
        );

    EccSec <= EccCoreEv(Ch_c-1 downto 0) or EccUserEv(Ch_c-1 downto 0) or EccLaneEv(Ch_c-1 downto 0);
    EccDed <= EccCoreEv(2*Ch_c-1 downto Ch_c) or EccUserEv(2*Ch_c-1 downto Ch_c) or EccLaneEv(2*Ch_c-1 downto Ch_c);

    -- Counters, DED flags; ECC_STATUS write clears all, ECC_COUNT write clears the selected channel
    EccClr   <= '1' when RbWr = '1' and unsigned(RbAddr) = RegEccStatus_c else '0';
    EccRdClr <= '1' when RbWr = '1' and unsigned(RbAddr) = RegEccCount_c else '0';

    i_ecc_mon : entity olo.olo_ft_ecc_monitor
        generic map (
            Channels_g     => Ch_c,
            CounterWidth_g => 16
        )
        port map (
            Clk        => Clk,
            Rst        => Rst,
            Clr        => EccClr,
            In_EccSec  => EccSec,
            In_EccDed  => EccDed,
            DedSticky  => EccDedStk,
            Evt_Sec    => EccSecEvt,
            Evt_Ded    => open,
            Rd_Channel => EccSel,
            Rd_Ena     => '1',
            Rd_Clr     => EccRdClr,
            Rd_SecCnt  => EccSecCnt,
            Rd_DedCnt  => EccDedCnt,
            Rd_Valid   => open
        );

    -- Error injection: ECC_INJECT selects the channel and single or double error; the command goes
    -- to the clock domain of the write side of the channel
    p_ecc_inj : process (all) is
        variable Ch_v : natural;
    begin
        EccInjCmd <= (others => '0');
        Ch_v      := to_integer(unsigned(RbWrData(3 downto 0)));
        if RbWr = '1' and unsigned(RbAddr) = RegEccInject_c and Ch_v < Ch_c then
            if RbWrData(8) = '1' then
                EccInjCmd(Ch_c + Ch_v) <= '1';
            else
                EccInjCmd(Ch_v) <= '1';
            end if;
        end if;
    end process;

    -- The write domain of a channel is a constant: one branch of each selection is unreachable
    g_inj_dom : for i in 0 to Ch_c-1 generate
        -- coverage off
        EccInjToU(i)         <= EccInjCmd(i) when WrDomain_c(i) = DomUser else '0';
        EccInjToU(Ch_c + i)  <= EccInjCmd(Ch_c + i) when WrDomain_c(i) = DomUser else '0';
        EccInjToC(i)         <= EccInjCmd(i) when WrDomain_c(i) = DomCore else '0';
        EccInjToC(Ch_c + i)  <= EccInjCmd(Ch_c + i) when WrDomain_c(i) = DomCore else '0';
        EccInjToL(i)         <= EccInjCmd(i) when WrDomain_c(i) = DomLane else '0';
        EccInjToL(Ch_c + i)  <= EccInjCmd(Ch_c + i) when WrDomain_c(i) = DomLane else '0';
        EccInjMgmt(i)        <= EccInjCmd(i) when WrDomain_c(i) = DomMgmt else '0';
        EccInjMgmt(Ch_c + i) <= EccInjCmd(Ch_c + i) when WrDomain_c(i) = DomMgmt else '0';
        -- coverage on
    end generate;

    i_ecc_inj_core : entity work.ofb_cc_pulse
        generic map (
            NumPulses_g => 2 * Ch_c
        )
        port map (
            In_Clk    => Clk,
            In_Rst    => Rst,
            In_Pulse  => EccInjToC,
            Out_Clk   => CoreClk,
            Out_Rst   => CoreRst,
            Out_Pulse => EccInj_Core
        );

    i_ecc_inj_user : entity work.ofb_cc_pulse
        generic map (
            NumPulses_g => 2 * Ch_c
        )
        port map (
            In_Clk    => Clk,
            In_Rst    => Rst,
            In_Pulse  => EccInjToU,
            Out_Clk   => UserClk,
            Out_Rst   => UserRst,
            Out_Pulse => EccInj_User
        );

    i_ecc_inj_lane : entity work.ofb_cc_pulse
        generic map (
            NumPulses_g => 2 * Ch_c
        )
        port map (
            In_Clk    => Clk,
            In_Rst    => Rst,
            In_Pulse  => EccInjToL,
            Out_Clk   => LaneClk,
            Out_Rst   => LaneRst,
            Out_Pulse => EccInj_Lane
        );

end architecture;

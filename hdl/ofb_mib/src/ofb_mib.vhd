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

library work;
    use work.ofb_pkg.all;

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
        Clk                   : in    std_logic;
        Rst                   : in    std_logic;
        S_AxiLite_ArAddr      : in    std_logic_vector(11 downto 0);
        S_AxiLite_ArValid     : in    std_logic;
        S_AxiLite_ArReady     : out   std_logic;
        S_AxiLite_AwAddr      : in    std_logic_vector(11 downto 0);
        S_AxiLite_AwValid     : in    std_logic;
        S_AxiLite_AwReady     : out   std_logic;
        S_AxiLite_WData       : in    std_logic_vector(31 downto 0);
        S_AxiLite_WStrb       : in    std_logic_vector(3 downto 0);
        S_AxiLite_WValid      : in    std_logic;
        S_AxiLite_WReady      : out   std_logic;
        S_AxiLite_BResp       : out   std_logic_vector(1 downto 0);
        S_AxiLite_BValid      : out   std_logic;
        S_AxiLite_BReady      : in    std_logic;
        S_AxiLite_RData       : out   std_logic_vector(31 downto 0);
        S_AxiLite_RResp       : out   std_logic_vector(1 downto 0);
        S_AxiLite_RValid      : out   std_logic;
        S_AxiLite_RReady      : in    std_logic;
        Irq                   : out   std_logic;
        -- Core clock domain: Data Link layer
        CoreClk               : in    std_logic;
        CoreRst               : in    std_logic;
        Dl_DataScrambled      : out   std_logic;
        Dl_BcInterval         : out   std_logic_vector(15 downto 0);
        Dl_LinkReset          : out   std_logic;
        Dl_InterfaceReset     : out   std_logic;
        Dl_LinkResetState     : in    std_logic_vector(1 downto 0);
        Dl_RxErrState         : in    std_logic_vector(1 downto 0);
        Dl_WordIdState        : in    std_logic_vector(2 downto 0);
        Dl_ErbEmpty           : in    std_logic;
        Dl_HasCredit          : in    std_logic_vector(NumVc_g-1 downto 0);
        Dl_EvCrc16Err         : in    std_logic;
        Dl_EvCrc8Err          : in    std_logic;
        Dl_EvFrameErr         : in    std_logic;
        Dl_EvSeqErr           : in    std_logic;
        Dl_EvRetry            : in    std_logic;
        Dl_EvProtocolError    : in    std_logic;
        Dl_EvFarEndLinkReset  : in    std_logic;
        Dl_EvBcDiscard        : in    std_logic;
        Dl_EvInputOverflow    : in    std_logic_vector(NumVc_g-1 downto 0);
        Dl_EvCreditOverflow   : in    std_logic_vector(NumVc_g-1 downto 0);
        Dl_BwOver             : in    std_logic_vector(NumVc_g-1 downto 0);
        Dl_BwUnder            : in    std_logic_vector(NumVc_g-1 downto 0);
        Dl_TimeSlot           : in    std_logic_vector(5 downto 0);
        Dl_RegWr              : out   std_logic; -- Register writes of the quality of service
        Dl_RegAddr            : out   std_logic_vector(11 downto 0);
        Dl_RegData            : out   std_logic_vector(31 downto 0);
        -- Lane clock domain: Multi-Lane layer, Lane layers, Physical adapters
        LaneClk               : in    std_logic;
        LaneRst               : in    std_logic;
        Lane_Start            : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_AutoStart        : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_Reset            : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_NearLoopback     : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_FarLoopback      : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_StandbyReason    : out   std_logic_vector(8*NumLanes_g-1 downto 0);
        Lane_State            : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        Lane_RxPolarity       : in    std_logic_vector(NumLanes_g-1 downto 0);
        Lane_NoSignal         : in    std_logic_vector(NumLanes_g-1 downto 0);
        Lane_RxErrCount       : in    std_logic_vector(8*NumLanes_g-1 downto 0);
        Lane_FarCapability    : in    std_logic_vector(8*NumLanes_g-1 downto 0);
        Lane_FarStandbyReason : in    std_logic_vector(8*NumLanes_g-1 downto 0);
        Lane_FarLostReason    : in    std_logic_vector(8*NumLanes_g-1 downto 0);
        Lane_EvRxErrOverflow  : in    std_logic_vector(NumLanes_g-1 downto 0);
        Lane_EvTimeout        : in    std_logic_vector(NumLanes_g-1 downto 0);
        Lane_EvFarStandby     : in    std_logic_vector(NumLanes_g-1 downto 0);
        Lane_EvFarLostSignal  : in    std_logic_vector(NumLanes_g-1 downto 0);
        Ml_DataSending        : in    std_logic_vector(NumLanes_g-1 downto 0);
        Ml_DataReceiving      : in    std_logic_vector(NumLanes_g-1 downto 0);
        Ml_AlignState         : in    std_logic_vector(1 downto 0);
        -- User clock domain: Network interface
        UserClk               : in    std_logic;
        UserRst               : in    std_logic;
        Ni_EvFrameErr         : in    std_logic_vector(NumVc_g-1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_mib is

    constant Id_c : std_logic_vector(31 downto 0) := x"0FB10002";

    -- Widths of the crossing vectors
    constant CoreCfgW_c  : positive := 17;
    constant CoreStatW_c : positive := 8 + 3 * NumVc_g + 6;
    constant CoreEvW_c   : positive := 8 + 2 * NumVc_g;
    constant LaneCfgW_c  : positive := 13;
    constant LaneStatW_c : positive := 38;

    type Cnt16Array_t is array (0 to NumLanes_g-1) of unsigned(15 downto 0);
    type Slv32Array_t is array (0 to NumVc_g-1) of std_logic_vector(31 downto 0);
    type Slv16Array_t is array (0 to NumVc_g-1) of std_logic_vector(15 downto 0);
    type LaneCtrlArray_t is array (0 to NumLanes_g-1) of std_logic_vector(LaneCfgW_c-1 downto 0);

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
    signal DlErrors   : std_logic_vector(9 downto 0);
    signal VcInOvf    : std_logic_vector(NumVc_g-1 downto 0);
    signal VcCrOvf    : std_logic_vector(NumVc_g-1 downto 0);
    signal VcFrErr    : std_logic_vector(NumVc_g-1 downto 0);
    signal LaneEvents : std_logic_vector(4*NumLanes_g-1 downto 0);
    signal Retries    : unsigned(31 downto 0);
    signal Crc16Cnt   : unsigned(15 downto 0);
    signal Crc8Cnt    : unsigned(15 downto 0);
    signal FrameCnt   : unsigned(15 downto 0);
    signal SeqCnt     : unsigned(15 downto 0);
    signal TimeoutCnt : Cnt16Array_t;

    -- Crossings
    signal CoreCfgIn  : std_logic_vector(CoreCfgW_c-1 downto 0);
    signal CoreCfgOut : std_logic_vector(CoreCfgW_c-1 downto 0);
    signal CoreStatIn : std_logic_vector(CoreStatW_c-1 downto 0);
    signal CoreStat   : std_logic_vector(CoreStatW_c-1 downto 0);
    signal CoreEvIn   : std_logic_vector(CoreEvW_c-1 downto 0);
    signal CoreEv     : std_logic_vector(CoreEvW_c-1 downto 0);
    signal LaneCfgIn  : std_logic_vector(LaneCfgW_c*NumLanes_g-1 downto 0);
    signal LaneCfgOut : std_logic_vector(LaneCfgW_c*NumLanes_g-1 downto 0);
    signal LaneStatIn : std_logic_vector(LaneStatW_c*NumLanes_g+2*NumLanes_g+1 downto 0);
    signal LaneStat   : std_logic_vector(LaneStatW_c*NumLanes_g+2*NumLanes_g+1 downto 0);
    signal LaneEvIn   : std_logic_vector(4*NumLanes_g-1 downto 0);
    signal LaneEv     : std_logic_vector(4*NumLanes_g-1 downto 0);
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
            Addr_v       := to_integer(unsigned(RbAddr));
            Lane_v       := (Addr_v / 16#20#) - 8;
            Reg_v        := Addr_v mod 16#20#;

            -- Events: sticky flags and counters
            DlErrors(3 downto 0) <= DlErrors(3 downto 0) or CoreEv(3 downto 0);
            DlErrors(6 downto 4) <= DlErrors(6 downto 4) or CoreEv(7 downto 5);
            DlErrors(7)          <= DlErrors(7) or (or CoreEv(7 + NumVc_g downto 8));
            DlErrors(8)          <= DlErrors(8) or (or CoreEv(7 + 2 * NumVc_g downto 8 + NumVc_g));
            DlErrors(9)          <= DlErrors(9) or (or UserEv);
            VcInOvf              <= VcInOvf or CoreEv(7 + NumVc_g downto 8);
            VcCrOvf              <= VcCrOvf or CoreEv(7 + 2 * NumVc_g downto 8 + NumVc_g);
            VcFrErr              <= VcFrErr or UserEv;
            LaneEvents           <= LaneEvents or LaneEv;
            -- (to_01: the status crossing has no value before its first transfer)
            VcBwOver  <= VcBwOver or to_01(CoreStat(7 + 2 * NumVc_g downto 8 + NumVc_g));
            VcBwUnder <= VcBwUnder or to_01(CoreStat(7 + 3 * NumVc_g downto 8 + 2 * NumVc_g));
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

            -- Writes
            if RbWr = '1' then

                case Addr_v is
                    when 16#008# =>
                        CmdLinkReset  <= RbWrData(0);
                        CmdIfReset    <= RbWrData(1);
                        DataScrambled <= RbWrData(8);
                    when 16#00C# =>
                        BcInterval <= RbWrData(15 downto 0);
                    when 16#014# =>
                        DlErrors <= DlErrors and not RbWrData(9 downto 0);
                    when 16#018# =>
                        Retries <= (others => '0');
                    when 16#01C# =>
                        Crc16Cnt <= (others => '0');
                    when 16#020# =>
                        Crc8Cnt <= (others => '0');
                    when 16#024# =>
                        FrameCnt <= (others => '0');
                    when 16#028# =>
                        SeqCnt <= (others => '0');
                    when 16#034# =>
                        VcInOvf <= VcInOvf and not RbWrData(NumVc_g-1 downto 0);
                    when 16#038# =>
                        VcCrOvf <= VcCrOvf and not RbWrData(NumVc_g-1 downto 0);
                    when 16#03C# =>
                        VcFrErr <= VcFrErr and not RbWrData(NumVc_g-1 downto 0);
                    when 16#044# =>
                        IrqMask <= RbWrData;
                    when 16#048# =>
                        VcBwOver <= VcBwOver and not RbWrData(NumVc_g-1 downto 0);
                    when 16#04C# =>
                        VcBwUnder <= VcBwUnder and not RbWrData(NumVc_g-1 downto 0);
                    when 16#050# =>
                        IdleLimit <= RbWrData;
                    when others =>
                        if Addr_v >= 16#400# and Addr_v < 16#400# + 16 * NumVc_g then
                            Vc_v := (Addr_v - 16#400#) / 16;
                            if Reg_v mod 16 = 0 then
                                VcCfg(Vc_v)(3 downto 0) <= RbWrData(3 downto 0);
                                VcCfg(Vc_v)(8)          <= RbWrData(8);
                                if Vc_v /= 0 then
                                    -- VN0 is always mapped to VC0 (ECSS 5.8.3bb)
                                    VcCfg(Vc_v)(21 downto 16) <= RbWrData(21 downto 16);
                                end if;
                            elsif Reg_v mod 16 = 4 then
                                VcBw(Vc_v) <= RbWrData(15 downto 0);
                            elsif Reg_v mod 16 = 8 then
                                VcSlotsLo(Vc_v) <= RbWrData;
                            else
                                VcSlotsHi(Vc_v) <= RbWrData;
                            end if;
                        end if;
                        if Lane_v >= 0 and Lane_v < NumLanes_g then
                            if Reg_v = 16#00# then
                                LaneCtrl(Lane_v) <= RbWrData(15 downto 8) & RbWrData(4 downto 0);
                            elsif Reg_v = 16#08# then
                                LaneEvents(4*Lane_v+3 downto 4*Lane_v) <= LaneEvents(4*Lane_v+3 downto 4*Lane_v) and
                                                                          not RbWrData(3 downto 0);
                            elsif Reg_v = 16#10# then
                                TimeoutCnt(Lane_v) <= (others => '0');
                            end if;
                        end if;
                end case;

            end if;

            -- Link Reset command: Data Link status cleared; Interface Reset: configuration reset
            if (RbWr = '1' and Addr_v = 16#008# and RbWrData(0) = '1') then
                DlErrors <= (others => '0');
                VcInOvf  <= (others => '0');
                VcCrOvf  <= (others => '0');
                Retries  <= (others => '0');
                Crc16Cnt <= (others => '0');
                Crc8Cnt  <= (others => '0');
                FrameCnt <= (others => '0');
                SeqCnt   <= (others => '0');
            end if;
            if Rst = '1' or (RbWr = '1' and Addr_v = 16#008# and RbWrData(1) = '1') then
                DataScrambled <= '1';
                BcInterval    <= x"0028";
                IdleLimit     <= std_logic_vector(to_unsigned(156250, 32));
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

                for i in 0 to NumLanes_g-1 loop
                    LaneCtrl(i)(1) <= '1';
                end loop;

            end if;
            if Rst = '1' then
                CmdLinkReset <= '0';
                CmdIfReset   <= '0';
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
            Lane_v    := (Addr_v / 16#20#) - 8;
            Reg_v     := Addr_v mod 16#20#;
            Data_v    := (others => '0');

            case Addr_v is
                when 16#000# =>
                    Data_v := Id_c;
                when 16#004# =>
                    Data_v(7 downto 0)  := std_logic_vector(to_unsigned(NumVc_g, 8));
                    Data_v(11 downto 8) := std_logic_vector(to_unsigned(NumLanes_g, 4));
                when 16#008# =>
                    Data_v(8) := DataScrambled;
                when 16#00C# =>
                    Data_v(15 downto 0) := BcInterval;
                when 16#010# =>
                    Data_v(1 downto 0) := CoreStat(1 downto 0);
                    Data_v(3 downto 2) := CoreStat(3 downto 2);
                    Data_v(6 downto 4) := CoreStat(6 downto 4);
                    Data_v(8)          := CoreStat(7);
                when 16#014# =>
                    Data_v(9 downto 0) := DlErrors;
                when 16#018# =>
                    Data_v := std_logic_vector(Retries);
                when 16#01C# =>
                    Data_v(15 downto 0) := std_logic_vector(Crc16Cnt);
                when 16#020# =>
                    Data_v(15 downto 0) := std_logic_vector(Crc8Cnt);
                when 16#024# =>
                    Data_v(15 downto 0) := std_logic_vector(FrameCnt);
                when 16#028# =>
                    Data_v(15 downto 0) := std_logic_vector(SeqCnt);
                when 16#030# =>
                    Data_v(NumVc_g-1 downto 0) := CoreStat(7 + NumVc_g downto 8);
                when 16#034# =>
                    Data_v(NumVc_g-1 downto 0) := VcInOvf;
                when 16#038# =>
                    Data_v(NumVc_g-1 downto 0) := VcCrOvf;
                when 16#03C# =>
                    Data_v(NumVc_g-1 downto 0) := VcFrErr;
                when 16#040# =>
                    Base_v                        := LaneStatW_c * NumLanes_g;
                    Data_v(NumLanes_g-1 downto 0) := LaneStat(Base_v + NumLanes_g - 1 downto Base_v);
                    Data_v(NumLanes_g+3 downto 4) := LaneStat(Base_v + 2 * NumLanes_g - 1 downto Base_v + NumLanes_g);
                    Data_v(9 downto 8)            := LaneStat(Base_v + 2 * NumLanes_g + 1 downto Base_v + 2 * NumLanes_g);
                when 16#044# =>
                    Data_v := IrqMask;
                when 16#048# =>
                    Data_v(NumVc_g-1 downto 0) := VcBwOver;
                when 16#04C# =>
                    Data_v(NumVc_g-1 downto 0) := VcBwUnder;
                when 16#050# =>
                    Data_v := IdleLimit;
                when 16#054# =>
                    Data_v(5 downto 0) := CoreStat(CoreStatW_c - 1 downto CoreStatW_c - 6);
                when others =>
                    if Addr_v >= 16#400# and Addr_v < 16#400# + 16 * NumVc_g then
                        Vc_v := (Addr_v - 16#400#) / 16;
                        if Reg_v mod 16 = 0 then
                            Data_v := VcCfg(Vc_v);
                        elsif Reg_v mod 16 = 4 then
                            Data_v(15 downto 0) := VcBw(Vc_v);
                        elsif Reg_v mod 16 = 8 then
                            Data_v := VcSlotsLo(Vc_v);
                        else
                            Data_v := VcSlotsHi(Vc_v);
                        end if;
                    end if;
                    if Lane_v >= 0 and Lane_v < NumLanes_g then
                        Base_v := LaneStatW_c * Lane_v;
                        if Reg_v = 16#00# then
                            Data_v(15 downto 8) := LaneCtrl(Lane_v)(12 downto 5);
                            Data_v(4 downto 0)  := LaneCtrl(Lane_v)(4 downto 0);
                        elsif Reg_v = 16#04# then
                            Data_v(5 downto 0)   := LaneStat(Base_v + 5 downto Base_v);
                            Data_v(15 downto 8)  := LaneStat(Base_v + 13 downto Base_v + 6);
                            Data_v(23 downto 16) := LaneStat(Base_v + 21 downto Base_v + 14);
                        elsif Reg_v = 16#08# then
                            Data_v(3 downto 0) := LaneEvents(4*Lane_v+3 downto 4*Lane_v);
                        elsif Reg_v = 16#0C# then
                            Data_v(15 downto 0) := LaneStat(Base_v + 37 downto Base_v + 22);
                        elsif Reg_v = 16#10# then
                            Data_v(15 downto 0) := std_logic_vector(TimeoutCnt(Lane_v));
                        end if;
                    end if;
            end case;

            RbRdData <= Data_v;

            -- Interrupt
            Irq_v := or (DlErrors and IrqMask(9 downto 0));

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
    CoreCfgIn <= DataScrambled & BcInterval;

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
        if RbWr = '1' and (Addr_v = 16#050# or (Addr_v >= 16#400# and Addr_v < 16#400# + 16 * NumVc_g)) then
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
            In_Clk    => Clk,
            In_Rst    => Rst,
            In_Data   => QosWrIn,
            In_Valid  => QosWr,
            Out_Clk   => CoreClk,
            Out_Rst   => CoreRst,
            Out_Data  => QosWrOut,
            Out_Valid => Dl_RegWr,
            Out_Ready => '1'
        );

    Dl_RegAddr <= QosWrOut(43 downto 32);
    Dl_RegData <= QosWrOut(31 downto 0);

    CoreStatIn <= Dl_TimeSlot & Dl_BwUnder & Dl_BwOver & Dl_HasCredit & Dl_ErbEmpty & Dl_WordIdState & Dl_RxErrState &
                  Dl_LinkResetState;

    i_core_stat : entity olo.olo_base_cc_status
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
        LaneCfgIn(LaneCfgW_c*i+LaneCfgW_c-1 downto LaneCfgW_c*i) <= LaneCtrl(i);
        Lane_Start(i)                                            <= LaneCfgOut(LaneCfgW_c*i);
        Lane_AutoStart(i)                                        <= LaneCfgOut(LaneCfgW_c*i+1);
        Lane_Reset(i)                                            <= LaneCfgOut(LaneCfgW_c*i+2);
        Lane_NearLoopback(i)                                     <= LaneCfgOut(LaneCfgW_c*i+3);
        Lane_FarLoopback(i)                                      <= LaneCfgOut(LaneCfgW_c*i+4);
        Lane_StandbyReason(8*i+7 downto 8*i)                     <= LaneCfgOut(LaneCfgW_c*i+12 downto LaneCfgW_c*i+5);

    end generate;

    p_lane_vec : process (all) is
        variable Stat_v : std_logic_vector(LaneStatW_c-1 downto 0);
        variable Ev_v   : std_logic_vector(3 downto 0);
    begin

        for i in 0 to NumLanes_g-1 loop
            Stat_v := Lane_FarLostReason(8*i+7 downto 8*i) & Lane_FarStandbyReason(8*i+7 downto 8*i) &
                      Lane_FarCapability(8*i+7 downto 8*i) & Lane_RxErrCount(8*i+7 downto 8*i) &
                      Lane_NoSignal(i) & Lane_RxPolarity(i) & Lane_State(4*i+3 downto 4*i);

            Ev_v := Lane_EvFarLostSignal(i) & Lane_EvFarStandby(i) & Lane_EvTimeout(i) & Lane_EvRxErrOverflow(i);

            LaneStatIn(LaneStatW_c*i+LaneStatW_c-1 downto LaneStatW_c*i) <= Stat_v;
            LaneEvIn(4*i+3 downto 4*i)                                   <= Ev_v;
        end loop;

        LaneStatIn(LaneStatIn'high downto LaneStatW_c*NumLanes_g) <= Ml_AlignState & Ml_DataReceiving & Ml_DataSending;
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

    i_lane_stat : entity olo.olo_base_cc_status
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
            NumPulses_g => 4 * NumLanes_g
        )
        port map (
            In_Clk    => LaneClk,
            In_Rst    => LaneRst,
            In_Pulse  => LaneEvIn,
            Out_Clk   => Clk,
            Out_Rst   => Rst,
            Out_Pulse => LaneEv
        );

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

end architecture;

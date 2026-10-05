---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Reference design for the AMD VCK190 evaluation board: one OpenFibre core with four lanes on the
-- QSFP1 cage (GTY quad 200, 6.25 Gbit/s). The lanes start with AutoStart when the far end starts;
-- every received packet and broadcast message is sent back on the same virtual channel (echo), so
-- that SpaceFibre test equipment can exercise the link without software. LEDs show the transceiver
-- and link state.
--
-- Documentation: hdl/ofb_vck190/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

library unisim;
    use unisim.vcomponents.all;

library work;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_vck190_top is
    generic (
        NumVc_g       : positive range 1 to 32 := 8;
        LedPollBits_g : positive range 4 to 24 := 16 -- link state read every 2**LedPollBits_g cycles
    );
    port (
        -- 200 MHz LVDS system clock (DDR4 DIMM clock, bank 700)
        SysClk_P    : in    std_logic;
        SysClk_N    : in    std_logic;
        -- Transceiver reference clock, 156.25 MHz (MGTREFCLK1 of quad 200)
        GtRefClk_P  : in    std_logic;
        GtRefClk_N  : in    std_logic;
        -- QSFP1, lanes 0 to 3
        Qsfp_TxP    : out   std_logic_vector(3 downto 0);
        Qsfp_TxN    : out   std_logic_vector(3 downto 0);
        Qsfp_RxP    : in    std_logic_vector(3 downto 0);
        Qsfp_RxN    : in    std_logic_vector(3 downto 0);
        -- LEDs: transmitter ready, receiver ready, all lanes aligned, link initialised
        Led         : out   std_logic_vector(3 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture struct of ofb_vck190_top is

    constant Lanes_c : positive := 4;

    -- Clocks and resets
    signal SysClkIn : std_logic;
    signal SysClk   : std_logic;
    signal PorRst   : std_logic;
    signal RefClk   : std_logic;
    signal LaneClk  : std_logic;
    signal LaneRst  : std_logic;
    signal CoreRst  : std_logic;

    -- Physical adapter interface
    signal PhyTxData : std_logic_vector(32*Lanes_c-1 downto 0);
    signal PhyTxK    : std_logic_vector(4*Lanes_c-1 downto 0);
    signal PhyRxData : std_logic_vector(32*Lanes_c-1 downto 0);
    signal PhyRxK    : std_logic_vector(4*Lanes_c-1 downto 0);
    signal PhyRxCode : std_logic_vector(4*Lanes_c-1 downto 0);
    signal PhyRxDisp : std_logic_vector(4*Lanes_c-1 downto 0);
    signal PhyRxVld  : std_logic_vector(Lanes_c-1 downto 0);
    signal TxEnable  : std_logic_vector(Lanes_c-1 downto 0);
    signal RxEnable  : std_logic_vector(Lanes_c-1 downto 0);
    signal CdrEnable : std_logic_vector(Lanes_c-1 downto 0);
    signal RxInvert  : std_logic_vector(Lanes_c-1 downto 0);
    signal NoSignal  : std_logic_vector(Lanes_c-1 downto 0);
    signal SerNearLb : std_logic_vector(Lanes_c-1 downto 0);
    signal SerFarLb  : std_logic_vector(Lanes_c-1 downto 0);
    signal TxReady   : std_logic;
    signal RxReady   : std_logic;
    signal Aligned   : std_logic_vector(Lanes_c-1 downto 0);

    -- Echo of the virtual channels and broadcast messages
    signal VcData  : std_logic_vector(32*Lanes_c*NumVc_g-1 downto 0);
    signal VcUser  : std_logic_vector(4*Lanes_c*NumVc_g-1 downto 0);
    signal VcValid : std_logic_vector(NumVc_g-1 downto 0);
    signal VcReady : std_logic_vector(NumVc_g-1 downto 0);
    signal BcData  : std_logic_vector(63 downto 0);
    signal BcUser  : std_logic_vector(17 downto 0);
    signal BcValid : std_logic;
    signal BcReady : std_logic;

    -- MIB poller (link state for the LED)
    signal ArAddr  : std_logic_vector(11 downto 0)      := x"010";
    signal ArValid : std_logic                          := '0';
    signal ArReady : std_logic;
    signal RData   : std_logic_vector(31 downto 0);
    signal RValid  : std_logic;
    signal PollCnt : unsigned(LedPollBits_g-1 downto 0) := (others => '0');
    signal LinkUp  : std_logic                          := '0';

begin

    -----------------------------------------------------------------------------------------------
    -- Clocks and power-on reset
    -----------------------------------------------------------------------------------------------
    i_sysclk_ibuf : component ibufds
        port map (
            I  => SysClk_P,
            IB => SysClk_N,
            O  => SysClkIn
        );

    i_sysclk_bufg : component bufg
        port map (
            I => SysClkIn,
            O => SysClk
        );

    i_por : entity olo.olo_base_reset_gen
        generic map (
            RstPulseCycles_g => 1000
        )
        port map (
            Clk    => SysClk,
            RstOut => PorRst
        );

    -- Port names of the primitive
    -- vsg_off port_map_002
    i_refclk : component ibufds_gte5
        port map (
            I     => GtRefClk_P,
            IB    => GtRefClk_N,
            CEB   => '0',
            O     => RefClk,
            ODIV2 => open
        );

    -- vsg_on port_map_002

    -----------------------------------------------------------------------------------------------
    -- Physical adapter and core
    -----------------------------------------------------------------------------------------------
    i_pa : entity work.ofb_pa_gty
        generic map (
            NumLanes_g => Lanes_c
        )
        port map (
            FreeRunClk             => SysClk,
            Rst                    => PorRst,
            RefClk                 => RefClk,
            LaneClk                => LaneClk,
            LaneRst                => LaneRst,
            Gt_TxP                 => Qsfp_TxP,
            Gt_TxN                 => Qsfp_TxN,
            Gt_RxP                 => Qsfp_RxP,
            Gt_RxN                 => Qsfp_RxN,
            PhyTx_Data             => PhyTxData,
            PhyTx_K                => PhyTxK,
            PhyRx_Data             => PhyRxData,
            PhyRx_K                => PhyRxK,
            PhyRx_CodeErr          => PhyRxCode,
            PhyRx_DispErr          => PhyRxDisp,
            PhyRx_Valid            => PhyRxVld,
            Phy_TxEnable           => TxEnable,
            Phy_RxEnable           => RxEnable,
            Phy_CdrEnable          => CdrEnable,
            Phy_RxInvert           => RxInvert,
            Phy_NoSignal           => NoSignal,
            Stat_TxReady           => TxReady,
            Stat_RxReady           => RxReady,
            Stat_Aligned           => Aligned,
            Stat_RxBufErr          => open,
            Stat_ClkCor            => open,
            Phy_SerialNearLoopback => SerNearLb,
            Phy_SerialFarLoopback  => SerFarLb
        );

    CoreRst <= PorRst or LaneRst;

    i_core : entity work.ofb_core
        generic map (
            NumVc_g       => NumVc_g,
            NumLanes_g    => Lanes_c,
            LaneClkFreq_g => 156.25e6,
            CoreClkFreq_g => 156.25e6,
            VcInDepth_g   => 256 * Lanes_c
        )
        port map (
            Rst                    => CoreRst,
            UserClk                => LaneClk,
            CoreClk                => LaneClk,
            LaneClk                => LaneClk,
            MgmtClk                => SysClk,
            S_Vc_TData             => VcData,
            S_Vc_TUser             => VcUser,
            S_Vc_TValid            => VcValid,
            S_Vc_TReady            => VcReady,
            M_Vc_TData             => VcData,
            M_Vc_TUser             => VcUser,
            M_Vc_TValid            => VcValid,
            M_Vc_TReady            => VcReady,
            S_Bc_TData             => BcData,
            S_Bc_TUser             => BcUser(16 downto 0),
            S_Bc_TValid            => BcValid,
            S_Bc_TReady            => BcReady,
            M_Bc_TData             => BcData,
            M_Bc_TUser             => BcUser,
            M_Bc_TValid            => BcValid,
            M_Bc_TReady            => BcReady,
            S_AxiLite_ArAddr       => ArAddr,
            S_AxiLite_ArValid      => ArValid,
            S_AxiLite_ArReady      => ArReady,
            S_AxiLite_AwAddr       => (others => '0'),
            S_AxiLite_AwValid      => '0',
            S_AxiLite_AwReady      => open,
            S_AxiLite_WData        => (others => '0'),
            S_AxiLite_WStrb        => (others => '0'),
            S_AxiLite_WValid       => '0',
            S_AxiLite_WReady       => open,
            S_AxiLite_BResp        => open,
            S_AxiLite_BValid       => open,
            S_AxiLite_BReady       => '1',
            S_AxiLite_RData        => RData,
            S_AxiLite_RResp        => open,
            S_AxiLite_RValid       => RValid,
            S_AxiLite_RReady       => '1',
            Irq                    => open,
            PhyTx_Data             => PhyTxData,
            PhyTx_K                => PhyTxK,
            PhyRx_Data             => PhyRxData,
            PhyRx_K                => PhyRxK,
            PhyRx_CodeErr          => PhyRxCode,
            PhyRx_DispErr          => PhyRxDisp,
            PhyRx_Valid            => PhyRxVld,
            Phy_TxEnable           => TxEnable,
            Phy_RxEnable           => RxEnable,
            Phy_CdrEnable          => CdrEnable,
            Phy_RxInvert           => RxInvert,
            Phy_NoSignal           => NoSignal,
            Phy_SerialNearLoopback => SerNearLb,
            Phy_SerialFarLoopback  => SerFarLb,
            Phy_BitSync            => Aligned
        );

    -----------------------------------------------------------------------------------------------
    -- Link state: DL_STATUS read every 2**LedPollBits_g cycles of the system clock
    -----------------------------------------------------------------------------------------------
    p_poll : process (SysClk) is
    begin
        if rising_edge(SysClk) then
            PollCnt <= PollCnt + 1;
            if PollCnt = 0 then
                ArValid <= '1';
            elsif ArReady = '1' then
                ArValid <= '0';
            end if;
            if RValid = '1' then
                if RData(1 downto 0) = "11" then
                    LinkUp <= '1';
                else
                    LinkUp <= '0';
                end if;
            end if;
            if PorRst = '1' then
                PollCnt <= (others => '0');
                ArValid <= '0';
                LinkUp  <= '0';
            end if;
        end if;
    end process;

    Led(0) <= TxReady;
    Led(1) <= RxReady;
    Led(2) <= '1' when Aligned = (Aligned'range => '1') else '0';
    Led(3) <= LinkUp;

end architecture;

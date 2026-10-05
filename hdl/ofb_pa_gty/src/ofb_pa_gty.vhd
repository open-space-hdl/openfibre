---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Physical adapter PA-1 for one AMD Versal GTY quad: serialiser, 8B/10B codec, comma alignment and
-- receive clock correction in the transceiver (Versal Transceivers Wizard instance ofb_gtw, created
-- by tcl/ofb_gtw.tcl), mapped to the symbol stream interface of ofb_core.
--
-- Documentation: hdl/ofb_pa_gty/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library olo;

library unisim;
    use unisim.vcomponents.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_pa_gty is
    generic (
        NumLanes_g  : positive range 1 to 4 := 4;
        SimDevice_g : string                := "VERSAL_AI_CORE" -- SIM_DEVICE of BUFG_GT (device family)
    );
    port (
        -- Free-running clock of the transceiver reset controller, asynchronous reset (high active)
        FreeRunClk    : in    std_logic;
        Rst           : in    std_logic;
        -- Reference clock of the quad (output O of the IBUFDS_GTE5 of the reference clock pins)
        RefClk        : in    std_logic;
        -- Word clock of the lanes (transmit user clock of the quad) and its reset
        LaneClk       : out   std_logic;
        LaneRst       : out   std_logic;
        -- Serial lines
        Gt_TxP        : out   std_logic_vector(NumLanes_g-1 downto 0);
        Gt_TxN        : out   std_logic_vector(NumLanes_g-1 downto 0);
        Gt_RxP        : in    std_logic_vector(NumLanes_g-1 downto 0);
        Gt_RxN        : in    std_logic_vector(NumLanes_g-1 downto 0);
        -- Symbol streams (LaneClk), as the Physical adapter ports of ofb_core
        PhyTx_Data    : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        PhyTx_K       : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        PhyRx_Data    : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        PhyRx_K       : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        PhyRx_CodeErr : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        PhyRx_DispErr : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        PhyRx_Valid   : out   std_logic_vector(NumLanes_g-1 downto 0);
        Phy_TxEnable  : in    std_logic_vector(NumLanes_g-1 downto 0);
        Phy_RxEnable  : in    std_logic_vector(NumLanes_g-1 downto 0);
        Phy_CdrEnable : in    std_logic_vector(NumLanes_g-1 downto 0);
        Phy_RxInvert  : in    std_logic_vector(NumLanes_g-1 downto 0);
        Phy_NoSignal  : out   std_logic_vector(NumLanes_g-1 downto 0);
        -- Status (LaneClk)
        Stat_TxReady  : out   std_logic;
        Stat_RxReady  : out   std_logic;
        Stat_Aligned  : out   std_logic_vector(NumLanes_g-1 downto 0);
        Stat_RxBufErr : out   std_logic_vector(NumLanes_g-1 downto 0);
        Stat_ClkCor   : out   std_logic_vector(NumLanes_g-1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture struct of ofb_pa_gty is

    -- The wizard always has the four channels of the quad
    constant Ch_c : positive := 4;

    type Data128_t is array (0 to Ch_c-1) of std_logic_vector(127 downto 0);
    type Ctrl16_t is array (0 to Ch_c-1) of std_logic_vector(15 downto 0);
    type Ctrl8_t is array (0 to Ch_c-1) of std_logic_vector(7 downto 0);
    type Status3_t is array (0 to Ch_c-1) of std_logic_vector(2 downto 0);
    type Status2_t is array (0 to Ch_c-1) of std_logic_vector(1 downto 0);

    -- Port names of the transceiver wizard
    -- vsg_off port_010
    component ofb_gtw is
        port (
            gtpowergood                      : out   std_logic;
            gtwiz_freerun_clk                : in    std_logic;
            QUAD0_GTREFCLK0                  : in    std_logic;
            QUAD0_TX0_outclk                 : out   std_logic;
            QUAD0_RX0_outclk                 : out   std_logic;
            QUAD0_rxp                        : in    std_logic_vector(3 downto 0);
            QUAD0_rxn                        : in    std_logic_vector(3 downto 0);
            QUAD0_txp                        : out   std_logic_vector(3 downto 0);
            QUAD0_txn                        : out   std_logic_vector(3 downto 0);
            QUAD0_TX0_usrclk                 : in    std_logic;
            QUAD0_TX1_usrclk                 : in    std_logic;
            QUAD0_TX2_usrclk                 : in    std_logic;
            QUAD0_TX3_usrclk                 : in    std_logic;
            QUAD0_RX0_usrclk                 : in    std_logic;
            QUAD0_RX1_usrclk                 : in    std_logic;
            QUAD0_RX2_usrclk                 : in    std_logic;
            QUAD0_RX3_usrclk                 : in    std_logic;
            INTF0_TX0_ch_txdata              : in    std_logic_vector(127 downto 0);
            INTF0_TX0_ch_txbufstatus         : out   std_logic_vector(1 downto 0);
            INTF0_TX0_ch_txresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_TX0_ch_txpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_TX0_ch_txrate              : in    std_logic_vector(7 downto 0);
            INTF0_TX0_ch_txelecidle          : in    std_logic_vector(0 downto 0);
            INTF0_TX0_ch_txctrl0             : in    std_logic_vector(15 downto 0);
            INTF0_TX0_ch_txctrl1             : in    std_logic_vector(15 downto 0);
            INTF0_TX0_ch_txctrl2             : in    std_logic_vector(7 downto 0);
            INTF0_TX1_ch_txdata              : in    std_logic_vector(127 downto 0);
            INTF0_TX1_ch_txbufstatus         : out   std_logic_vector(1 downto 0);
            INTF0_TX1_ch_txresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_TX1_ch_txpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_TX1_ch_txrate              : in    std_logic_vector(7 downto 0);
            INTF0_TX1_ch_txelecidle          : in    std_logic_vector(0 downto 0);
            INTF0_TX1_ch_txctrl0             : in    std_logic_vector(15 downto 0);
            INTF0_TX1_ch_txctrl1             : in    std_logic_vector(15 downto 0);
            INTF0_TX1_ch_txctrl2             : in    std_logic_vector(7 downto 0);
            INTF0_TX2_ch_txdata              : in    std_logic_vector(127 downto 0);
            INTF0_TX2_ch_txbufstatus         : out   std_logic_vector(1 downto 0);
            INTF0_TX2_ch_txresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_TX2_ch_txpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_TX2_ch_txrate              : in    std_logic_vector(7 downto 0);
            INTF0_TX2_ch_txelecidle          : in    std_logic_vector(0 downto 0);
            INTF0_TX2_ch_txctrl0             : in    std_logic_vector(15 downto 0);
            INTF0_TX2_ch_txctrl1             : in    std_logic_vector(15 downto 0);
            INTF0_TX2_ch_txctrl2             : in    std_logic_vector(7 downto 0);
            INTF0_TX3_ch_txdata              : in    std_logic_vector(127 downto 0);
            INTF0_TX3_ch_txbufstatus         : out   std_logic_vector(1 downto 0);
            INTF0_TX3_ch_txresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_TX3_ch_txpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_TX3_ch_txrate              : in    std_logic_vector(7 downto 0);
            INTF0_TX3_ch_txelecidle          : in    std_logic_vector(0 downto 0);
            INTF0_TX3_ch_txctrl0             : in    std_logic_vector(15 downto 0);
            INTF0_TX3_ch_txctrl1             : in    std_logic_vector(15 downto 0);
            INTF0_TX3_ch_txctrl2             : in    std_logic_vector(7 downto 0);
            INTF0_RX0_ch_rxbufstatus         : out   std_logic_vector(2 downto 0);
            INTF0_RX0_ch_rxcdrhold           : in    std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxrate              : in    std_logic_vector(7 downto 0);
            INTF0_RX0_ch_rxdata              : out   std_logic_vector(127 downto 0);
            INTF0_RX0_ch_rxclkcorcnt         : out   std_logic_vector(1 downto 0);
            INTF0_RX0_ch_rxcommadet          : out   std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxbyteisaligned     : out   std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxbyterealign       : out   std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxctrl0             : out   std_logic_vector(15 downto 0);
            INTF0_RX0_ch_rxctrl1             : out   std_logic_vector(15 downto 0);
            INTF0_RX0_ch_rxctrl2             : out   std_logic_vector(7 downto 0);
            INTF0_RX0_ch_rxctrl3             : out   std_logic_vector(7 downto 0);
            INTF0_RX0_ch_rxelecidle          : out   std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxbufstatus         : out   std_logic_vector(2 downto 0);
            INTF0_RX1_ch_rxcdrhold           : in    std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxrate              : in    std_logic_vector(7 downto 0);
            INTF0_RX1_ch_rxdata              : out   std_logic_vector(127 downto 0);
            INTF0_RX1_ch_rxclkcorcnt         : out   std_logic_vector(1 downto 0);
            INTF0_RX1_ch_rxcommadet          : out   std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxbyteisaligned     : out   std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxbyterealign       : out   std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxctrl0             : out   std_logic_vector(15 downto 0);
            INTF0_RX1_ch_rxctrl1             : out   std_logic_vector(15 downto 0);
            INTF0_RX1_ch_rxctrl2             : out   std_logic_vector(7 downto 0);
            INTF0_RX1_ch_rxctrl3             : out   std_logic_vector(7 downto 0);
            INTF0_RX1_ch_rxelecidle          : out   std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxbufstatus         : out   std_logic_vector(2 downto 0);
            INTF0_RX2_ch_rxcdrhold           : in    std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxrate              : in    std_logic_vector(7 downto 0);
            INTF0_RX2_ch_rxdata              : out   std_logic_vector(127 downto 0);
            INTF0_RX2_ch_rxclkcorcnt         : out   std_logic_vector(1 downto 0);
            INTF0_RX2_ch_rxcommadet          : out   std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxbyteisaligned     : out   std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxbyterealign       : out   std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxctrl0             : out   std_logic_vector(15 downto 0);
            INTF0_RX2_ch_rxctrl1             : out   std_logic_vector(15 downto 0);
            INTF0_RX2_ch_rxctrl2             : out   std_logic_vector(7 downto 0);
            INTF0_RX2_ch_rxctrl3             : out   std_logic_vector(7 downto 0);
            INTF0_RX2_ch_rxelecidle          : out   std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxbufstatus         : out   std_logic_vector(2 downto 0);
            INTF0_RX3_ch_rxcdrhold           : in    std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxrate              : in    std_logic_vector(7 downto 0);
            INTF0_RX3_ch_rxdata              : out   std_logic_vector(127 downto 0);
            INTF0_RX3_ch_rxclkcorcnt         : out   std_logic_vector(1 downto 0);
            INTF0_RX3_ch_rxcommadet          : out   std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxbyteisaligned     : out   std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxbyterealign       : out   std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxctrl0             : out   std_logic_vector(15 downto 0);
            INTF0_RX3_ch_rxctrl1             : out   std_logic_vector(15 downto 0);
            INTF0_RX3_ch_rxctrl2             : out   std_logic_vector(7 downto 0);
            INTF0_RX3_ch_rxctrl3             : out   std_logic_vector(7 downto 0);
            INTF0_RX3_ch_rxelecidle          : out   std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_TX_clr_out                 : out   std_logic;
            INTF0_TX_clrb_leaf_out           : out   std_logic;
            INTF0_RX_clr_out                 : out   std_logic;
            INTF0_RX_clrb_leaf_out           : out   std_logic;
            INTF0_rst_all_in                 : in    std_logic;
            INTF0_rst_tx_pll_and_datapath_in : in    std_logic;
            INTF0_rst_tx_datapath_in         : in    std_logic;
            INTF0_rst_tx_done_out            : out   std_logic;
            INTF0_rst_rx_pll_and_datapath_in : in    std_logic;
            INTF0_rst_rx_datapath_in         : in    std_logic;
            INTF0_rst_rx_done_out            : out   std_logic
        );
    end component;

    -- vsg_on port_010

    -- Clocks
    signal TxOutClk : std_logic;
    signal TxClr    : std_logic;
    signal UsrClk   : std_logic;

    -- Channel signals of the quad
    signal TxData     : Data128_t;
    signal TxCtrl2    : Ctrl8_t;
    signal TxElecIdle : std_logic_vector(Ch_c-1 downto 0);
    signal RxPolarity : std_logic_vector(Ch_c-1 downto 0);
    signal RxCdrHold  : std_logic_vector(Ch_c-1 downto 0);
    signal RxData     : Data128_t;
    signal RxCtrl0    : Ctrl16_t;
    signal RxCtrl1    : Ctrl16_t;
    signal RxCtrl3    : Ctrl8_t;
    signal RxElecIdle : std_logic_vector(Ch_c-1 downto 0);
    signal RxAligned  : std_logic_vector(Ch_c-1 downto 0);
    signal RxBufStat  : Status3_t;
    signal RxClkCor   : Status2_t;

    -- Serial lines of the four channels
    signal TxP4 : std_logic_vector(Ch_c-1 downto 0);
    signal TxN4 : std_logic_vector(Ch_c-1 downto 0);
    signal RxP4 : std_logic_vector(Ch_c-1 downto 0);
    signal RxN4 : std_logic_vector(Ch_c-1 downto 0);

    -- Reset controller status
    signal TxDone : std_logic;
    signal RxDone : std_logic;

    -- Status synchronised to LaneClk
    signal SyncIn  : std_logic_vector(2*NumLanes_g+1 downto 0);
    signal SyncOut : std_logic_vector(2*NumLanes_g+1 downto 0);
    signal RxReady : std_logic;
    signal RxSeenK : std_logic_vector(Ch_c-1 downto 0) := (others => '0');

begin

    -----------------------------------------------------------------------------------------------
    -- User clock: transmit output clock of channel 0 for all transmitters and receivers (the
    -- receive elastic buffers cross from the recovered clock to the user clock)
    -----------------------------------------------------------------------------------------------
    -- vsg_off port_map_002 generic_map_002
    i_bufg : component bufg_gt
        generic map (
            SIM_DEVICE => SimDevice_g
        )
        port map (
            CE      => '1',
            CEMASK  => '0',
            CLR     => TxClr,
            CLRMASK => '0',
            DIV     => "000",
            I       => TxOutClk,
            O       => UsrClk
        );

    -- vsg_on port_map_002 generic_map_002

    LaneClk <= UsrClk;

    -----------------------------------------------------------------------------------------------
    -- First K character of every receiver after the receivers are ready
    -----------------------------------------------------------------------------------------------
    p_seen : process (UsrClk) is
    begin
        if rising_edge(UsrClk) then

            for c in 0 to Ch_c-1 loop
                if RxCtrl0(c)(3 downto 0) /= "0000" then
                    RxSeenK(c) <= '1';
                end if;
            end loop;

            if RxReady = '0' then
                RxSeenK <= (others => '0');
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Lanes to channels; channels without a lane send electrical idle
    -----------------------------------------------------------------------------------------------
    g_ch : for c in 0 to Ch_c-1 generate

        g_lane : if c < NumLanes_g generate
            Gt_TxP(c)     <= TxP4(c);
            Gt_TxN(c)     <= TxN4(c);
            RxP4(c)       <= Gt_RxP(c);
            RxN4(c)       <= Gt_RxN(c);
            TxData(c)     <= x"000000000000000000000000" & PhyTx_Data(32*c+31 downto 32*c);
            TxCtrl2(c)    <= "0000" & PhyTx_K(4*c+3 downto 4*c);
            TxElecIdle(c) <= not Phy_TxEnable(c);
            RxPolarity(c) <= Phy_RxInvert(c);
            RxCdrHold(c)  <= not Phy_CdrEnable(c);

            PhyRx_Data(32*c+31 downto 32*c) <= RxData(c)(31 downto 0);
            PhyRx_K(4*c+3 downto 4*c)       <= RxCtrl0(c)(3 downto 0);
            PhyRx_DispErr(4*c+3 downto 4*c) <= RxCtrl1(c)(3 downto 0);
            PhyRx_CodeErr(4*c+3 downto 4*c) <= RxCtrl3(c)(3 downto 0);
            -- Words are valid from the first K character after the receivers are ready (the receive buffer
            -- outputs zero words while it starts)
            PhyRx_Valid(c)   <= RxReady and Phy_RxEnable(c) and (RxSeenK(c) or (or RxCtrl0(c)(3 downto 0)));
            Stat_RxBufErr(c) <= RxBufStat(c)(2);
            Stat_ClkCor(c)   <= '1' when RxClkCor(c) /= "00" else '0';
        end generate;

        g_unused : if c >= NumLanes_g generate
            RxP4(c)       <= '0';
            RxN4(c)       <= '1';
            TxData(c)     <= (others => '0');
            TxCtrl2(c)    <= (others => '0');
            TxElecIdle(c) <= '1';
            RxPolarity(c) <= '0';
            RxCdrHold(c)  <= '0';
        end generate;

    end generate;

    -----------------------------------------------------------------------------------------------
    -- Status to LaneClk: reset done (FreeRunClk), electrical idle and comma alignment (asynchronous)
    -----------------------------------------------------------------------------------------------
    SyncIn(0) <= TxDone;
    SyncIn(1) <= RxDone;

    g_sync : for l in 0 to NumLanes_g-1 generate
        SyncIn(2 + l)              <= RxElecIdle(l);
        SyncIn(2 + NumLanes_g + l) <= RxAligned(l);
    end generate;

    i_sync : entity olo.olo_intf_sync
        generic map (
            Width_g => 2*NumLanes_g+2
        )
        port map (
            Clk       => UsrClk,
            DataAsync => SyncIn,
            DataSync  => SyncOut
        );

    RxReady      <= SyncOut(1);
    Stat_TxReady <= SyncOut(0);
    Stat_RxReady <= SyncOut(1);
    LaneRst      <= not SyncOut(0);
    Phy_NoSignal <= SyncOut(NumLanes_g+1 downto 2);
    Stat_Aligned <= SyncOut(2*NumLanes_g+1 downto NumLanes_g+2);

    -----------------------------------------------------------------------------------------------
    -- Transceiver wizard instance
    -----------------------------------------------------------------------------------------------
    -- vsg_off port_map_002
    i_gtw : component ofb_gtw
        port map (
            gtpowergood                      => open,
            gtwiz_freerun_clk                => FreeRunClk,
            QUAD0_GTREFCLK0                  => RefClk,
            QUAD0_TX0_outclk                 => TxOutClk,
            QUAD0_RX0_outclk                 => open,
            QUAD0_rxp                        => RxP4,
            QUAD0_rxn                        => RxN4,
            QUAD0_txp                        => TxP4,
            QUAD0_txn                        => TxN4,
            QUAD0_TX0_usrclk                 => UsrClk,
            QUAD0_TX1_usrclk                 => UsrClk,
            QUAD0_TX2_usrclk                 => UsrClk,
            QUAD0_TX3_usrclk                 => UsrClk,
            QUAD0_RX0_usrclk                 => UsrClk,
            QUAD0_RX1_usrclk                 => UsrClk,
            QUAD0_RX2_usrclk                 => UsrClk,
            QUAD0_RX3_usrclk                 => UsrClk,
            INTF0_TX0_ch_txdata              => TxData(0),
            INTF0_TX0_ch_txbufstatus         => open,
            INTF0_TX0_ch_txresetdone         => open,
            INTF0_TX0_ch_txpolarity          => "0",
            INTF0_TX0_ch_txrate              => x"00",
            INTF0_TX0_ch_txelecidle(0)       => TxElecIdle(0),
            INTF0_TX0_ch_txctrl0             => x"0000",
            INTF0_TX0_ch_txctrl1             => x"0000",
            INTF0_TX0_ch_txctrl2             => TxCtrl2(0),
            INTF0_TX1_ch_txdata              => TxData(1),
            INTF0_TX1_ch_txbufstatus         => open,
            INTF0_TX1_ch_txresetdone         => open,
            INTF0_TX1_ch_txpolarity          => "0",
            INTF0_TX1_ch_txrate              => x"00",
            INTF0_TX1_ch_txelecidle(0)       => TxElecIdle(1),
            INTF0_TX1_ch_txctrl0             => x"0000",
            INTF0_TX1_ch_txctrl1             => x"0000",
            INTF0_TX1_ch_txctrl2             => TxCtrl2(1),
            INTF0_TX2_ch_txdata              => TxData(2),
            INTF0_TX2_ch_txbufstatus         => open,
            INTF0_TX2_ch_txresetdone         => open,
            INTF0_TX2_ch_txpolarity          => "0",
            INTF0_TX2_ch_txrate              => x"00",
            INTF0_TX2_ch_txelecidle(0)       => TxElecIdle(2),
            INTF0_TX2_ch_txctrl0             => x"0000",
            INTF0_TX2_ch_txctrl1             => x"0000",
            INTF0_TX2_ch_txctrl2             => TxCtrl2(2),
            INTF0_TX3_ch_txdata              => TxData(3),
            INTF0_TX3_ch_txbufstatus         => open,
            INTF0_TX3_ch_txresetdone         => open,
            INTF0_TX3_ch_txpolarity          => "0",
            INTF0_TX3_ch_txrate              => x"00",
            INTF0_TX3_ch_txelecidle(0)       => TxElecIdle(3),
            INTF0_TX3_ch_txctrl0             => x"0000",
            INTF0_TX3_ch_txctrl1             => x"0000",
            INTF0_TX3_ch_txctrl2             => TxCtrl2(3),
            INTF0_RX0_ch_rxbufstatus         => RxBufStat(0),
            INTF0_RX0_ch_rxcdrhold(0)        => RxCdrHold(0),
            INTF0_RX0_ch_rxpolarity(0)       => RxPolarity(0),
            INTF0_RX0_ch_rxrate              => x"00",
            INTF0_RX0_ch_rxdata              => RxData(0),
            INTF0_RX0_ch_rxclkcorcnt         => RxClkCor(0),
            INTF0_RX0_ch_rxcommadet          => open,
            INTF0_RX0_ch_rxbyteisaligned(0)  => RxAligned(0),
            INTF0_RX0_ch_rxbyterealign       => open,
            INTF0_RX0_ch_rxctrl0             => RxCtrl0(0),
            INTF0_RX0_ch_rxctrl1             => RxCtrl1(0),
            INTF0_RX0_ch_rxctrl2             => open,
            INTF0_RX0_ch_rxctrl3             => RxCtrl3(0),
            INTF0_RX0_ch_rxelecidle(0)       => RxElecIdle(0),
            INTF0_RX0_ch_rxresetdone         => open,
            INTF0_RX1_ch_rxbufstatus         => RxBufStat(1),
            INTF0_RX1_ch_rxcdrhold(0)        => RxCdrHold(1),
            INTF0_RX1_ch_rxpolarity(0)       => RxPolarity(1),
            INTF0_RX1_ch_rxrate              => x"00",
            INTF0_RX1_ch_rxdata              => RxData(1),
            INTF0_RX1_ch_rxclkcorcnt         => RxClkCor(1),
            INTF0_RX1_ch_rxcommadet          => open,
            INTF0_RX1_ch_rxbyteisaligned(0)  => RxAligned(1),
            INTF0_RX1_ch_rxbyterealign       => open,
            INTF0_RX1_ch_rxctrl0             => RxCtrl0(1),
            INTF0_RX1_ch_rxctrl1             => RxCtrl1(1),
            INTF0_RX1_ch_rxctrl2             => open,
            INTF0_RX1_ch_rxctrl3             => RxCtrl3(1),
            INTF0_RX1_ch_rxelecidle(0)       => RxElecIdle(1),
            INTF0_RX1_ch_rxresetdone         => open,
            INTF0_RX2_ch_rxbufstatus         => RxBufStat(2),
            INTF0_RX2_ch_rxcdrhold(0)        => RxCdrHold(2),
            INTF0_RX2_ch_rxpolarity(0)       => RxPolarity(2),
            INTF0_RX2_ch_rxrate              => x"00",
            INTF0_RX2_ch_rxdata              => RxData(2),
            INTF0_RX2_ch_rxclkcorcnt         => RxClkCor(2),
            INTF0_RX2_ch_rxcommadet          => open,
            INTF0_RX2_ch_rxbyteisaligned(0)  => RxAligned(2),
            INTF0_RX2_ch_rxbyterealign       => open,
            INTF0_RX2_ch_rxctrl0             => RxCtrl0(2),
            INTF0_RX2_ch_rxctrl1             => RxCtrl1(2),
            INTF0_RX2_ch_rxctrl2             => open,
            INTF0_RX2_ch_rxctrl3             => RxCtrl3(2),
            INTF0_RX2_ch_rxelecidle(0)       => RxElecIdle(2),
            INTF0_RX2_ch_rxresetdone         => open,
            INTF0_RX3_ch_rxbufstatus         => RxBufStat(3),
            INTF0_RX3_ch_rxcdrhold(0)        => RxCdrHold(3),
            INTF0_RX3_ch_rxpolarity(0)       => RxPolarity(3),
            INTF0_RX3_ch_rxrate              => x"00",
            INTF0_RX3_ch_rxdata              => RxData(3),
            INTF0_RX3_ch_rxclkcorcnt         => RxClkCor(3),
            INTF0_RX3_ch_rxcommadet          => open,
            INTF0_RX3_ch_rxbyteisaligned(0)  => RxAligned(3),
            INTF0_RX3_ch_rxbyterealign       => open,
            INTF0_RX3_ch_rxctrl0             => RxCtrl0(3),
            INTF0_RX3_ch_rxctrl1             => RxCtrl1(3),
            INTF0_RX3_ch_rxctrl2             => open,
            INTF0_RX3_ch_rxctrl3             => RxCtrl3(3),
            INTF0_RX3_ch_rxelecidle(0)       => RxElecIdle(3),
            INTF0_RX3_ch_rxresetdone         => open,
            INTF0_TX_clr_out                 => TxClr,
            INTF0_TX_clrb_leaf_out           => open,
            INTF0_RX_clr_out                 => open,
            INTF0_RX_clrb_leaf_out           => open,
            INTF0_rst_all_in                 => Rst,
            INTF0_rst_tx_pll_and_datapath_in => '0',
            INTF0_rst_tx_datapath_in         => '0',
            INTF0_rst_tx_done_out            => TxDone,
            INTF0_rst_rx_pll_and_datapath_in => '0',
            INTF0_rst_rx_datapath_in         => '0',
            INTF0_rst_rx_done_out            => RxDone
        );

-- vsg_on port_map_002

end architecture;

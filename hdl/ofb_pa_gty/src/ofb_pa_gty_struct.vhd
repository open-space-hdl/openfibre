---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Architecture struct of the Physical adapter PA-1 for one AMD Versal GTY quad: serialiser, 8B/10B
-- codec, comma alignment and receive clock correction in the transceiver (Versal Transceivers Wizard
-- instance ofb_gtw, created by tcl/ofb_gtw.tcl). The entity is in ofb_pa_gty.vhd.
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
    type Status4_t is array (0 to Ch_c-1) of std_logic_vector(3 downto 0);
    type Status5_t is array (0 to Ch_c-1) of std_logic_vector(4 downto 0);
    type Status7_t is array (0 to Ch_c-1) of std_logic_vector(6 downto 0);

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
            QUAD0_ch0_loopback               : in    std_logic_vector(2 downto 0);
            QUAD0_ch1_loopback               : in    std_logic_vector(2 downto 0);
            QUAD0_ch2_loopback               : in    std_logic_vector(2 downto 0);
            QUAD0_ch3_loopback               : in    std_logic_vector(2 downto 0);
            INTF0_TX0_ch_txdata              : in    std_logic_vector(127 downto 0);
            INTF0_TX0_ch_txbufstatus         : out   std_logic_vector(1 downto 0);
            INTF0_TX0_ch_txresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_TX0_ch_txpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_TX0_ch_txrate              : in    std_logic_vector(7 downto 0);
            INTF0_TX0_ch_txelecidle          : in    std_logic_vector(0 downto 0);
            INTF0_TX0_ch_txctrl0             : in    std_logic_vector(15 downto 0);
            INTF0_TX0_ch_txctrl1             : in    std_logic_vector(15 downto 0);
            INTF0_TX0_ch_txctrl2             : in    std_logic_vector(7 downto 0);
            INTF0_TX0_ch_txprbssel           : in    std_logic_vector(3 downto 0);
            INTF0_TX0_ch_txprbsforceerr      : in    std_logic_vector(0 downto 0);
            INTF0_TX1_ch_txdata              : in    std_logic_vector(127 downto 0);
            INTF0_TX1_ch_txbufstatus         : out   std_logic_vector(1 downto 0);
            INTF0_TX1_ch_txresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_TX1_ch_txpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_TX1_ch_txrate              : in    std_logic_vector(7 downto 0);
            INTF0_TX1_ch_txelecidle          : in    std_logic_vector(0 downto 0);
            INTF0_TX1_ch_txctrl0             : in    std_logic_vector(15 downto 0);
            INTF0_TX1_ch_txctrl1             : in    std_logic_vector(15 downto 0);
            INTF0_TX1_ch_txctrl2             : in    std_logic_vector(7 downto 0);
            INTF0_TX1_ch_txprbssel           : in    std_logic_vector(3 downto 0);
            INTF0_TX1_ch_txprbsforceerr      : in    std_logic_vector(0 downto 0);
            INTF0_TX2_ch_txdata              : in    std_logic_vector(127 downto 0);
            INTF0_TX2_ch_txbufstatus         : out   std_logic_vector(1 downto 0);
            INTF0_TX2_ch_txresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_TX2_ch_txpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_TX2_ch_txrate              : in    std_logic_vector(7 downto 0);
            INTF0_TX2_ch_txelecidle          : in    std_logic_vector(0 downto 0);
            INTF0_TX2_ch_txctrl0             : in    std_logic_vector(15 downto 0);
            INTF0_TX2_ch_txctrl1             : in    std_logic_vector(15 downto 0);
            INTF0_TX2_ch_txctrl2             : in    std_logic_vector(7 downto 0);
            INTF0_TX2_ch_txprbssel           : in    std_logic_vector(3 downto 0);
            INTF0_TX2_ch_txprbsforceerr      : in    std_logic_vector(0 downto 0);
            INTF0_TX3_ch_txdata              : in    std_logic_vector(127 downto 0);
            INTF0_TX3_ch_txbufstatus         : out   std_logic_vector(1 downto 0);
            INTF0_TX3_ch_txresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_TX3_ch_txpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_TX3_ch_txrate              : in    std_logic_vector(7 downto 0);
            INTF0_TX3_ch_txelecidle          : in    std_logic_vector(0 downto 0);
            INTF0_TX3_ch_txctrl0             : in    std_logic_vector(15 downto 0);
            INTF0_TX3_ch_txctrl1             : in    std_logic_vector(15 downto 0);
            INTF0_TX3_ch_txctrl2             : in    std_logic_vector(7 downto 0);
            INTF0_TX3_ch_txprbssel           : in    std_logic_vector(3 downto 0);
            INTF0_TX3_ch_txprbsforceerr      : in    std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxbufstatus         : out   std_logic_vector(2 downto 0);
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
            INTF0_RX0_ch_rxresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxprbssel           : in    std_logic_vector(3 downto 0);
            INTF0_RX0_ch_rxprbscntreset      : in    std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxprbserr           : out   std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxprbslocked        : out   std_logic_vector(0 downto 0);
            INTF0_RX0_ch_gtrxreset           : in    std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxresetmode         : in    std_logic_vector(1 downto 0);
            INTF0_RX0_ch_rxpcsresetmask      : in    std_logic_vector(4 downto 0);
            INTF0_RX0_ch_rxpmaresetmask      : in    std_logic_vector(6 downto 0);
            INTF0_RX1_ch_rxbufstatus         : out   std_logic_vector(2 downto 0);
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
            INTF0_RX1_ch_rxresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxprbssel           : in    std_logic_vector(3 downto 0);
            INTF0_RX1_ch_rxprbscntreset      : in    std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxprbserr           : out   std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxprbslocked        : out   std_logic_vector(0 downto 0);
            INTF0_RX1_ch_gtrxreset           : in    std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxresetmode         : in    std_logic_vector(1 downto 0);
            INTF0_RX1_ch_rxpcsresetmask      : in    std_logic_vector(4 downto 0);
            INTF0_RX1_ch_rxpmaresetmask      : in    std_logic_vector(6 downto 0);
            INTF0_RX2_ch_rxbufstatus         : out   std_logic_vector(2 downto 0);
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
            INTF0_RX2_ch_rxresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxprbssel           : in    std_logic_vector(3 downto 0);
            INTF0_RX2_ch_rxprbscntreset      : in    std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxprbserr           : out   std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxprbslocked        : out   std_logic_vector(0 downto 0);
            INTF0_RX2_ch_gtrxreset           : in    std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxresetmode         : in    std_logic_vector(1 downto 0);
            INTF0_RX2_ch_rxpcsresetmask      : in    std_logic_vector(4 downto 0);
            INTF0_RX2_ch_rxpmaresetmask      : in    std_logic_vector(6 downto 0);
            INTF0_RX3_ch_rxbufstatus         : out   std_logic_vector(2 downto 0);
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
            INTF0_RX3_ch_rxresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxprbssel           : in    std_logic_vector(3 downto 0);
            INTF0_RX3_ch_rxprbscntreset      : in    std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxprbserr           : out   std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxprbslocked        : out   std_logic_vector(0 downto 0);
            INTF0_RX3_ch_gtrxreset           : in    std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxresetmode         : in    std_logic_vector(1 downto 0);
            INTF0_RX3_ch_rxpcsresetmask      : in    std_logic_vector(4 downto 0);
            INTF0_RX3_ch_rxpmaresetmask      : in    std_logic_vector(6 downto 0);
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
    signal RxData     : Data128_t;
    signal RxCtrl0    : Ctrl16_t;
    signal RxCtrl1    : Ctrl16_t;
    signal RxCtrl3    : Ctrl8_t;
    signal RxAligned  : std_logic_vector(Ch_c-1 downto 0);
    signal RxBufStat  : Status3_t;
    signal RxClkCor   : Status2_t;
    signal PrbsTxSel  : Status4_t;
    signal PrbsRxSel  : Status4_t;
    signal PrbsForce  : std_logic_vector(Ch_c-1 downto 0);
    signal PrbsCntRst : std_logic_vector(Ch_c-1 downto 0);
    signal PrbsErr    : std_logic_vector(Ch_c-1 downto 0);
    signal PrbsLocked : std_logic_vector(Ch_c-1 downto 0);

    -- Serial lines of the four channels
    signal TxP4 : std_logic_vector(Ch_c-1 downto 0);
    signal TxN4 : std_logic_vector(Ch_c-1 downto 0);
    signal RxP4 : std_logic_vector(Ch_c-1 downto 0);
    signal RxN4 : std_logic_vector(Ch_c-1 downto 0);

    -- Reset controller status
    signal TxDone : std_logic;
    signal RxDone : std_logic;

    -- Transmitters ready, register of FreeRunClk
    signal TxReadyReg : std_logic := '0';
    signal TxArmed    : std_logic := '0'; -- rst_tx_done was 0 since the release of the reset

    -- Status synchronised to LaneClk
    signal SyncIn  : std_logic_vector(NumLanes_g downto 0);
    signal SyncOut : std_logic_vector(NumLanes_g downto 0);
    signal RxReady : std_logic;
    signal RxSeenK : std_logic_vector(Ch_c-1 downto 0) := (others => '0');

    -- Serial loopbacks: loopback mode per channel, transmit datapath reset after a change of the
    -- far-end loopback (FreeRunClk)
    type Loopback_t is array (0 to Ch_c-1) of std_logic_vector(2 downto 0);

    constant LbNearPma_c : std_logic_vector(2 downto 0) := "010";
    constant LbFarPma_c  : std_logic_vector(2 downto 0) := "100";

    signal Loopback  : Loopback_t                              := (others => "000");
    signal FarLbLane : std_logic_vector(NumLanes_g-1 downto 0) := (others => '0');
    signal FarLbFree : std_logic_vector(NumLanes_g-1 downto 0);
    signal FarLbLast : std_logic_vector(NumLanes_g-1 downto 0) := (others => '0');
    signal TxDpCnt   : natural range 0 to 255                  := 0;
    signal TxDpReset : std_logic                               := '0';

    -- Reset synchronised to FreeRunClk and stretched
    signal RstFree : std_logic;

    -- Receive elastic buffer reset (PA-RS-03): RX component reset in single mode as recommended by AM002 for the
    -- situations "after RX elastic buffer error", "after comma alignment" and "after recovered clock becomes stable":
    -- RXRESETMODE 11, RXPMARESETMASK 0, RXPCSRESETMASK 00100, started by a GTRXRESET pulse. Outside this reset the
    -- ports carry the values the wizard ties them to without these optional ports (sequential mode, all masks set,
    -- GTRXRESET low), as the master reset of the wizard requires.
    constant RstModeSeq_c       : std_logic_vector(1 downto 0) := "00";
    constant RstModeSingle_c    : std_logic_vector(1 downto 0) := "11";
    constant PcsMaskAll_c       : std_logic_vector(4 downto 0) := "11111";
    constant PcsMaskBuf_c       : std_logic_vector(4 downto 0) := "00100";
    constant PmaMaskAll_c       : std_logic_vector(6 downto 0) := "1111111";
    constant PmaMaskNone_c      : std_logic_vector(6 downto 0) := "0000000";
    -- FreeRunClk cycles: masks stable before the pulse, GTRXRESET pulse (at least one reference clock period), masks
    -- held after the pulse (single mode has no reset done), minimum distance between two buffer resets (100 MHz:
    -- 0.08 us, 0.16 us, 1.28 us, 2.56 us)
    constant BufSetupCycles_c   : positive := 8;
    constant BufPulseCycles_c   : positive := 16;
    constant BufHoldCycles_c    : positive := 128;
    constant BufHoldoffCycles_c : positive := 256;
    -- LaneClk cycles after a lane start in which its first comma alignment requests a buffer reset (52 us at
    -- 156.25 MHz: the initialisation timeout of 5000 words and the lock of the clock-data recovery)
    constant AlignWinCycles_c   : positive := 8192;

    type BufRstState_t is (BufIdle_s, BufSetup_s, BufPulse_s, BufHold_s, BufHoldoff_s);
    type BufRstStates_t is array (0 to NumLanes_g-1) of BufRstState_t;
    type BufRstCnts_t is array (0 to NumLanes_g-1) of natural range 0 to BufHoldoffCycles_c-1;
    type BufReqCnts_t is array (0 to NumLanes_g-1) of natural range 0 to 15;
    type AlignWins_t is array (0 to NumLanes_g-1) of natural range 0 to AlignWinCycles_c-1;

    signal RxGtReset   : std_logic_vector(Ch_c-1 downto 0)       := (others => '0');
    signal RxRstMode   : Status2_t                               := (others => RstModeSeq_c);
    signal RxPcsMask   : Status5_t                               := (others => PcsMaskAll_c);
    signal RxPmaMask   : Status7_t                               := (others => PmaMaskAll_c);
    signal RxRealign   : std_logic_vector(Ch_c-1 downto 0);
    signal ReadyLast   : std_logic                               := '0';
    signal RxEnLast    : std_logic_vector(NumLanes_g-1 downto 0) := (others => '0');
    signal AlignLast   : std_logic_vector(NumLanes_g-1 downto 0) := (others => '0');
    signal AlignArmed  : std_logic_vector(NumLanes_g-1 downto 0) := (others => '0');
    signal AlignWin    : AlignWins_t                             := (others => 0);
    signal BufReqCnt   : BufReqCnts_t                            := (others => 0);
    signal BufReqLane  : std_logic_vector(NumLanes_g-1 downto 0) := (others => '0');
    signal BufReqFree  : std_logic_vector(NumLanes_g-1 downto 0);
    signal BufPend     : std_logic_vector(NumLanes_g-1 downto 0) := (others => '0');
    signal BufRstSt    : BufRstStates_t                          := (others => BufIdle_s);
    signal BufRstCnt   : BufRstCnts_t                            := (others => 0);
    -- Reset window of a lane (setup, pulse, hold) in FreeRunClk and synchronised to LaneClk: the buffer outputs
    -- no valid words then, so its words are not passed
    signal BufBusy     : std_logic_vector(NumLanes_g-1 downto 0) := (others => '0');
    signal BufBusyLane : std_logic_vector(NumLanes_g-1 downto 0) := (others => '0');

begin

    -- Reset of the transceiver reset controller and of the FreeRunClk logic: asserted asynchronously,
    -- released synchronously to FreeRunClk after at least RstPulseCycles_g cycles (PA-RS-02)
    i_rst_free : entity olo.olo_base_reset_gen
        generic map (
            RstPulseCycles_g => RstPulseCycles_g,
            SyncTmr_g        => true
        )
        port map (
            Clk    => FreeRunClk,
            RstIn  => Rst,
            RstOut => RstFree
        );

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

            -- Reset of the receive elastic buffer: words again from the first K character after it
            for l in 0 to NumLanes_g-1 loop
                if BufBusyLane(l) = '1' then
                    RxSeenK(l) <= '0';
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

            PhyRx_Data(32*c+31 downto 32*c) <= RxData(c)(31 downto 0);
            PhyRx_K(4*c+3 downto 4*c)       <= RxCtrl0(c)(3 downto 0);
            PhyRx_DispErr(4*c+3 downto 4*c) <= RxCtrl1(c)(3 downto 0);
            PhyRx_CodeErr(4*c+3 downto 4*c) <= RxCtrl3(c)(3 downto 0);
            -- Words are valid from the first K character after the receivers are ready (the receive buffer
            -- outputs zero words while it starts)
            PhyRx_Valid(c)   <= RxReady and Phy_RxEnable(c) and not BufBusyLane(c) and
                                (RxSeenK(c) or (or RxCtrl0(c)(3 downto 0)));
            Stat_RxBufErr(c) <= RxBufStat(c)(2);
            Stat_ClkCor(c)   <= '1' when RxClkCor(c) /= "00" else '0';
            Loopback(c)      <= LbNearPma_c when Phy_SerialNearLoopback(c) = '1' else
                                LbFarPma_c when Phy_SerialFarLoopback(c) = '1' else
                                "000";
            PrbsTxSel(c)     <= Phy_PrbsTxSel(4*c+3 downto 4*c);
            PrbsRxSel(c)     <= Phy_PrbsRxSel(4*c+3 downto 4*c);
            PrbsForce(c)     <= Phy_PrbsForceErr(c);
            PrbsCntRst(c)    <= Phy_PrbsCntReset(c);
            -- Checker status: outputs of the transceiver in the receive user clock domain (LaneClk)
            Phy_PrbsErr(c)    <= PrbsErr(c);
            Phy_PrbsLocked(c) <= PrbsLocked(c);
        end generate;

        g_unused : if c >= NumLanes_g generate
            RxP4(c)       <= '0';
            RxN4(c)       <= '1';
            TxData(c)     <= (others => '0');
            TxCtrl2(c)    <= (others => '0');
            TxElecIdle(c) <= '1';
            RxPolarity(c) <= '0';
            RxGtReset(c)  <= '0';
            RxRstMode(c)  <= RstModeSeq_c;
            RxPcsMask(c)  <= PcsMaskAll_c;
            RxPmaMask(c)  <= PmaMaskAll_c;
            PrbsTxSel(c)  <= "0000";
            PrbsRxSel(c)  <= "0000";
            PrbsForce(c)  <= '0';
            PrbsCntRst(c) <= '0';
        end generate;

    end generate;

    -----------------------------------------------------------------------------------------------
    -- Status to LaneClk: receive reset done (FreeRunClk) and comma alignment (asynchronous)
    -----------------------------------------------------------------------------------------------
    SyncIn(0) <= RxDone;

    g_sync : for l in 0 to NumLanes_g-1 generate
        SyncIn(1 + l) <= RxAligned(l);
    end generate;

    -- The far-end loopback enables come from logic of the lane clock domain (the voters of the MIB
    -- crossing): a register of the lane clock in front of the synchroniser
    p_farlb_lane : process (UsrClk) is
    begin
        if rising_edge(UsrClk) then
            FarLbLane <= Phy_SerialFarLoopback;
        end if;
    end process;

    i_farlb_sync : entity olo.olo_intf_sync
        generic map (
            Width_g   => NumLanes_g,
            SyncTmr_g => true
        )
        port map (
            Clk       => FreeRunClk,
            DataAsync => FarLbLane,
            DataSync  => FarLbFree
        );

    p_txdp_reset : process (FreeRunClk) is
    begin
        if rising_edge(FreeRunClk) then
            FarLbLast <= FarLbFree;
            if FarLbFree /= FarLbLast then
                TxDpCnt <= 255;
            elsif TxDpCnt /= 0 then
                TxDpCnt <= TxDpCnt - 1;
            end if;
            if TxDpCnt /= 0 then
                TxDpReset <= '1';
            else
                TxDpReset <= '0';
            end if;
            if RstFree = '1' then
                FarLbLast <= (others => '0');
                TxDpCnt   <= 0;
                TxDpReset <= '0';
            end if;
        end if;
    end process;

    i_sync : entity olo.olo_intf_sync
        generic map (
            Width_g   => NumLanes_g+1,
            SyncTmr_g => true
        )
        port map (
            Clk       => UsrClk,
            DataAsync => SyncIn,
            DataSync  => SyncOut
        );

    -----------------------------------------------------------------------------------------------
    -- Receive elastic buffer reset (PA-RS-03). A request of a lane comes from an overflow or underflow of its
    -- buffer (RXBUFSTATUS[2]) and, once per lane start (receivers ready or line receiver enable rising), from
    -- the first comma alignment within AlignWinCycles_c after it (RXBYTEISALIGNED rising or an RXBYTEREALIGN
    -- pulse): the recovered clock is then stable on the new signal. Further realignments, and a realignment
    -- during traffic of a lane that was already aligned when it started, do not request a reset: a reset can
    -- neither start the next one through the comma aligner nor drop words of a running link. The request is stretched in LaneClk and synchronised
    -- to FreeRunClk; the buffer of that lane alone is reset, at most once per holdoff time.
    -----------------------------------------------------------------------------------------------
    g_bufrst : if RxBufReset_g generate

        p_bufreq : process (UsrClk) is
            variable AlignEv_v : boolean;
        begin
            if rising_edge(UsrClk) then
                ReadyLast <= RxReady;
                RxEnLast  <= Phy_RxEnable;
                AlignLast <= SyncOut(NumLanes_g downto 1);

                for l in 0 to NumLanes_g-1 loop
                    AlignEv_v := RxRealign(l) = '1' or (SyncOut(1 + l) = '1' and AlignLast(l) = '0');
                    if RxBufStat(l)(2) = '1' or (AlignArmed(l) = '1' and AlignEv_v) then
                        BufReqCnt(l)  <= 15;
                        BufReqLane(l) <= '1';
                    elsif BufReqCnt(l) /= 0 then
                        BufReqCnt(l) <= BufReqCnt(l) - 1;
                    else
                        BufReqLane(l) <= '0';
                    end if;
                    -- One alignment request per lane start, within AlignWinCycles_c after it: a realignment
                    -- later in operation (a lane already aligned when it started) requests no reset
                    if AlignEv_v then
                        AlignArmed(l) <= '0';
                    elsif AlignWin(l) /= 0 then
                        AlignWin(l) <= AlignWin(l) - 1;
                    else
                        AlignArmed(l) <= '0';
                    end if;
                    if (RxReady = '1' and ReadyLast = '0') or (Phy_RxEnable(l) = '1' and RxEnLast(l) = '0') then
                        AlignArmed(l) <= '1';
                        AlignWin(l)   <= AlignWinCycles_c - 1;
                    end if;
                end loop;

                if RxReady = '0' then
                    AlignArmed <= (others => '0');
                    AlignWin   <= (others => 0);
                    BufReqCnt  <= (others => 0);
                    BufReqLane <= (others => '0');
                end if;
            end if;
        end process;

        i_bufreq_sync : entity olo.olo_intf_sync
            generic map (
                Width_g   => NumLanes_g,
                SyncTmr_g => true
            )
            port map (
                Clk       => FreeRunClk,
                DataAsync => BufReqLane,
                DataSync  => BufReqFree
            );

        g_lane : for l in 0 to NumLanes_g-1 generate

            p_bufrst : process (FreeRunClk) is
            begin
                if rising_edge(FreeRunClk) then

                    case BufRstSt(l) is

                        when BufIdle_s =>
                            if BufReqFree(l) = '1' or BufPend(l) = '1' then
                                BufRstSt(l)  <= BufSetup_s;
                                BufRstCnt(l) <= 0;
                                BufPend(l)   <= '0';
                            end if;

                        when BufSetup_s =>
                            if BufRstCnt(l) = BufSetupCycles_c-1 then
                                BufRstSt(l)  <= BufPulse_s;
                                BufRstCnt(l) <= 0;
                            else
                                BufRstCnt(l) <= BufRstCnt(l) + 1;
                            end if;

                        when BufPulse_s =>
                            if BufRstCnt(l) = BufPulseCycles_c-1 then
                                BufRstSt(l)  <= BufHold_s;
                                BufRstCnt(l) <= 0;
                            else
                                BufRstCnt(l) <= BufRstCnt(l) + 1;
                            end if;

                        when BufHold_s =>
                            if BufRstCnt(l) = BufHoldCycles_c-1 then
                                BufRstSt(l)  <= BufHoldoff_s;
                                BufRstCnt(l) <= 0;
                            else
                                BufRstCnt(l) <= BufRstCnt(l) + 1;
                            end if;

                        when BufHoldoff_s =>
                            if BufRstCnt(l) = BufHoldoffCycles_c-1 then
                                BufRstSt(l)  <= BufIdle_s;
                                BufRstCnt(l) <= 0;
                            else
                                BufRstCnt(l) <= BufRstCnt(l) + 1;
                            end if;

                        -- coverage off
                        when others =>
                            BufRstSt(l) <= BufIdle_s;
                        -- coverage on

                    end case;

                    -- Ports of the component reset: single mode from the setup to the end of the hold time,
                    -- GTRXRESET during the pulse, otherwise the values of the master reset
                    case BufRstSt(l) is
                        when BufSetup_s | BufHold_s =>
                            RxRstMode(l) <= RstModeSingle_c;
                            RxPcsMask(l) <= PcsMaskBuf_c;
                            RxPmaMask(l) <= PmaMaskNone_c;
                            RxGtReset(l) <= '0';
                            BufBusy(l)   <= '1';
                        when BufPulse_s =>
                            RxRstMode(l) <= RstModeSingle_c;
                            RxPcsMask(l) <= PcsMaskBuf_c;
                            RxPmaMask(l) <= PmaMaskNone_c;
                            RxGtReset(l) <= '1';
                            BufBusy(l)   <= '1';
                        when others =>
                            RxRstMode(l) <= RstModeSeq_c;
                            RxPcsMask(l) <= PcsMaskAll_c;
                            RxPmaMask(l) <= PmaMaskAll_c;
                            RxGtReset(l) <= '0';
                            BufBusy(l)   <= '0';
                    end case;

                    -- A request after the reset pulse (hold or holdoff time) is served after the holdoff
                    if BufReqFree(l) = '1' and (BufRstSt(l) = BufHold_s or BufRstSt(l) = BufHoldoff_s) then
                        BufPend(l) <= '1';
                    end if;

                    -- Only while the receivers are ready: no component reset during a reset of the wizard
                    if RstFree = '1' or RxDone = '0' then
                        BufRstSt(l)  <= BufIdle_s;
                        BufRstCnt(l) <= 0;
                        BufPend(l)   <= '0';
                        RxRstMode(l) <= RstModeSeq_c;
                        RxPcsMask(l) <= PcsMaskAll_c;
                        RxPmaMask(l) <= PmaMaskAll_c;
                        RxGtReset(l) <= '0';
                        BufBusy(l)   <= '0';
                    end if;
                end if;
            end process;

        end generate;

        i_bufbusy_sync : entity olo.olo_intf_sync
            generic map (
                Width_g   => NumLanes_g,
                SyncTmr_g => true
            )
            port map (
                Clk       => UsrClk,
                DataAsync => BufBusy,
                DataSync  => BufBusyLane
            );

    end generate;

    -- Without the buffer reset the ports keep the values of the master reset
    g_no_bufrst : if not RxBufReset_g generate

        g_lane : for l in 0 to NumLanes_g-1 generate
            RxGtReset(l) <= '0';
            RxRstMode(l) <= RstModeSeq_c;
            RxPcsMask(l) <= PcsMaskAll_c;
            RxPmaMask(l) <= PmaMaskAll_c;
        end generate;

        BufBusyLane <= (others => '0');

    end generate;

    -----------------------------------------------------------------------------------------------
    -- Transmitters ready (PA-ST-02): the reset done of the transceiver reset controller (already in
    -- FreeRunClk) from a register. The user clock stops while the transmitters are reset (the reset
    -- controller clears the BUFG_GT until the transmit PMA reset is done), so the status is kept in
    -- the free-running clock domain.
    -----------------------------------------------------------------------------------------------
    -- rst_tx_done is taken only after it was 0 once since the release of the reset: when the reset
    -- is released, it still shows the state from before the master reset of the wizard (PA-ST-02)
    p_tx_ready : process (FreeRunClk) is
    begin
        if rising_edge(FreeRunClk) then
            if TxDone = '0' then
                TxArmed <= '1';
            end if;
            TxReadyReg <= TxDone and TxArmed;
            if RstFree = '1' then
                TxArmed    <= '0';
                TxReadyReg <= '0';
            end if;
        end if;
    end process;

    Stat_TxReady <= TxReadyReg;

    -- Lane reset: set without a clock edge while the transmitters are not ready, released
    -- synchronously to the user clock
    i_lane_rst : entity olo.olo_base_reset_gen
        generic map (
            RstInPolarity_g => '0',
            SyncTmr_g       => true
        )
        port map (
            Clk    => UsrClk,
            RstOut => LaneRst,
            RstIn  => TxReadyReg
        );

    RxReady      <= SyncOut(0);
    Stat_RxReady <= SyncOut(0);
    Stat_Aligned <= SyncOut(NumLanes_g downto 1);

    -- No loss of signal indication (PA-IF-03, ECSS 5.4.2b.1): the receive electrical idle of the transceiver is a
    -- static 0 in this configuration (AM002: OOB detection off, no data detection above 2.5 Gbit/s). A lost signal
    -- shows as words with errors, which the Lane layer counts as RXERR (ECSS 5.5.8, 5.5.2.11e.3).
    Phy_NoSignal <= (others => '0');

    -----------------------------------------------------------------------------------------------
    -- Transceiver wizard instance
    -----------------------------------------------------------------------------------------------
    -- vsg_off port_map_002
    i_gtw : component ofb_gtw
        port map (
            gtpowergood                        => open,
            gtwiz_freerun_clk                  => FreeRunClk,
            QUAD0_GTREFCLK0                    => RefClk,
            QUAD0_TX0_outclk                   => TxOutClk,
            QUAD0_RX0_outclk                   => open,
            QUAD0_rxp                          => RxP4,
            QUAD0_rxn                          => RxN4,
            QUAD0_txp                          => TxP4,
            QUAD0_txn                          => TxN4,
            QUAD0_TX0_usrclk                   => UsrClk,
            QUAD0_TX1_usrclk                   => UsrClk,
            QUAD0_TX2_usrclk                   => UsrClk,
            QUAD0_TX3_usrclk                   => UsrClk,
            QUAD0_RX0_usrclk                   => UsrClk,
            QUAD0_RX1_usrclk                   => UsrClk,
            QUAD0_RX2_usrclk                   => UsrClk,
            QUAD0_RX3_usrclk                   => UsrClk,
            QUAD0_ch0_loopback                 => Loopback(0),
            QUAD0_ch1_loopback                 => Loopback(1),
            QUAD0_ch2_loopback                 => Loopback(2),
            QUAD0_ch3_loopback                 => Loopback(3),
            INTF0_TX0_ch_txdata                => TxData(0),
            INTF0_TX0_ch_txbufstatus           => open,
            INTF0_TX0_ch_txresetdone           => open,
            INTF0_TX0_ch_txpolarity            => "0",
            INTF0_TX0_ch_txrate                => x"00",
            INTF0_TX0_ch_txelecidle(0)         => TxElecIdle(0),
            INTF0_TX0_ch_txctrl0               => x"0000",
            INTF0_TX0_ch_txctrl1               => x"0000",
            INTF0_TX0_ch_txctrl2               => TxCtrl2(0),
            INTF0_TX0_ch_txprbssel             => PrbsTxSel(0),
            INTF0_TX0_ch_txprbsforceerr(0)     => PrbsForce(0),
            INTF0_TX1_ch_txdata                => TxData(1),
            INTF0_TX1_ch_txbufstatus           => open,
            INTF0_TX1_ch_txresetdone           => open,
            INTF0_TX1_ch_txpolarity            => "0",
            INTF0_TX1_ch_txrate                => x"00",
            INTF0_TX1_ch_txelecidle(0)         => TxElecIdle(1),
            INTF0_TX1_ch_txctrl0               => x"0000",
            INTF0_TX1_ch_txctrl1               => x"0000",
            INTF0_TX1_ch_txctrl2               => TxCtrl2(1),
            INTF0_TX1_ch_txprbssel             => PrbsTxSel(1),
            INTF0_TX1_ch_txprbsforceerr(0)     => PrbsForce(1),
            INTF0_TX2_ch_txdata                => TxData(2),
            INTF0_TX2_ch_txbufstatus           => open,
            INTF0_TX2_ch_txresetdone           => open,
            INTF0_TX2_ch_txpolarity            => "0",
            INTF0_TX2_ch_txrate                => x"00",
            INTF0_TX2_ch_txelecidle(0)         => TxElecIdle(2),
            INTF0_TX2_ch_txctrl0               => x"0000",
            INTF0_TX2_ch_txctrl1               => x"0000",
            INTF0_TX2_ch_txctrl2               => TxCtrl2(2),
            INTF0_TX2_ch_txprbssel             => PrbsTxSel(2),
            INTF0_TX2_ch_txprbsforceerr(0)     => PrbsForce(2),
            INTF0_TX3_ch_txdata                => TxData(3),
            INTF0_TX3_ch_txbufstatus           => open,
            INTF0_TX3_ch_txresetdone           => open,
            INTF0_TX3_ch_txpolarity            => "0",
            INTF0_TX3_ch_txrate                => x"00",
            INTF0_TX3_ch_txelecidle(0)         => TxElecIdle(3),
            INTF0_TX3_ch_txctrl0               => x"0000",
            INTF0_TX3_ch_txctrl1               => x"0000",
            INTF0_TX3_ch_txctrl2               => TxCtrl2(3),
            INTF0_TX3_ch_txprbssel             => PrbsTxSel(3),
            INTF0_TX3_ch_txprbsforceerr(0)     => PrbsForce(3),
            INTF0_RX0_ch_rxbufstatus           => RxBufStat(0),
            INTF0_RX0_ch_rxpolarity(0)         => RxPolarity(0),
            INTF0_RX0_ch_rxrate                => x"00",
            INTF0_RX0_ch_rxdata                => RxData(0),
            INTF0_RX0_ch_rxclkcorcnt           => RxClkCor(0),
            INTF0_RX0_ch_rxcommadet            => open,
            INTF0_RX0_ch_rxbyteisaligned(0)    => RxAligned(0),
            INTF0_RX0_ch_rxbyterealign(0)      => RxRealign(0),
            INTF0_RX0_ch_rxctrl0               => RxCtrl0(0),
            INTF0_RX0_ch_rxctrl1               => RxCtrl1(0),
            INTF0_RX0_ch_rxctrl2               => open,
            INTF0_RX0_ch_rxctrl3               => RxCtrl3(0),
            INTF0_RX0_ch_rxresetdone           => open,
            INTF0_RX0_ch_rxprbssel             => PrbsRxSel(0),
            INTF0_RX0_ch_rxprbscntreset(0)     => PrbsCntRst(0),
            INTF0_RX0_ch_rxprbserr(0)          => PrbsErr(0),
            INTF0_RX0_ch_rxprbslocked(0)       => PrbsLocked(0),
            INTF0_RX0_ch_gtrxreset(0)          => RxGtReset(0),
            INTF0_RX0_ch_rxresetmode           => RxRstMode(0),
            INTF0_RX0_ch_rxpcsresetmask        => RxPcsMask(0),
            INTF0_RX0_ch_rxpmaresetmask        => RxPmaMask(0),
            INTF0_RX1_ch_rxbufstatus           => RxBufStat(1),
            INTF0_RX1_ch_rxpolarity(0)         => RxPolarity(1),
            INTF0_RX1_ch_rxrate                => x"00",
            INTF0_RX1_ch_rxdata                => RxData(1),
            INTF0_RX1_ch_rxclkcorcnt           => RxClkCor(1),
            INTF0_RX1_ch_rxcommadet            => open,
            INTF0_RX1_ch_rxbyteisaligned(0)    => RxAligned(1),
            INTF0_RX1_ch_rxbyterealign(0)      => RxRealign(1),
            INTF0_RX1_ch_rxctrl0               => RxCtrl0(1),
            INTF0_RX1_ch_rxctrl1               => RxCtrl1(1),
            INTF0_RX1_ch_rxctrl2               => open,
            INTF0_RX1_ch_rxctrl3               => RxCtrl3(1),
            INTF0_RX1_ch_rxresetdone           => open,
            INTF0_RX1_ch_rxprbssel             => PrbsRxSel(1),
            INTF0_RX1_ch_rxprbscntreset(0)     => PrbsCntRst(1),
            INTF0_RX1_ch_rxprbserr(0)          => PrbsErr(1),
            INTF0_RX1_ch_rxprbslocked(0)       => PrbsLocked(1),
            INTF0_RX1_ch_gtrxreset(0)          => RxGtReset(1),
            INTF0_RX1_ch_rxresetmode           => RxRstMode(1),
            INTF0_RX1_ch_rxpcsresetmask        => RxPcsMask(1),
            INTF0_RX1_ch_rxpmaresetmask        => RxPmaMask(1),
            INTF0_RX2_ch_rxbufstatus           => RxBufStat(2),
            INTF0_RX2_ch_rxpolarity(0)         => RxPolarity(2),
            INTF0_RX2_ch_rxrate                => x"00",
            INTF0_RX2_ch_rxdata                => RxData(2),
            INTF0_RX2_ch_rxclkcorcnt           => RxClkCor(2),
            INTF0_RX2_ch_rxcommadet            => open,
            INTF0_RX2_ch_rxbyteisaligned(0)    => RxAligned(2),
            INTF0_RX2_ch_rxbyterealign(0)      => RxRealign(2),
            INTF0_RX2_ch_rxctrl0               => RxCtrl0(2),
            INTF0_RX2_ch_rxctrl1               => RxCtrl1(2),
            INTF0_RX2_ch_rxctrl2               => open,
            INTF0_RX2_ch_rxctrl3               => RxCtrl3(2),
            INTF0_RX2_ch_rxresetdone           => open,
            INTF0_RX2_ch_rxprbssel             => PrbsRxSel(2),
            INTF0_RX2_ch_rxprbscntreset(0)     => PrbsCntRst(2),
            INTF0_RX2_ch_rxprbserr(0)          => PrbsErr(2),
            INTF0_RX2_ch_rxprbslocked(0)       => PrbsLocked(2),
            INTF0_RX2_ch_gtrxreset(0)          => RxGtReset(2),
            INTF0_RX2_ch_rxresetmode           => RxRstMode(2),
            INTF0_RX2_ch_rxpcsresetmask        => RxPcsMask(2),
            INTF0_RX2_ch_rxpmaresetmask        => RxPmaMask(2),
            INTF0_RX3_ch_rxbufstatus           => RxBufStat(3),
            INTF0_RX3_ch_rxpolarity(0)         => RxPolarity(3),
            INTF0_RX3_ch_rxrate                => x"00",
            INTF0_RX3_ch_rxdata                => RxData(3),
            INTF0_RX3_ch_rxclkcorcnt           => RxClkCor(3),
            INTF0_RX3_ch_rxcommadet            => open,
            INTF0_RX3_ch_rxbyteisaligned(0)    => RxAligned(3),
            INTF0_RX3_ch_rxbyterealign(0)      => RxRealign(3),
            INTF0_RX3_ch_rxctrl0               => RxCtrl0(3),
            INTF0_RX3_ch_rxctrl1               => RxCtrl1(3),
            INTF0_RX3_ch_rxctrl2               => open,
            INTF0_RX3_ch_rxctrl3               => RxCtrl3(3),
            INTF0_RX3_ch_rxresetdone           => open,
            INTF0_RX3_ch_rxprbssel             => PrbsRxSel(3),
            INTF0_RX3_ch_rxprbscntreset(0)     => PrbsCntRst(3),
            INTF0_RX3_ch_rxprbserr(0)          => PrbsErr(3),
            INTF0_RX3_ch_rxprbslocked(0)       => PrbsLocked(3),
            INTF0_RX3_ch_gtrxreset(0)          => RxGtReset(3),
            INTF0_RX3_ch_rxresetmode           => RxRstMode(3),
            INTF0_RX3_ch_rxpcsresetmask        => RxPcsMask(3),
            INTF0_RX3_ch_rxpmaresetmask        => RxPmaMask(3),
            INTF0_TX_clr_out                   => TxClr,
            INTF0_TX_clrb_leaf_out             => open,
            INTF0_RX_clr_out                   => open,
            INTF0_RX_clrb_leaf_out             => open,
            INTF0_rst_all_in                   => RstFree,
            INTF0_rst_tx_pll_and_datapath_in   => '0',
            INTF0_rst_tx_datapath_in           => TxDpReset,
            INTF0_rst_tx_done_out              => TxDone,
            INTF0_rst_rx_pll_and_datapath_in   => '0',
            INTF0_rst_rx_datapath_in           => '0',
            INTF0_rst_rx_done_out              => RxDone
        );

-- vsg_on port_map_002

end architecture;

---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Architecture struct of the Physical adapter PA-1 for one AMD Versal GTY quad: serialiser, 8B/10B
-- codec, comma alignment and receive clock correction in the transceiver (Versal Transceivers Wizard
-- instance ofb_gtw, created by tcl/ofb_gtw.tcl), and the reset sequencer of every lane
-- (ofb_pa_gty_lane_rst): entire receiver reset when the lane leaves the states that use the line, transmit
-- buffer reset, receive elastic buffer reset. The entity is in ofb_pa_gty.vhd.
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
    type Status16_t is array (0 to Ch_c-1) of std_logic_vector(15 downto 0);

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
            QUAD0_ch0_phyready               : out   std_logic;
            QUAD0_ch0_phyesmadaptsave        : in    std_logic;
            QUAD0_ch0_clkrsvd0               : in    std_logic;
            QUAD0_ch0_clkrsvd1               : in    std_logic;
            QUAD0_ch0_dmonitorclk            : in    std_logic;
            QUAD0_ch0_iloresetmask           : in    std_logic;
            QUAD0_ch0_loopback               : in    std_logic_vector(2 downto 0);
            QUAD0_ch0_dmonfiforeset          : in    std_logic;
            QUAD0_ch0_pcsrsvdin              : in    std_logic_vector(15 downto 0);
            QUAD0_ch0_gtrsvd                 : in    std_logic_vector(15 downto 0);
            QUAD0_ch0_tstin                  : in    std_logic_vector(19 downto 0);
            QUAD0_ch0_pcsrsvdout             : out   std_logic_vector(15 downto 0);
            QUAD0_ch0_pinrsvdas              : out   std_logic_vector(15 downto 0);
            QUAD0_ch0_dmonitoroutclk         : out   std_logic;
            QUAD0_ch0_resetexception         : out   std_logic;
            QUAD0_ch0_dmonitorout            : out   std_logic_vector(31 downto 0);
            QUAD0_ch0_hsdppcsreset           : in    std_logic;
            QUAD0_ch1_phyready               : out   std_logic;
            QUAD0_ch1_phyesmadaptsave        : in    std_logic;
            QUAD0_ch1_clkrsvd0               : in    std_logic;
            QUAD0_ch1_clkrsvd1               : in    std_logic;
            QUAD0_ch1_dmonitorclk            : in    std_logic;
            QUAD0_ch1_iloresetmask           : in    std_logic;
            QUAD0_ch1_loopback               : in    std_logic_vector(2 downto 0);
            QUAD0_ch1_dmonfiforeset          : in    std_logic;
            QUAD0_ch1_pcsrsvdin              : in    std_logic_vector(15 downto 0);
            QUAD0_ch1_gtrsvd                 : in    std_logic_vector(15 downto 0);
            QUAD0_ch1_tstin                  : in    std_logic_vector(19 downto 0);
            QUAD0_ch1_pcsrsvdout             : out   std_logic_vector(15 downto 0);
            QUAD0_ch1_pinrsvdas              : out   std_logic_vector(15 downto 0);
            QUAD0_ch1_dmonitoroutclk         : out   std_logic;
            QUAD0_ch1_resetexception         : out   std_logic;
            QUAD0_ch1_dmonitorout            : out   std_logic_vector(31 downto 0);
            QUAD0_ch1_hsdppcsreset           : in    std_logic;
            QUAD0_ch2_phyready               : out   std_logic;
            QUAD0_ch2_phyesmadaptsave        : in    std_logic;
            QUAD0_ch2_clkrsvd0               : in    std_logic;
            QUAD0_ch2_clkrsvd1               : in    std_logic;
            QUAD0_ch2_dmonitorclk            : in    std_logic;
            QUAD0_ch2_iloresetmask           : in    std_logic;
            QUAD0_ch2_loopback               : in    std_logic_vector(2 downto 0);
            QUAD0_ch2_dmonfiforeset          : in    std_logic;
            QUAD0_ch2_pcsrsvdin              : in    std_logic_vector(15 downto 0);
            QUAD0_ch2_gtrsvd                 : in    std_logic_vector(15 downto 0);
            QUAD0_ch2_tstin                  : in    std_logic_vector(19 downto 0);
            QUAD0_ch2_pcsrsvdout             : out   std_logic_vector(15 downto 0);
            QUAD0_ch2_pinrsvdas              : out   std_logic_vector(15 downto 0);
            QUAD0_ch2_dmonitoroutclk         : out   std_logic;
            QUAD0_ch2_resetexception         : out   std_logic;
            QUAD0_ch2_dmonitorout            : out   std_logic_vector(31 downto 0);
            QUAD0_ch2_hsdppcsreset           : in    std_logic;
            QUAD0_ch3_phyready               : out   std_logic;
            QUAD0_ch3_phyesmadaptsave        : in    std_logic;
            QUAD0_ch3_clkrsvd0               : in    std_logic;
            QUAD0_ch3_clkrsvd1               : in    std_logic;
            QUAD0_ch3_dmonitorclk            : in    std_logic;
            QUAD0_ch3_iloresetmask           : in    std_logic;
            QUAD0_ch3_loopback               : in    std_logic_vector(2 downto 0);
            QUAD0_ch3_dmonfiforeset          : in    std_logic;
            QUAD0_ch3_pcsrsvdin              : in    std_logic_vector(15 downto 0);
            QUAD0_ch3_gtrsvd                 : in    std_logic_vector(15 downto 0);
            QUAD0_ch3_tstin                  : in    std_logic_vector(19 downto 0);
            QUAD0_ch3_pcsrsvdout             : out   std_logic_vector(15 downto 0);
            QUAD0_ch3_pinrsvdas              : out   std_logic_vector(15 downto 0);
            QUAD0_ch3_dmonitoroutclk         : out   std_logic;
            QUAD0_ch3_resetexception         : out   std_logic;
            QUAD0_ch3_dmonitorout            : out   std_logic_vector(31 downto 0);
            QUAD0_ch3_hsdppcsreset           : in    std_logic;
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
            INTF0_TX0_ch_gttxreset           : in    std_logic_vector(0 downto 0);
            INTF0_TX0_ch_txresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_TX0_ch_txpcsresetmask      : in    std_logic_vector(0 downto 0);
            INTF0_TX0_ch_txpmaresetmask      : in    std_logic_vector(2 downto 0);
            INTF0_TX0_ch_txpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_TX0_ch_txprbsforceerr      : in    std_logic_vector(0 downto 0);
            INTF0_TX0_ch_txprbssel           : in    std_logic_vector(3 downto 0);
            INTF0_TX0_ch_txrate              : in    std_logic_vector(7 downto 0);
            INTF0_TX0_ch_txresetmode         : in    std_logic_vector(1 downto 0);
            INTF0_TX0_ch_txelecidle          : in    std_logic_vector(0 downto 0);
            INTF0_TX0_ch_txctrl0             : in    std_logic_vector(15 downto 0);
            INTF0_TX0_ch_txctrl1             : in    std_logic_vector(15 downto 0);
            INTF0_TX0_ch_txctrl2             : in    std_logic_vector(7 downto 0);
            INTF0_TX1_ch_txdata              : in    std_logic_vector(127 downto 0);
            INTF0_TX1_ch_txbufstatus         : out   std_logic_vector(1 downto 0);
            INTF0_TX1_ch_gttxreset           : in    std_logic_vector(0 downto 0);
            INTF0_TX1_ch_txresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_TX1_ch_txpcsresetmask      : in    std_logic_vector(0 downto 0);
            INTF0_TX1_ch_txpmaresetmask      : in    std_logic_vector(2 downto 0);
            INTF0_TX1_ch_txpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_TX1_ch_txprbsforceerr      : in    std_logic_vector(0 downto 0);
            INTF0_TX1_ch_txprbssel           : in    std_logic_vector(3 downto 0);
            INTF0_TX1_ch_txrate              : in    std_logic_vector(7 downto 0);
            INTF0_TX1_ch_txresetmode         : in    std_logic_vector(1 downto 0);
            INTF0_TX1_ch_txelecidle          : in    std_logic_vector(0 downto 0);
            INTF0_TX1_ch_txctrl0             : in    std_logic_vector(15 downto 0);
            INTF0_TX1_ch_txctrl1             : in    std_logic_vector(15 downto 0);
            INTF0_TX1_ch_txctrl2             : in    std_logic_vector(7 downto 0);
            INTF0_TX2_ch_txdata              : in    std_logic_vector(127 downto 0);
            INTF0_TX2_ch_txbufstatus         : out   std_logic_vector(1 downto 0);
            INTF0_TX2_ch_gttxreset           : in    std_logic_vector(0 downto 0);
            INTF0_TX2_ch_txresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_TX2_ch_txpcsresetmask      : in    std_logic_vector(0 downto 0);
            INTF0_TX2_ch_txpmaresetmask      : in    std_logic_vector(2 downto 0);
            INTF0_TX2_ch_txpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_TX2_ch_txprbsforceerr      : in    std_logic_vector(0 downto 0);
            INTF0_TX2_ch_txprbssel           : in    std_logic_vector(3 downto 0);
            INTF0_TX2_ch_txrate              : in    std_logic_vector(7 downto 0);
            INTF0_TX2_ch_txresetmode         : in    std_logic_vector(1 downto 0);
            INTF0_TX2_ch_txelecidle          : in    std_logic_vector(0 downto 0);
            INTF0_TX2_ch_txctrl0             : in    std_logic_vector(15 downto 0);
            INTF0_TX2_ch_txctrl1             : in    std_logic_vector(15 downto 0);
            INTF0_TX2_ch_txctrl2             : in    std_logic_vector(7 downto 0);
            INTF0_TX3_ch_txdata              : in    std_logic_vector(127 downto 0);
            INTF0_TX3_ch_txbufstatus         : out   std_logic_vector(1 downto 0);
            INTF0_TX3_ch_gttxreset           : in    std_logic_vector(0 downto 0);
            INTF0_TX3_ch_txresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_TX3_ch_txpcsresetmask      : in    std_logic_vector(0 downto 0);
            INTF0_TX3_ch_txpmaresetmask      : in    std_logic_vector(2 downto 0);
            INTF0_TX3_ch_txpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_TX3_ch_txprbsforceerr      : in    std_logic_vector(0 downto 0);
            INTF0_TX3_ch_txprbssel           : in    std_logic_vector(3 downto 0);
            INTF0_TX3_ch_txrate              : in    std_logic_vector(7 downto 0);
            INTF0_TX3_ch_txresetmode         : in    std_logic_vector(1 downto 0);
            INTF0_TX3_ch_txelecidle          : in    std_logic_vector(0 downto 0);
            INTF0_TX3_ch_txctrl0             : in    std_logic_vector(15 downto 0);
            INTF0_TX3_ch_txctrl1             : in    std_logic_vector(15 downto 0);
            INTF0_TX3_ch_txctrl2             : in    std_logic_vector(7 downto 0);
            INTF0_RX0_ch_rxbufstatus         : out   std_logic_vector(2 downto 0);
            INTF0_RX0_ch_rxcdrlock           : out   std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxprbserr           : out   std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxprbslocked        : out   std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxcdrhold           : in    std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxpcsresetmask      : in    std_logic_vector(4 downto 0);
            INTF0_RX0_ch_rxpmaresetmask      : in    std_logic_vector(6 downto 0);
            INTF0_RX0_ch_rxpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxprbscntreset      : in    std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxrate              : in    std_logic_vector(7 downto 0);
            INTF0_RX0_ch_rxresetmode         : in    std_logic_vector(1 downto 0);
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
            INTF0_RX0_ch_gtrxreset           : in    std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxcdrreset          : in    std_logic_vector(0 downto 0);
            INTF0_RX0_ch_rxprbssel           : in    std_logic_vector(3 downto 0);
            INTF0_RX1_ch_rxbufstatus         : out   std_logic_vector(2 downto 0);
            INTF0_RX1_ch_rxcdrlock           : out   std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxprbserr           : out   std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxprbslocked        : out   std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxcdrhold           : in    std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxpcsresetmask      : in    std_logic_vector(4 downto 0);
            INTF0_RX1_ch_rxpmaresetmask      : in    std_logic_vector(6 downto 0);
            INTF0_RX1_ch_rxpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxprbscntreset      : in    std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxrate              : in    std_logic_vector(7 downto 0);
            INTF0_RX1_ch_rxresetmode         : in    std_logic_vector(1 downto 0);
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
            INTF0_RX1_ch_gtrxreset           : in    std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxcdrreset          : in    std_logic_vector(0 downto 0);
            INTF0_RX1_ch_rxprbssel           : in    std_logic_vector(3 downto 0);
            INTF0_RX2_ch_rxbufstatus         : out   std_logic_vector(2 downto 0);
            INTF0_RX2_ch_rxcdrlock           : out   std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxprbserr           : out   std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxprbslocked        : out   std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxcdrhold           : in    std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxpcsresetmask      : in    std_logic_vector(4 downto 0);
            INTF0_RX2_ch_rxpmaresetmask      : in    std_logic_vector(6 downto 0);
            INTF0_RX2_ch_rxpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxprbscntreset      : in    std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxrate              : in    std_logic_vector(7 downto 0);
            INTF0_RX2_ch_rxresetmode         : in    std_logic_vector(1 downto 0);
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
            INTF0_RX2_ch_gtrxreset           : in    std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxcdrreset          : in    std_logic_vector(0 downto 0);
            INTF0_RX2_ch_rxprbssel           : in    std_logic_vector(3 downto 0);
            INTF0_RX3_ch_rxbufstatus         : out   std_logic_vector(2 downto 0);
            INTF0_RX3_ch_rxcdrlock           : out   std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxprbserr           : out   std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxprbslocked        : out   std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxcdrhold           : in    std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxpcsresetmask      : in    std_logic_vector(4 downto 0);
            INTF0_RX3_ch_rxpmaresetmask      : in    std_logic_vector(6 downto 0);
            INTF0_RX3_ch_rxpolarity          : in    std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxprbscntreset      : in    std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxrate              : in    std_logic_vector(7 downto 0);
            INTF0_RX3_ch_rxresetmode         : in    std_logic_vector(1 downto 0);
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
            INTF0_RX3_ch_gtrxreset           : in    std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxresetdone         : out   std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxcdrreset          : in    std_logic_vector(0 downto 0);
            INTF0_RX3_ch_rxprbssel           : in    std_logic_vector(3 downto 0);
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
    signal TxBufStat  : Status2_t;
    signal RxPolarity : std_logic_vector(Ch_c-1 downto 0);
    signal RxData     : Data128_t;
    signal RxCtrl0    : Ctrl16_t;
    signal RxCtrl1    : Ctrl16_t;
    signal RxCtrl3    : Ctrl8_t;
    signal RxAligned  : std_logic_vector(Ch_c-1 downto 0);
    signal RxRealign  : std_logic_vector(Ch_c-1 downto 0);
    signal RxBufStat  : Status3_t;
    signal RxClkCor   : Status2_t;
    signal RxRstDone  : std_logic_vector(Ch_c-1 downto 0);
    signal RxCdrLock  : std_logic_vector(Ch_c-1 downto 0);
    signal RxElecIdle : std_logic_vector(Ch_c-1 downto 0);
    signal PrbsTxSel  : Status4_t;
    signal PrbsRxSel  : Status4_t;
    signal PrbsForce  : std_logic_vector(Ch_c-1 downto 0);
    signal PrbsCntRst : std_logic_vector(Ch_c-1 downto 0);
    signal PrbsErr    : std_logic_vector(Ch_c-1 downto 0);
    signal PrbsLocked : std_logic_vector(Ch_c-1 downto 0);

    -- Channel reset ports, driven by the reset sequencers (FreeRunClk)
    signal RxGtReset : std_logic_vector(Ch_c-1 downto 0);
    signal RxRstMode : Status2_t;
    signal RxPcsMask : Status5_t;
    signal RxPmaMask : Status7_t;
    signal RxCdrRst  : std_logic_vector(Ch_c-1 downto 0);
    signal RxCdrHold : std_logic_vector(Ch_c-1 downto 0);
    signal TxGtReset : std_logic_vector(Ch_c-1 downto 0);
    signal TxRstMode : Status2_t;
    signal TxPmaMask : Status3_t;
    signal TxPcsMask : std_logic_vector(Ch_c-1 downto 0);
    signal PcsRsvdIn : Status16_t;

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

    -- Status of the transceiver synchronised to LaneClk: receive reset done of the wizard, comma alignment,
    -- RXRESETDONE, CDR lock and electrical idle of every lane
    signal SyncIn   : std_logic_vector(4*NumLanes_g downto 0);
    signal SyncOut  : std_logic_vector(4*NumLanes_g downto 0);
    signal Aligned  : std_logic_vector(NumLanes_g-1 downto 0);
    signal RxReadyL : std_logic_vector(NumLanes_g-1 downto 0);
    signal RxSeenK  : std_logic_vector(Ch_c-1 downto 0) := (others => '0');
    signal OnDiscL  : std_logic;

    -- Serial loopbacks: loopback mode per channel, transmit datapath reset after a change of the
    -- far-end loopback (FreeRunClk), near-end loopback for the CDR hold (FreeRunClk)
    type Loopback_t is array (0 to Ch_c-1) of std_logic_vector(2 downto 0);

    constant LbNearPma_c : std_logic_vector(2 downto 0) := "010";
    constant LbFarPma_c  : std_logic_vector(2 downto 0) := "100";

    signal Loopback  : Loopback_t                                := (others => "000");
    signal LbLane    : std_logic_vector(2*NumLanes_g-1 downto 0) := (others => '0');
    signal LbFree    : std_logic_vector(2*NumLanes_g-1 downto 0);
    signal FarLbFree : std_logic_vector(NumLanes_g-1 downto 0);
    signal NearLbF   : std_logic_vector(NumLanes_g-1 downto 0);
    signal FarLbLast : std_logic_vector(NumLanes_g-1 downto 0)   := (others => '0');
    signal TxDpCnt   : natural range 0 to 255                    := 0;
    signal TxDpReset : std_logic                                 := '0';

    -- Reset synchronised to FreeRunClk and stretched
    signal RstFree : std_logic;

    -- Requests of the reset sequencers (LaneClk, stretched for the crossing to FreeRunClk). Receive elastic buffer
    -- reset (PA-RS-03): an overflow or underflow of the buffer (RXBUFSTATUS[2]) and, once per lane start (receiver
    -- ready or line receiver enable rising), the first comma alignment within AlignWinCycles_c after it. Entire
    -- receiver reset (PA-RS-04): the lane leaves the states that use the line (Phy_CdrEnable falling), or the
    -- command of the MIB.
    constant AlignWinCycles_c : positive := 8192;

    type ReqCnts_t is array (0 to NumLanes_g-1) of natural range 0 to 15;
    type AlignWins_t is array (0 to NumLanes_g-1) of natural range 0 to AlignWinCycles_c-1;

    signal ReadyLast  : std_logic_vector(NumLanes_g-1 downto 0)   := (others => '0');
    signal RxEnLast   : std_logic_vector(NumLanes_g-1 downto 0)   := (others => '0');
    signal CdrEnLast  : std_logic_vector(NumLanes_g-1 downto 0)   := (others => '0');
    signal AlignLast  : std_logic_vector(NumLanes_g-1 downto 0)   := (others => '0');
    signal AlignArmed : std_logic_vector(NumLanes_g-1 downto 0)   := (others => '0');
    signal AlignWin   : AlignWins_t                               := (others => 0);
    signal BufReqCnt  : ReqCnts_t                                 := (others => 0);
    signal FullReqCnt : ReqCnts_t                                 := (others => 0);
    signal ReqLane    : std_logic_vector(2*NumLanes_g-1 downto 0) := (others => '0');
    signal ReqFree    : std_logic_vector(2*NumLanes_g-1 downto 0);

    -- Status of the transceiver synchronised to FreeRunClk: RXRESETDONE, electrical idle, transmit buffer error
    signal GtFreeIn  : std_logic_vector(3*NumLanes_g-1 downto 0);
    signal GtFree    : std_logic_vector(3*NumLanes_g-1 downto 0);
    signal TxBufErrF : std_logic_vector(NumLanes_g-1 downto 0);

    -- Configuration synchronised to FreeRunClk: CDR-only mode, CDR hold, PCSRSVDIN base. The per-bit synchronisers
    -- can show a mix of old and new bits for one cycle after a change: the value is taken only after it has been
    -- unchanged for CfgStableCycles_c cycles, so that a change is never taken half-way
    constant CfgDefault_c      : std_logic_vector(17 downto 0) := x"0360" & "10";
    constant CfgStableCycles_c : positive                      := 8;

    signal CfgIn   : std_logic_vector(17 downto 0);
    signal CfgSync : std_logic_vector(17 downto 0);
    signal CfgLast : std_logic_vector(17 downto 0)          := CfgDefault_c;
    signal CfgFree : std_logic_vector(17 downto 0)          := CfgDefault_c;
    signal CfgCnt  : natural range 0 to CfgStableCycles_c-1 := 0;

    -- Reset sequencers (FreeRunClk) and their status in LaneClk
    signal RxBusyF   : std_logic_vector(NumLanes_g-1 downto 0);
    signal BufBusyF  : std_logic_vector(NumLanes_g-1 downto 0);
    signal DoneEvF   : std_logic_vector(NumLanes_g-1 downto 0);
    signal TimeoEvF  : std_logic_vector(NumLanes_g-1 downto 0);
    signal DoneTgl   : std_logic_vector(NumLanes_g-1 downto 0) := (others => '0');
    signal TimeoTgl  : std_logic_vector(NumLanes_g-1 downto 0) := (others => '0');
    signal SeqIn     : std_logic_vector(4*NumLanes_g-1 downto 0);
    signal SeqLane   : std_logic_vector(4*NumLanes_g-1 downto 0);
    signal RxBusyL   : std_logic_vector(NumLanes_g-1 downto 0);
    signal BufBusyL  : std_logic_vector(NumLanes_g-1 downto 0);
    signal DoneLast  : std_logic_vector(NumLanes_g-1 downto 0) := (others => '0');
    signal TimeoLast : std_logic_vector(NumLanes_g-1 downto 0) := (others => '0');

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
    -- First K character of every receiver after it is ready
    -----------------------------------------------------------------------------------------------
    p_seen : process (UsrClk) is
    begin
        if rising_edge(UsrClk) then

            for c in 0 to Ch_c-1 loop
                if RxCtrl0(c)(3 downto 0) /= "0000" then
                    RxSeenK(c) <= '1';
                end if;
            end loop;

            for l in 0 to NumLanes_g-1 loop
                if RxReadyL(l) = '0' then
                    RxSeenK(l) <= '0';
                end if;
            end loop;

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
            -- Words are valid from the first K character after the receiver is ready (the receive buffer outputs
            -- zero words while it starts), not during an entire receiver reset and not during the reset window of the
            -- receive elastic buffer; after the window they pass as without the reset, so an idle line still reaches
            -- the Lane layer (PA-RS-03)
            PhyRx_Valid(c)   <= RxReadyL(c) and Phy_RxEnable(c) and not BufBusyL(c) and
                                (RxSeenK(c) or (or RxCtrl0(c)(3 downto 0)));
            Stat_RxBufErr(c) <= RxBufStat(c)(2);
            Stat_ClkCor(c)   <= '1' when RxClkCor(c) /= "00" else '0';
            -- Transmit buffer status of the transceiver in the transmit user clock domain (LaneClk)
            Stat_TxBufErr(c) <= TxBufStat(c)(1);
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

        -- Channels without a lane: the values the wizard ties the ports to without the optional and debug ports
        g_unused : if c >= NumLanes_g generate
            RxP4(c)       <= '0';
            RxN4(c)       <= '1';
            TxData(c)     <= (others => '0');
            TxCtrl2(c)    <= (others => '0');
            TxElecIdle(c) <= '1';
            RxPolarity(c) <= '0';
            RxGtReset(c)  <= '0';
            RxRstMode(c)  <= "00";
            RxPcsMask(c)  <= "11111";
            RxPmaMask(c)  <= "1111111";
            RxCdrRst(c)   <= '0';
            RxCdrHold(c)  <= '0';
            TxGtReset(c)  <= '0';
            TxRstMode(c)  <= "00";
            TxPmaMask(c)  <= "111";
            TxPcsMask(c)  <= '1';
            PcsRsvdIn(c)  <= x"0240";
            PrbsTxSel(c)  <= "0000";
            PrbsRxSel(c)  <= "0000";
            PrbsForce(c)  <= '0';
            PrbsCntRst(c) <= '0';
        end generate;

    end generate;

    -----------------------------------------------------------------------------------------------
    -- Status of the transceiver to LaneClk: receive reset done of the wizard (FreeRunClk), comma alignment,
    -- RXRESETDONE, CDR lock and electrical idle (asynchronous)
    -----------------------------------------------------------------------------------------------
    SyncIn(0) <= RxDone;

    g_sync : for l in 0 to NumLanes_g-1 generate
        SyncIn(1 + l)                <= RxAligned(l);
        SyncIn(1 + NumLanes_g + l)   <= RxRstDone(l);
        SyncIn(1 + 2*NumLanes_g + l) <= RxCdrLock(l);
        SyncIn(1 + 3*NumLanes_g + l) <= RxElecIdle(l);
    end generate;

    i_sync : entity olo.olo_intf_sync
        generic map (
            Width_g   => 4*NumLanes_g+1,
            SyncTmr_g => true
        )
        port map (
            Clk       => UsrClk,
            DataAsync => SyncIn,
            DataSync  => SyncOut
        );

    Aligned          <= SyncOut(NumLanes_g downto 1);
    Stat_RxResetDone <= SyncOut(2*NumLanes_g downto NumLanes_g+1);
    Stat_CdrLock     <= SyncOut(3*NumLanes_g downto 2*NumLanes_g+1);
    Stat_RxElecIdle  <= SyncOut(4*NumLanes_g downto 3*NumLanes_g+1);

    -- Entire receiver reset on lane disconnection, static configuration to LaneClk
    i_ondisc_sync : entity olo.olo_intf_sync
        generic map (
            Width_g   => 1,
            SyncTmr_g => true
        )
        port map (
            Clk          => UsrClk,
            DataAsync(0) => Cfg_RxResetOnDisc,
            DataSync(0)  => OnDiscL
        );

    -----------------------------------------------------------------------------------------------
    -- Serial loopbacks to FreeRunClk. The enables come from logic of the lane clock domain (the voters of the MIB
    -- crossing): a register of the lane clock in front of the synchroniser
    -----------------------------------------------------------------------------------------------
    p_lb_lane : process (UsrClk) is
    begin
        if rising_edge(UsrClk) then
            LbLane <= Phy_SerialNearLoopback & Phy_SerialFarLoopback;
        end if;
    end process;

    i_lb_sync : entity olo.olo_intf_sync
        generic map (
            Width_g   => 2*NumLanes_g,
            SyncTmr_g => true
        )
        port map (
            Clk       => FreeRunClk,
            DataAsync => LbLane,
            DataSync  => LbFree
        );

    FarLbFree <= LbFree(NumLanes_g-1 downto 0);
    NearLbF   <= LbFree(2*NumLanes_g-1 downto NumLanes_g);

    -- Transmit datapath reset after a change of the far-end loopback
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

    -----------------------------------------------------------------------------------------------
    -- Requests of the reset sequencers (LaneClk). One alignment request per lane start, within AlignWinCycles_c
    -- after it: a realignment later in operation (a lane already aligned when it started) requests no reset. No
    -- buffer request while the receiver of the lane is not ready (an entire receiver reset includes the buffer).
    -----------------------------------------------------------------------------------------------
    p_req : process (UsrClk) is
        variable AlignEv_v : boolean;
        variable BufEv_v   : boolean;
        variable FullEv_v  : boolean;
    begin
        if rising_edge(UsrClk) then
            ReadyLast <= RxReadyL;
            RxEnLast  <= Phy_RxEnable;
            CdrEnLast <= Phy_CdrEnable;
            AlignLast <= Aligned;

            for l in 0 to NumLanes_g-1 loop
                -- Receive elastic buffer reset (PA-RS-03)
                AlignEv_v := RxRealign(l) = '1' or (Aligned(l) = '1' and AlignLast(l) = '0');
                BufEv_v   := RxBufReset_g and (RxBufStat(l)(2) = '1' or (AlignArmed(l) = '1' and AlignEv_v));
                if BufEv_v then
                    BufReqCnt(l)            <= 15;
                    ReqLane(NumLanes_g + l) <= '1';
                elsif BufReqCnt(l) /= 0 then
                    BufReqCnt(l) <= BufReqCnt(l) - 1;
                else
                    ReqLane(NumLanes_g + l) <= '0';
                end if;
                if AlignEv_v then
                    AlignArmed(l) <= '0';
                elsif AlignWin(l) /= 0 then
                    AlignWin(l) <= AlignWin(l) - 1;
                else
                    AlignArmed(l) <= '0';
                end if;
                if (RxReadyL(l) = '1' and ReadyLast(l) = '0') or (Phy_RxEnable(l) = '1' and RxEnLast(l) = '0') then
                    AlignArmed(l) <= '1';
                    AlignWin(l)   <= AlignWinCycles_c - 1;
                end if;
                if RxReadyL(l) = '0' then
                    AlignArmed(l)           <= '0';
                    AlignWin(l)             <= 0;
                    BufReqCnt(l)            <= 0;
                    ReqLane(NumLanes_g + l) <= '0';
                end if;

                -- Entire receiver reset (PA-RS-04): the lane leaves the states that use the line, or the command
                FullEv_v := (CdrEnLast(l) = '1' and Phy_CdrEnable(l) = '0' and OnDiscL = '1') or Cmd_RxReset(l) = '1';
                if FullEv_v then
                    FullReqCnt(l) <= 15;
                    ReqLane(l)    <= '1';
                elsif FullReqCnt(l) /= 0 then
                    FullReqCnt(l) <= FullReqCnt(l) - 1;
                else
                    ReqLane(l) <= '0';
                end if;
            end loop;

        end if;
    end process;

    i_req_sync : entity olo.olo_intf_sync
        generic map (
            Width_g   => 2*NumLanes_g,
            SyncTmr_g => true
        )
        port map (
            Clk       => FreeRunClk,
            DataAsync => ReqLane,
            DataSync  => ReqFree
        );

    -----------------------------------------------------------------------------------------------
    -- Status of the transceiver and configuration to FreeRunClk
    -----------------------------------------------------------------------------------------------
    g_gtfree : for l in 0 to NumLanes_g-1 generate
        GtFreeIn(l)                <= RxRstDone(l);
        GtFreeIn(NumLanes_g + l)   <= RxElecIdle(l);
        GtFreeIn(2*NumLanes_g + l) <= TxBufStat(l)(1);
    end generate;

    i_gt_sync : entity olo.olo_intf_sync
        generic map (
            Width_g   => 3*NumLanes_g,
            SyncTmr_g => true
        )
        port map (
            Clk       => FreeRunClk,
            DataAsync => GtFreeIn,
            DataSync  => GtFree
        );

    -- A transmit buffer error counts only while the transmitters are ready
    TxBufErrF <= GtFree(3*NumLanes_g-1 downto 2*NumLanes_g) when TxReadyReg = '1' else (others => '0');

    CfgIn <= Cfg_PcsRsvdIn & Cfg_CdrHoldIdle & Cfg_RxResetCdrOnly;

    i_cfg_sync : entity olo.olo_intf_sync
        generic map (
            Width_g   => 18,
            SyncTmr_g => true
        )
        port map (
            Clk       => FreeRunClk,
            DataAsync => CfgIn,
            DataSync  => CfgSync
        );

    p_cfg : process (FreeRunClk) is
    begin
        if rising_edge(FreeRunClk) then
            CfgLast <= CfgSync;
            if CfgSync /= CfgLast then
                CfgCnt <= 0;
            elsif CfgCnt /= CfgStableCycles_c-1 then
                CfgCnt <= CfgCnt + 1;
            else
                CfgFree <= CfgLast;
            end if;
            if RstFree = '1' then
                CfgLast <= CfgDefault_c;
                CfgFree <= CfgDefault_c;
                CfgCnt  <= 0;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Reset sequencer of every lane (PA-RS-03 to PA-RS-06) and CDR hold during electrical idle (PA-IF-04)
    -----------------------------------------------------------------------------------------------
    g_seq : for l in 0 to NumLanes_g-1 generate

        i_seq : entity work.ofb_pa_gty_lane_rst
            generic map (
                DoneHighCycles_g => RxRstDoneCycles_g,
                CdrWaitCycles_g  => CdrWaitCycles_g,
                GapCycles_g      => RxRstGapCycles_g
            )
            port map (
                Clk            => FreeRunClk,
                Rst            => RstFree,
                Req_Full       => ReqFree(l),
                Req_Buf        => ReqFree(NumLanes_g + l),
                Req_Tx         => TxBufErrF(l),
                Cfg_CdrOnly    => CfgFree(0),
                Cfg_PcsRsvdIn  => CfgFree(17 downto 2),
                Gt_MasterDone  => RxDone,
                Gt_RxResetDone => GtFree(l),
                Gt_RxReset     => RxGtReset(l),
                Gt_RxResetMode => RxRstMode(l),
                Gt_RxPmaMask   => RxPmaMask(l),
                Gt_RxPcsMask   => RxPcsMask(l),
                Gt_RxCdrReset  => RxCdrRst(l),
                Gt_TxReset     => TxGtReset(l),
                Gt_TxResetMode => TxRstMode(l),
                Gt_TxPmaMask   => TxPmaMask(l),
                Gt_TxPcsMask   => TxPcsMask(l),
                Gt_PcsRsvdIn   => PcsRsvdIn(l),
                Stat_RxBusy    => RxBusyF(l),
                Stat_BufBusy   => BufBusyF(l),
                Ev_RxResetDone => DoneEvF(l),
                Ev_Timeout     => TimeoEvF(l)
            );

        -- Events as toggles for the crossing to LaneClk; CDR hold while the receiver reports electrical idle, the
        -- receivers of the wizard are ready, no reset sequence runs and the lane is not in near-end loopback (the
        -- electrical idle of the pins does not apply then)
        p_free : process (FreeRunClk) is
        begin
            if rising_edge(FreeRunClk) then
                if DoneEvF(l) = '1' then
                    DoneTgl(l) <= not DoneTgl(l);
                end if;
                if TimeoEvF(l) = '1' then
                    TimeoTgl(l) <= not TimeoTgl(l);
                end if;
                RxCdrHold(l) <= CfgFree(1) and GtFree(NumLanes_g + l) and RxDone and not RxBusyF(l) and
                                not BufBusyF(l) and not NearLbF(l);
                if RstFree = '1' then
                    DoneTgl(l)   <= '0';
                    TimeoTgl(l)  <= '0';
                    RxCdrHold(l) <= '0';
                end if;
            end if;
        end process;

        SeqIn(l)                <= RxBusyF(l);
        SeqIn(NumLanes_g + l)   <= BufBusyF(l);
        SeqIn(2*NumLanes_g + l) <= DoneTgl(l);
        SeqIn(3*NumLanes_g + l) <= TimeoTgl(l);

    end generate;

    i_seq_sync : entity olo.olo_intf_sync
        generic map (
            Width_g   => 4*NumLanes_g,
            SyncTmr_g => true
        )
        port map (
            Clk       => UsrClk,
            DataAsync => SeqIn,
            DataSync  => SeqLane
        );

    RxBusyL  <= SeqLane(NumLanes_g-1 downto 0);
    BufBusyL <= SeqLane(2*NumLanes_g-1 downto NumLanes_g);

    -- Receiver of a lane ready: the receivers of the wizard are ready and no entire receiver reset of the lane runs
    -- (RXRESETDONE itself is not used: it is not asserted after a single-mode reset)
    RxReadyL <= (RxReadyL'range => SyncOut(0)) and not RxBusyL;

    -- One-cycle events in LaneClk
    p_events : process (UsrClk) is
    begin
        if rising_edge(UsrClk) then
            DoneLast          <= SeqLane(3*NumLanes_g-1 downto 2*NumLanes_g);
            TimeoLast         <= SeqLane(4*NumLanes_g-1 downto 3*NumLanes_g);
            Ev_RxReset        <= SeqLane(3*NumLanes_g-1 downto 2*NumLanes_g) xor DoneLast;
            Ev_RxResetTimeout <= SeqLane(4*NumLanes_g-1 downto 3*NumLanes_g) xor TimeoLast;
        end if;
    end process;

    Stat_RxResetBusy <= RxBusyL;

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

    -- Receivers ready: every lane
    Stat_RxReady <= and RxReadyL;
    Stat_Aligned <= Aligned;

    -- No loss of signal indication (PA-IF-03, ECSS 5.4.2b.1): the receive electrical idle of the transceiver detects
    -- data only up to 2.5 Gbit/s (AM002), so it serves the CDR hold only. A lost signal shows as words with errors,
    -- which the Lane layer counts as RXERR (ECSS 5.5.8, 5.5.2.11e.3).
    Phy_NoSignal <= (others => '0');

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
            QUAD0_ch0_phyready               => open,
            QUAD0_ch0_phyesmadaptsave        => '0',
            QUAD0_ch0_clkrsvd0               => '0',
            QUAD0_ch0_clkrsvd1               => '0',
            QUAD0_ch0_dmonitorclk            => '0',
            QUAD0_ch0_iloresetmask           => '1',
            QUAD0_ch0_loopback               => Loopback(0),
            QUAD0_ch0_dmonfiforeset          => '0',
            QUAD0_ch0_pcsrsvdin              => PcsRsvdIn(0),
            QUAD0_ch0_gtrsvd                 => x"0000",
            QUAD0_ch0_tstin                  => x"00000",
            QUAD0_ch0_pcsrsvdout             => open,
            QUAD0_ch0_pinrsvdas              => open,
            QUAD0_ch0_dmonitoroutclk         => open,
            QUAD0_ch0_resetexception         => open,
            QUAD0_ch0_dmonitorout            => open,
            QUAD0_ch0_hsdppcsreset           => '0',
            QUAD0_ch1_phyready               => open,
            QUAD0_ch1_phyesmadaptsave        => '0',
            QUAD0_ch1_clkrsvd0               => '0',
            QUAD0_ch1_clkrsvd1               => '0',
            QUAD0_ch1_dmonitorclk            => '0',
            QUAD0_ch1_iloresetmask           => '1',
            QUAD0_ch1_loopback               => Loopback(1),
            QUAD0_ch1_dmonfiforeset          => '0',
            QUAD0_ch1_pcsrsvdin              => PcsRsvdIn(1),
            QUAD0_ch1_gtrsvd                 => x"0000",
            QUAD0_ch1_tstin                  => x"00000",
            QUAD0_ch1_pcsrsvdout             => open,
            QUAD0_ch1_pinrsvdas              => open,
            QUAD0_ch1_dmonitoroutclk         => open,
            QUAD0_ch1_resetexception         => open,
            QUAD0_ch1_dmonitorout            => open,
            QUAD0_ch1_hsdppcsreset           => '0',
            QUAD0_ch2_phyready               => open,
            QUAD0_ch2_phyesmadaptsave        => '0',
            QUAD0_ch2_clkrsvd0               => '0',
            QUAD0_ch2_clkrsvd1               => '0',
            QUAD0_ch2_dmonitorclk            => '0',
            QUAD0_ch2_iloresetmask           => '1',
            QUAD0_ch2_loopback               => Loopback(2),
            QUAD0_ch2_dmonfiforeset          => '0',
            QUAD0_ch2_pcsrsvdin              => PcsRsvdIn(2),
            QUAD0_ch2_gtrsvd                 => x"0000",
            QUAD0_ch2_tstin                  => x"00000",
            QUAD0_ch2_pcsrsvdout             => open,
            QUAD0_ch2_pinrsvdas              => open,
            QUAD0_ch2_dmonitoroutclk         => open,
            QUAD0_ch2_resetexception         => open,
            QUAD0_ch2_dmonitorout            => open,
            QUAD0_ch2_hsdppcsreset           => '0',
            QUAD0_ch3_phyready               => open,
            QUAD0_ch3_phyesmadaptsave        => '0',
            QUAD0_ch3_clkrsvd0               => '0',
            QUAD0_ch3_clkrsvd1               => '0',
            QUAD0_ch3_dmonitorclk            => '0',
            QUAD0_ch3_iloresetmask           => '1',
            QUAD0_ch3_loopback               => Loopback(3),
            QUAD0_ch3_dmonfiforeset          => '0',
            QUAD0_ch3_pcsrsvdin              => PcsRsvdIn(3),
            QUAD0_ch3_gtrsvd                 => x"0000",
            QUAD0_ch3_tstin                  => x"00000",
            QUAD0_ch3_pcsrsvdout             => open,
            QUAD0_ch3_pinrsvdas              => open,
            QUAD0_ch3_dmonitoroutclk         => open,
            QUAD0_ch3_resetexception         => open,
            QUAD0_ch3_dmonitorout            => open,
            QUAD0_ch3_hsdppcsreset           => '0',
            QUAD0_TX0_usrclk                 => UsrClk,
            QUAD0_TX1_usrclk                 => UsrClk,
            QUAD0_TX2_usrclk                 => UsrClk,
            QUAD0_TX3_usrclk                 => UsrClk,
            QUAD0_RX0_usrclk                 => UsrClk,
            QUAD0_RX1_usrclk                 => UsrClk,
            QUAD0_RX2_usrclk                 => UsrClk,
            QUAD0_RX3_usrclk                 => UsrClk,
            INTF0_TX0_ch_txdata              => TxData(0),
            INTF0_TX0_ch_txbufstatus         => TxBufStat(0),
            INTF0_TX0_ch_gttxreset(0)        => TxGtReset(0),
            INTF0_TX0_ch_txresetdone         => open,
            INTF0_TX0_ch_txpcsresetmask(0)   => TxPcsMask(0),
            INTF0_TX0_ch_txpmaresetmask      => TxPmaMask(0),
            INTF0_TX0_ch_txpolarity          => "0",
            INTF0_TX0_ch_txprbsforceerr(0)   => PrbsForce(0),
            INTF0_TX0_ch_txprbssel           => PrbsTxSel(0),
            INTF0_TX0_ch_txrate              => x"00",
            INTF0_TX0_ch_txresetmode         => TxRstMode(0),
            INTF0_TX0_ch_txelecidle(0)       => TxElecIdle(0),
            INTF0_TX0_ch_txctrl0             => x"0000",
            INTF0_TX0_ch_txctrl1             => x"0000",
            INTF0_TX0_ch_txctrl2             => TxCtrl2(0),
            INTF0_TX1_ch_txdata              => TxData(1),
            INTF0_TX1_ch_txbufstatus         => TxBufStat(1),
            INTF0_TX1_ch_gttxreset(0)        => TxGtReset(1),
            INTF0_TX1_ch_txresetdone         => open,
            INTF0_TX1_ch_txpcsresetmask(0)   => TxPcsMask(1),
            INTF0_TX1_ch_txpmaresetmask      => TxPmaMask(1),
            INTF0_TX1_ch_txpolarity          => "0",
            INTF0_TX1_ch_txprbsforceerr(0)   => PrbsForce(1),
            INTF0_TX1_ch_txprbssel           => PrbsTxSel(1),
            INTF0_TX1_ch_txrate              => x"00",
            INTF0_TX1_ch_txresetmode         => TxRstMode(1),
            INTF0_TX1_ch_txelecidle(0)       => TxElecIdle(1),
            INTF0_TX1_ch_txctrl0             => x"0000",
            INTF0_TX1_ch_txctrl1             => x"0000",
            INTF0_TX1_ch_txctrl2             => TxCtrl2(1),
            INTF0_TX2_ch_txdata              => TxData(2),
            INTF0_TX2_ch_txbufstatus         => TxBufStat(2),
            INTF0_TX2_ch_gttxreset(0)        => TxGtReset(2),
            INTF0_TX2_ch_txresetdone         => open,
            INTF0_TX2_ch_txpcsresetmask(0)   => TxPcsMask(2),
            INTF0_TX2_ch_txpmaresetmask      => TxPmaMask(2),
            INTF0_TX2_ch_txpolarity          => "0",
            INTF0_TX2_ch_txprbsforceerr(0)   => PrbsForce(2),
            INTF0_TX2_ch_txprbssel           => PrbsTxSel(2),
            INTF0_TX2_ch_txrate              => x"00",
            INTF0_TX2_ch_txresetmode         => TxRstMode(2),
            INTF0_TX2_ch_txelecidle(0)       => TxElecIdle(2),
            INTF0_TX2_ch_txctrl0             => x"0000",
            INTF0_TX2_ch_txctrl1             => x"0000",
            INTF0_TX2_ch_txctrl2             => TxCtrl2(2),
            INTF0_TX3_ch_txdata              => TxData(3),
            INTF0_TX3_ch_txbufstatus         => TxBufStat(3),
            INTF0_TX3_ch_gttxreset(0)        => TxGtReset(3),
            INTF0_TX3_ch_txresetdone         => open,
            INTF0_TX3_ch_txpcsresetmask(0)   => TxPcsMask(3),
            INTF0_TX3_ch_txpmaresetmask      => TxPmaMask(3),
            INTF0_TX3_ch_txpolarity          => "0",
            INTF0_TX3_ch_txprbsforceerr(0)   => PrbsForce(3),
            INTF0_TX3_ch_txprbssel           => PrbsTxSel(3),
            INTF0_TX3_ch_txrate              => x"00",
            INTF0_TX3_ch_txresetmode         => TxRstMode(3),
            INTF0_TX3_ch_txelecidle(0)       => TxElecIdle(3),
            INTF0_TX3_ch_txctrl0             => x"0000",
            INTF0_TX3_ch_txctrl1             => x"0000",
            INTF0_TX3_ch_txctrl2             => TxCtrl2(3),
            INTF0_RX0_ch_rxbufstatus         => RxBufStat(0),
            INTF0_RX0_ch_rxcdrlock(0)        => RxCdrLock(0),
            INTF0_RX0_ch_rxprbserr(0)        => PrbsErr(0),
            INTF0_RX0_ch_rxprbslocked(0)     => PrbsLocked(0),
            INTF0_RX0_ch_rxcdrhold(0)        => RxCdrHold(0),
            INTF0_RX0_ch_rxpcsresetmask      => RxPcsMask(0),
            INTF0_RX0_ch_rxpmaresetmask      => RxPmaMask(0),
            INTF0_RX0_ch_rxpolarity(0)       => RxPolarity(0),
            INTF0_RX0_ch_rxprbscntreset(0)   => PrbsCntRst(0),
            INTF0_RX0_ch_rxrate              => x"00",
            INTF0_RX0_ch_rxresetmode         => RxRstMode(0),
            INTF0_RX0_ch_rxdata              => RxData(0),
            INTF0_RX0_ch_rxclkcorcnt         => RxClkCor(0),
            INTF0_RX0_ch_rxcommadet          => open,
            INTF0_RX0_ch_rxbyteisaligned(0)  => RxAligned(0),
            INTF0_RX0_ch_rxbyterealign(0)    => RxRealign(0),
            INTF0_RX0_ch_rxctrl0             => RxCtrl0(0),
            INTF0_RX0_ch_rxctrl1             => RxCtrl1(0),
            INTF0_RX0_ch_rxctrl2             => open,
            INTF0_RX0_ch_rxctrl3             => RxCtrl3(0),
            INTF0_RX0_ch_rxelecidle(0)       => RxElecIdle(0),
            INTF0_RX0_ch_gtrxreset(0)        => RxGtReset(0),
            INTF0_RX0_ch_rxresetdone(0)      => RxRstDone(0),
            INTF0_RX0_ch_rxcdrreset(0)       => RxCdrRst(0),
            INTF0_RX0_ch_rxprbssel           => PrbsRxSel(0),
            INTF0_RX1_ch_rxbufstatus         => RxBufStat(1),
            INTF0_RX1_ch_rxcdrlock(0)        => RxCdrLock(1),
            INTF0_RX1_ch_rxprbserr(0)        => PrbsErr(1),
            INTF0_RX1_ch_rxprbslocked(0)     => PrbsLocked(1),
            INTF0_RX1_ch_rxcdrhold(0)        => RxCdrHold(1),
            INTF0_RX1_ch_rxpcsresetmask      => RxPcsMask(1),
            INTF0_RX1_ch_rxpmaresetmask      => RxPmaMask(1),
            INTF0_RX1_ch_rxpolarity(0)       => RxPolarity(1),
            INTF0_RX1_ch_rxprbscntreset(0)   => PrbsCntRst(1),
            INTF0_RX1_ch_rxrate              => x"00",
            INTF0_RX1_ch_rxresetmode         => RxRstMode(1),
            INTF0_RX1_ch_rxdata              => RxData(1),
            INTF0_RX1_ch_rxclkcorcnt         => RxClkCor(1),
            INTF0_RX1_ch_rxcommadet          => open,
            INTF0_RX1_ch_rxbyteisaligned(0)  => RxAligned(1),
            INTF0_RX1_ch_rxbyterealign(0)    => RxRealign(1),
            INTF0_RX1_ch_rxctrl0             => RxCtrl0(1),
            INTF0_RX1_ch_rxctrl1             => RxCtrl1(1),
            INTF0_RX1_ch_rxctrl2             => open,
            INTF0_RX1_ch_rxctrl3             => RxCtrl3(1),
            INTF0_RX1_ch_rxelecidle(0)       => RxElecIdle(1),
            INTF0_RX1_ch_gtrxreset(0)        => RxGtReset(1),
            INTF0_RX1_ch_rxresetdone(0)      => RxRstDone(1),
            INTF0_RX1_ch_rxcdrreset(0)       => RxCdrRst(1),
            INTF0_RX1_ch_rxprbssel           => PrbsRxSel(1),
            INTF0_RX2_ch_rxbufstatus         => RxBufStat(2),
            INTF0_RX2_ch_rxcdrlock(0)        => RxCdrLock(2),
            INTF0_RX2_ch_rxprbserr(0)        => PrbsErr(2),
            INTF0_RX2_ch_rxprbslocked(0)     => PrbsLocked(2),
            INTF0_RX2_ch_rxcdrhold(0)        => RxCdrHold(2),
            INTF0_RX2_ch_rxpcsresetmask      => RxPcsMask(2),
            INTF0_RX2_ch_rxpmaresetmask      => RxPmaMask(2),
            INTF0_RX2_ch_rxpolarity(0)       => RxPolarity(2),
            INTF0_RX2_ch_rxprbscntreset(0)   => PrbsCntRst(2),
            INTF0_RX2_ch_rxrate              => x"00",
            INTF0_RX2_ch_rxresetmode         => RxRstMode(2),
            INTF0_RX2_ch_rxdata              => RxData(2),
            INTF0_RX2_ch_rxclkcorcnt         => RxClkCor(2),
            INTF0_RX2_ch_rxcommadet          => open,
            INTF0_RX2_ch_rxbyteisaligned(0)  => RxAligned(2),
            INTF0_RX2_ch_rxbyterealign(0)    => RxRealign(2),
            INTF0_RX2_ch_rxctrl0             => RxCtrl0(2),
            INTF0_RX2_ch_rxctrl1             => RxCtrl1(2),
            INTF0_RX2_ch_rxctrl2             => open,
            INTF0_RX2_ch_rxctrl3             => RxCtrl3(2),
            INTF0_RX2_ch_rxelecidle(0)       => RxElecIdle(2),
            INTF0_RX2_ch_gtrxreset(0)        => RxGtReset(2),
            INTF0_RX2_ch_rxresetdone(0)      => RxRstDone(2),
            INTF0_RX2_ch_rxcdrreset(0)       => RxCdrRst(2),
            INTF0_RX2_ch_rxprbssel           => PrbsRxSel(2),
            INTF0_RX3_ch_rxbufstatus         => RxBufStat(3),
            INTF0_RX3_ch_rxcdrlock(0)        => RxCdrLock(3),
            INTF0_RX3_ch_rxprbserr(0)        => PrbsErr(3),
            INTF0_RX3_ch_rxprbslocked(0)     => PrbsLocked(3),
            INTF0_RX3_ch_rxcdrhold(0)        => RxCdrHold(3),
            INTF0_RX3_ch_rxpcsresetmask      => RxPcsMask(3),
            INTF0_RX3_ch_rxpmaresetmask      => RxPmaMask(3),
            INTF0_RX3_ch_rxpolarity(0)       => RxPolarity(3),
            INTF0_RX3_ch_rxprbscntreset(0)   => PrbsCntRst(3),
            INTF0_RX3_ch_rxrate              => x"00",
            INTF0_RX3_ch_rxresetmode         => RxRstMode(3),
            INTF0_RX3_ch_rxdata              => RxData(3),
            INTF0_RX3_ch_rxclkcorcnt         => RxClkCor(3),
            INTF0_RX3_ch_rxcommadet          => open,
            INTF0_RX3_ch_rxbyteisaligned(0)  => RxAligned(3),
            INTF0_RX3_ch_rxbyterealign(0)    => RxRealign(3),
            INTF0_RX3_ch_rxctrl0             => RxCtrl0(3),
            INTF0_RX3_ch_rxctrl1             => RxCtrl1(3),
            INTF0_RX3_ch_rxctrl2             => open,
            INTF0_RX3_ch_rxctrl3             => RxCtrl3(3),
            INTF0_RX3_ch_rxelecidle(0)       => RxElecIdle(3),
            INTF0_RX3_ch_gtrxreset(0)        => RxGtReset(3),
            INTF0_RX3_ch_rxresetdone(0)      => RxRstDone(3),
            INTF0_RX3_ch_rxcdrreset(0)       => RxCdrRst(3),
            INTF0_RX3_ch_rxprbssel           => PrbsRxSel(3),
            INTF0_TX_clr_out                 => TxClr,
            INTF0_TX_clrb_leaf_out           => open,
            INTF0_RX_clr_out                 => open,
            INTF0_RX_clrb_leaf_out           => open,
            INTF0_rst_all_in                 => RstFree,
            INTF0_rst_tx_pll_and_datapath_in => '0',
            INTF0_rst_tx_datapath_in         => TxDpReset,
            INTF0_rst_tx_done_out            => TxDone,
            INTF0_rst_rx_pll_and_datapath_in => '0',
            INTF0_rst_rx_datapath_in         => '0',
            INTF0_rst_rx_done_out            => RxDone
        );

-- vsg_on port_map_002

end architecture;

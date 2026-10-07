# ofb_pa_gty: Architecture and Design Description

## 1. Block diagram

```text
              FreeRunClk, Rst                RefClk (IBUFDS_GTE5 outside)
                    |                              |
                    v                              v
 PhyTx_* ---> +----------------------------------------------+ ---> Gt_TxP / Gt_TxN
 (LaneClk)    | ofb_gtw (Versal Transceivers Wizard, 1 quad) |
 PhyRx_* <--- |  reset controller, 4 channels: 8B/10B, comma | <--- Gt_RxP / Gt_RxN
              |  alignment, RX elastic buffer, clock corr.   |
              +----------------------------------------------+
                    | QUAD0_TX0_outclk          | rst_tx_done, rst_rx_done, rxelecidle, rxbyteisaligned
                    v                           v
                 BUFG_GT ---> LaneClk ---> olo_ft_sync -----> LaneRst, PhyRx_Valid, Phy_NoSignal, status
                 (CLR = TX_clr_out)
```

## 2. Clocking

The transmit output clock of channel 0 (`TXOUTCLKPMA`, 6.25 Gbit/s / 40 bits = 156.25 MHz) drives one `BUFG_GT`. Its
output is the user clock of all eight transmitters and receivers of the quad and `LaneClk` of the core. The receive
elastic buffers cross from the recovered clocks to this clock and remove or insert SKIP words (clock correction
sequence of four symbols, `RX_CC_LEN_SEQ` 4). The wizard reset controller clears the `BUFG_GT` (`INTF0_TX_clr_out`)
until the transmit PLL is locked and holds the receivers in reset until their PMA reset is done.

## 3. Channel mapping

| Core port (lane l) | Transceiver channel l |
| --- | --- |
| `PhyTx_Data` word l | `ch_txdata(31:0)` |
| `PhyTx_K` flags l | `ch_txctrl2(3:0)` (K character per byte); `ch_txctrl0`, `ch_txctrl1` zero (normal disparity) |
| `Phy_TxEnable(l)` | `ch_txelecidle` = not enable |
| `Phy_RxInvert(l)` | `ch_rxpolarity` |
| `Phy_CdrEnable(l)` | `ch_rxcdrhold` = not enable |
| `PhyRx_Data` word l | `ch_rxdata(31:0)` |
| `PhyRx_K` flags l | `ch_rxctrl0(3:0)` (K character per byte) |
| `PhyRx_DispErr` flags l | `ch_rxctrl1(3:0)` (disparity error per byte) |
| `PhyRx_CodeErr` flags l | `ch_rxctrl3(3:0)` (not in table per byte) |
| `PhyRx_Valid(l)` | receivers ready (synchronised `rst_rx_done`), `Phy_RxEnable(l)` and a K character received on the lane since the receivers are ready (the receive buffer outputs zero words while it starts) |
| `Phy_NoSignal(l)` | `ch_rxelecidle`, synchronised |
| `Phy_SerialNearLoopback(l)`, `Phy_SerialFarLoopback(l)` | `QUAD0_chl_loopback` = 010 (near-end PMA loopback) or 100 (far-end PMA loopback); a change of the far-end loopback (synchronised to FreeRunClk) pulses `INTF0_rst_tx_datapath_in` for 256 cycles |
| `Phy_PrbsTxSel(l)`, `Phy_PrbsForceErr(l)` | `ch_txprbssel`, `ch_txprbsforceerr` (PRBS generator of the channel, after the 8B/10B encoder) |
| `Phy_PrbsRxSel(l)`, `Phy_PrbsCntReset(l)` | `ch_rxprbssel`, `ch_rxprbscntreset` (PRBS checker of the channel, before the 8B/10B decoder) |
| `Phy_PrbsErr(l)`, `Phy_PrbsLocked(l)` | `ch_rxprbserr`, `ch_rxprbslocked` (receive user clock = `LaneClk`) |
| `Stat_ClkCor(l)` | `ch_rxclkcorcnt` /= 0 (a SKIP word inserted or removed in this cycle) |
| `Stat_RxBufErr(l)` | `ch_rxbufstatus(2)` (receive elastic buffer overflow or underflow) |

Channels without a lane (`NumLanes_g` < 4) send electrical idle; their receive outputs are not used.

## 4. Status crossing

`rst_tx_done` and `rst_rx_done` (free-running clock domain), `ch_rxelecidle` and `ch_rxbyteisaligned` (asynchronous)
cross to `LaneClk` in one `olo_ft_sync` (two stages, three synchroniser chains with a majority voter). `LaneRst` is
the inverted transmitter ready.

## 5. Transceiver configuration

`tcl/ofb_gtw.tcl` sets the line rate settings `LR0_SETTINGS` of interface 0 (`INTF0_GT_SETTINGS`) and the optional
ports (`INTF0_OPTIONAL_PORTS`, the dictionary of all ports with the used ones enabled). The settings are listed in the
specification (section 3).

# ofb_pa_gty: Architecture and Design Description

## 1. Block diagram

![Block diagram of ofb_pa_gty: lane mapping, transceiver wizard ofb_gtw with BUFG_GT, status crossing and far-end
loopback reset](img/ofb_pa_gty_arch.drawio.svg)

## 2. Clocking

The transmit output clock of channel 0 (`TXOUTCLKPMA`, 6.25 Gbit/s / 40 bits = 156.25 MHz) drives one `BUFG_GT`. Its
output is the user clock of all eight transmitters and receivers of the quad and `LaneClk` of the core. The receive
elastic buffers cross from the recovered clocks to this clock and remove or insert SKIP words (clock correction
sequence of four symbols, `RX_CC_LEN_SEQ` 4). The wizard reset controller clears the `BUFG_GT` (`INTF0_TX_clr_out`)
while the transmit PMA reset of a channel is not done (the AND of `TXPMARESETDONE` of the four channels) and for 17
cycles of `FreeRunClk` after it; `LaneClk` therefore stops during every reset of the transmitters in operation (a
reset through `Rst`, a transmit datapath reset after a change of the far-end loopback) and can end with a short pulse
(AMD AM003, `BUFG_GT`). The receivers are held in reset until their PMA reset is done.

`Rst` passes an `olo_base_reset_gen` on `FreeRunClk` (`SyncTmr_g` = true): asserted asynchronously, released
synchronously after at least `RstPulseCycles_g` cycles (default 1000). The stretched reset drives the reset of the
wizard (`INTF0_rst_all_in`) and the transmit datapath reset logic, so that a reset pulse of any width restarts the
transceivers completely (PA-RS-02).

## 3. Channel mapping

| Core port (lane l) | Transceiver channel l |
| --- | --- |
| `PhyTx_Data` word l | `ch_txdata(31:0)` |
| `PhyTx_K` flags l | `ch_txctrl2(3:0)` (K character per byte); `ch_txctrl0`, `ch_txctrl1` zero (normal disparity) |
| `Phy_TxEnable(l)` | `ch_txelecidle` = not enable |
| `Phy_RxInvert(l)` | `ch_rxpolarity` |
| `Phy_CdrEnable(l)` | not used: the CDR runs in every lane state (PA-IF-02; `ch_rxcdrhold` is not enabled in the wizard) |
| `PhyRx_Data` word l | `ch_rxdata(31:0)` |
| `PhyRx_K` flags l | `ch_rxctrl0(3:0)` (K character per byte) |
| `PhyRx_DispErr` flags l | `ch_rxctrl1(3:0)` (disparity error per byte) |
| `PhyRx_CodeErr` flags l | `ch_rxctrl3(3:0)` (not in table per byte) |
| `PhyRx_Valid(l)` | receivers ready (synchronised `rst_rx_done`), `Phy_RxEnable(l)` and a K character received on the lane since the receivers are ready (the receive buffer outputs zero words while it starts) |
| `Phy_NoSignal(l)` | always 0 (PA-IF-03, ECSS 5.4.2.4b.1): the receive electrical idle of the transceiver detects data only up to 2.5 Gbit/s and only with the OOB circuit, so `ch_rxelecidle` is not enabled; a lost signal reaches the Lane layer as words with errors (RXERR) |
| `Phy_SerialNearLoopback(l)`, `Phy_SerialFarLoopback(l)` | `QUAD0_chl_loopback` = 010 (near-end PMA loopback) or 100 (far-end PMA loopback); a change of the far-end loopback (synchronised to FreeRunClk) pulses `INTF0_rst_tx_datapath_in` for 256 cycles |
| `Phy_PrbsTxSel(l)`, `Phy_PrbsForceErr(l)` | `ch_txprbssel`, `ch_txprbsforceerr` (PRBS generator of the channel, after the 8B/10B encoder) |
| `Phy_PrbsRxSel(l)`, `Phy_PrbsCntReset(l)` | `ch_rxprbssel`, `ch_rxprbscntreset` (PRBS checker of the channel, before the 8B/10B decoder) |
| `Phy_PrbsErr(l)`, `Phy_PrbsLocked(l)` | `ch_rxprbserr`, `ch_rxprbslocked` (receive user clock = `LaneClk`) |
| `Stat_ClkCor(l)` | `ch_rxclkcorcnt` /= 0 (a SKIP word inserted or removed in this cycle) |
| `Stat_RxBufErr(l)` | `ch_rxbufstatus(2)` (receive elastic buffer overflow or underflow) |
| (receive elastic buffer reset, section 5) | `ch_gtrxreset`, `ch_rxresetmode`, `ch_rxpcsresetmask`, `ch_rxpmaresetmask` of channel l; requests from `ch_rxbufstatus(2)`, `ch_rxbyteisaligned` and `ch_rxbyterealign` |

Channels without a lane (`NumLanes_g` < 4) send electrical idle; their receive outputs are not used.

## 4. Status crossing

`rst_rx_done` (free-running clock domain) and `ch_rxbyteisaligned` (asynchronous) cross to `LaneClk` in one
`olo_intf_sync` with `SyncTmr_g` = true (two stages, three synchroniser chains with a majority voter).

`Stat_TxReady` is `rst_tx_done` (the transmit reset done of the wizard, already synchronised to `FreeRunClk`) from a
register of `FreeRunClk` (PA-ST-02): it falls while `LaneClk` stands still, and it drives `Phy_TxReady` of the core
without further logic. It is taken only after `rst_tx_done` was 0 once since the release of the reset (`TxArmed`):
when the reset is released, `rst_tx_done` still shows 1 until the master reset of the wizard starts (in the
transceiver model about 28 us later, while `LaneClk` does not run yet). A wizard that kept `rst_tx_done` at 1 through
its master reset would leave `Stat_TxReady` at 0 for good: the link would not start, a visible failure instead of a
ready status without a lane clock. `LaneRst` comes from an `olo_base_reset_gen` on `LaneClk` (`RstInPolarity_g` = '0',
`SyncTmr_g` = true) with `Stat_TxReady` as input: set without a clock edge while the transmitters are not ready,
released synchronously.

## 5. Receive elastic buffer reset

With `RxBufReset_g` (default) the adapter resets the receive elastic buffer of a lane alone (PA-RS-03). The
transceiver documentation (AM002, recommended receiver resets) asks for such a reset after an overflow or underflow of
the buffer, after a comma alignment and after the recovered clock becomes stable on new data; without it the content
of the buffer stays invalid. In a lane start the receiver reset completes before the far end sends, so the recovered
clock becomes stable only later.

- Requests, per lane in `LaneClk`: `ch_rxbufstatus(2)` (overflow or underflow) at any time, and one alignment request
  per lane start. The start arms the alignment request when the receivers become ready or line receiver enable rises;
  the first comma alignment within 8192 `LaneClk` cycles (52 us, the initialisation timeout and the lock of the
  clock-data recovery) after it (`ch_rxbyteisaligned` rising, synchronised, or a `ch_rxbyterealign` pulse) requests
  the reset and disarms it, and the end of the window disarms it as well. A lane that was already aligned when it
  started (the comma aligner locked before the receivers were ready) has no alignment event in its start; without the
  window, a realignment during traffic would reset its buffer and drop words of the running link. Further
  realignments do not request a reset, so a reset cannot start the next one through the comma aligner (the PRBS
  test, for example, realigns all the time on the random data).
- A request is stretched to 16 `LaneClk` cycles and crosses to `FreeRunClk` in an `olo_intf_sync` with
  `SyncTmr_g` = true.
- Sequencer, per lane in `FreeRunClk`: `ch_rxresetmode` = 11 (single mode), `ch_rxpmaresetmask` = 0000000 and
  `ch_rxpcsresetmask` = 00100 (RX elastic buffer) for 8 cycles, then `ch_gtrxreset` for 16 cycles (at least one
  reference clock period), the masks held for 128 more cycles (single mode reports no reset done), then the values of
  the master reset again (sequential mode, all masks set, `ch_gtrxreset` low, the values the wizard ties these ports to
  when they are not used) and a holdoff of 256 cycles before the next reset. A request during the hold or the holdoff
  is served after the holdoff. While the receivers are not ready (`rst_rx_done` low) or the free-running reset is
  active, the sequencer stays idle with the master reset values.
- Received words: during the reset the buffer delivers words of value 0. The reset window (setup, pulse and hold)
  crosses back to `LaneClk` (`olo_intf_sync`, `SyncTmr_g` = true); while it is active `PhyRx_Valid` of the lane is
  low, and afterwards the words are valid again from the first K character, as after the start of the receivers. The
  words of the reset window are missing, not replaced: a frame across it fails its CRC in the Data Link layer.

With `RxBufReset_g` = false the ports keep the master reset values: the behaviour is that of the transceiver without
the reset.

## 6. Transceiver configuration

`tcl/ofb_gtw.tcl` sets the line rate settings `LR0_SETTINGS` of interface 0 (`INTF0_GT_SETTINGS`) and the optional
ports (`INTF0_OPTIONAL_PORTS`, the dictionary of all ports with the used ones enabled). The settings are listed in the
specification (section 3).

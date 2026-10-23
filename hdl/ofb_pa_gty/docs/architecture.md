# ofb_pa_gty: Architecture and Design Description

## 1. Block diagram

![Block diagram of ofb_pa_gty: lane mapping, transceiver wizard ofb_gtw with BUFG_GT, status crossing and far-end
loopback reset](img/ofb_pa_gty_arch.drawio.svg)

## 2. Clocking

The transmit output clock of channel 0 (`TXPROGDIVCLK`, the programmable divider from the LCPLL, 156.25 MHz)
drives one `BUFG_GT`. Its
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
| `Phy_CdrEnable(l)` | falling edge (`LaneClk`): request of the entire receiver reset of the lane with `Cfg_RxResetOnDisc` (section 5); the CDR is not stopped by it (PA-IF-02) |
| `Cmd_RxReset(l)` | request of the entire receiver reset of the lane (section 5) |
| (CDR hold, PA-IF-04) | `ch_rxcdrhold` = `Cfg_CdrHoldIdle` and `ch_rxelecidle` (synchronised to `FreeRunClk`) and receivers ready and no reset sequence of the lane and no near-end loopback, a register of `FreeRunClk` |
| `PhyRx_Data` word l | `ch_rxdata(31:0)` |
| `PhyRx_K` flags l | `ch_rxctrl0(3:0)` (K character per byte) |
| `PhyRx_DispErr` flags l | `ch_rxctrl1(3:0)` (disparity error per byte) |
| `PhyRx_CodeErr` flags l | `ch_rxctrl3(3:0)` (not in table per byte) |
| `PhyRx_Valid(l)` | receiver of the lane ready (synchronised `rst_rx_done` and no entire receiver reset of the lane in progress), `Phy_RxEnable(l)`, not in the reset window of the receive elastic buffer, and a K character received on the lane since the receiver is ready (the receive buffer outputs zero words while it starts) |
| `Phy_NoSignal(l)` | always 0 (PA-IF-03, ECSS 5.4.2.4b.1): the receive electrical idle of the transceiver is specified for data detection up to 2.5 Gbit/s only, so it serves the CDR hold and the status only; a lost signal reaches the Lane layer as words with errors (RXERR) |
| `Phy_SerialNearLoopback(l)`, `Phy_SerialFarLoopback(l)` | `QUAD0_chl_loopback` = 010 (near-end PMA loopback) or 100 (far-end PMA loopback); a change of the far-end loopback (synchronised to FreeRunClk) pulses `INTF0_rst_tx_datapath_in` for 256 cycles |
| `Phy_PrbsTxSel(l)`, `Phy_PrbsForceErr(l)` | `ch_txprbssel`, `ch_txprbsforceerr` (PRBS generator of the channel, after the 8B/10B encoder) |
| `Phy_PrbsRxSel(l)`, `Phy_PrbsCntReset(l)` | `ch_rxprbssel`, `ch_rxprbscntreset` (PRBS checker of the channel, before the 8B/10B decoder) |
| `Phy_PrbsErr(l)`, `Phy_PrbsLocked(l)` | `ch_rxprbserr`, `ch_rxprbslocked` (receive user clock = `LaneClk`) |
| `Stat_ClkCor(l)` | `ch_rxclkcorcnt` /= 0 (a SKIP word inserted or removed in this cycle) |
| `Stat_RxBufErr(l)` | `ch_rxbufstatus(2)` (receive elastic buffer overflow or underflow) |
| `Stat_TxBufErr(l)` | `ch_txbufstatus(1)` (transmit buffer overflow or underflow) |
| `Stat_RxResetDone(l)`, `Stat_CdrLock(l)`, `Stat_RxElecIdle(l)` | `ch_rxresetdone`, `ch_rxcdrlock`, `ch_rxelecidle` (synchronised to `LaneClk`) |
| `Stat_RxResetBusy(l)`, `Ev_RxReset(l)`, `Ev_RxResetTimeout(l)` | receiver reset of the lane in progress, completed, timed out (sequencer, section 5) |
| (reset sequencer, section 5) | `ch_gtrxreset`, `ch_rxresetmode`, `ch_rxpcsresetmask`, `ch_rxpmaresetmask`, `ch_rxcdrreset`, `ch_gttxreset`, `ch_txresetmode`, `ch_txpcsresetmask`, `ch_txpmaresetmask` and `QUAD0_chl_pcsrsvdin` of channel l; requests from `Phy_CdrEnable`, `Cmd_RxReset`, `ch_txbufstatus(1)`, `ch_rxbufstatus(2)`, `ch_rxbyteisaligned` and `ch_rxbyterealign` |
| (other channel debug inputs) | the values the wizard ties them to without the debug ports: 0, `iloresetmask` 1 |

Channels without a lane (`NumLanes_g` < 4) send electrical idle; their receive outputs are not used.

## 4. Status crossing

`rst_rx_done` (free-running clock domain), `ch_rxbyteisaligned`, `ch_rxresetdone`, `ch_rxcdrlock` and
`ch_rxelecidle` (asynchronous) cross to `LaneClk` in one `olo_intf_sync` with `SyncTmr_g` = true (two stages, three
synchroniser chains with a majority voter). `ch_rxresetdone`, `ch_rxelecidle` and `ch_txbufstatus(1)` cross to
`FreeRunClk` for the reset sequencers in a second one. The configuration inputs (`Cfg_RxResetCdrOnly`,
`Cfg_CdrHoldIdle`, `Cfg_PcsRsvdIn`, 18 bits, static levels from any clock domain) cross to `FreeRunClk` in a third
one. Per-bit synchronisers do not keep a multi-bit value coherent: after a change, each bit takes the new value in one
of two consecutive cycles, so a mix of old and new bits can show for one cycle. Coherence follows from two rules:
the synchronised value is taken only after it has been unchanged for 8 cycles of `FreeRunClk` (longer than the
synchroniser depth and its one-cycle skew), and a sequencer applies the taken PCSRSVDIN only at the start of a reset
sequence, never during one. The source changes rarely (a register write, for example PA_CTRL of the MIB): software
changes it while the lanes are stopped or before a receiver reset command, and a change during traffic takes effect at
the next reset sequence of each lane. A handshake crossing is not used because the adapter has no clock of the
source. `Cfg_RxResetOnDisc` (one bit) crosses to `LaneClk`. The state of each sequencer
(receiver reset in progress, buffer reset window, completion and timeout as toggles) crosses back to `LaneClk`.

`Stat_TxReady` is `rst_tx_done` (the transmit reset done of the wizard, already synchronised to `FreeRunClk`) from a
register of `FreeRunClk` (PA-ST-02): it falls while `LaneClk` stands still, and it drives `Phy_TxReady` of the core
without further logic. It is taken only after `rst_tx_done` was 0 once since the release of the reset (`TxArmed`):
when the reset is released, `rst_tx_done` still shows 1 until the master reset of the wizard starts (in the
transceiver model about 28 us later, while `LaneClk` does not run yet). A wizard that kept `rst_tx_done` at 1 through
its master reset would leave `Stat_TxReady` at 0 for good: the link would not start, a visible failure instead of a
ready status without a lane clock. `LaneRst` comes from an `olo_base_reset_gen` on `LaneClk` (`RstInPolarity_g` = '0',
`SyncTmr_g` = true) with `Stat_TxReady` as input: set without a clock edge while the transmitters are not ready,
released synchronously.

## 5. Reset sequencer

Every lane has a reset sequencer `ofb_pa_gty_lane_rst` in `FreeRunClk`, shared by both architectures (the model
drives its own channel emulation with it). It serves three requests, one sequence at a time and in this order of
priority, with a holdoff of 256 cycles between two sequences; a sequence starts only while the receivers of the wizard
are ready (`rst_rx_done`) and is never aborted. All outputs to the transceiver come from registers (GTRXRESET,
GTTXRESET and PCSRSVDIN are asynchronous inputs). Outside the sequences the reset ports have the values the wizard ties
them to when they are not used (sequential mode, all masks set), as its reset controller requires, and PCSRSVDIN has
the base value taken at the start of the last sequence (`Cfg_PcsRsvdIn`, after a reset the default 0x0360).

1. Entire receiver reset (PA-RS-04): requested by the falling edge of `Phy_CdrEnable` with `Cfg_RxResetOnDisc`, or by
   `Cmd_RxReset`, in `LaneClk` (stretched to 16 cycles for the crossing). `ch_rxresetmode` 00 (sequential), all PMA
   and PCS reset masks set and PCSRSVDIN = base or 0x0300 (RXDAPIRESETMASK) for 8 cycles, then `ch_gtrxreset` with
   PCSRSVDIN = base or 0x0700 (RXDAPIRESET) for 16 cycles (at least one reference clock period), then PCSRSVDIN =
   base or 0x0300 until `ch_rxresetdone` falls and rises again (AM002, "RX reset in response to GTRXRESET pulse in full
   sequential mode"). The waits are bounded (PA-RS-05): 1000000 cycles for the fall, `RxRstDoneCycles_g` for the rise;
   on expiry the sequence ends with a timeout event. A request while a receiver reset runs, or within
   `RxRstGapCycles_g` after its end (completed or timed out), is dropped. With `Cfg_RxResetCdrOnly` the sequence is a
   pulse of `ch_rxcdrreset` (16 cycles) and a wait of `CdrWaitCycles_g`. While the reset runs, the receiver of the lane
   is not ready: its words are not valid and `Stat_RxReady` is low. The entire receiver reset includes the elastic
   buffer, so a pending buffer request is cleared; the first comma alignment of the next lane start requests the
   buffer reset again (below).
2. Transmit buffer reset (PA-RS-06): requested while `ch_txbufstatus(1)` is set and the transmitters are ready.
   `ch_txresetmode` 11 (single), `ch_txpmaresetmask` 000, `ch_txpcsresetmask` 1 and PCSRSVDIN 0 for 8 cycles, then
   `ch_gttxreset` for 16 cycles, the masks held for 128 more cycles.
3. Receive elastic buffer reset (PA-RS-03), below.

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
- Sequence: `ch_rxresetmode` = 11 (single mode), `ch_rxpmaresetmask` = 0000000, `ch_rxpcsresetmask` = 00100 (RX
  elastic buffer) and PCSRSVDIN 0 for 8 cycles, then `ch_gtrxreset` for 16 cycles (at least one reference clock
  period), the masks held for 128 more cycles (single mode reports no reset done), then the values outside the
  sequences again and the holdoff. A request during the hold or the holdoff is served after the holdoff. The buffer
  requests count only while the receiver of the lane is ready (no entire receiver reset in progress).
- Received words: during the reset the buffer delivers words of value 0. The reset window (setup, pulse and hold,
  152 cycles of `FreeRunClk`, 1.52 us at 100 MHz, about 238 words) crosses back to `LaneClk` (`olo_intf_sync`,
  `SyncTmr_g` = true); while it is active `PhyRx_Valid` of the lane is low, and after it the words are valid as
  without the reset. The words of the window are missing, not replaced and not counted as RXERR: a frame across it
  fails in the Data Link layer, and the retry recovers it. The zero words of the reset last about 0.3 us on the
  transceiver model, so they lie inside the window with a margin of a factor of 5; the hardware test confirms it.
  A word after the window that is wrong but correctly coded (for example a shifted word until the next K character)
  reaches the Data Link layer, whose CRC rejects the frame, and the retry recovers it; the word synchronisation check
  of the Lane layer catches a lost alignment at the next K character.
- Idle line: the buffer reports an error when the line becomes idle, and the reset follows. The window has a fixed
  length, and after it the receiver delivers words again (code errors, then words without lane meaning), so the
  RXERR counter of the Lane layer overflows and the lane detects the lost signal (PA-IF-03); resets are at least
  the holdoff apart, so each gap carries more than 400 words. Withholding the words until the first K character
  instead would hide the idle line, which delivers none: the lane would stay Active through an interruption.

With `RxBufReset_g` = false the ports keep the master reset values: the behaviour is that of the transceiver without
the reset.

## 6. Transceiver configuration

`tcl/ofb_gtw.tcl` sets the line rate settings `LR0_SETTINGS` of interface 0 (`INTF0_GT_SETTINGS`), the optional
ports (`INTF0_OPTIONAL_PORTS`, the dictionary of all ports with the used ones enabled) and the debug ports of the four
channels (`QUAD0_CHn_DEBUG_EN`, for PCSRSVDIN). The wizard keeps one interface with four lanes: its reset controller
resets the four receivers together, so the reset of one receiver goes through the channel reset ports of the
sequencers instead. The settings are listed in the specification (section 3).

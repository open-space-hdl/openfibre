# ofb_pa_gty: Specification

## 1. Overview

`ofb_pa_gty` is the Physical adapter PA-1 of OpenFibre for one AMD Versal GTY quad (ECSS-E-ST-50-11C clause 5.4 and
the symbol level of clauses 5.3.2 and 5.5.6). It connects up to four lanes of `ofb_core` to the transceiver: the
serialiser and deserialiser, the 8B/10B codec (PA-2), the comma alignment and the receive elastic buffer with clock
correction (PA-3) are functions of the transceiver.

| Block | Implementation | Function |
| --- | --- | --- |
| PA-1 | `ofb_pa_gty` | Mapping of the symbol streams and the lane control to the transceiver channels, user clock, status |
| PA-2 | Transceiver (`ofb_gtw`) | 8B/10B encoding and decoding |
| PA-3 | Transceiver (`ofb_gtw`) | Comma alignment, receive elastic buffer with clock correction |

`ofb_gtw` is an instance of the Versal Transceivers Wizard, created by `tcl/ofb_gtw.tcl`. The module is the only
target-specific part of OpenFibre; it is not part of the GHDL regression (section 4).

## 2. Requirements

| ID | Requirement | ECSS |
| --- | --- | --- |
| PA-IF-01 | The adapter shall take one word of four symbols (8 bits and a K flag each, symbol 0 first) per lane and `LaneClk` cycle for transmission and pass one received word of four decoded symbols per cycle with a K flag, a code error flag and a disparity error flag per symbol and a valid flag. | 5.4.1b, c, 5.5.1k, l, 6.4.2 |
| PA-IF-02 | The adapter shall disable the line driver (electrical idle) when line driver enable is low, mark received words invalid when line receiver enable is low and invert the received bits when Invert RX Polarity is high. CDR enable shall not stop the clock data recovery; its falling edge, when the lane leaves the states that use the line (Started, Connecting, Active, LossOfSignal) for ClearLine, Disabled or Wait, shall start the entire receiver reset of the lane (PA-RS-04), so that the next initialisation attempt starts with a receiver that acquires the far-end signal afresh. | 5.4.1d, 5.4.2h, 6.4.3, 5.5.2.4c, 5.5.2.5b, 5.5.2.6d |
| PA-IF-03 | NoSignal shall always be de-asserted: the receiver of the transceiver gives no loss of signal indication at the line rate of the adapter (the receive electrical idle detection of the transceiver is specified for data only up to 2.5 Gbit/s; the adapter uses it for the CDR hold, PA-IF-04, and reports it as status). A lost signal shows as received words with code or disparity errors, which the Lane layer counts as RXERR words. | 5.4.1e, 5.4.2.4a, 5.4.2.4b.1 |
| PA-IF-04 | With `Cfg_CdrHoldIdle` (MIB PA_CTRL CDR_HOLD_IDLE, default 1) the adapter shall hold the clock data recovery of a lane while its receiver reports electrical idle (out-of-band detection of the transceiver enabled), the receivers are ready, no reset sequence of the lane runs and the lane is not in near-end serial loopback, so that the recovered clock does not wander while the line is idle; with `Cfg_CdrHoldIdle` 0 the CDR shall never be held. | 5.4.1d, 5.5.2.4c |
| PA-LB-01 | The near-end serial loopback of a lane shall connect the serialiser output of the channel to its deserialiser input (near-end PMA loopback), the far-end serial loopback the received serial signal to the line driver (far-end PMA loopback); after a change of a far-end loopback the transmitters shall be reset. | 5.4.1h, 5.4.2.2a to c |
| PA-SE-01 | Every lane shall transmit and receive at 6.25 Gbit/s, symbols serialised least significant bit first. | 5.4.2a to c, 5.4.2.3b |
| PA-SE-02 | The symbols shall be encoded and decoded with 8B/10B; a symbol that is not a valid code group shall set the code error flag, a running disparity error the disparity error flag. | 5.3.2, 5.5.7j, k |
| PA-SY-01 | The receiver shall align the symbols on positive and negative commas (7-bit comma sequences) and realign when a comma is detected in another position; the comma shall be placed in symbol 0 of a received word. | 5.5.6a to g, 5.5.7c |
| PA-CC-01 | The received words shall pass a receive elastic buffer into `LaneClk`; the buffer shall insert or remove SKIP words (K28.7, LLCW, SKIP, SKIP) to compensate the difference of the signalling rates. | 5.5.3 (receive side) |
| PA-CK-01 | `LaneClk` shall be the transmit user clock of the quad (156.25 MHz at 6.25 Gbit/s, from a reference clock of 100 MHz or 156.25 MHz for which `tcl/ofb_gtw.tcl` creates the wizard instance), common to all lanes; all transmitters and receivers use it. | 5.6.2 (note), 5.4.2.3a |
| PA-RS-01 | The asynchronous reset shall start the reset sequence of the transceiver; `LaneRst` shall be high until the transmitters are ready, the received words invalid until the receivers are ready. | none (implementation) |
| PA-RS-02 | `Rst` shall be accepted with any pulse width: a reset generator on `FreeRunClk` with triplicated synchroniser shall stretch it to at least `RstPulseCycles_g` cycles for the reset of the transceivers and of the logic in the free-running clock domain. | none (implementation) |
| PA-RS-03 | With `RxBufReset_g` (default), the adapter shall reset the receive elastic buffer of a lane alone after an overflow or underflow of that buffer, and once per lane start (receivers ready, or line receiver enable rising) at the first comma alignment within 8192 `LaneClk` cycles after it (52 us: the initialisation timeout and the lock of the clock-data recovery), when the recovered clock is stable on the new signal: an RX component reset of the channel in single mode (RX elastic buffer only), as the transceiver documentation recommends for these situations, at most one per holdoff time and never during a reset of the transceivers. Further comma realignments, and a realignment after the window of a lane that was already aligned when it started, shall not start a reset: a realignment during traffic must never reset the buffer. While the buffer of a lane is reset (a window of fixed length), the received words of that lane shall not be valid; after the window they shall be valid as without the reset, so that the adapter never waits for a word that an idle line cannot deliver and a lost signal still reaches the Lane layer as RXERR words (PA-IF-03). | 5.5.3 (receive side), 5.5.8 |
| PA-RS-04 | The adapter shall reset the entire receiver of one lane (PMA with the clock data recovery, PCS with the elastic buffer), the other lanes undisturbed, on the falling edge of CDR enable while `Cfg_RxResetOnDisc` (MIB PA_CTRL RX_RESET_ON_DISCONNECT, default 1) is set, and on the receiver reset command of the lane (`Cmd_RxReset`, MIB LANE_CTRL RX_RESET): GTRXRESET and PCSRSVDIN[10] pulsed in sequential mode with all PMA and PCS reset masks and PCSRSVDIN[9:8] high from before the pulse until RXRESETDONE, the reset that the transceiver documentation (AM002) recommends after the remote end powers up, after electrical idle and after connecting the line. A sequence shall start only while the receivers of the reset controller are ready and shall never be aborted. While it runs, the received words of the lane shall not be valid and the receivers shall not report ready; the reset of the receive elastic buffer at the next lane start follows (PA-RS-03). A request while a receiver reset of the lane runs, or within `RxRstGapCycles_g` after its end, shall be dropped, so that lanes with the initialisation timeout of the standard (5000 words, shorter than a receiver reset) get initialisation attempts between two resets. With `Cfg_RxResetCdrOnly` (RX_RESET_CDR_ONLY) the adapter shall pulse RXCDRRESET and wait `CdrWaitCycles_g` instead. Outside the reset sequences PCSRSVDIN shall be `Cfg_PcsRsvdIn` (PA_CTRL PCSRSVDIN, default 0x0360), taken at the start of the next reset sequence of the lane, never during a sequence. | 5.4.2g, 5.5.2.4c |
| PA-RS-05 | Every wait of a reset sequence for the transceiver shall be bounded: RXRESETDONE shall fall within 10 ms after the GTRXRESET pulse and rise within `RxRstDoneCycles_g` (default 150 ms at 100 MHz, the longest reset time that PG442 gives) after that. On expiry the sequence shall end with the masks released, the lane shall report a receiver reset timeout event and accept requests again after the gap. | none (implementation) |
| PA-RS-06 | The adapter shall reset the transmit buffer of one lane while the transceiver reports a transmit buffer overflow or underflow (TXBUFSTATUS[1]) and the transmitters are ready: GTTXRESET in single mode on the transmit PCS (TXRESETMODE 11, TXPMARESETMASK 000, TXPCSRESETMASK 1, PCSRSVDIN 0), at most one per holdoff time; outside this sequence the transmit reset ports shall have the values of the reset controller (sequential mode, all masks set). | none (implementation) |
| PA-ST-01 | The adapter shall report transmitter ready, receiver ready, comma alignment per lane, receive buffer errors per lane and a pulse per clock correction of a receive elastic buffer. | 5.4.2e |
| PA-ST-03 | The adapter shall report per lane in `LaneClk`: transmit buffer error, RXRESETDONE, receiver reset in progress, CDR lock and receiver electrical idle, and a single-cycle event per completed receiver reset and per receiver reset timeout. | none (implementation) |
| PA-ST-02 | `Stat_TxReady` shall be a register of `FreeRunClk` from the transmit reset done of the transceiver reset controller, taken only after it was 0 once since the release of the reset, so that it is 1 only while `LaneClk` runs and falls while a transmitter reset stops `LaneClk`; `LaneRst` shall be set without a clock edge while the transmitters are not ready and released synchronously to `LaneClk`. | none (implementation) |
| PA-PR-01 | For the bit error rate test of the electrical link, the PRBS generator and the PRBS checker of every transceiver channel shall be selectable per lane (`LaneClk`, 4 bits, transceiver encoding: 0 off, 1 PRBS-7, 2 PRBS-9, 3 PRBS-15, 4 PRBS-23, 5 PRBS-31); they bypass the 8B/10B codec. A single-cycle pulse shall insert one error into the transmitted pattern, another one reset the checker; the checker shall report per `LaneClk` cycle whether the received word contains a bit error, and its lock to the pattern. | none (test function) |

Requirements of the behavioural model (architecture `mdl`, [model.md](model.md)):

| ID | Requirement | ECSS |
| --- | --- | --- |
| PA-MD-01 | The model shall be an architecture of the entity `ofb_pa_gty` in plain VHDL-2008 without vendor libraries, run unchanged in GHDL and QuestaSim, and be listed alone in `compile_order_sim.txt`; `compile_order.txt` shall list `struct` alone, and a check shall reject a list with both. | none (verification model) |
| PA-MD-02 | The pins shall carry the 8B/10B bit stream with running disparity at a unit interval of the `RefClk` period / 40, symbol 0 and bit a first; `LaneClk` shall be `RefClk`; electrical idle shall drive both pins '0'. | 5.3.2, 5.4.2a to c |
| PA-MD-03 | The receiver shall count the received bits in its own unit interval, align on 7-bit commas and realign on a comma in another position, place the comma in symbol 0, flag code and disparity errors and invert the received bits with `Phy_RxInvert`. | 5.5.6, 5.5.7c |
| PA-MD-04 | A receive buffer per lane shall pass the words into `LaneClk` and remove or repeat SKIP words to compensate different reference clocks, with a pulse of `Stat_ClkCor` per correction and `Stat_RxBufErr` on overflow or underflow; after an underflow, and with `RxBufReset_g` after an overflow, the buffer starts again at its start level (PA-RS-03). | 5.5.3 |
| PA-MD-05 | A reset sequence shall start at the end of the stretched reset (`RstPulseCycles_g`), but not before `PowerUpTime` after the start of the simulation; the transmit reset done shall show 1 for `TxDoneStale` after the end of the stretched reset (the state of the previous start), at the latest until `LaneClk` starts, `LaneClk` shall start `ClkDelay` after the start of the sequence, `Stat_TxReady` (a register of `FreeRunClk` that takes the reset done only after it was 0 once since the release of the reset, PA-ST-02) shall rise `TxReadyDelay` after it and `LaneRst` fall two `LaneClk` cycles later, `Stat_RxReady` shall rise `RxReadyDelay` later; a reset during the sequence shall start it again; a receiver shall decode words only `CdrLockTime` after the first transition of a signal at its pins after electrical idle or a reset (control record, defaults from the transceiver model). | none (implementation) |
| PA-MD-06 | `Phy_TxEnable` low and the idle control shall give electrical idle; `Phy_RxEnable` low shall stop the reception, `Phy_CdrEnable` shall have no effect; `Phy_NoSignal` shall always be 0 (`NoSignalNever`, default, as `struct`; while the line has been idle for `NoSignalDelay` the receiver delivers 13 words with code errors and then words without errors that are not lane words, as the receiver of the transceiver), or 1 while the line has been idle for `NoSignalDelay` (`NoSignalLine`, a Physical adapter with a loss of signal indication). | 5.4.1e, 5.4.2.4a, 5.4.2.4b.1 |
| PA-MD-07 | The control record shall invert the transmitted pair, delay the transmitted bits of a lane (skew), inject single bit errors, dropouts and a bit error rate, per instance (`ModelIdx_g`) and lane. | none (verification model) |
| PA-MD-08 | The near-end serial loopback shall pass the transmitted bits to the own receiver while the pins are driven; the far-end serial loopback shall send the received bits back on the pins. | 5.4.2.2 |
| PA-MD-09 | The PRBS generator and checker (PRBS-7, -9, -15, -23, -31) shall work per lane on the bit stream as in PA-PR-01, with lock, error per word, force error and checker reset; a reset of the transmitters shall restart the generator from its seed. | none (test function) |
| PA-MD-10 | Two cores over two models shall initialise the link and transfer packets like over the transceiver model: link initialised after the transmitters are ready within 10 % and the first burst delivered within 1 % of the time of TC-PA-02. | none (verification model) |
| PA-MD-11 | The outputs of the lane clock domain shall change after the edge of `LaneClk` at the port, never in the delta cycle of that edge, so that a design clocked by the port samples the values of the previous edge. | none (verification model) |
| PA-MD-12 | The model shall use the reset sequencer of `struct` for the entire receiver reset, the CDR-only reset and the transmit buffer reset (requests as in PA-RS-04 and PA-RS-06, bounds as in PA-RS-05). RXRESETDONE shall be low from a GTRXRESET pulse in sequential mode until `RxResetTime` after its end, or stay low with `RxResetHang`; every receiver and CDR reset shall relock the receiver (`CdrLockTime`), and no word shall be delivered while RXRESETDONE is low or the reset runs; `TxBufErrReq` shall set the transmit buffer error until the transmit buffer reset; the status and events of PA-ST-03 shall be reported (CDR lock as the comma alignment, electrical idle while the line is idle). The CDR hold and PCSRSVDIN have no effect in the model. | none (verification model) |

## 3. Configuration parameters

| Generic | Default | Description |
| --- | --- | --- |
| `NumLanes_g` | 4 | Number of lanes (1 to 4); channels 0 to `NumLanes_g` - 1 of the quad, the other channels send electrical idle |
| `RxBufReset_g` | true | Reset of the receive elastic buffer of a lane after a buffer error and after the first comma alignment of a lane start (PA-RS-03); false leaves the buffers to the transceiver |
| `RxRstDoneCycles_g` | 15000000 | Bound of the wait for RXRESETDONE high in an entire receiver reset, `FreeRunClk` cycles (150 ms at 100 MHz, PA-RS-05) |
| `CdrWaitCycles_g` | 10000 | Wait after the RXCDRRESET pulse in the CDR-only receiver reset, `FreeRunClk` cycles (100 us at 100 MHz) |
| `RxRstGapCycles_g` | 400000 | Gap after a receiver reset of a lane in which requests of a receiver reset are dropped, `FreeRunClk` cycles (4 ms at 100 MHz, PA-RS-04); 0: none, for a design whose initialisation timeout is longer than a receiver reset |
| `ModelIdx_g` | 0 | Architecture `mdl` only: index of the control record of the instance (`ofb_pa_model_pkg`); `struct` ignores it |

Configuration inputs (static levels from any clock domain, the MIB register PA_CTRL in a core; synchronised to
`FreeRunClk` and taken when unchanged for 8 cycles, so a multi-bit value is never taken half-way; change them while the
lanes are stopped or before a receiver reset command):

| Input | Default | Description |
| --- | --- | --- |
| `Cfg_RxResetOnDisc` | 1 | Entire receiver reset of a lane at the falling edge of its CDR enable (PA-RS-04) |
| `Cfg_RxResetCdrOnly` | 0 | RXCDRRESET and a fixed wait instead of the entire receiver reset |
| `Cfg_CdrHoldIdle` | 1 | CDR hold while the receiver reports electrical idle (PA-IF-04) |
| `Cfg_PcsRsvdIn` | 0x0360 | PCSRSVDIN of every channel outside the reset sequences, taken at the start of the next reset sequence of the lane. 0x0360 is a transceiver setting for laboratory use, with bits 9:8 (RXDAPIRESETMASK) set and bit 10 (RXDAPIRESET) clear, as the reset sequences require (the wizard ties PCSRSVDIN to 0x0240 when its debug ports are not used). Other values are outside the verified configuration |

Transceiver settings (`tcl/ofb_gtw.tcl`): line rate 6.25 Gbit/s, reference clock frequency (argument, 156.25 MHz for
the VCK190), LCPLL, 8B/10B, user data width 32 bits, internal width 40 bits, transmit user clock from TXPROGDIVCLK
(156.25 MHz from the LCPLL), comma alignment on 4-byte boundaries with the comma mask 0011111111 (the 7-bit comma
sequences of PA-SY-01), receive elastic buffer with clock correction sequence K28.7 D14.6 D31.3 D31.3 (expected rate
difference 200 ppm, clock correction periodicity setting 2000; the transmitters of the Lane layer send the SKIP words
every 5000 words, ECSS 5.5.3d), elastic buffer reset on comma alignment, out-of-band detection enabled (receive
electrical idle for PA-IF-04), the per-channel reset, CDR and debug ports of PA-RS-04 to PA-RS-06. The line driver
settings of the wizard are used unchanged: TXDIFFCTRL 11001, TXMAINCURSOR 77, pre-cursor and post-cursor 0.

## 4. Verification environment

The transceiver is an encrypted model of the AMD simulation libraries. Its test runs separately from the GHDL
regression with the AMD simulator (`tools/run_xsim.py`); the final end-to-end test of two cores over the transceiver
model follows the same flow.

## 5. Interpretation of the standard

- The serial loopbacks (5.4.2.2) are the PMA loopbacks of the transceiver. In near-end loopback the transmitter
  still drives the line. A far-end loopback resets the transmit datapath of the quad (the transceiver requires a
  transmit reset after entering or leaving it), so the transmitters of the other lanes restart as well. The far-end
  loopback retimes the received bits with the transmit clock of the loopback end: with different reference clocks at
  the two ends, bits are lost or repeated at intervals given by the frequency difference (seen in the simulation at
  1000 ppm); the error recovery of the Data Link layer at the far end corrects the affected frames.
- Bit synchronisation status (5.4.2e) is reported as the comma alignment of the receiver (`Stat_Aligned`). The
  VCK190 reference design connects it to `Phy_BitSync` of the core (LANE_STATUS bit 6).
- The deserialiser is ready within 150000 bits after a valid signal appears (5.4.2g) once the transceiver reset
  sequence is complete; the receive clock data recovery of the GTY locks within a few microseconds.
- The standard leaves the receiver of a lane that restarts to the Physical layer. The adapter resets the entire
  receiver of the lane when the lane leaves the states that use the line (PA-RS-04), the reset the transceiver
  documentation recommends after the remote end powers up, after electrical idle and after connecting the line. The
  reset can take longer than the initialisation timeout of 5000 words (5.5.2.6b.1, 32 us at 156.25 MHz; PG442 gives
  up to 150 ms for a transceiver reset): with that timeout a lane makes initialisation attempts between two resets
  (the gap of PA-RS-04); a design may set a longer initialisation timeout (LANE_INIT_TIMEOUT, a deviation from the
  standard) so that the lane stays in Started while its receiver resets.

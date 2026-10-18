# ofb_pa_gty: Verification Report

## 1. Test results

Run on 2026-10-05 with Vivado 2025.2 (transceiver wizard gtwiz_versal 1.0, xsim): `python tools/run_xsim.py`.

| Testbench | Test | Result | Simulated time |
| --- | --- | --- | --- |
| `ofb_pa_gty_tb` | TC-PA-01, TC-PA-04, TC-PA-06 | Pass | 132 us |
| `ofb_pa_gty_cc_tb`, run `cc` | TC-PA-03 | Pass | 94 us |
| `ofb_pa_gty_cc_tb`, run `far` | TC-PA-05 | Pass | 144 us |
| `ofb_pa_gty_core_tb` | TC-PA-02 | Pass | 199 us |
| `ofb_pa_gty_core_tb`, runs `lanes1` to `lanes3` | TC-PA-02 with 1 to 3 lanes (2026-10-15) | Pass | 98 to 104 us |
| `ofb_pa_gty_core_tb` | TC-PA-02 with the transmitter ready input of the core and the reset of the adapter of A (2026-10-16) | Pass | 294 us |
| `ofb_pa_gty_core_tb`, runs `lanes1` and `lanes2` | TC-PA-02 with 1 and 2 lanes, transmitter ready input (2026-10-16) | Pass | 99 to 103 us |

TC-PA-01: transmitters ready after 64.9 us, receivers ready after 68.2 us; 342 data words per lane checked without
error, all lanes aligned, NoSignal low.

TC-PA-04: with the external loopback removed and the near-end serial loopback enabled, 409 data words per lane
received in order without error.

TC-PA-06: PRBS-31 sent and checked on every channel with the external loopback; the checkers locked 14.3 us after the
patterns were selected, no error in 5 us; the line of each lane inverted for 1 ns gave 2 or 3 words with errors on that
lane only, the checker stayed locked, no error afterwards; the PRBS-7 checker of lane 0 on the PRBS-31 pattern counted
769 words with errors in 5 us (nearly every word).

TC-PA-05: same reference clock frequency at both ends; about 3210 data words per lane and end before, then with the
far-end serial loopback at B 3006 data words per lane of A received in order without error.

TC-PA-03 (1000 ppm): 8 clock corrections at A (SKIP words inserted), 4 at B (SKIP words removed), no receive buffer
error; about 3480 data words per lane and end received in order, no word lost or repeated.

TC-PA-02 (200 ppm): transceivers ready after 64.9 us, link initialised after 94.2 us (four lanes data-sending and
data-receiving, Both-Ends Ready at both ends, ML_STATUS 0x2FF); first burst delivered after 98.3 us; 4 clock
corrections at A and 1 at B by 194.3 us; all 24 packets per VC and direction and 4 broadcast messages per direction
delivered in order, DL_ERRORS zero and no retry at either end.

TC-PA-02 with one to three lanes (run on 2026-10-15, `python tools/run_xsim.py ofb_pa_gty_core_tb.lanes1` to
`.lanes3`, link initialisation and first burst; four lanes are the full run above):

| Lanes | Transceivers ready | Link initialised | First burst delivered | ML_STATUS |
| --- | --- | --- | --- | --- |
| 1 | 64.9 us | 94.06 us | 104.18 us | 0x611 |
| 2 | 64.9 us | 94.11 us | 100.23 us | 0x233 |
| 3 | 64.9 us | 94.16 us | 98.28 us | 0x277 |

All packets of the first burst and the broadcast messages delivered in order at both ends, DL_ERRORS zero.

A simulation of the transceiver model takes about 10 minutes of elaboration and 2 to 25 minutes of simulation.
A line `model error <run> (attempt 1 of 3: transceiver model power-up error DIV_VAL_CHK, ...), elaborating again` in
the output of `tools/run_xsim.py` is expected now and then: it is the power-up error of the simulation model
(section 2), and the runner repeats the run with a new elaboration. A run fails only when the last of three attempts
fails.

Rerun on the merged tree (serial loopbacks, bit synchronisation, fault injection campaign, DED containment) with
the CPU otherwise idle: all runs pass, `ofb_pa_gty_core_tb` with the changed Multi-Lane and Data Link layers as
well.

Rerun with the fault-tolerant status crossings, reset synchronisers and transceiver status synchronisers (Open
Logic backlog on the 4.7.0 development state): all runs pass; `ofb_pa_gty_core_tb` needed a second run (power-up
error of the model in the first one, section 2).

Rerun with the PRBS test ports (TC-PA-06 added): all runs pass with the results above, `ofb_pa_gty_core_tb` at the
first attempt.

Rerun after the timing changes of the second build (end flags in the input VC buffers, input stage of the column
encoder): `ofb_pa_gty_cc_tb` (both runs), `ofb_pa_gty_core_tb` (link initialised after 94.2 us, first burst after
98.3 us, all packets delivered, no error, no retry) and `ofb_vck190_tb` pass. `ofb_pa_gty_tb`, the first run after the
runner had generated the wizard instance again, reached TX ready 14 ns early and two lanes never aligned (the
non-deterministic behaviour of the transceiver model, section 2); its rerun passes with the results above.
Rerun of `ofb_pa_gty_core_tb` with the output register of the receive frame buffer: link initialised after 94.2 us,
all packets and broadcast messages delivered, no error, no retry (pass).

Rerun after the findings of the first VCK190 build (lane reset and far-end loopback enables from registers,
register stages of the input VC buffers, latch-free pulse crossing): `ofb_pa_gty_tb` and both runs of
`ofb_pa_gty_cc_tb` pass with the results above. `ofb_pa_gty_core_tb` first failed: the transceiver model of end B
reported the power-up error of the model (section 2; the link never came up)
and the input VC buffers of end A delivered one beat of undefined words before their reset (see the Data Link
report); the rerun with the fix passes with the results above (link initialised after 94.2 us, all packets and
broadcast messages delivered, no error, no retry).

Rerun on 2026-10-12 with Open Logic 4.7.0-ft.2 (status crossings, reset generators and transceiver status
synchronisers as base entities with `SyncTmr_g` = true): `ofb_pa_gty_tb`, `ofb_pa_gty_cc_tb.cc` and `ofb_vck190_tb`
pass at the first attempt. `ofb_pa_gty_cc_tb.far` and `ofb_pa_gty_core_tb` first failed with the power-up error
of the transceiver model of end B (section 2; the receivers never became ready); after a new elaboration both pass
with the results above (far end: receivers ready after 68.2 us, every lane checked without error;
`ofb_pa_gty_core_tb`: all packets and broadcast messages delivered, no error, no retry, simulation done at
198.6 us).

Rerun on 2026-10-13 with the packet ports of the VCs (the generator sends packets of whole words in beats with
`TKEEP` and `TLAST`, the checker compares the words of every beat with `TKEEP` and the end of each packet with
`TLAST` and no EEP): `ofb_pa_gty_core_tb` passes at the first attempt (first burst delivered after 98.3 us, broadcast
messages without error, simulation done at 198.6 us), and again on 2026-10-14 after the change of the continuous mode
of the output VC buffers (same results). `ofb_pa_gty_tb` and `ofb_pa_gty_cc_tb` do not contain the core and were not
run again.

Rerun on 2026-10-14 with the detection of the model power-up error in `tools/run_xsim.py` (section 2), next to other
simulations on the host: all five runs pass at the first attempt with the results above (`ofb_pa_gty_cc_tb.far`:
receivers ready after 68.2 us, every lane checked without error; `ofb_pa_gty_core_tb`: simulation done at 198.6 us).

Run on 2026-10-16 with the transmitter ready input of the core (`Phy_TxReady` from `Stat_TxReady`, the core reset is
the power-on reset alone), `Stat_TxReady` taken only after the transmit reset ran, one link reset pulse per entry at
the crossing of the core and the row acceptance of the Multi-Lane layer. Each end reports the first `LaneClk` edge,
every edge of `Stat_TxReady` and every change of its receivers ready and lanes aligned status, and checks that
`Stat_TxReady` is 1 only while its `LaneClk` runs (no violation in any run):

| Run | First `LaneClk` edge | `Stat_TxReady` 1 | All lanes aligned | Receivers ready | Link initialised | First burst delivered | ML_STATUS | DL_ERRORS after the start |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Four lanes (full run) | 64.097 us | 64.885 us | 66.541 / 66.696 us | 68.212 / 68.213 us | 93.085 us | 97.205 us | 0x2FF | 0 at both ends, no retry |
| `lanes1` | 64.097 us | 64.885 us | 66.522 / 66.696 us | 68.212 / 68.213 us | 92.935 us | 103.055 us | 0x611 | 0 at both ends |
| `lanes2` | 64.097 us | 64.885 us | 66.529 / 66.696 us | 68.212 / 68.213 us | 92.985 us | 99.105 us | 0x233 | 0 at both ends |

The full run then resets the adapter of A with the link up: `Stat_TxReady` of A falls at 197.485 us, 2.45 us before
`LaneClk` of A stops (199.937 us); while it stands still the MIB of A reads DL_STATUS 0x101 (TX_READY 0) and
DL_ERRORS 0x1000 (TX_LOST). The transmitters of A are ready again at 228.725 us, the link is initialised again at
290.205 us and the third burst is delivered at 294.205 us; afterwards A holds TX_LOST and B the Far-End Link Reset
flag (DL_ERRORS 0x0020), B no TX_LOST. Four clock corrections at A and one at B by 193.2 us, every packet and
broadcast message of the three bursts delivered in order. `lanes2` needed a second elaboration (power-up error of the
transceiver model of B in the first one, section 2). `lanes3` ran on the transmitter ready state before the two changes
of the first rows of a link: link initialised after 93.035 us, first burst after 97.155 us, ML_STATUS 0x277,
DL_ERRORS zero.

Runs on 2026-10-17 with the lane initialisation timeline of the testbench (lane enables and `Phy_NoSignal` of every
lane, kind of the lane words sent, first valid word, words with errors, lane states polled through the MIB):

- `ofb_pa_gty_core_tb.relock` (one lane; the transmitter of lane 0 of B disabled at its adapter from 104.535 us to
  110.735 us, 6.2 us): link initialised at 92.935 us, traffic started at 93.055 us, first burst complete at
  101.466 us (8.411 us after the start of the traffic), delivered at 103.055 us; lane 0 Active again at both ends
  26.04 us after the transmitter of B was enabled again, no initialisation timeout, DL_ERRORS zero at both ends,
  second burst delivered at 147.135 us.
- `ofb_pa_gty_core_tb` (four lanes, full run): link initialised at 93.085 us, traffic started at 93.205 us, first
  burst complete at 96.692 us (3.487 us after the start of the traffic), delivered at 97.205 us; four clock
  corrections at A and one at B by 193.2 us, DL_ERRORS zero and no retry at both ends. The reset of A in operation
  (request from 197.445 us to 197.545 us): `LaneClk` of A runs again 30.391 us after the end of the request,
  `Stat_TxReady` rises after 31.180 us, `Phy_NoSignal` falls after 32.765 us and `Stat_RxReady` rises after
  34.512 us; the link is initialised again at 290.205 us and the third burst is delivered at 294.205 us. Each lane of B
  counts one initialisation timeout (LANE_TIMEOUT_COUNT 1): B detects the loss 1.8 us after the end of the request
  and starts its lanes again at 4.0 us; A sends again only from 31.97 us, when its `LaneClk` runs and its lanes
  start, and the receivers of B lock 16.8 us later, so the initialisation timeout of B (32 us) expires at 36.0 us and
  B starts once more. This is the expected behaviour of the Lane layer.

`Phy_NoSignal` in the transceiver model: it is 1 from the first `LaneClk` edge and falls at both ends at 66.471 us
(lanes 0 and 1 of A at 66.471 us, lanes 2 and 3 one `LaneClk` cycle later, every lane of B at 66.472 us), at A 7 ns
before B enables its transmitter, 1.586 us after TX ready. It then stays 0, also during the interruption of the lane
restart run, although the pins of A are idle 61 ns after the transmitter of B is disabled. The receive electrical idle
of the transceiver model therefore marks a point of the reset sequence and does not follow the line.

Loss of the signal in the transceiver model: from 102 ns after the line becomes idle, the receiver of A delivers 13
words with code or disparity errors and then valid words without errors that are not lane words. The Lane layer
loses the word synchronisation after the errors (ECSS 5.5.8), counts every following word as RXERR (RXERR_COUNT 127
at the poll 1.1 us after the disable, 255 at the poll 2.4 us after it) and enters LossOfSignal when the counter
overflows: LOST_SIGNAL from 106.369 us, 1.77 us after the line became idle (LANE_EVENTS RXERR_OVERFLOW at A,
FAR_LOST_SIGNAL at B). After the return of the signal the receiver delivers valid words without errors before its
clock-data recovery has locked: the run of 1023 such words ends 6.54 us after the return, the first lane word comes
17.12 us (A) and 17.18 us (B) after it.

### Behavioural model (architecture `mdl`)

Run on 2026-10-17 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7: `python run.py "*ofb_pa_gty_model*"`, 46 of 46 tests
pass: TC-PA-10 to TC-PA-18 with one to four lanes (TC-PA-11 and TC-PA-18 also with the reference clocks 1000 ppm
apart) and TC-PA-02 with the model (`ofb_pa_gty_model_core_tb`: one to four lanes, and the lane restart with
`Phy_NoSignal` as in the transceiver model, `lanes1_relock`, and following the line, `lanes1_relock_line`). Mutation
checks: a model whose `Stat_TxReady` takes the reset done without the arming of PA-ST-02 fails TC-PA-10 (TX ready
from the reset done of the previous start); a model whose lane clock domain changes its outputs in the delta cycle of
the `LaneClk` edge (PA-MD-11) fails TC-PA-10.

QuestaSim on 2026-10-18 at a time resolution of 1 fs (commit 9dff622, the tree of main 77f4eea): the 46 tests pass
with and without coverage ([coverage record](../../../docs/coverage.md)). The full run with four lanes gives the same
times as GHDL to the femtosecond: first clock correction at both ends at 353.205 us, first burst complete at
96.649726 us, link initialised again after the reset of A at 450.205 us.

Run on 2026-10-18 with GHDL 6.0.0 (mcode): TC-PA-10 also resets A a second time in each phase of its reset sequence
(while the reset done of the previous start shows, before `LaneClk` starts, before TX ready, before RX ready;
`TxDoneStale` 1 us). In every phase `LaneClk` runs again 20.48 to 20.49 us and TX ready rises 21.27 to 21.28 us after
the second reset request, the full delays after the end of the second stretched reset; `ofb_pa_gty_model*` 46 of 46.
Mutation checks: a model that continues its sequence after a reset in one of the four phases fails TC-PA-10, for each
phase.

Run on 2026-10-18 with GHDL 6.0.0 (mcode): TC-PA-17 also resets A twice with PRBS-31 selected; the first 256 bits on
the pins of lane 0 of A are the same after both resets (PA-MD-09), 4 of 4 configurations. Mutation check: a model
whose PRBS generator is not reset with the transmitters fails TC-PA-17.

TC-PA-10 with the default reset sequence: the stretched reset of B ends 5 us after that of A, both before
`PowerUpTime`; `LaneClk` starts at 64.099 us, both ends are TX ready at 64.885 us, `Phy_NoSignal` falls on every lane
of both ends at 66.474 us and the lanes of B align 16.833 us after TX ready. After the reset of A in operation
(stretched reset of 10 cycles in this testbench), `LaneClk` runs again 20.484 us and `Stat_TxReady` rises 21.273 us
after the end of the reset request, although `TxDoneStale` lasts beyond `ClkDelay`. TC-PA-15 with `NoSignalSequence`
at B: while the line from A is idle, `Phy_NoSignal` stays 0 and the receiver of B delivers 13 words with code errors
and then words without errors.

Two cores over two models at the pins (`ofb_core_tb`, configuration `lanes4_pin`, protocol tests with `CdrLockTime`
500 ns), run on 2026-10-17: link start, traffic, error recovery with bit errors and throughput pass (TC-CORE-01, 02, 03,
16, 4 of 4). A to B 18.638 Gbit/s (93.2 % of the lane capacity), both directions 17.904 and 17.960 Gbit/s, latency of a
packet of one byte 495 ns (with the word-level channel model 391.8 ns: serialisation and the receive buffer of the model
add about 100 ns).

TC-PA-02 with the model (`ofb_pa_gty_model_core_tb`, the testbench of the transceiver model run) against the
transceiver model; the link and the first burst are polled every microsecond, the other times are exact:

| Event | Transceiver model, four lanes | Model, four lanes | Transceiver model, one lane | Model, one lane |
| --- | --- | --- | --- | --- |
| First `LaneClk` edge | 64.097 us | 64.096 / 64.099 us | 64.097 us | 64.096 / 64.099 us |
| `Stat_TxReady` 1 | 64.885 us | 64.885 us | 64.885 us | 64.885 us |
| `Phy_NoSignal` 0 | 66.471 to 66.477 us | 66.474 us | 66.471 us | 66.474 us |
| Receivers ready | 68.212 us | 68.215 / 68.221 us | 68.212 us | 68.215 / 68.221 us |
| First valid received word (B / A) | 83.358 / 83.700 us | 83.322 / 83.664 us | 83.358 / 83.700 us | 83.322 / 83.664 us |
| Link initialised (poll) | 93.085 us | 93.085 us | 92.935 us | 92.935 us |
| First burst delivered (poll) | 97.205 us | 97.205 us | 103.055 us | 103.055 us |
| Traffic started | 93.205 us | 93.205 us | 93.055 us | 93.055 us |
| First burst complete | 96.692 us | 96.650 us | 101.466 us | 101.431 us |

Both simulators decode the same INIT1 word of the far end first, at both ends (the 42nd; INIT1 comes every 65 words,
0.416 us). The first valid word arrives 36 ns earlier in the model: its receive path is shorter (113 ns from the
transmit interface of the far end to the receive interface, 151 ns in the transceiver model). For the same reason the
first burst is complete 42 ns (four lanes) and 35 ns (one lane) earlier.

PA-MD-10: the link is initialised 28.20 us (four lanes) and 28.05 us (one lane) after the transmitters are ready in
both simulators, on the same poll (bound 10 %). The first burst is complete 31.765 us after the transmitters are ready
in the model against 31.807 us (four lanes, 0.13 % earlier) and 36.546 us against 36.581 us (one lane, 0.10 %
earlier; bound 1 %).

`CdrLockTime`: every first decoded word bounds the lock time of the transceiver model to one INIT1 period. Counted from
the first transition at the receiver pins (it follows the transmitter enable of the far end, the transmit latency
cancels):

| Run | Receiver | First INIT1 word decoded | Lock time |
| --- | --- | --- | --- |
| One and four lanes, power-up | A and B | 42nd | 16.653 us to 17.069 us |
| One lane, lane restart | A (after B is enabled again) | 47th | 16.588 us to 17.004 us |
| One lane, lane restart | B (after A restarts) | 42nd | 16.653 us to 17.069 us |

The intersection is 16.653 us to 17.004 us; `CdrLockTime` is its middle, 16.83 us. With it the model decodes the same
INIT1 words in all three cases.

The receive buffers of the model correct the clock difference later than those of the transceiver model: with
200 ppm between the reference clocks, the full run with four lanes sees the first correction at both ends at
193.2 us with the transceiver model and at 353.2 us with the model (the buffer of the model starts at 16 words and
corrects below 8 or above 24 words, a drift of 8 words, which takes 40000 words at 200 ppm). The full run therefore
releases its second burst and resets the adapter of A later with the model. PA-MD-10 is not affected: the link
initialisation and the first burst do not depend on the corrections (a correction shifts the data stream of a lane by
one word, 6.4 ns, below 0.1 % of the time of the first burst).

The reset of A in operation in both simulators, times after the end of the reset request:

| Event | Transceiver model | Model |
| --- | --- | --- |
| LOST_SIGNAL sent by B (RXERR overflow) | 1.805 us | 1.679 us |
| `LaneClk` of A runs again | 30.391 us | 30.394 us |
| `Stat_TxReady` of A | 31.180 us | 31.180 us |
| `Phy_NoSignal` of A falls | 32.765 us | 32.769 us |
| `Stat_RxReady` of A | 34.512 us | 34.516 us |
| Initialisation timeout at B, lanes of B start again | 36.0 us, 38.0 us | 35.9 us, 37.9 us |
| Link initialised again (poll) | 92.66 us | 92.66 us |
| Third burst delivered (poll) | 96.66 us | 96.66 us |
| LANE_TIMEOUT_COUNT of each lane of B | 1 | 1 |

The transceiver model keeps its transmitter running for about 0.13 us after the reset request; the model goes to
electrical idle at once, so B detects the loss 0.13 us earlier. LANE_EVENTS of B shows RXERR_OVERFLOW and TIMEOUT in
both simulators and FAR_LOST_SIGNAL only with the transceiver model (no effect on the link initialisation).

Lane restart (one lane, the transmitter of lane 0 of B disabled for 6.2 us), polled every microsecond through the MIB:

| Event | Transceiver model | Model, `NoSignalSequence` | Model, `NoSignalLine` |
| --- | --- | --- | --- |
| Pins of A idle after the disable | 61 ns | 1 ns | 1 ns |
| First word with errors at A | 104.698 us | 104.643 us | none (no words) |
| LOST_SIGNAL sent by A | 106.369 us (RXERR overflow) | 106.314 us (RXERR overflow) | 104.656 us (`Phy_NoSignal`) |
| Lane 0 of A at the polls | ClearLine 106.895 us, Started 109.375 us, Connecting 135.415 us, Active 136.655 us | same | ClearLine 105.655 us, Started 108.135 us, Connecting 135.415 us, Active 136.655 us |
| First INIT1 word decoded after the return (A, B) | 47th, 42nd | 47th, 42nd | 51st, 42nd (the lane of B starts 1.6 us earlier) |
| Lane 0 Active again after B is enabled again | 26.04 us | 26.04 us | 26.04 us |
| LANE_EVENTS of A, B | RXERR_OVERFLOW, FAR_LOST_SIGNAL | RXERR_OVERFLOW, FAR_LOST_SIGNAL | none, FAR_LOST_SIGNAL |
| Initialisation timeouts (A, B), second burst | 0, 0, delivered | 0, 0, delivered | 0, 0, delivered |

Lane restart sweep with the model and the final defaults, run on 2026-10-18 (`ofb_pa_gty_core_tb`, `Relock_g`, the
transmitter of lane 0 of B disabled at its adapter for `CutNs_g`, the end of the interruption at the next poll of the
testbench; temporary configurations, `lanes1_relock` is in the regression):

| Lanes | Interruption | Initialisation timeouts (A, B) | Lane Active again after the transmitter of B was enabled again |
| --- | --- | --- | --- |
| 1 | 6.2 us, 8.7 us | 0, 0 | 26.04 us |
| 1 | 11.2, 12.4, 16.1, 21.1 us | 1, 1 | 53.32, 52.08, 48.36, 43.40 us |
| 1 | 40.9 us | 1, 1 | 26.04 us |
| 4 | 6.2 us | 0, 0 | 26.04 us |
| 4 | 16.1 us | 1, 1 | 48.36 us |

The first lane word is decoded 17.0 to 17.6 us after the signal returns, the first 1023 words without error end 23.6
to 23.7 us after it. From an interruption of 11.2 us on, the initialisation timeout expires once at each end and the
lane is Active again within 54 us. In every run the other lanes stay Active and a second burst is delivered without
error.

## 2. Summary

All test cases pass. VSG reports no errors and no warnings (the port names of the transceiver wizard and of
`BUFG_GT` are excluded from the naming rules with `vsg_off` comments).

Findings during verification:

| Finding | Fix |
| --- | --- |
| QuestaSim at its default time resolution of 1 ps (2026-10-18): `ofb_pa_gty_model_core_tb.lanes4` saw no clock correction at either end by 1001 us (GHDL: one at each end at 353.2 us). The reference clock of B, 200 ppm slower than that of A, toggles after 3200.64 ps, which 1 ps truncates to 3200 ps: both ends ran at the same frequency | `run.py` runs QuestaSim at 1 fs, as GHDL; the model description states the resolution (section 6) |
| No clock correction: the receive buffers overflowed and underflowed (data words lost or repeated, TC-PA-03). The combined fields `RX_CC_K` and `RX_CC_VAL` of the wizard are not derived from the per-character keys when the settings are set by Tcl | `tcl/ofb_gtw.tcl` sets the combined fields in the format of the Gigabit Ethernet preset of the wizard (K flags in `RX_CC_K`, values in `RX_CC_VAL`) and `RX_PPM_OFFSET` 200 |
| The receive buffers output zero words for a few hundred cycles after the receivers are ready (TC-PA-03) | `PhyRx_Valid` from the first K character of the lane after the receivers are ready |
| Far-end serial loopback at B with the reference clock of B 1000 ppm slower: 1 or 2 errors per lane in 3000 words at A (the loopback retimes the bits with the transmit clock of B) | Property of the transceiver loopback, documented in the specification (section 5); TC-PA-05 runs with equal reference clock frequencies |
| `export_simulation` occasionally prints the file list to stdout instead of writing `vlog.prj`, also with stdin closed | The runner recovers `vlog.prj` from the log |
| Optional ports of the wizard set through `INTF0_TXRX_OPTIONAL_PORTS` are ignored | `INTF0_OPTIONAL_PORTS` takes the dictionary of all ports (`tcl/ofb_gtw.tcl`) |
| With an inherited stdin, `export_simulation` writes the file list `vlog.prj` to stdout | The runner starts Vivado with stdin closed |
| xsim does not order the files of a module | The runner orders the files by the units they define and use |
| TC-PA-03 after the generic `RefPpmB_g` was introduced: no clock correction (the offset of B was computed wrongly) | Offset in whole picoseconds: `RefPpmB_g * 3200 ps / 1000000` |
| TC-PA-06: the forced error of the PRBS generator (`TXPRBSFORCEERR`, held for 1 to 64 cycles, near-end and external loopback) gave no error at the checker, although the port reaches the channel of the quad; the checker detects other errors | The transceiver model does not insert the forced error: TC-PA-06 inverts the line for 1 ns instead; the forced error is tested in the core testbench (TC-CORE-18, register to adapter port) and on the hardware (TC-VCK-HW-08) |
| The transceiver model gives different results for the same sources: one `ofb_pa_gty_tb` run reached TX ready 14 ns early and two lanes never aligned; runs of `ofb_pa_gty_cc_tb.far`, `ofb_pa_gty_core_tb` and `ofb_vck190_tb` failed with a power-up error of the model of one quad (`DIV_VAL_CHK`: `div_val has to be >= 9 and <= 163 : 0`, about 38 us after the start, when the model programs the LCPLL; that quad never becomes ready). Analysis with `ofb_pa_gty_cc_tb.far` on 2026-10-14: the elaborator builds a different snapshot from the same sources every time (the snapshot files differ, with and without multithreaded elaboration); 7 fresh elaborations gave 6 passing and 1 failing snapshot. The failing snapshot fails in every further run with the same error at the same picosecond, with other simulations on the host or without, and also when the reset release of end B or of both ends is delayed by 3.2 us (20 x 160 ns, the least common multiple of the 6.4 ns reference clock and the 10 ns free-running clock periods), when the reference clock of B is shifted by 1.1 ns or its free-running clock by 3.7 ns: the error does not depend on the testbench timing. All 1947 parameters and ports of the quad level of the wizard are equal in failing and passing snapshots and at both ends; the outputs of the model of the failing quad differ from 1 to 2 us on (power-up of the encrypted model). The firmware files of the model have the same names in every run | Cause in the simulation model, not in the design or the testbench; the device image is not affected. `tools/run_xsim.py` detects the error in the log and elaborates the test run again (at most three attempts, every repetition reported) |
| The runner reused an exported wizard instance generated before the PRBS ports were added to `tcl/ofb_gtw.tcl` (elaboration error: formal port `INTF0_TX1_ch_txprbssel` does not exist) | The runner keeps a hash of `tcl/ofb_gtw.tcl` and generates, exports and compiles the wizard instance again when it changes |
| `ofb_pa_gty_core_tb.lanes1` with the transmitter ready input of the core (2026-10-16, before the changes of the first rows of a link): link and first burst as before, but DL_ERRORS 0x8 (sequence error) at both ends after the start | Defect of the core: the last link reset pulse of the crossing discarded the first two rows of the new link in the single-lane bypass (verification reports of `ofb_core` and `ofb_multilane`); after the change DL_ERRORS is zero and the link is initialised 1.1 us earlier (92.935 us) |
| The transceiver model reaches TX ready at power-up at the same time after the start of the simulation, whatever the end of the stretched reset (64.885 us with the stretched reset ending at 10.21 us, 64.83 us in a system testbench with 6.0 us), and after a reset of the adapter in operation 21.17 us after the end of the stretched reset (full run of 2026-10-16). The model counted every reset sequence from the end of the stretched reset with the delays of the first start (TX ready 4.2 us early with 6.0 us, about 33 us late after a reset in operation) | The model starts a reset sequence at the end of the stretched reset, not before `PowerUpTime`; `ClkDelay` and `TxReadyDelay` count from the start of the sequence, and the reset done of the previous start ends at the latest when `LaneClk` starts (TC-PA-10 checks the power-up with two ends of the stretched reset and a reset in operation) |
| First comparison of the lane initialisation with the model (2026-10-17, `CdrLockTime` 17.1 us): the first valid word reached B 0.37 us later than with the transceiver model. In the model `Phy_NoSignal` fell with the first transition at the pins, in the transceiver model at a point of its reset sequence 0.33 us after A enabled its transmitter, so B started to send 0.33 us later there; and the model decoded the 43rd INIT1 word of the far end, the transceiver model the 42nd | `NoSignalMode` with the default `NoSignalSequence` (`NoSignalTime` 22.755 us) and `CdrLockTime` 16.83 us, the middle of the lock times bounded by all first decoded words: both simulators decode the same INIT1 words |
| `Phy_NoSignal` of the transceiver model does not follow the line: it stayed 0 while the line from B was idle for 6.2 us (lane restart run). A signal detection delay of 0.32 us had been assumed from the power-up alone | `NoSignalSequence` reproduces the transceiver model, and the Lane layer detects a lost signal through its RXERR counter as there; `NoSignalLine` keeps the detection by `Phy_NoSignal` for the tests of that path (`lanes1_relock_line`, TC-PA-15) |
| With `NoSignalSequence` the lane did not restart in `lanes1_relock`: the model delivered no words on an idle line, so the Lane layer saw neither a lost signal nor an error; the testbench passed because it only checked that the lane was Active after the interruption | The receiver delivers 13 words with code errors and then words without errors while the line is idle, as the transceiver model (the same path: word synchronisation lost, RXERR counter overflow, LOST_SIGNAL 55 ns earlier than with the transceiver model); the testbench fails when lane 0 of A does not leave Active during the interruption |
| After a reset of the adapter in operation the transmitter of the model left the last bit on the pins: `LaneClk` stopped in the delta cycle in which TX ready fell, so the transmitter saw no edge and did not go to electrical idle. B detected the loss only when `LaneClk` of A ran again, 32.2 us after the request (transceiver model 1.8 us) | The transmitter goes to electrical idle as soon as TX ready falls; B detects the loss 1.68 us after the request, and the link is initialised again on the same poll as with the transceiver model |
| `ofb_pa_gty_core_tb` with the transmitter ready input of the core (2026-10-15, full run with four lanes): `Stat_TxReady` was 1 from 10.225 us to 38.135 us at both ends, 225 ns after the release of the stretched reset, while `LaneClk` started only at 64.097 us; it became 1 again at 64.885 us. The transmit reset done of the wizard still showed 1 when the reset was released and fell only when its master reset started. Both cores saw the transmitters drop and set TX_LOST (DL_ERRORS 0x1000 after the start at both ends); the bench checked only bits 9:0 | `Stat_TxReady` takes the reset done only after it was 0 once since the release of the reset (PA-ST-02). The bench checks that `Stat_TxReady` is 1 only while `LaneClk` of its end runs, reports every edge of `Stat_TxReady` and the first edge of `LaneClk`, and checks DL_ERRORS bits 12:0 (TX_LOST 0 after the start, 1 at A only after the reset of A) |

# ofb_core: Verification Report

## 1. Test results

Run on 2026-10-15 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*ofb_core*"`; the full
regression passes in GHDL (232 of 232) and in QuestaSim, with and without coverage (232 of 232 each).

Generics of the GHDL simulations, checked on 2026-10-14: VUnit 5.0.0.dev7 appends the generics of a test to the list
of the option `ghdl.sim_flags` in place, and configurations that share that list pass their generics on to later GHDL
simulations. `run.py` sets the simulation options after the configurations, so every configuration held its own list:
an elaboration of all 228 tests without the own copy of the list per simulation gave every GHDL command exactly the
generics of its configuration, and the GHDL results before that copy are valid. With the simulation options set
before the configurations, the check of `run.py` stops the run (mutation check). QuestaSim and the AMD Vivado
simulator are not affected.

Run on 2026-10-15 with the configurations of the generic ranges: the full regression `python run.py`, 287 of 287
tests pass in GHDL and in QuestaSim, with and without coverage (287 of 287 each; the three tests of `vc32` with 32
VCs and two lanes in a separate run, commit 0bab3a2, see `docs/coverage.md`). Run on 2026-10-15 with the
transmitter ready input `Phy_TxReady` (TC-CORE-21 to TC-CORE-25, asynchronous input with one reset generator per
clock domain): 309 of 309 tests pass in GHDL (2026-10-16). Run on 2026-10-16 with one pulse per entry into the
link reset at the crossing (CORE-PL-06) and the row acceptance of the Multi-Lane layer (ML-BP-04), TC-CORE-26,
TC-CORE-27 and the configuration `eqclk`: 322 of 322 tests pass in GHDL; TC-CORE-27 (`ofb_core_cc_tb`) ran in its
own run, 3 of 3. Run on 2026-10-16 with the generics `LaneStart_g` and `AutoStart_g` (TC-CORE-28): the full
regression, 332 of 332 tests, passes in GHDL and in QuestaSim with and without coverage (332 of 332 each); TC-CORE-29
(added afterwards, only the testbench changes, `docs/coverage.md`) passes in GHDL and in both QuestaSim modes, 4 of
4 each.

Run on 2026-10-17 with the alignment watchdog of the Multi-Lane layer (ML-AL-11, register map version 9): the tests
TC-CORE-30 to TC-CORE-33 pass in their configurations (5 of 5), with the default bound of 10000 words:

| Test | Result |
| --- | --- |
| TC-CORE-30 (`lanes4_wd`, `lanes2_wd`) | Static skew of 4 words; no expiry after the normal link start and after the loss of one word at A (A is Both-Ends Ready again 0.55 us after the loss with four lanes, 0.49 us with two, polled through the MIB: about 85 words against the bound of 10000); after the loss of 4 words A stays in Not Ready until the watchdog expires, the lanes start again, the link aligns without a link reset, every packet is delivered in order without EEP, ML_ALIGN_TIMEOUTS 1 at A and 0 at B |
| TC-CORE-31 (`lanes4_wd`) | Skew for 10 % less than the bound: no expiry; for 10 % more: one expiry at A, none at B; short alignments of A during the skew (when a SKIP word leaves a gap on all lanes) do not restart the count |
| TC-CORE-32 (`lanes4_wdoff`) | Watchdog off: A stays in Not Ready and B in Near-End Ready for 192 us, no expiry; a LaneReset through LANE_CTRL recovers the link |
| TC-CORE-33 (`lanes4_wdfar`) | Watchdog off at B: A in Near-End Ready expires after twice the bound, the lanes of both ends start again, every packet is delivered in order without EEP |

A lane manager that ignores the watchdog fails TC-CORE-30 (mutation check): the link stays stalled.

Run on 2026-10-22 with the join hold of the Multi-Lane layer (ML-LM-17, release 0.1.1): the tests TC-CORE-34 and
TC-CORE-35 pass in their configurations (10 of 10):

| Test | Result |
| --- | --- |
| TC-CORE-34 (`lanes1` to `lanes4`) | The last lane of A started 3 us after the others, packets waiting on every VC: all packets delivered, all lanes data-sending and data-receiving, DL_ERRORS 0 and no retry at both ends |
| TC-CORE-34 (`lanes4_nohold`) | The same with the hold off at both cores: 2 retries (the test detects the realignment loss) |
| TC-CORE-35 (`lanes2` to `lanes4`) | Last lane cut: B reaches Both-Ends Ready 3787 to 3796 words after the first lane of A entered Active, when the cut lane of A times out (5000 words after it entered Started); every packet delivered over the other lanes |
| TC-CORE-35 (`lanes4_hold1024`) | With the bound 1024: B reaches Both-Ends Ready 1059 words after the first lane of A entered Active |

The full GHDL regression of the released tree runs in the CI of the release pull request. The QuestaSim regression was
not repeated for release 0.1.1 ([coverage.md](../../../docs/coverage.md), section 6).

Run on 2026-10-23 with the initialisation timeout from the MIB and the ports of the receiver reset (CORE-PL-07,
CORE-PL-08, release 0.1.3): the full regression, 423 of 423 tests in GHDL. TC-CORE-37 (`lanes2_pin_rxrst`, two lanes
through the adapter models without a gap between two receiver resets): lane 0 of A, started without a far end, stayed
in Started for 32.04 us with the reset value of 5000 words and for 96.0 us after LANE_INIT_TIMEOUT was set to 15000
words; after the RX_RESET command during traffic RX_RESETS of lane 0 of A read 1, the RX_RESET flag was set, no
receiver reset timed out, and every packet was delivered in order; with RX_RESET_CDR_ONLY the commanded reset left
RX_RESET_DONE at 1. Mutation checks: a core whose lanes do not take LANE_INIT_TIMEOUT fails TC-CORE-37, and a lane
whose timeout ignores `Cfg_InitTimeout` fails TC-CORE-37 and TC-LN-54. The QuestaSim regression was not repeated for
release 0.1.3 ([coverage.md](../../../docs/coverage.md), section 6).

Run on 2026-10-18 with the behavioural adapter model, two cores pin to pin through two `ofb_pa_gty` with the
architecture `mdl`: TC-CORE-03 passes with `CdrLockTime` 500 ns (`lanes4_pin`, no expiry of the alignment watchdog)
and with the lock time of the transceiver model and near the ends of the interval that bounds it, 16.65 us, 16.83 us
and 17.0 us (`lanes4_pin_lock16650`, `lanes4_pin_lock16830`, `lanes4_pin_lock17000`). In each of the three runs with
these lock times the alignment watchdog of A expires once (ML_ALIGN_TIMEOUTS 1 at A, 0 at B), the lanes start again,
the link stays initialised and every packet is delivered in order. Without the watchdog the error recovery with the
lock time of the transceiver model stalled with A in Not Ready (the defect in section 2).

Full regression at commit d587ac2, GHDL in the CI workflow (run 39081619707, 2026-10-18): 396 of 396 tests pass, 153
of them of `ofb_core_tb` and `ofb_core_cc_tb`:

| Testbench | Tests | Passed |
| --- | --- | --- |
| `ofb_core_tb` (configurations `lanes1` to `lanes4`) | 28 x 4 | 112 |
| `ofb_core_tb`, configuration `lanes1_slowcore` (TC-CORE-15 only) | 1 | 1 |
| `ofb_core_tb`, configurations `vc1` and `vc32` (TC-CORE-01, 02, 04) | 3 x 2 | 6 |
| `ofb_core_tb`, configuration `halfrate` (TC-CORE-01, 04, 21, 23) | 4 | 4 |
| `ofb_core_tb`, configuration `minbuf` (TC-CORE-01 to 04) | 4 | 4 |
| `ofb_core_tb`, configuration `noprbs` (TC-CORE-01, 02) | 2 | 2 |
| `ofb_core_tb`, configuration `eqclk` (TC-CORE-21 to 26) | 6 | 6 |
| `ofb_core_tb`, configurations `lanestart1`, `lanestart4` and `noauto` (TC-CORE-28) | 1 x 3 | 3 |
| `ofb_core_tb`, configurations `lanes4_wd` (TC-CORE-30, 31), `lanes2_wd` (TC-CORE-30), `lanes4_wdoff` (TC-CORE-32) and `lanes4_wdfar` (TC-CORE-33) | 2 + 1 + 1 + 1 | 5 |
| `ofb_core_tb`, configuration `lanes4_pin` (TC-CORE-01, 02, 03, 16) | 4 | 4 |
| `ofb_core_tb`, configurations `lanes4_pin_lock16650`, `lanes4_pin_lock16830` and `lanes4_pin_lock17000` (TC-CORE-03) | 1 x 3 | 3 |
| `ofb_core_cc_tb` (configurations `core_fast`, `equal`, `lane_half`) | 1 x 3 | 3 |

QuestaSim on 2026-10-18 ([coverage record](../../../docs/coverage.md)): the full regression at commit 9dff622 (the
tree of main 77f4eea) passes without coverage at a time resolution of 1 fs, 396 of 396; with coverage, every test of
`ofb_core_tb` and `ofb_core_cc_tb` passes at commit b6242a2 (153 of 153, identical design sources).

Generic ranges (verification plan, section "Generic ranges"): every value of a generic that changes the structure
is simulated, the boundaries of the numeric ranges are simulated or synthesised with GHDL (`lint/synth_check.py`),
and every value outside a range stops the elaboration with the message of its check (synth_check, rejected values).
The frequency generics of the testbench are derived from the generated clock periods.

| Generic | Range | Simulated | Synthesised | Rejected |
| --- | --- | --- | --- | --- |
| `NumVc_g` | 1 to 32 | 1, 4, 32 (32 VCs with two lanes; 8 in the system test with the transceiver model) | 1, 8, 32 (four lanes with 32 VCs elaborated and synthesised) | outside the subtype |
| `NumLanes_g` | 1 to 4 | 1, 2, 3, 4 (all test cases); with `ofb_pa_gty` and the transceiver model 1 to 4 | 1, 2, 3, 4 | outside the subtype |
| `LaneClkFreq_g` | positive | 156.25 MHz; 78.125 MHz (`halfrate`: ClearLine measured 2.010 us and 2.022 us) | 156.25 MHz | not positive (check by inspection: GHDL synthesis cannot override a real generic) |
| `CoreClkFreq_g` | positive | 166.7 MHz; 125 MHz (`lanes1_slowcore`) | 200 MHz | as `LaneClkFreq_g` |
| `VcOutDepth_g` | power of two, `VcOutDepth_g` x `NumLanes_g` >= 64 | 128 beats; 32 beats with two lanes (`minbuf`) | 64 with one lane, 16 with four lanes, 128 | 32 with one lane, 16 with two lanes, 96 |
| `VcInDepth_g` | `NumLanes_g` x power of two; >= 64 with one lane, >= 128 x `NumLanes_g` with several lanes | 256 x `NumLanes_g`; 256 with two lanes (`minbuf`) | 64 with one lane, 512 with four lanes, 256 x `NumLanes_g` | 96 and 192 with one lane, 128 with two lanes, 256 with four lanes |
| `ErbRows_g` | power of two, >= 64 | 512; 64 (`minbuf`) | 64, 512 | 32, 96 |
| `InitPrbsWords_g` | 0 to 64 | 64; 0 (`noprbs`) | 0, 64 | outside the subtype |
| `AlignTimeoutWords_g` | 0, or 1024 to 1000000 | 10000 (`lanes4_wd`, `lanes2_wd`), 0 (`lanes4_wdoff`, and at B in `lanes4_wdfar`); 1024 in the testbench of `ofb_multilane` (TC-ML-50) | 0 and 1024 with two lanes, 1000000 with four lanes (`lint/synth_check.py`, 2026-10-18) | 1023 with one and with two lanes |

Packets of 65542 bytes (TC-CORE-20, the largest Space Packet) pass with 1 to 4 lanes: one from A to B and two at the
same time from B to A, every byte compared.

Transmitters of the Physical adapter not ready (`Phy_TxReady`, 1 to 4 lanes). TC-CORE-21: with the transmitters of A
ready 50 us after the reset, A stays in Near-End Reset with every lane of A off (transmitter, receiver and CDR) and
the link of B is not initialised; afterwards the link comes up without an error flag at either end. TC-CORE-22: with
the transmitters of A never ready, A stays in Near-End Reset for 300 us without lane activity, interrupt, error
flag, retry or lane event, and its MIB stays accessible. TC-CORE-23: when the transmitters of A drop during traffic,
both ends reset the link, A sets TX_LOST and keeps its configuration, no lane of A is on in the last 5 us of the
hold, and the traffic is delivered after the transmitters return; TX_LOST stays set until it is cleared.
TC-CORE-24: LaneClk and CoreClk of A stop and its transmitters become not ready during traffic; while the clocks
stand still the MIB of A reads TX_READY 0 and TX_LOST 1, 200 ns after LaneClk runs again no lane of A is on, and
the link comes up again with the lanes released 1 us before the Data Link layer (round 0) and with the Data Link
layer released 1 us before the lanes (round 1); after each round DL_ERRORS of A holds only TX_LOST. TC-CORE-21 and
TC-CORE-23 also pass with LaneClk at 78.125 MHz (`halfrate`), where the Data Link layer is released first.
TC-CORE-25: with LaneClk and CoreClk of A standing still from the reset on, `Phy_TxReady` of A 1 from 10 us to
38 us (a transceiver that still reports the reset done of an earlier start), the clocks of A running from 64 us
and the transmitters ready from 65 us, the link comes up and the traffic is delivered; A holds only TX_LOST, B no
error flag (1 to 4 lanes). TC-CORE-26: both cores start with their lane and core clocks standing still until 64.1 us
and their transmitters ready from 64.885 us while the MIB runs from the reset on (the timeline of the transceiver
model): the link comes up, the traffic is delivered, and neither core reports an error flag or a retry (1 to 4
lanes).

First rows of a link (CORE-PL-06, ML-BP-04). With one lane and CoreClk at the frequency of LaneClk (`eqclk`, as in
the reference design, where both are the transmit clock of the transceiver), TC-CORE-21 and TC-CORE-26 failed before
the change with a sequence error (DL_ERRORS bit 3) and a retry: the link reset level held by the Data Link layer while
the transmitters were not ready crossed as a train of pulses, the last pulse reached the Multi-Lane layer a few
cycles after the Data Link layer had left Near-End Reset and discarded its first two rows, which the single-lane
bypass had already taken into the column encoder. TC-CORE-21 to TC-CORE-26 pass in `eqclk` with the change.
TC-CORE-27 checks the crossing at the ports of `ofb_core_cc` with CoreClk faster than, equal to and twice LaneClk:
no pulse at the release of the resets, one link reset and one LaneReset pulse per entry for levels of 1, 2 and 200
cycles (one while the long level is still held), none after the release, two for two entries within one transfer,
the hold of the lanes as a level and no pulse after it. At the ports of the core a pulse after the release of a hold
has no effect that a test could observe: a LaneReset that reaches a lane in ClearLine does not restart its 2 us
(`ofb_lane_init`, ECSS 5.5.2.4), and a link reset finds no row in the Multi-Lane layer while the lanes are not
Active (ML-BP-04). TC-CORE-27 is therefore the test of CORE-PL-06.

Reset values of LaneStart and AutoStart (TC-CORE-28, no write of LANE_CTRL): LANE_CTRL of every lane reads 0x62
with the defaults, 0x63 at A with `LaneStart_g` and 0x60 without `AutoStart_g`. With `LaneStart_g` at A and
AutoStart at B the link is initialised and the traffic delivered with one and four lanes; with AutoStart only at
both cores (1 to 4 lanes) every lane stays in Wait and without AutoStart in Disabled, no link in 200 us. No error
flag and no lane event at either core in any case. TC-CORE-29: with both Data Link layers waiting in Check Far-End
Reset, the loss of the transmitters of A moves A to Near-End Reset with TX_READY 0 and TX_LOST; TX_LOST cleared
while they stay not ready is not set again, and A returns to Check Far-End Reset when they are ready (1 to 4
lanes; without the condition in Check Far-End Reset the test fails).

Mutation checks (one lane): with the Data Link layer ignoring `Phy_TxReady`, TC-CORE-21 to TC-CORE-24 fail (A not
in Near-End Reset; in TC-CORE-24 a sequence error at A, DL_ERRORS 0x1008); without the hold of the lanes,
TC-CORE-21 to TC-CORE-24 fail (lanes of A on during the hold); with the MIB taking `Phy_TxReady` from a register
of LaneClk, TC-CORE-24 fails (TX_READY 1 while the clocks stand still). First rows of a link: without both changes,
TC-CORE-21 and TC-CORE-26 fail in `eqclk` (DL_ERRORS 0x8 at one or both cores) together with TC-ML-24 and TC-ML-49;
with the entry pulse alone the core tests pass and TC-ML-24 and TC-ML-49 fail; with the row acceptance alone all
core tests pass and TC-CORE-27 fails with 14 to 16 pulses while the level is held after the release of the
resets.

Throughput and latency (TC-CORE-16, lane capacity 5 Gbit/s per lane: 32 bits per 6.4 ns; core clock 166.7 MHz, user
clock 192.3 MHz; packets of 1 to 1024 bytes on four VCs):

| Configuration | Latency, packet of one byte | A to B only | Both directions, per direction |
| --- | --- | --- | --- |
| lanes1 | 370 ns | 4.73 Gbit/s (94.6 %) | 4.53 / 4.53 Gbit/s (90.6 / 90.6 %) |
| lanes2 | 393 ns | 9.44 Gbit/s (94.4 %) | 9.07 / 9.04 Gbit/s (90.7 / 90.4 %) |
| lanes3 | 400 ns | 14.10 Gbit/s (94.0 %) | 13.60 / 13.63 Gbit/s (90.7 / 90.9 %) |
| lanes4 | 402 ns | 18.71 Gbit/s (93.5 %) | 17.94 / 17.99 Gbit/s (89.7 / 89.9 %) |

The latency includes the behavioural Physical adapter (no serialisation delay) and the store-and-forward frame
buffer of the receiver. Measured on 2026-10-24 with the admission register of the error recovery buffer (DL-ER-09):
it adds one core clock cycle, which the measurement at the user port sees as 5.2 ns with one and two lanes and
10.4 ns with three and four lanes (one or two user clock cycles; without the register 365.0, 387.8, 389.8 and
391.8 ns in the same run). The throughput is unchanged within the variation of the random traffic. On 2026-10-13 the
input stage and the output register of the receive packet conversion had added about 25 ns to the latency of the
earlier measurement (339, 362 and 361 ns), with the throughput unchanged (the payload counts four bytes per word and
the word with the end marker, as before). The losses are the framing words (SDF, EDF per data frame of 64 words per
lane), the EOP and Fill characters, SKIP, and in both directions the ACKs and FCTs of the reverse traffic.

Fault injection campaign (TC-CORE-13): the regression runs seed 1; the extended campaign
`OFB_CAMPAIGN_SEEDS="2,3,4,5" python run.py "*test_fault_campaign*"` adds seeds 2 to 5. The
packets cycle through the length classes 1 to 4, 5 to 64, 65 to 256 and 257 to 1024 bytes, so that faults also hit
packets of several data frames. 15 runs, 600 faults, all pass (faults per kind; retries at A / B; coverage of the
line faults per lane, `CovLine`; broadcast messages received with the LATE flag at A / B, `CovLate`):

| Configuration | Bit error, burst, slip, SEC, DED, lane cut | Retries A / B | Line faults x lanes | LATE messages | Result |
| --- | --- | --- | --- | --- | --- |
| lanes1 | 17, 6, 8, 3, 6, 0 | 9 / 9 | 75 % | 5 / 4 | pass |
| lanes1, seed 2 | 17, 5, 5, 7, 6, 0 | 10 / 4 | 75 % | 6 / 3 | pass |
| lanes1, seed 3 | 8, 10, 7, 11, 4, 0 | 4 / 6 | 75 % | 3 / 3 | pass |
| lanes1, seed 4 | 15, 9, 6, 4, 6, 0 | 8 / 2 | 75 % | 4 / 2 | pass |
| lanes1, seed 5 | 16, 6, 6, 6, 6, 0 | 11 / 4 | 75 % | 4 / 3 | pass |
| lanes2 | 9, 8, 4, 5, 4, 10 | 9 / 11 | 100 % | 5 / 5 | pass |
| lanes2, seed 2 | 7, 5, 11, 8, 5, 4 | 13 / 12 | 100 % | 10 / 9 | pass |
| lanes2, seed 3 | 3, 7, 4, 9, 12, 5 | 6 / 7 | 100 % | 4 / 4 | pass |
| lanes2, seed 4 | 8, 5, 2, 11, 9, 5 | 5 / 9 | 100 % | 2 / 5 | pass |
| lanes2, seed 5 | 7, 4, 6, 8, 8, 7 | 6 / 12 | 88 % | 4 / 8 | pass |
| lanes4 | 8, 4, 10, 7, 4, 7 | 7 / 8 | 81 % | 4 / 6 | pass |
| lanes4, seed 2 | 9, 3, 5, 7, 10, 6 | 11 / 9 | 75 % | 6 / 4 | pass |
| lanes4, seed 3 | 14, 5, 6, 4, 3, 8 | 9 / 12 | 94 % | 6 / 7 | pass |
| lanes4, seed 4 | 6, 2, 6, 8, 7, 11 | 11 / 7 | 81 % | 6 / 4 | pass |
| lanes4, seed 5 | 13, 3, 4, 6, 11, 3 | 11 / 8 | 62 % | 4 / 5 | pass |

Every run injects every fault kind (lane cut with 2 and 4 lanes) and delivers packets of every length class on every
VC in both directions (`CovFault`, `CovPkt`: 100 %). The line fault coverage of one lane is 3 of 4 bins (no lane cut
with one lane); the union of the five seeds covers every line fault kind on every lane (2 lanes: 8 of 8 bins,
4 lanes: 16 of 16).

Functional coverage of the traffic (TC-CORE-17, all configurations): every length class on every VC in both
directions (`CovPkt`, 32 of 32 bins) and broadcast messages with and without DELAYED flag in both directions
(`CovBc`, 4 of 4 bins).

PRBS test (TC-CORE-18, all configurations): the checkers of B lock on every lane, no error, the forced error of A is
counted once at B on lane 0, the PRBS-7 checker on the PRBS-31 pattern counts errors. Without the forced error in the
adapter model the test fails (mutation check).

Restart of one end (TC-CORE-19, all configurations): after the power-on reset of B, the Interface Reset of B and
the power-on reset of A the other end reports Far-End Link Reset, the link initialises again and the traffic is
delivered. Without the fix of the lane manager (section 2) the link stays down after the Interface Reset of B in all
configurations (mutation check).

The campaign found three design defects (section 2): words lost in the Multi-Lane distributor in Not Ready, silent
corruption by double errors in the row crossings, and a second error recovery caused by the latency of the receive
error state machine of the Data Link layer.

## 2. Summary

All test cases pass and cover every requirement of the specification.

Defects found during verification:

| Finding | Fix |
| --- | --- |
| Simulation of two cores with the AMD transceiver model, one lane (2026-10-16): after the start both ends reported a sequence error (DL_ERRORS bit 3), all traffic was delivered. The Data Link layer held its link reset as a level while the transmitters were not ready, and the pulse crossing repeated it; the last pulse reached the Multi-Lane layer a few cycles after the Data Link layer had left Near-End Reset and discarded the first two rows (an idle frame word and the first FCT), which the single-lane bypass had taken into the column encoder although the lane was not Active. The far end received the second FCT first and requested a retransmission. Reproduced in GHDL with CoreClk at the frequency of LaneClk (TC-CORE-21, TC-CORE-26) | The crossing receives only the entry into the link reset, the lanes get the level from their hold (CORE-PL-06, TC-CORE-27); the Multi-Lane layer takes rows only while lane 0 is Active in the bypass (ML-BP-04, TC-ML-24, TC-ML-49); configuration `eqclk` |
| Generic ranges (2026-10-15): with more than one lane and an input VC buffer of one flow control unit (`VcInDepth_g` = 64 x `NumLanes_g`, for example the default 256 with four lanes), the traffic of TC-CORE-02 stopped for good. A beat of the input VC buffer is offered when N words are available or one of them ends a packet, so up to N - 1 words of a packet wait for the next words. The FCT counter frees one block per 64 words read and requests an FCT at M free blocks; with M blocks in the buffer, one waiting word keeps the counter at M - 1, no FCT is sent, the far end sends nothing more and the word waits for good. With one lane a beat is one word and nothing waits; with two flow control units the counter reaches M as soon as the credit of the far end is used up. All earlier versions are affected; the hardware builds use 256 x `NumLanes_g` and are not | The elaboration rejects input VC buffers below 128 x `NumLanes_g` words with several lanes (DL-VI-05); the logic is unchanged. Shown with temporary configurations: 2 lanes with 128 words and 4 lanes with 256 words stop, 1 lane with 64 words and two flow control units with 30, 50 and 95 % ready at the receiver pass |
| Testbench: `CoreClkFreq_g` kept its default of 200 MHz while the harness generated 166.7 MHz, so the scrubbing interval of the error recovery buffer did not match its clock | The harness derives `LaneClkFreq_g` and `CoreClkFreq_g` from the generated periods (CORE-CK-02) |
| After a Link Reset command the far end did not reset: the lane becomes active a few cycles after the capability event, and the lane active level crossed to the core clock faster than the event, so the link reset state machine saw an active lane | The Multi-Lane layer qualifies the capability event with "no lane active" at the time of the event (`Dl_FarCapabilityIdle`), and both cross in one FIFO word |
| TC-CORE-07 (2 and 4 lanes): with the SKIP request of the Multi-Lane layer the own SKIP counter of the Lane layer kept counting and left its range (GHDL bound check) after 5000 words in Active | The own counter only counts without `SkipExternal_g` |
| Testbench, 2 and 4 lanes: the generators of the VCs assigned their slice of the beat signal with a variable index, so every generator drove the whole signal (several drivers, X at the core input) | Beat built in a variable, the static slice of the VC assigned once |
| TC-CORE-13 (2 and 4 lanes): a word slip on one line corrupted packets in the other direction without any error (scoreboard mismatch): the end with the slip entered Not Ready and its distributor discarded held words of a frame that the far end kept | Multi-Lane layer: held words kept in Not Ready (ML-DS-12) |
| TC-CORE-13: a double error in a row crossing corrupted a word after the CRC-16 check (receive) or before the CRC-16 computation (transmit): silent corruption | Receive: the row becomes one RXERR; transmit: poisoned row, CRC-16 of the frame inverted (CORE-ED-02) |
| TC-CORE-13 (testbench): with about 6 % link load most line faults hit idle frames, one end saw no retry | Traffic raised to about 60 % of the link capacity |
| TC-CORE-14: a link reset during traffic caused a second link reset with the protocol error flag: ACKs of the far end for frames that the near end had discarded still arrived before the lanes went down | Data Link layer: received words pass to the receive checks only in Link Initialised (DL-LR-05) |
| TC-CORE-14 (testbench): the injected error waits for the next word written into the channel; without traffic after the injection the error was never read | Traffic after the injection; the test waits for the DED flag and for the far-end link reset before the traffic that recognises the lost packets |
| Code coverage after the register stages of the input VC buffers: with random traffic the DED of the input VC buffers no longer hit a beat that ends its packet | TC-CORE-14 injects the errors of the input VC buffers with no traffic in flight, into an early word of a 1024-byte packet and into a packet of one word per VC (packet length range `MinLen` to `MaxLen` in the testbench); at least two packets per VC end with EEP |
| Functional coverage (testbench): the campaign sent packets of at most 64 bytes, so no fault hit a packet of several data frames | Campaign packets cycle through all length classes up to 1024 bytes at the same load; 15 runs pass |
| TC-CORE-13 (2 lanes, seed 2): a packet delivered twice after a lane slip: two out-of-sequence words in consecutive cycles were checked against an old Receive Polarity Flag and started a second error recovery | Data Link layer: receive error state machine updated in the cycle of the word (DL-RE-01, TC-DL-26) |
| TC-CORE-03 (4 lanes) after the input stage of the column encoder: no retry at A. The 20 packets per VC were sent within about 200 cycles, while the bit errors are spread over 2740 cycles; with the one cycle of additional transmit latency the only bit errors of the A to B direction that had hit a data frame hit idle words, which with several lanes are lane slips with a realignment and no retry (Multi-Lane report) | Testbench: 200 packets per VC and end, so that the traffic lasts over most of the bit errors with every lane configuration |
| TC-CORE-19 (all configurations, found while testing the transmitter ready input): after a complete restart of one end while the other end was in Link Initialised, the link stayed down for good. The end in Link Initialised received the far-end capability with INIT3LinkResetFlag set, but the Multi-Lane layer reported that a lane was Active: the lane enters Active in the same cycle in which it passes the capability when it has already sent its three INIT3 words, and the lane states of that cycle were used. The end therefore did not reset, and the restarted end waited in Check Far-End Reset | The Multi-Lane layer uses the lane states of the cycle before the capability event: the capability belongs to the Connected state (ECSS 5.7.9 Near-End Reset a.3, ML-LM-14, TC-ML-48) |
| TC-CORE-14 with the packet ports of the VCs: a DED in the first beat of a packet in the input VC buffer leaves a packet without data (the EEP that replaces the beat); the Network interface discards it as a packet of zero length, so it no longer arrives as a packet ended with EEP | The test counts the packets ended with EEP and the packets of zero length at A (NI_RX_EMPTY_COUNT); the second error (packets of one word) gives exactly one packet of zero length per VC |
| Four-lane error recovery through the adapter models with the lock time of the transceiver model (17.1 us, 2026-10-17): bit errors that formed false commas cost words at the comma realignments of one lane of A, the lane skew exceeded the alignment FIFOs, A stayed in Not Ready and the Data Link layer could send no RETRY, ACK or NACK; the traffic stopped in both directions while the link stayed initialised, only a Link Reset recovered it | Alignment watchdog of the Multi-Lane layer (ML-AL-11, `AlignTimeoutWords_g`): LaneReset of the active lanes when the alignment stays in Not Ready; TC-CORE-30 to TC-CORE-33, TC-CORE-03 with `lanes4_pin_lock16650`, `lanes4_pin_lock16830` and `lanes4_pin_lock17000` |

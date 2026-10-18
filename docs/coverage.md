# OpenFibre: Code Coverage

## 1. Method

The code coverage of the OpenFibre sources is measured with QuestaSim (Questa Pro Microchip Edition 2024.3) over the
complete regression of `run.py`, the same test set that GHDL runs in CI:

```shell
python run.py --questa --coverage -p 1
```

The sources of `hdl/<module>/src` are compiled with `+cover=sbcef`: statements, branches, conditions, expressions
(focused expression coverage) and state machines. Open Logic, UVVM and the testbenches are not instrumented; Open Logic
is verified by its own regression. The behavioural model of the Physical adapter (architecture `mdl` of `ofb_pa_gty`
and its package, `hdl/ofb_pa_gty/sim`) runs in the regression and is instrumented as well. The transceiver wrapper
(architecture `struct`) and the VCK190 top level need the transceiver model and run in the AMD Vivado simulator
(`tools/run_xsim.py`); they are not part of this measurement. QuestaSim runs at a time resolution of 1 fs, as GHDL.
`run.py` merges the coverage of all tests into `coverage/coverage.ucdb` and writes the reports
`coverage/coverage_report.txt` (details per instance) and `coverage/coverage_byfile.txt`; a design unit is covered
when any of its instances in any test covers it.

Closure rules:

- Statements, branches, state machine states and transitions: every item is covered by a test or listed with its
  justification in section 4.
- Conditions and expressions: reported, not a closure criterion. Focused expression coverage requires every input
  term to change the result while the other terms do not mask it; many combinations cannot occur by construction (for
  example an EDAC flag of a FIFO is only defined together with its valid signal) or need two resets at the same time.
  Their misses were reviewed for untested behaviour; the behaviour behind them is covered by the branch and statement
  coverage.
- `-- coverage off` / `-- coverage on` are used for two kinds of code only: the `when others` branch of a state machine
  whose enumerated state type lists every state, and selections on a generate constant (the write domain of an EDAC
  channel, the bank of an input VC buffer), of which one branch cannot exist in a given instance.

## 2. Result

Runs on 2026-10-18 on the main branch with the behavioural model of the Physical adapter, the alignment watchdog of
the Multi-Lane layer and the MIB without the redundant transmitter register:

- Without coverage: the full regression at commit 9dff622 at a time resolution of 1 fs, 396 tests, all passed. The
  tree of 9dff622 is the tree of main 77f4eea (71b4665, `git rev-parse 9dff622^{tree}` and
  `git rev-parse 77f4eea^{tree}`).
- With coverage: the full regression at commit b6242a2 at the resolution of 1 ps that VUnit sets for QuestaSim, 396
  tests, 395 passed.
  `ofb_pa_gty_model_core_tb.lanes4` failed its check of the clock corrections: the reference clock of B, 200 ppm
  slower than that of A, toggles after 3200.64 ps, which 1 ps truncates to 3200 ps, so both ends ran at the same
  frequency. Since 9dff622 `run.py` runs QuestaSim at 1 fs. The 50 tests whose clocks have fractions of a picosecond
  ran again with coverage at 9dff622 (1 fs), all passed: `ofb_pa_gty_model_tb` 40, `ofb_pa_gty_model_core_tb` 6,
  `ofb_cc_pulse_tb` configuration `near` 4. The design sources are identical in both commits
  (`git diff --stat b6242a2 9dff622 -- 'hdl/*/src'` is empty).
- The coverage below merges 396 per-test databases (`vcover merge`). From b6242a2 (1 ps), the 346 tests whose time
  values are whole picoseconds: `ofb_core_tb` 150, `ofb_ml_link_tb` 36, `ofb_ni_tb` 28, `ofb_dl_row_tb` 22,
  `ofb_lane_init_tb` 14, `ofb_lane_tb` 14, `ofb_mib_tb` 11, `ofb_ml_codec_tb` 10, `ofb_cc_pulse_tb` 8 (configurations
  `in_fast` and `out_fast`), `ofb_lane_rx_tb` 8, `ofb_dl_mac_tb` 7, `ofb_dl_tb` 7, `ofb_ml_align_tb` 7,
  `ofb_multilane_tb` 6, `ofb_pkg_tb` 6, `ofb_lane_tx_tb` 4, `ofb_tb_8b10b_tb` 4, `ofb_core_cc_tb` 3,
  `ofb_ml_lane_mgr_tb` 1. From 9dff622 (1 fs), the 50 tests above. The merged coverage equals the coverage of all
  396 tests of b6242a2 in every file and metric.

Numbers are covered/total bins per file; bold marks a metric with misses.

| File | Statements | Branches | FSM States | FSM Transitions | Conditions | Expressions |
| --- | --- | --- | --- | --- | --- | --- |
| `ofb_core/src/ofb_core.vhd` | 3/3 |  |  |  |  |  |
| `ofb_core/src/ofb_core_cc.vhd` | 44/44 | 7/7 |  |  |  | **18/28** |
| `ofb_dl/src/ofb_dl.vhd` | 51/51 | 19/19 |  |  | **6/7** | **15/19** |
| `ofb_dl/src/ofb_dl_bc_in.vhd` | 12/12 |  |  |  |  | **9/11** |
| `ofb_dl/src/ofb_dl_bc_out.vhd` | 23/23 | 18/18 |  |  | **8/9** | **4/6** |
| `ofb_dl/src/ofb_dl_erb.vhd` | 151/151 | 67/67 | 3/3 | 4/4 | **35/37** | **23/41** |
| `ofb_dl/src/ofb_dl_link_reset.vhd` | 20/20 | 30/30 | 4/4 | 8/8 | **10/12** | 2/2 |
| `ofb_dl/src/ofb_dl_mac.vhd` | 60/60 | 34/34 |  |  | **13/16** | 2/2 |
| `ofb_dl/src/ofb_dl_pkg.vhd` | **40/41** | 21/21 |  |  | **8/9** |  |
| `ofb_dl/src/ofb_dl_qos_regs.vhd` | 19/19 | 15/15 |  |  | **3/4** |  |
| `ofb_dl/src/ofb_dl_rx_buf.vhd` | 27/27 | 15/15 |  |  | 9/9 | 14/14 |
| `ofb_dl/src/ofb_dl_rx_check.vhd` | 168/168 | 88/88 |  |  | 16/16 | 7/7 |
| `ofb_dl/src/ofb_dl_rx_err.vhd` | 9/9 | 23/23 | 4/4 | 8/8 | 4/4 |  |
| `ofb_dl/src/ofb_dl_tx_admit.vhd` | 71/71 | **31/32** |  |  | **17/19** | 4/4 |
| `ofb_dl/src/ofb_dl_tx_frame.vhd` | 123/123 | 39/39 |  |  | **18/19** | 6/6 |
| `ofb_dl/src/ofb_dl_vc_in.vhd` | **170/171** | **63/64** |  |  | **6/11** | **47/50** |
| `ofb_dl/src/ofb_dl_vc_out.vhd` | 112/112 | **64/65** |  |  | **35/37** | **21/25** |
| `ofb_lane/src/ofb_lane.vhd` | 9/9 |  |  |  |  | 2/2 |
| `ofb_lane/src/ofb_lane_init.vhd` | 179/179 | 124/124 | 10/10 | 20/20 | **53/60** | 10/10 |
| `ofb_lane/src/ofb_lane_loopback.vhd` | 17/17 | 6/6 |  |  |  |  |
| `ofb_lane/src/ofb_lane_rx.vhd` | 186/186 | 73/73 |  |  | 18/18 | 6/6 |
| `ofb_lane/src/ofb_lane_tx.vhd` | 56/56 | 24/24 |  |  | 2/2 |  |
| `ofb_mib/src/ofb_mib.vhd` | 299/299 | 153/153 |  |  | **28/32** | **10/15** |
| `ofb_multilane/src/ofb_ml_align.vhd` | 199/199 | **120/121** | 3/3 | 6/6 | **45/48** | 2/2 |
| `ofb_multilane/src/ofb_ml_col_dec.vhd` | 45/45 | 19/19 |  |  | 3/3 |  |
| `ofb_multilane/src/ofb_ml_col_enc.vhd` | 60/60 | 23/23 |  |  | 4/4 | **6/7** |
| `ofb_multilane/src/ofb_ml_lane_mgr.vhd` | 110/110 | 56/56 |  |  | **24/30** | **5/6** |
| `ofb_multilane/src/ofb_ml_pkg.vhd` | 43/43 | **32/33** |  |  | 8/8 |  |
| `ofb_multilane/src/ofb_ml_rx.vhd` | 79/79 | **39/41** | 5/5 | 16/16 | 5/5 |  |
| `ofb_multilane/src/ofb_ml_tx.vhd` | 102/102 | 48/48 |  |  | 19/19 | 5/5 |
| `ofb_multilane/src/ofb_multilane.vhd` | 38/38 | 10/10 |  |  | 2/2 | 7/7 |
| `ofb_ni/src/ofb_ni.vhd` | 12/12 |  |  |  |  |  |
| `ofb_ni/src/ofb_ni_vc_rx.vhd` | 176/176 | 66/66 |  |  | **21/22** | 13/13 |
| `ofb_ni/src/ofb_ni_vc_tx.vhd` | 59/59 | 31/31 |  |  | 11/11 | **5/6** |
| `ofb_pa_gty/sim/ofb_pa_gty_model.vhd` | **237/239** | **139/147** |  |  | **37/40** | **11/14** |
| `ofb_pa_gty/sim/ofb_pa_model_pkg.vhd` | 11/11 | **1/2** |  |  |  |  |
| `ofb_pkg/src/ofb_cc_pulse.vhd` | 19/19 | 8/8 |  |  |  |  |
| `ofb_pkg/src/ofb_pkg.vhd` | 55/55 | 10/10 |  |  | **1/2** |  |
| Total | 3094/3098 (99.9 %) | 1516/1532 (99.0 %) | 29/29 (100.0 %) | 62/62 (100.0 %) | 469/515 (91.1 %) | 254/308 (82.5 %) |

## 3. Gaps found and closed

The first run (88.8 % over all metrics and files, 97.5 % of the statements, 94.9 % of the branches, 82.3 % of the state
machine transitions) showed behaviour that the requirements ask for but no test exercised. The tests below close these
gaps; all of them passed without a change of the design.

| Gap | Test |
| --- | --- |
| Lane initialisation: exits of Wait, Started, InvertRxPolarity and Connecting on LaneReset, NoSignal, timeout and three STANDBY or LOST_SIGNAL words; polarity inversion detected from iINIT2 | TC-LN-33 |
| Lane receiver: realignment while the synchronisation state machine is in CheckSync | TC-LN-41 (extended) |
| Data Link receiver: CRC-8 errors of SIF, FULL, ACK and NACK; SIF inside a data frame, EDF inside an idle frame | TC-DL-27 |
| Receive error state machine: Error Positive to Error Negative on a sequence error with the expected polarity | TC-DL-12 (extended) |
| Link reset state machine: Interface Reset in Near-End Reset, Check Far-End Reset and Link Initialised; reset values of the time-slots 32 to 63 and of the idle limit after an Interface Reset | TC-DL-28 (mutation checked: an idle limit that keeps its value fails the test) |
| Error recovery buffer: all data items used by small frames | TC-DL-17 (extended) |
| Input VC buffer overflow (DL-VI-03), so far verified only by the absence of overflows; data frame for a VC that the core does not implement (DL-WI-02 clarified); EEP after a link reset held until the user is ready | TC-DL-29 |
| Continuous mode: flush of the output VC buffer while a segment is copied into the error recovery buffer | TC-DL-30 |
| MIB: CRC-8, frame and sequence counters, write clears of all counters, W1C of the overflow, bandwidth and lane event flags, idle limit and time-slots 63 to 32, undefined and read-only registers, SEC interrupt | TC-MG-08 |
| MIB: saturation of the event counters (MG-ST-02) | TC-MG-09 |
| Multi-Lane receiver: packing after frame structure errors (five transitions of the frame state) | TC-ML-47 |
| Lane alignment: incorrect ALIGN on an active lane that is not data-receiving | TC-ML-42 (extended) |
| Link reset state machine: transmitters not ready while the link waits in Check Far-End Reset (condition of `ofb_dl_link_reset.vhd` line 86) | TC-CORE-29 (mutation checked: without the condition the test fails) |
| MIB: TX_LOST cleared while the transmitters stay not ready, not set again (expression of `ofb_mib.vhd` line 365) | TC-CORE-29 |

After the register stages of the input VC buffers and the latch-free pulse crossing, two branches that earlier tests
had reached only by their timing were no longer covered. Deterministic tests replace the coincidence:

| Gap | Test |
| --- | --- |
| Broadcast message that waits while no lane is active, sent with the LATE flag (DL-BO-03) | TC-DL-06 (extended: messages submitted while the lanes of both ends are not active) |
| Input VC buffer: DED in a beat that ends its packet (nothing to discard), and a rest of several beats discarded after a DED | TC-CORE-14 (extended: two errors injected with no traffic in flight, into an early word of a 1024-byte packet and into a packet of one word) |
| Receive error state machine: Error Negative to Error Positive on a sequence error with the expected polarity (reached only by chance in TC-CORE-03, whose bit errors hit other frames after the timing changes of the second build) | TC-DL-12 (extended, mutation checked: a state machine that stays in Error Negative fails the test) |

The PRBS test registers of the MIB (MG-5) added two branches that no test can reach: the saturation of the 48-bit
word counter (2^48 words) and the read of an undefined lane register (every word of the lane stride is now a
register). The design closes both:

| Gap | Change |
| --- | --- |
| Saturation of the PRBS counters (32 and 48 bits) | One saturating increment for all counters of the MIB (`satInc`), covered by TC-MG-09 |
| Read decode of the lane registers: no undefined offset left | Last branch of the decode is the PRBS word counter (as in the VC decode); TC-MG-08 reads and writes the registers of a lane beyond `NumLanes_g` instead |

## 4. Remaining misses

In the design sources, seven branches and two statements remain uncovered. None of them is behaviour that a
requirement asks for; each is defensive, constant by construction or not executed as a separate statement by the
simulator:

| Location | Item not covered | Justification |
| --- | --- | --- |
| `ofb_dl/src/ofb_dl_pkg.vhd:235` | Statement: body of `segmentRows` | The call on line 377 of `ofb_dl.vhd` is covered; QuestaSim evaluates the call without executing the body as a statement (also with `vopt -O0`). The result, the segment length of 64 x N words, is checked by TC-CORE-02 and TC-CORE-08. |
| `ofb_dl/src/ofb_dl_tx_admit.vhd:166` | Branch: segment of zero rows | Defensive. A segment is taken only when the output VC buffer is ready (credit and data of at least one row, `ofb_dl_vc_out.vhd` line 433) and the error recovery buffer has free rows (line 141). |
| `ofb_dl/src/ofb_dl_vc_in.vhd:554`, statement 555 | Branch: FCT request and FCT sent in the same cycle | Coincidence of two independent events that the testbenches do not force; the update is the sum of the single-event branches on lines 550 and 552, which are covered (TC-DL-20 checks the FCT count). |
| `ofb_dl/src/ofb_dl_vc_out.vhd:365` | Branch: credit below one row when a row is read | Defensive. A segment never exceeds the credit (ECSS 5.7.3.1f, line 431), checked by TC-DL-19. |
| `ofb_multilane/src/ofb_ml_align.vhd:350` | Branch: ALIGN held in a lane while the state machine is in Not Ready after an alignment | The Misaligned condition of this case is covered; the branch only suppresses the output error, and Not Ready passes no words. |
| `ofb_multilane/src/ofb_ml_pkg.vhd:111` | Branch: K28.7 followed by a K character other than K27.7 | Such words are lane control words, which the Lane layer filters (LN-RX-04, TC-LN-44); they do not reach the Multi-Lane layer. |
| `ofb_multilane/src/ofb_ml_rx.vhd:112` | Branch: output queue full | Defensive, guarded by an assertion of severity error that the regression never raised. |
| `ofb_multilane/src/ofb_ml_rx.vhd:195` | Branch: shift of the waiting words beyond the accumulator | Constant: `i < NumLanes_g` and `AccSize_c = 2 x NumLanes_g`, so the condition is always true; the guard keeps the index in range for elaboration. |

In the behavioural model of the Physical adapter, nine branches and two statements remain uncovered. The model is
a verification model; none of the items is behaviour that the model description or a test relies on:

| Location | Item not covered | Justification |
| --- | --- | --- |
| `ofb_pa_gty/sim/ofb_pa_gty_model.vhd:223` | Branch: the reset sequence starts while the stretched reset is already released | The process starts at time 0 and after every sequence when the stretched reset rises, so the reset is always active when it reaches this line. |
| `ofb_pa_gty/sim/ofb_pa_gty_model.vhd:231`, `242` | Branches: no reset done of the previous start, TX ready already due when the wait begins | Constant by construction: `TxDoneStale` and `ClkDelay` are positive, so the reset done of the previous start lasts beyond the start of the sequence (line 228), and `ClkDelay` < `TxReadyDelay` (model description, section 3). |
| `ofb_pa_gty/sim/ofb_pa_gty_model.vhd:236`, `240`, `245`, `248` | Branches: a reset of the adapter during the reset sequence (while the reset done of the previous start shows, before `LaneClk` starts, before TX ready, before RX ready) | The testbenches reset the adapter at power-up and in operation, after RX ready (TC-PA-10, TC-PA-02). The sequence then starts again from the top of the process. |
| `ofb_pa_gty/sim/ofb_pa_gty_model.vhd:390`, statements 391 and 392 | Branch: reset of the PRBS generator inside the `LaneClk` branch of the transmitter | Not reachable: `LaneClk` stops in the delta cycle in which the stretched reset rises, and the transmitter takes the reset through TX ready (line 322). The PRBS generator keeps its state over a reset; its checker synchronises itself (TC-PA-17). |
| `ofb_pa_gty/sim/ofb_pa_model_pkg.vhd:149` | Branch: word pushed into a full receive buffer | Defensive. The receiver checks the level before it pushes and counts the lost word (`ofb_pa_gty_model.vhd` line 544, TC-PA-18). |

The condition and expression metrics are reported, not closed. The redundant register `TxSeen` of the MIB, whose term
of the TX_LOST expression could not be reached, has been removed; the expression of `ofb_mib.vhd` is the fall of
`Phy_TxReady` alone.

## 5. Reproduction

```shell
python run.py --questa --coverage -p 1
vcover report -du=* -details -zeros -code sbf coverage/coverage.ucdb
```

The second command lists the statements, branches and state machine items that are not covered, per design unit.

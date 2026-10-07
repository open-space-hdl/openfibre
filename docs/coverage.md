# OpenFibre: Code Coverage

## 1. Method

The code coverage of the OpenFibre sources is measured with QuestaSim (Questa Pro Microchip Edition 2024.3) over the
complete regression of `run.py`, the same test set that GHDL runs in CI:

```shell
python run.py --questa --coverage -p 1
```

The sources of `hdl/<module>/src` are compiled with `+cover=sbcef`: statements, branches, conditions, expressions
(focused expression coverage) and state machines. Open Logic, UVVM and the testbenches are not instrumented; Open Logic
is verified by its own regression. The transceiver wrapper `ofb_pa_gty` and the VCK190 top level need the transceiver
model and run in the AMD Vivado simulator (`tools/run_xsim.py`); they are not part of this measurement. `run.py` merges
the coverage of all tests into `coverage/coverage.ucdb` and writes the reports `coverage/coverage_report.txt` (details
per instance) and `coverage/coverage_byfile.txt`; a design unit is covered when any of its instances in any test
covers it.

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

Run on 2026-10-07: 209 tests, all passed, 51 minutes with one simulator licence. Numbers are covered/total bins per
file; bold marks a metric with misses.

| File | Statements | Branches | FSM States | FSM Transitions | Conditions | Expressions |
| --- | --- | --- | --- | --- | --- | --- |
| `ofb_core/src/ofb_core.vhd` | 1/1 |  |  |  |  |  |
| `ofb_core/src/ofb_core_cc.vhd` | 38/38 | 4/4 |  |  |  | **14/24** |
| `ofb_dl/src/ofb_dl.vhd` | 51/51 | 19/19 |  |  | **6/7** | **15/19** |
| `ofb_dl/src/ofb_dl_bc_in.vhd` | 12/12 |  |  |  |  | **9/11** |
| `ofb_dl/src/ofb_dl_bc_out.vhd` | 23/23 | 18/18 |  |  | **8/9** | **4/6** |
| `ofb_dl/src/ofb_dl_erb.vhd` | 151/151 | 67/67 | 3/3 | 4/4 | **35/37** | **22/41** |
| `ofb_dl/src/ofb_dl_link_reset.vhd` | 20/20 | 29/29 | 4/4 | 8/8 | **8/10** | 2/2 |
| `ofb_dl/src/ofb_dl_mac.vhd` | 60/60 | 34/34 |  |  | **13/16** | 2/2 |
| `ofb_dl/src/ofb_dl_pkg.vhd` | **40/41** | 21/21 |  |  | **8/9** |  |
| `ofb_dl/src/ofb_dl_qos_regs.vhd` | 19/19 | 15/15 |  |  | **3/4** |  |
| `ofb_dl/src/ofb_dl_rx_buf.vhd` | 22/22 | 12/12 |  |  | 6/6 | **13/14** |
| `ofb_dl/src/ofb_dl_rx_check.vhd` | 168/168 | 88/88 |  |  | 16/16 | **6/7** |
| `ofb_dl/src/ofb_dl_rx_err.vhd` | 9/9 | 23/23 | 4/4 | 8/8 | 4/4 |  |
| `ofb_dl/src/ofb_dl_tx_admit.vhd` | 71/71 | **31/32** |  |  | **17/19** | **3/4** |
| `ofb_dl/src/ofb_dl_tx_frame.vhd` | 123/123 | 39/39 |  |  | **18/19** | **5/6** |
| `ofb_dl/src/ofb_dl_vc_in.vhd` | **118/119** | **75/76** |  |  | **16/23** | **4/8** |
| `ofb_dl/src/ofb_dl_vc_out.vhd` | 100/100 | **56/57** |  |  | **26/30** | **16/23** |
| `ofb_lane/src/ofb_lane.vhd` | 9/9 |  |  |  |  | 2/2 |
| `ofb_lane/src/ofb_lane_init.vhd` | 179/179 | 124/124 | 10/10 | 20/20 | **52/60** | 10/10 |
| `ofb_lane/src/ofb_lane_loopback.vhd` | 17/17 | 6/6 |  |  |  |  |
| `ofb_lane/src/ofb_lane_rx.vhd` | 186/186 | 73/73 |  |  | **16/18** | 6/6 |
| `ofb_lane/src/ofb_lane_tx.vhd` | 56/56 | 24/24 |  |  | 2/2 |  |
| `ofb_mib/src/ofb_mib.vhd` | 268/268 | 134/134 |  |  | **26/30** | **7/12** |
| `ofb_multilane/src/ofb_ml_align.vhd` | 181/181 | **111/112** | 3/3 | 6/6 | **39/42** | 2/2 |
| `ofb_multilane/src/ofb_ml_col_dec.vhd` | 45/45 | 19/19 |  |  | 3/3 |  |
| `ofb_multilane/src/ofb_ml_col_enc.vhd` | 55/55 | 23/23 |  |  | 4/4 | **4/5** |
| `ofb_multilane/src/ofb_ml_lane_mgr.vhd` | 110/110 | 56/56 |  |  | **24/30** | **2/3** |
| `ofb_multilane/src/ofb_ml_pkg.vhd` | 43/43 | **32/33** |  |  | 8/8 |  |
| `ofb_multilane/src/ofb_ml_rx.vhd` | 79/79 | **39/41** | 5/5 | 16/16 | 5/5 |  |
| `ofb_multilane/src/ofb_ml_tx.vhd` | 102/102 | 48/48 |  |  | 17/17 | 5/5 |
| `ofb_multilane/src/ofb_multilane.vhd` | 36/36 | 10/10 |  |  | 2/2 | 3/3 |
| `ofb_ni/src/ofb_ni.vhd` | 16/16 |  |  |  |  |  |
| `ofb_ni/src/ofb_ni_vc.vhd` | 55/55 | 31/31 |  |  | **16/20** | 2/2 |
| `ofb_pkg/src/ofb_cc_pulse.vhd` | 19/19 | 8/8 |  |  |  |  |
| `ofb_pkg/src/ofb_pkg.vhd` | 55/55 | 10/10 |  |  | **1/2** |  |
| Total | 2537/2539 (99.9 %) | 1279/1286 (99.5 %) | 29/29 (100.0 %) | 62/62 (100.0 %) | 399/452 (88.3 %) | 158/217 (72.8 %) |

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

After the register stages of the input VC buffers and the latch-free pulse crossing, two branches that earlier tests
had reached only by their timing were no longer covered. Deterministic tests replace the coincidence:

| Gap | Test |
| --- | --- |
| Broadcast message that waits while no lane is active, sent with the LATE flag (DL-BO-03) | TC-DL-06 (extended: messages submitted while the lanes of both ends are not active) |
| Input VC buffer: DED in a beat that ends its packet (nothing to discard), and a rest of several beats discarded after a DED | TC-CORE-14 (extended: two errors injected with no traffic in flight, into an early word of a 1024-byte packet and into a packet of one word) |

The PRBS test registers of the MIB (MG-5) added two branches that no test can reach: the saturation of the 48-bit
word counter (2^48 words) and the read of an undefined lane register (every word of the lane stride is now a
register). The design closes both:

| Gap | Change |
| --- | --- |
| Saturation of the PRBS counters (32 and 48 bits) | One saturating increment for all counters of the MIB (`satInc`), covered by TC-MG-09 |
| Read decode of the lane registers: no undefined offset left | Last branch of the decode is the PRBS word counter (as in the VC decode); TC-MG-08 reads and writes the registers of a lane beyond `NumLanes_g` instead |

## 4. Remaining misses

Seven branches and two statements remain uncovered. None of them is behaviour that a requirement asks for; each is
defensive, constant by construction or not executed as a separate statement by the simulator:

| Location | Item not covered | Justification |
| --- | --- | --- |
| `ofb_dl/src/ofb_dl_pkg.vhd:235` | Statement: body of `segmentRows` | The call on line 373 of `ofb_dl.vhd` is covered; QuestaSim evaluates the call without executing the body as a statement (also with `vopt -O0`). The result, the segment length of 64 x N words, is checked by TC-CORE-02 and TC-CORE-08. |
| `ofb_dl/src/ofb_dl_tx_admit.vhd:166` | Branch: segment of zero rows | Defensive. A segment is taken only when the output VC buffer is ready (credit and data of at least one row, `ofb_dl_vc_out.vhd` line 383) and the error recovery buffer has free rows (line 141). |
| `ofb_dl/src/ofb_dl_vc_in.vhd:445`, statement 446 | Branch: FCT request and FCT sent in the same cycle | Coincidence of two independent events that the testbenches do not force; the update is the sum of the single-event branches on lines 441 and 443, which are covered (TC-DL-20 checks the FCT count). |
| `ofb_dl/src/ofb_dl_vc_out.vhd:339` | Branch: credit below one row when a row is read | Defensive. A segment never exceeds the credit (ECSS 5.7.3.1f, line 382), checked by TC-DL-19. |
| `ofb_multilane/src/ofb_ml_align.vhd:336` | Branch: ALIGN held in a lane while the state machine is in Not Ready after an alignment | The Misaligned condition of this case is covered; the branch only suppresses the output error, and Not Ready passes no words. |
| `ofb_multilane/src/ofb_ml_pkg.vhd:111` | Branch: K28.7 followed by a K character other than K27.7 | Such words are lane control words, which the Lane layer filters (LN-RX-04, TC-LN-44); they do not reach the Multi-Lane layer. |
| `ofb_multilane/src/ofb_ml_rx.vhd:112` | Branch: output queue full | Defensive, guarded by an assertion of severity error that the regression never raised. |
| `ofb_multilane/src/ofb_ml_rx.vhd:195` | Branch: shift of the waiting words beyond the accumulator | Constant: `i < NumLanes_g` and `AccSize_c = 2 x NumLanes_g`, so the condition is always true; the guard keeps the index in range for elaboration. |

## 5. Reproduction

```shell
python run.py --questa --coverage -p 1
vcover report -du=* -details -zeros -code sbf coverage/coverage.ucdb
```

The second command lists the statements, branches and state machine items that are not covered, per design unit.

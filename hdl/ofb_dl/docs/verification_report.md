# ofb_dl: Verification Report

## 1. Test results

Run on 2026-10-06 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*ofb_dl*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `ofb_dl_tb` (layer, two complete ends) | 7 | 7 |
| `ofb_dl_row_tb` (row level) | 21 | 21 |
| `ofb_dl_mac_tb` (medium access controller) | 7 | 7 |

Full regression of the repository: 205 of 205 tests pass (after the register stages of the input VC buffers and the
latch-free pulse crossing; 193 of 193 in phase 5, after the code coverage closure;
phase 4: rows of several words, verified in the core
testbench with 2 and 4 lanes, plan section 3.5). VSG reports no errors and no warnings.

Error and recovery counters of the layer tests (both ends):

| Test | RETRY sent | Sequence errors | Result |
| --- | --- | --- | --- |
| `test_error_recovery` (30 bit errors per direction) | 8 per end | 2 per end | All packets and broadcast messages delivered once and in order, no link reset |
| `test_lane_loss` (5 us cut during traffic) | 1 per end | 3 per end | All packets delivered, no link reset |

## 2. Summary

All 34 test cases pass and cover the requirements of the specification (verification plan, section 4).

Defects found and fixed during verification:

| Finding | Fix |
| --- | --- |
| `olo_ft_fifo_packet` does not support the feature set DROP_ONLY (Last outside the ECC code word) | Frame buffer uses DROP_SKIP_ONLY |
| Counters of the error recovery buffer left their range in delta cycles before the admission signals settled (GHDL bound check) | Range guards on every increment |
| The input VC buffer inserted one EEP per cycle of the buffer reset | One EEP per link reset |
| The end-of-packet count of the output VC buffer crossed faster than the buffer level: packets were split into several data frames | Count delayed behind the level |
| Testbench: delivery check before the generators had started; lane loss test cut the lane after the traffic had ended | Testbench timing |
| TC-CORE-14 (core): words of the far end that arrived after a near-end link reset (an ACK of a discarded frame) caused a protocol error and a second link reset | Received words are checked only in Link Initialised (DL-LR-05) |
| TC-CORE-13 (fault injection campaign of the core, 2 lanes): after a lane slip, an EDF and a SIF out of sequence arrived in consecutive cycles and were both checked against the old Receive Polarity Flag (the receive error state machine changed two cycles after the word). The second moved Error Negative on to Error Positive; the NACK with the other polarity started a second error recovery, and a data frame already accepted was resent with a new sequence number and delivered twice | The events of the word taken go to DR-3 without register, the next word is checked against the updated flag (DL-RE-01, TC-DL-26, mutation checked: the old latency fails TC-DL-26) |
| Found with the MIB testbench: `olo_ft_cc_pulse` stretches every output pulse to two cycles, so the input VC buffer requested two FCTs per 64 words read (credit for more words than the buffer holds) | `ofb_cc_pulse` with an edge detector; TC-DL-20 checks the FCT count (mutation checked: 6 instead of 4 FCTs without the fix) |
| First build of the VCK190 design: every failing timing path (up to 2.673 ns at 156.25 MHz, 18 to 25 logic levels) started at the bank RAMs of the input VC buffers: RAM, SECDED decoder, rotation of the banks, end-of-packet search and word count, ready of the banks back into the read logic of the FIFOs | Register stage (`olo_base_pl_stage`) after every bank; the beat is formed from the registers (architecture section 3.9). The ECC events are taken at the FIFO outputs |
| `ofb_pa_gty_core_tb` and `ofb_vck190_tb` (xsim) after the register stages were added: one beat of undefined words per VC at the far end before its links started. The user clock of that end is the transmit clock of the transceiver, which starts late; the register stages had no reset before their first clock edge (their reset came only from the buffer, whose reset needs clock edges), and the beat logic took an undefined valid flag as valid | The register stages are also reset by the user reset (asserted from the start), and only a valid flag of '1' is taken; both tests pass |
| First build of the VCK190 design: the latches of `olo_ft_cc_pulse` can lose a pulse (gate and data follow the input pulse); a lost FCT block pulse of an input VC buffer leaks credit until the VC stalls | `ofb_cc_pulse` without latch (`ofb_pkg` report) |
| Second build of the VCK190 design: setup violations of up to 0.055 ns at 150 MHz (1538 endpoints, 15 to 18 logic levels), all in the user side of the input VC buffers, from `RdBank` and the bank stages through the beat formation to the reads of the bank stages and to the pipeline stage of the Network interface: the end of a beat was found by decoding the rotated 36-bit words of the banks | The end flags of every word (EOP or EEP in the word, EOP, EEP or Fill in character 3) are decoded before the bank stage and stored with the word, the beat logic works on these single bits, and the banks of the beat are marked in `BeatSel`, from which the reads of the banks follow without the word count compare (the path from the bank RAM to the stage had 2.27 ns of slack) |
| Second build of the VCK190 design: the path from the frame buffer (RAM, SECDED decoder) through the distribution to the input VC buffers and their bank selection into the input register of a bank met the lane clock with only 0.359 ns of slack (12 logic levels) | Output register in `ofb_dl_rx_buf` (one cycle more from the frame buffer to the input VC buffers) |

Phase 3 (quality of service, continuous mode): the MAC unit tests and TC-DL-21 / TC-DL-22 passed on the first run;
mutation check: with equal priorities the first frame of TC-DL-21 comes from VC 0 and the test fails as expected.

Phase 4 (rows of several words): the tests of this module (one lane) pass unchanged after the conversion to rows; the
core tests TC-CORE-02 to TC-CORE-09 pass with 2 and 4 lanes.

Phase 5 (coverage): TC-DL-23 (FULL after RXERR) and TC-DL-24 (broadcast input discard) close the open items of the
plan; mutation check: without the FULL after RXERR rule TC-DL-23 fails.

Code coverage (QuestaSim, [docs/coverage.md](../../../docs/coverage.md)): the first measurement showed behaviour that
the requirements ask for but no test exercised: the input VC buffer overflow (DL-VI-03 was verified only by the absence
of overflows), the Interface Reset in each state of the link reset state machine with the reset values of the time-slots
32 to 63 and of the idle limit, CRC-8 errors of SIF, FULL, ACK and NACK, frame structure errors, the transition from
Error Positive to Error Negative, the data item limit of the error recovery buffer and a continuous mode flush during
the copy of a segment. TC-DL-27 to TC-DL-30 and the extensions of TC-DL-12 and TC-DL-17 cover them and passed without a
design change (TC-DL-28 mutation checked); DL-WI-02 now states that a data frame for a VC that the core does not
implement is discarded. Three branches and the body of one function remain, each justified in the coverage report.
The measurement after the register stages of the input VC buffers and the latch-free pulse crossing showed two
branches that the tests had reached only by their timing: a broadcast message waiting while no lane is active (LATE
flag, DL-BO-03) and a DED in a beat that ends its packet. TC-DL-06 now submits broadcast messages while the lanes of
both ends are down (both delivered with LATE at each end), TC-CORE-14 injects the errors of the input VC buffers with
no traffic in flight into a long and into a one-word packet; both passed without a design change.

Observations:

- Store and forward in the error recovery buffer adds the copy time of a data segment (up to 64 words) to the latency
  of a frame; the throughput is not affected.
- The interpretations of section 5 of the specification are exercised by the tests: segment size limited by the
  credit (`test_credit`), FULL per item kind (`test_tx_idle_fct`, `test_erb_full`), complete resend of an interrupted
  frame (`test_error_recovery`).

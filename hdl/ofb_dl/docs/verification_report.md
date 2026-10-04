# ofb_dl: Verification Report

## 1. Test results

Run on 2026-10-05 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*ofb_dl*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `ofb_dl_tb` (layer, two complete ends) | 7 | 7 |
| `ofb_dl_row_tb` (row level) | 15 | 15 |
| `ofb_dl_mac_tb` (medium access controller) | 7 | 7 |

Full regression of the repository: 151 of 151 tests pass (with phase 4: rows of several words, verified in the core
testbench with 2 and 4 lanes, plan section 3.5). VSG reports no errors and no warnings.

Error and recovery counters of the layer tests (both ends):

| Test | RETRY sent | Sequence errors | Result |
| --- | --- | --- | --- |
| `test_error_recovery` (30 bit errors per direction) | 8 per end | 2 per end | All packets and broadcast messages delivered once and in order, no link reset |
| `test_lane_loss` (5 us cut during traffic) | 1 per end | 3 per end | All packets delivered, no link reset |

## 2. Summary

All 29 test cases pass and cover the requirements of the specification (verification plan, section 4).

Defects found and fixed during verification:

| Finding | Fix |
| --- | --- |
| `olo_ft_fifo_packet` does not support the feature set DROP_ONLY (Last outside the ECC code word) | Frame buffer uses DROP_SKIP_ONLY |
| Counters of the error recovery buffer left their range in delta cycles before the admission signals settled (GHDL bound check) | Range guards on every increment |
| The input VC buffer inserted one EEP per cycle of the buffer reset | One EEP per link reset |
| The end-of-packet count of the output VC buffer crossed faster than the buffer level: packets were split into several data frames | Count delayed behind the level |
| Testbench: delivery check before the generators had started; lane loss test cut the lane after the traffic had ended | Testbench timing |
| Found with the MIB testbench: `olo_ft_cc_pulse` stretches every output pulse to two cycles, so the input VC buffer requested two FCTs per 64 words read (credit for more words than the buffer holds) | `ofb_cc_pulse` with an edge detector; TC-DL-20 checks the FCT count (mutation checked: 6 instead of 4 FCTs without the fix) |

Phase 3 (quality of service, continuous mode): the MAC unit tests and TC-DL-21 / TC-DL-22 passed on the first run;
mutation check: with equal priorities the first frame of TC-DL-21 comes from VC 0 and the test fails as expected.

Phase 4 (rows of several words): the tests of this module (one lane) pass unchanged after the conversion to rows; the
core tests TC-CORE-02 to TC-CORE-09 pass with 2 and 4 lanes.

Phase 5 (coverage): TC-DL-23 (FULL after RXERR) and TC-DL-24 (broadcast input discard) close the open items of the
plan; mutation check: without the FULL after RXERR rule TC-DL-23 fails.

Observations:

- Store and forward in the error recovery buffer adds the copy time of a data segment (up to 64 words) to the latency
  of a frame; the throughput is not affected.
- The interpretations of section 5 of the specification are exercised by the tests: segment size limited by the
  credit (`test_credit`), FULL per item kind (`test_tx_idle_fct`, `test_erb_full`), complete resend of an interrupted
  frame (`test_error_recovery`).

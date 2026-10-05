# ofb_core: Verification Report

## 1. Test results

Run on 2026-10-05 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*ofb_core*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `ofb_core_tb` (configurations `lanes1`, `lanes2`, `lanes4`) | 14 x 3 | 42 |

Fault injection campaign (TC-CORE-13): the regression runs seed 1; the extended campaign
`OFB_CAMPAIGN_SEEDS="2,3,4,5" python run.py "*test_fault_campaign*"` adds seeds 2 to 5. 15 runs, 600 faults, all
pass (faults per kind; retries at A / B):

| Configuration | Bit error, burst, slip, SEC, DED, lane cut | Retries A / B | Result |
| --- | --- | --- | --- |
| lanes1 | 17, 6, 8, 3, 6, 0 | 10 / 11 | pass |
| lanes1, seed 2 | 17, 5, 5, 7, 6, 0 | 13 / 5 | pass |
| lanes1, seed 3 | 8, 10, 7, 11, 4, 0 | 6 / 7 | pass |
| lanes1, seed 4 | 15, 9, 6, 4, 6, 0 | 9 / 5 | pass |
| lanes1, seed 5 | 16, 6, 6, 6, 6, 0 | 13 / 5 | pass |
| lanes2 | 9, 8, 4, 5, 4, 10 | 11 / 12 | pass |
| lanes2, seed 2 | 7, 5, 11, 8, 5, 4 | 13 / 12 | pass |
| lanes2, seed 3 | 3, 7, 4, 9, 12, 5 | 6 / 8 | pass |
| lanes2, seed 4 | 8, 5, 2, 11, 9, 5 | 6 / 9 | pass |
| lanes2, seed 5 | 7, 4, 6, 8, 8, 7 | 6 / 13 | pass |
| lanes4 | 8, 4, 10, 7, 4, 7 | 9 / 11 | pass |
| lanes4, seed 2 | 9, 3, 5, 7, 10, 6 | 12 / 10 | pass |
| lanes4, seed 3 | 14, 5, 6, 4, 3, 8 | 11 / 12 | pass |
| lanes4, seed 4 | 6, 2, 6, 8, 7, 11 | 11 / 8 | pass |
| lanes4, seed 5 | 13, 3, 4, 6, 11, 3 | 11 / 10 | pass |

The campaign found three design defects (section 2): words lost in the Multi-Lane distributor in Not Ready, silent
corruption by double errors in the row crossings, and a second error recovery caused by the latency of the receive
error state machine of the Data Link layer.

## 2. Summary

All test cases pass and cover every requirement of the specification.

Defects found during verification:

| Finding | Fix |
| --- | --- |
| After a Link Reset command the far end did not reset: the lane becomes active a few cycles after the capability event, and the lane active level crossed to the core clock faster than the event, so the link reset state machine saw an active lane | The Multi-Lane layer qualifies the capability event with "no lane active" at the time of the event (`Dl_FarCapabilityIdle`), and both cross in one FIFO word |
| TC-CORE-07 (2 and 4 lanes): with the SKIP request of the Multi-Lane layer the own SKIP counter of the Lane layer kept counting and left its range (GHDL bound check) after 5000 words in Active | The own counter only counts without `SkipExternal_g` |
| Testbench, 2 and 4 lanes: the generators of the VCs assigned their slice of the beat signal with a variable index, so every generator drove the whole signal (several drivers, X at the core input) | Beat built in a variable, the static slice of the VC assigned once |
| TC-CORE-13 (2 and 4 lanes): a word slip on one line corrupted packets in the other direction without any error (scoreboard mismatch): the end with the slip entered Not Ready and its distributor discarded held words of a frame that the far end kept | Multi-Lane layer: held words kept in Not Ready (ML-DS-12) |
| TC-CORE-13: a double error in a row crossing corrupted a word after the CRC-16 check (receive) or before the CRC-16 computation (transmit): silent corruption | Receive: the row becomes one RXERR; transmit: poisoned row, CRC-16 of the frame inverted (CORE-ED-02) |
| TC-CORE-13 (testbench): with about 6 % link load most line faults hit idle frames, one end saw no retry | Traffic raised to about 60 % of the link capacity |
| TC-CORE-14: a link reset during traffic caused a second link reset with the protocol error flag: ACKs of the far end for frames that the near end had discarded still arrived before the lanes went down | Data Link layer: received words pass to the receive checks only in Link Initialised (DL-LR-05) |
| TC-CORE-14 (testbench): the injected error waits for the next word written into the channel; without traffic after the injection the error was never read | Traffic after the injection; the test waits for the DED flag and for the far-end link reset before the traffic that recognises the lost packets |
| TC-CORE-13 (2 lanes, seed 2): a packet delivered twice after a lane slip: two out-of-sequence words in consecutive cycles were checked against an old Receive Polarity Flag and started a second error recovery | Data Link layer: receive error state machine updated in the cycle of the word (DL-RE-01, TC-DL-26) |

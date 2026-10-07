# ofb_core: Verification Report

## 1. Test results

Run on 2026-10-07 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*ofb_core*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `ofb_core_tb` (configurations `lanes1`, `lanes2`, `lanes4`) | 18 x 3 | 54 |
| `ofb_core_tb`, configuration `lanes1_slowcore` (TC-CORE-15 only) | 1 | 1 |

Throughput and latency (TC-CORE-16, lane capacity 5 Gbit/s per lane: 32 bits per 6.4 ns; core clock 166.7 MHz, user
clock 192.3 MHz; packets of 1 to 1024 bytes on four VCs):

| Configuration | Latency, packet of one byte | A to B only | Both directions, per direction |
| --- | --- | --- | --- |
| lanes1 | 339 ns | 4.73 Gbit/s (94.7 %) | 4.53 / 4.52 Gbit/s (90.6 / 90.5 %) |
| lanes2 | 362 ns | 9.43 Gbit/s (94.3 %) | 9.06 / 9.04 Gbit/s (90.6 / 90.4 %) |
| lanes4 | 361 ns | 18.72 Gbit/s (93.6 %) | 17.95 / 18.01 Gbit/s (89.7 / 90.0 %) |

The latency includes the behavioural Physical adapter (no serialisation delay) and the store-and-forward frame
buffer of the receiver. The losses are the framing words (SDF, EDF per data frame of 64 words per lane), the
EOP and Fill characters, SKIP, and in both directions the ACKs and FCTs of the reverse traffic.

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
| Code coverage after the register stages of the input VC buffers: with random traffic the DED of the input VC buffers no longer hit a beat that ends its packet | TC-CORE-14 injects the errors of the input VC buffers with no traffic in flight, into an early word of a 1024-byte packet and into a packet of one word per VC (packet length range `MinLen` to `MaxLen` in the testbench); at least two packets per VC end with EEP |
| Functional coverage (testbench): the campaign sent packets of at most 64 bytes, so no fault hit a packet of several data frames | Campaign packets cycle through all length classes up to 1024 bytes at the same load; 15 runs pass |
| TC-CORE-13 (2 lanes, seed 2): a packet delivered twice after a lane slip: two out-of-sequence words in consecutive cycles were checked against an old Receive Polarity Flag and started a second error recovery | Data Link layer: receive error state machine updated in the cycle of the word (DL-RE-01, TC-DL-26) |

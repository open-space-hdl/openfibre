# ofb_core: Verification Report

## 1. Test results

Run on 2026-10-05 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*ofb_core*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `ofb_core_tb` (configurations `lanes1`, `lanes2`, `lanes4`) | 13 x 3 | 39 |

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

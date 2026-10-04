# ofb_core: Verification Report

## 1. Test results

Run on 2026-10-05 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*ofb_core*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `ofb_core_tb` (configurations `lanes1`, `lanes2`, `lanes4`) | 10 x 3 | 30 |

## 2. Summary

All test cases pass and cover every requirement of the specification.

Defects found during verification:

| Finding | Fix |
| --- | --- |
| After a Link Reset command the far end did not reset: the lane becomes active a few cycles after the capability event, and the lane active level crossed to the core clock faster than the event, so the link reset state machine saw an active lane | The Multi-Lane layer qualifies the capability event with "no lane active" at the time of the event (`Dl_FarCapabilityIdle`), and both cross in one FIFO word |
| TC-CORE-07 (2 and 4 lanes): with the SKIP request of the Multi-Lane layer the own SKIP counter of the Lane layer kept counting and left its range (GHDL bound check) after 5000 words in Active | The own counter only counts without `SkipExternal_g` |
| Testbench, 2 and 4 lanes: the generators of the VCs assigned their slice of the beat signal with a variable index, so every generator drove the whole signal (several drivers, X at the core input) | Beat built in a variable, the static slice of the VC assigned once |

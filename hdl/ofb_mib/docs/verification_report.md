# ofb_mib: Verification Report

## 1. Test results

Run on 2026-10-07 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*ofb_mib*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `ofb_mib_tb` | 10 | 10 |

Full regression of the repository: 209 of 209 tests pass (with the PRBS test registers of MG-5). VSG reports no
errors and no warnings.

## 2. Summary

All test cases pass and cover every requirement of the specification.

Code coverage (QuestaSim, [docs/coverage.md](../../../docs/coverage.md)): the first measurement showed registers whose
write, clear or read path no test used (counter clears, W1C of several flags, CRC-8, frame and sequence counters, idle
limit, time-slots 63 to 32, lane events, SEC interrupt) and no test of the counter saturation (MG-ST-02). TC-MG-08 and
TC-MG-09 cover them and passed without a design change; every statement and branch is covered.

Register map: TC-MG-01 reads every fixed reset value of the register description (`regs/ofb_regs.yml`) back through
the generated package `ofb_regs_pkg`; a reset value changed in the description fails TC-MG-01 (mutation check).

PRBS test registers (TC-MG-10): an error counter that ignores the hold bit fails the test (mutation check: 15 instead
of 10 counted words).

Defects found during verification:

| Finding | Fix |
| --- | --- |
| ECSS table audit (5.9.4e): the Link Reset command cleared only the Data Link status; the lane event flags and the flags of bandwidth use were kept | The command clears the status of all layers, the EDAC status excepted (MG-ST-01, TC-MG-04) |
| The sticky bandwidth flags latched the undefined value of the status crossing before its first transfer (simulation) | The sticky flags accumulate the crossed status only 32 cycles after reset (first fix with `to_01` replaced: not synthesizable, found with `lint/synth_check.py`) |
| Every event was counted twice and every command gave two pulses: `olo_ft_cc_pulse` stretches its output pulses to two cycles of the output clock | `ofb_cc_pulse` (edge detector after `olo_ft_cc_pulse`), also used in the input VC buffer of the Data Link layer, where the same effect doubled the FCT requests |
| First build of the VCK190 design: the latches of `olo_ft_cc_pulse` can lose commands and events (gate and data follow the input pulse) | `ofb_cc_pulse` without latch: handshake with single-cycle output pulses (`ofb_pkg` report) |
